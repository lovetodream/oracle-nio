//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOConcurrencyHelpers
import NIOCore

struct StatementResult {
    enum Value: Equatable {
        case noRows(affectedRows: Int, lastRowID: RowID?)
        case describeInfo([OracleColumn])
    }

    var value: Value
    var logger: Logger
    var batchErrors: Optional<[OracleSQLError.BatchError]>
    var rowCounts: Optional<[Int]>
    var cursorID: UInt16?
}

final class OracleRowStream: @unchecked Sendable {

    private typealias AsyncSequenceSource = NIOThrowingAsyncSequenceProducer<
        DataRow, Error, AdaptiveRowBuffer, OracleRowStream
    >.Source

    enum Source {
        case stream([OracleColumn], OracleRowsDataSource)
        case noRows(Result<Void, Error>)
    }

    let eventLoop: EventLoop
    let logger: Logger

    private enum BufferState {
        case streaming(
            buffer: CircularBuffer<DataRow>, dataSource: OracleRowsDataSource
        )
        case finished(buffer: CircularBuffer<DataRow>)
        case failure(Error)
    }

    private enum DownstreamState {
        case waitingForConsumer(BufferState)
        case iteratingRows(
            onRow: (OracleRow) throws -> Void, EventLoopPromise<Void>, OracleRowsDataSource
        )
        case waitingForAll(
            [OracleRow], EventLoopPromise<[OracleRow]>, OracleRowsDataSource
        )
        case consumed(Result<Void, Error>)
        case asyncSequence(AsyncSequenceSource, OracleRowsDataSource)
    }

    final class MetadataListeners {
        private let lock = NIOLock()
        /// This property must only be accessed when ``lock`` is aquired.
        private nonisolated(unsafe) var affectedRowsListeners: [CheckedContinuation<Int, Error>] = []
        /// This property must only be accessed when ``lock`` is aquired.
        private nonisolated(unsafe) var affectedRows: Int?
        /// This property must only be accessed when ``lock`` is aquired.
        private nonisolated(unsafe) var lastRowIDListeners: [CheckedContinuation<RowID?, Error>] = []
        /// This property must only be accessed when ``lock`` is aquired.
        private nonisolated(unsafe) var lastRowID: RowID??
        /// This property must only be accessed when ``lock`` is aquired.
        private nonisolated(unsafe) var error: (any Error)?

        let rowCounts: [Int]?
        let batchErrors: [OracleSQLError.BatchError]?

        init(
            affectedRows: Int? = nil,
            lastRowID: RowID? = nil,
            rowCounts: [Int]?,
            batchErrors: [OracleSQLError.BatchError]?
        ) {
            self.affectedRows = affectedRows
            self.lastRowID = lastRowID
            self.rowCounts = rowCounts
            self.batchErrors = batchErrors
        }

        func addAffectedRowsListener(_ listener: CheckedContinuation<Int, Error>) {
            lock.withLock {
                if let affectedRows {
                    listener.resume(returning: affectedRows)
                } else if let error {
                    listener.resume(throwing: error)
                } else {
                    affectedRowsListeners.append(listener)
                }
            }
        }

        func receiveAffectedRows(_ affectedRows: Int) {
            let listeners = lock.withLock {
                self.affectedRows = affectedRows
                let listeners = self.affectedRowsListeners
                self.affectedRowsListeners.removeAll()
                return listeners
            }
            for listener in listeners {
                listener.resume(returning: affectedRows)
            }
        }

        func addLastRowIDListener(_ listener: CheckedContinuation<RowID?, Error>) {
            lock.withLock {
                if let lastRowID {
                    listener.resume(returning: lastRowID)
                } else if let error {
                    listener.resume(throwing: error)
                } else {
                    lastRowIDListeners.append(listener)
                }
            }
        }

        func receiveLastRowID(_ rowID: RowID?) {
            let listeners = lock.withLock {
                self.lastRowID = .some(rowID)
                let listeners = self.lastRowIDListeners
                self.lastRowIDListeners.removeAll()
                return listeners
            }
            for listener in listeners {
                listener.resume(returning: rowID)
            }
        }

        func receiveError(_ error: any Error) {
            let affectedRowsListeners = lock.withLock {
                self.error = error
                let listeners = self.affectedRowsListeners
                self.affectedRowsListeners.removeAll()
                return listeners
            }
            for listener in affectedRowsListeners {
                listener.resume(throwing: error)
            }
        }
    }

    private let rowDescription: [OracleColumn]
    private let lookupTable: [String: Int]
    private let listeners: MetadataListeners
    private var downstreamState: DownstreamState

    init(
        source: Source,
        eventLoop: EventLoop,
        logger: Logger,
        affectedRows: Int?,
        lastRowID: RowID?,
        rowCounts: [Int]?,
        batchErrors: [OracleSQLError.BatchError]?
    ) {
        let bufferState: BufferState
        switch source {
        case .stream(let rowDescription, let dataSource):
            self.rowDescription = rowDescription
            bufferState = .streaming(buffer: .init(), dataSource: dataSource)
        case .noRows(.success):
            self.rowDescription = []
            bufferState = .finished(buffer: .init())
        case .noRows(.failure(let error)):
            self.rowDescription = []
            bufferState = .failure(error)
        }

        self.downstreamState = .waitingForConsumer(bufferState)

        self.eventLoop = eventLoop
        self.logger = logger

        var lookup: [String: Int] = [:]
        lookup.reserveCapacity(rowDescription.count)
        for (index, column) in rowDescription.enumerated() {
            lookup[column.name] = index
        }
        self.lookupTable = lookup

        self.listeners = MetadataListeners(
            affectedRows: affectedRows,
            lastRowID: lastRowID,
            rowCounts: rowCounts,
            batchErrors: batchErrors
        )
    }

    // MARK: Async Sequence

    func asyncSequence() -> OracleRowSequence {
        self.eventLoop.preconditionInEventLoop()

        guard case .waitingForConsumer(let bufferState) = downstreamState else {
            preconditionFailure("invalid state")
        }

        let producer = NIOThrowingAsyncSequenceProducer.makeSequence(
            elementType: DataRow.self,
            failureType: Error.self,
            backPressureStrategy: AdaptiveRowBuffer(),
            finishOnDeinit: true,
            delegate: self
        )

        let source = producer.source

        switch bufferState {
        case .streaming(let bufferedRows, let dataSource):
            let yieldResult = source.yield(contentsOf: bufferedRows)
            self.downstreamState = .asyncSequence(source, dataSource)
            self.executeActionBasedOnYieldResult(
                yieldResult, source: dataSource
            )
        case .finished(let buffer):
            _ = source.yield(contentsOf: buffer)
            source.finish()
            self.downstreamState = .consumed(.success(()))
        case .failure(let error):
            source.finish(error)
            self.downstreamState = .consumed(.failure(error))
        }

        return OracleRowSequence(
            producer.sequence,
            lookupTable: self.lookupTable,
            columns: self.rowDescription,
            listeners: self.listeners
        )
    }

    func demand() {
        if self.eventLoop.inEventLoop {
            self.demand0()
        } else {
            self.eventLoop.execute {
                self.demand0()
            }
        }
    }

    private func demand0() {
        switch self.downstreamState {
        case .waitingForConsumer, .iteratingRows, .waitingForAll:
            preconditionFailure("invalid state")

        case .consumed:
            break

        case .asyncSequence(_, let dataSource):
            dataSource.request(for: self)
        }
    }

    func cancel() {
        if self.eventLoop.inEventLoop {
            self.cancel0()
        } else {
            self.eventLoop.execute {
                self.cancel0()
            }
        }
    }

    private func cancel0() {
        switch self.downstreamState {
        case .asyncSequence(_, let dataSource):
            self.downstreamState = .consumed(.failure(CancellationError()))
            dataSource.cancel(for: self)

        case .consumed:
            return

        case .waitingForConsumer, .iteratingRows, .waitingForAll:
            preconditionFailure("invalid state")
        }
    }

    // MARK: Consume in array

    func all() -> EventLoopFuture<[OracleRow]> {
        if self.eventLoop.inEventLoop {
            return self.all0()
        } else {
            return self.eventLoop.flatSubmit {
                self.all0()
            }
        }
    }

    private func all0() -> EventLoopFuture<[OracleRow]> {
        self.eventLoop.preconditionInEventLoop()

        guard
            case .waitingForConsumer(let bufferState) = self.downstreamState
        else {
            preconditionFailure("Invalid state: \(self.downstreamState)")
        }

        switch bufferState {
        case .streaming(let bufferedRows, let dataSource):
            let promise = self.eventLoop.makePromise(of: [OracleRow].self)
            let rows = bufferedRows.map { data in
                OracleRow(
                    lookupTable: self.lookupTable,
                    data: data,
                    columns: self.rowDescription
                )
            }
            self.downstreamState = .waitingForAll(rows, promise, dataSource)
            // immediately request more
            dataSource.request(for: self)
            return promise.futureResult

        case .finished(let buffer):
            let rows = buffer.map { data in
                OracleRow(
                    lookupTable: self.lookupTable,
                    data: data,
                    columns: self.rowDescription
                )
            }

            self.downstreamState = .consumed(.success(()))
            return self.eventLoop.makeSucceededFuture(rows)

        case .failure(let error):
            self.downstreamState = .consumed(.failure(error))
            return self.eventLoop.makeFailedFuture(error)
        }
    }

    // MARK: Consume on EventLoop

    func onRow(
        _ onRow: @escaping @Sendable (OracleRow) throws -> Void
    ) -> EventLoopFuture<Void> {
        if self.eventLoop.inEventLoop {
            return self.onRow0(onRow)
        } else {
            return self.eventLoop.flatSubmit {
                self.onRow0(onRow)
            }
        }
    }

    private func onRow0(
        _ onRow: @escaping (OracleRow) throws -> Void
    ) -> EventLoopFuture<Void> {
        self.eventLoop.preconditionInEventLoop()

        guard case .waitingForConsumer(let bufferState) = downstreamState else {
            preconditionFailure("Invalid state: \(self.downstreamState)")
        }

        switch bufferState {
        case .streaming(var buffer, let dataSource):
            let promise = self.eventLoop.makePromise(of: Void.self)
            do {
                for data in buffer {
                    let row = OracleRow(
                        lookupTable: self.lookupTable,
                        data: data,
                        columns: self.rowDescription
                    )
                    try onRow(row)
                }

                buffer.removeAll()
                self.downstreamState =
                    .iteratingRows(onRow: onRow, promise, dataSource)
                // immediately request more
                dataSource.request(for: self)
            } catch {
                self.downstreamState = .consumed(.failure(error))
                dataSource.cancel(for: self)
                promise.fail(error)
            }

            return promise.futureResult

        case .finished(let buffer):
            do {
                for data in buffer {
                    let row = OracleRow(
                        lookupTable: self.lookupTable,
                        data: data,
                        columns: self.rowDescription
                    )
                    try onRow(row)
                }

                self.downstreamState = .consumed(.success(()))
                return self.eventLoop.makeSucceededVoidFuture()
            } catch {
                self.downstreamState = .consumed(.failure(error))
                return self.eventLoop.makeFailedFuture(error)
            }
        case .failure(let error):
            self.downstreamState = .consumed(.failure(error))
            return self.eventLoop.makeFailedFuture(error)
        }

    }

    internal func receive(_ newRows: [DataRow]) {
        precondition(!newRows.isEmpty, "Expected to get rows!")
        self.eventLoop.preconditionInEventLoop()
        self.logger.trace(
            "Row stream received rows",
            metadata: [
                "row_count": "\(newRows.count)"
            ])

        switch self.downstreamState {
        case .waitingForConsumer(.streaming(var buffer, let dataSource)):
            buffer.append(contentsOf: newRows)
            self.downstreamState = .waitingForConsumer(
                .streaming(buffer: buffer, dataSource: dataSource)
            )

        case .waitingForConsumer(.finished), .waitingForConsumer(.failure):
            preconditionFailure(
                "How can new rows be received, if an end was already signaled?"
            )

        case .iteratingRows(let onRow, let promise, let dataSource):
            do {
                for data in newRows {
                    let row = OracleRow(
                        lookupTable: self.lookupTable,
                        data: data,
                        columns: self.rowDescription
                    )
                    try onRow(row)
                }
                // immediately request more
                dataSource.request(for: self)
            } catch {
                dataSource.cancel(for: self)
                self.downstreamState = .consumed(.failure(error))
                promise.fail(error)
                return
            }

        case .waitingForAll(var rows, let promise, let dataSource):
            for data in newRows {
                let row = OracleRow(
                    lookupTable: self.lookupTable,
                    data: data,
                    columns: self.rowDescription
                )
                rows.append(row)
            }
            self.downstreamState = .waitingForAll(rows, promise, dataSource)
            // immediately request more
            dataSource.request(for: self)

        case .asyncSequence(let consumer, let source):
            let yieldResult = consumer.yield(contentsOf: newRows)
            self.executeActionBasedOnYieldResult(yieldResult, source: source)

        case .consumed(.success):
            preconditionFailure(
                "How can we receive further rows, if we are supposed to be done"
            )

        case .consumed(.failure):
            break
        }
    }

    internal struct Success {
        let affectedRows: Int
        let lastRowID: RowID?
    }
    internal func receive(completion result: Result<Success, Error>) {
        self.eventLoop.preconditionInEventLoop()

        switch result {
        case .success(let success):
            self.receiveEnd()
            self.listeners.receiveAffectedRows(success.affectedRows)
            self.listeners.receiveLastRowID(success.lastRowID)
        case .failure(let error):
            self.receiveError(error)
            self.listeners.receiveError(error)
        }
    }

    private func receiveEnd() {
        switch self.downstreamState {
        case .waitingForConsumer(.streaming(let buffer, _)):
            self.downstreamState = .waitingForConsumer(
                .finished(buffer: buffer)
            )

        case .waitingForConsumer(.finished), .waitingForConsumer(.failure):
            preconditionFailure(
                "How can we get another end, if an end was already signaled?"
            )

        case .iteratingRows(_, let promise, _):
            self.downstreamState = .consumed(.success(()))
            promise.succeed()

        case .waitingForAll(let rows, let promise, _):
            self.downstreamState = .consumed(.success(()))
            promise.succeed(rows)

        case .asyncSequence(let source, _):
            source.finish()
            self.downstreamState = .consumed(.success(()))

        case .consumed:
            break
        }
    }

    private func receiveError(_ error: Error) {
        switch self.downstreamState {
        case .waitingForConsumer(.streaming):
            self.downstreamState = .waitingForConsumer(.failure(error))

        case .waitingForConsumer(.finished), .waitingForConsumer(.failure):
            preconditionFailure(
                "How can we get another end, if an end was already signaled?"
            )

        case .iteratingRows(_, let promise, _):
            self.downstreamState = .consumed(.failure(error))
            promise.fail(error)

        case .waitingForAll(_, let promise, _):
            self.downstreamState = .consumed(.failure(error))
            promise.fail(error)

        case .asyncSequence(let consumer, _):
            consumer.finish(error)
            self.downstreamState = .consumed(.failure(error))

        case .consumed:
            break
        }
    }

    private func executeActionBasedOnYieldResult(
        _ yieldResult: AsyncSequenceSource.YieldResult,
        source: OracleRowsDataSource
    ) {
        self.eventLoop.preconditionInEventLoop()
        switch yieldResult {
        case .dropped:
            // ignore
            break
        case .produceMore:
            source.request(for: self)
        case .stopProducing:
            // ignore:
            break
        }
    }
}

extension OracleRowStream: NIOAsyncSequenceProducerDelegate {
    func produceMore() {
        self.demand()
    }

    func didTerminate() {
        self.cancel()
    }
}

protocol OracleRowsDataSource {
    func request(for stream: OracleRowStream)
    func cancel(for stream: OracleRowStream)
}

#if swift(>=5.10)
    extension OracleRowStream.MetadataListeners: Sendable {}
#else
    extension OracleRowStream.MetadataListeners: @unchecked Sendable {}
#endif
