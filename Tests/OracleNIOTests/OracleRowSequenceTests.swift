//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Atomics
import Logging
import NIOCore
import NIOEmbedded
import NIOPosix
import Testing

@testable import OracleNIO

@Suite struct OracleRowSequenceTests {
    let logger = Logger(label: "OracleRowSequenceTests")

    let testColumn = DescribeInfo.Column(
        name: "test",
        dataType: .binaryInteger,
        dataTypeSize: 0,
        precision: 0,
        scale: 0,
        bufferSize: 0,
        nullsAllowed: false,
        typeScheme: nil,
        typeName: nil,
        domainSchema: nil,
        domainName: nil,
        annotations: [:],
        vectorDimensions: nil,
        vectorFormat: nil
    )

    @Test func backPressureWorks() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = stream.asyncSequence()
        #expect(dataSource.requestCount == 0)
        let dataRow: DataRow = [ByteBuffer(integer: Int64(1))]
        stream.receive([dataRow])

        var iterator = rowSequence.makeAsyncIterator()
        let row = try await iterator.next()
        #expect(dataSource.requestCount == 1)
        #expect(row?.data == dataRow)

        stream.receive(completion: .success(.init(affectedRows: 0, lastRowID: nil)))
        let empty = try await iterator.next()
        #expect(empty == nil)
    }


    @Test func cancellationWorksWhileIterating() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = stream.asyncSequence()
        #expect(dataSource.requestCount == 0)
        let dataRows: [DataRow] = (0..<128).map { [ByteBuffer(integer: Int64($0))] }
        stream.receive(dataRows)

        var counter = 0
        for try await row in rowSequence {
            #expect(try row.decode(TestInt.self).value == counter)
            counter += 1

            if counter == 64 {
                break
            }
        }

        #expect(dataSource.cancelCount == 1)
    }

    @Test func cancellationWorksBeforeIterating() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = stream.asyncSequence()
        #expect(dataSource.requestCount == 0)
        let dataRows: [DataRow] = (0..<128).map { [ByteBuffer(integer: Int64($0))] }
        stream.receive(dataRows)

        var iterator: OracleRowSequence.AsyncIterator? = rowSequence.makeAsyncIterator()
        iterator = nil

        #expect(dataSource.cancelCount == 1)
        #expect(iterator == nil, "Suppress warning")
    }

    @Test func droppingTheSequenceCancelsTheSource() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        var rowSequence: OracleRowSequence? = stream.asyncSequence()
        rowSequence = nil

        #expect(dataSource.cancelCount == 1)
        #expect(rowSequence == nil, "Suppress warning")
    }

    @Test func streamBasedOnCompletedQuery() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = stream.asyncSequence()
        let dataRows: [DataRow] = (0..<128).map { [ByteBuffer(integer: Int64($0))] }
        stream.receive(dataRows)
        stream.receive(completion: .success(.init(affectedRows: 0, lastRowID: nil)))

        var counter = 0
        for try await row in rowSequence {
            #expect(try row.decode(TestInt.self).value == counter)
            counter += 1
        }

        #expect(dataSource.cancelCount == 0)
    }

    @Test func streamIfInitializedWithAllData() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let dataRows: [DataRow] = (0..<128).map { [ByteBuffer(integer: Int64($0))] }
        stream.receive(dataRows)
        stream.receive(completion: .success(.init(affectedRows: 0, lastRowID: nil)))

        let rowSequence = stream.asyncSequence()

        var counter = 0
        for try await row in rowSequence {
            #expect(try row.decode(TestInt.self).value == counter)
            counter += 1
        }

        #expect(dataSource.cancelCount == 0)
    }

    @Test func streamIfInitializedWithError() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        stream.receive(completion: .failure(OracleSQLError.uncleanShutdown))

        let rowSequence = stream.asyncSequence()

        await #expect(throws: OracleSQLError.uncleanShutdown) {
            var counter = 0
            for try await _ in rowSequence {
                counter += 1
            }
        }
    }

    @Test func succeedingRowContinuationsWorks() async throws {
        let dataSource = MockRowDataSource()
        let eventLoop = NIOSingletons.posixEventLoopGroup.next()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: eventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = try await eventLoop.submit { stream.asyncSequence() }.get()
        var rowIterator = rowSequence.makeAsyncIterator()

        eventLoop.scheduleTask(in: .seconds(1)) {
            let dataRows: [DataRow] = (0..<1).map { [ByteBuffer(integer: Int64($0))] }
            stream.receive(dataRows)
        }

        let row1 = try await rowIterator.next()
        #expect(try row1?.decode(TestInt.self).value == 0)

        eventLoop.scheduleTask(in: .seconds(1)) {
            stream.receive(completion: .success(.init(affectedRows: 0, lastRowID: nil)))
        }

        let row2 = try await rowIterator.next()
        #expect(row2 == nil)
    }

    @Test func failingRowContinuationsWorks() async throws {
        let dataSource = MockRowDataSource()
        let eventLoop = NIOSingletons.posixEventLoopGroup.next()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: eventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = try await eventLoop.submit { stream.asyncSequence() }.get()
        var rowIterator = rowSequence.makeAsyncIterator()

        eventLoop.scheduleTask(in: .seconds(1)) {
            let dataRows: [DataRow] = (0..<1).map { [ByteBuffer(integer: Int64($0))] }
            stream.receive(dataRows)
        }

        let row1 = try await rowIterator.next()
        #expect(try row1?.decode(TestInt.self).value == 0)

        eventLoop.scheduleTask(in: .seconds(1)) {
            stream.receive(completion: .failure(OracleSQLError.uncleanShutdown))
        }

        await #expect(throws: OracleSQLError.uncleanShutdown) {
            _ = try await rowIterator.next()
        }
    }

    @Test func adaptiveRowBufferShrinksAndGrows() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let initialDataRows: [DataRow] = (0..<AdaptiveRowBuffer.defaultBufferTarget + 1).map {
            [ByteBuffer(integer: Int64($0))]
        }
        stream.receive(initialDataRows)

        let rowSequence = stream.asyncSequence()
        var rowIterator = rowSequence.makeAsyncIterator()

        #expect(dataSource.requestCount == 0)
        _ = try await rowIterator.next()  // new buffer size will be target -> don't ask for more
        #expect(dataSource.requestCount == 0)
        _ = try await rowIterator.next()  // new buffer will be (target - 1) -> ask for more
        #expect(dataSource.requestCount == 1)

        // if the buffer gets new rows so that it has equal or more than target (the target size
        // should be halved), however shrinking is only allowed AFTER the first extra rows were
        // received.
        let addDataRows1: [DataRow] = [[ByteBuffer(integer: Int64(0))]]
        stream.receive(addDataRows1)
        #expect(dataSource.requestCount == 1)
        _ = try await rowIterator.next()  // new buffer will be (target - 1) -> ask for more
        #expect(dataSource.requestCount == 2)

        // if the buffer gets new rows so that it has equal or more than target (the target size
        // should be halved)
        let addDataRows2: [DataRow] = [[ByteBuffer(integer: Int64(0))], [ByteBuffer(integer: Int64(0))]]
        stream.receive(addDataRows2)  // this should to target being halved.
        _ = try await rowIterator.next()  // new buffer will be (target - 1) -> ask for more
        for _ in 0..<(AdaptiveRowBuffer.defaultBufferTarget / 2) {
            _ = try await rowIterator.next()  // Remove all rows until we are back at target
            #expect(dataSource.requestCount == 2)
        }

        // if we remove another row we should trigger getting new rows.
        _ = try await rowIterator.next()  // new buffer will be (target - 1) -> ask for more
        #expect(dataSource.requestCount == 3)

        // remove all remaining rows... this will trigger a target size double
        for _ in 0..<(AdaptiveRowBuffer.defaultBufferTarget / 2 - 1) {
            _ = try await rowIterator.next()  // Remove all rows until we are back at target
            #expect(dataSource.requestCount == 3)
        }

        let fillBufferDataRows: [DataRow] = (0..<AdaptiveRowBuffer.defaultBufferTarget + 1).map {
            [ByteBuffer(integer: Int64($0))]
        }
        stream.receive(fillBufferDataRows)

        #expect(dataSource.requestCount == 3)
        _ = try await rowIterator.next()  // new buffer size will be target -> don't ask for more
        #expect(dataSource.requestCount == 3)
        _ = try await rowIterator.next()  // new buffer will be (target - 1) -> ask for more
        #expect(dataSource.requestCount == 4)
    }

    @Test func adaptiveRowShrinksToMin() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        var currentTarget = AdaptiveRowBuffer.defaultBufferTarget

        let initialDataRows: [DataRow] = (0..<currentTarget).map { [ByteBuffer(integer: Int64($0))] }
        stream.receive(initialDataRows)

        let rowSequence = stream.asyncSequence()
        var rowIterator = rowSequence.makeAsyncIterator()

        // shrinking the buffer is only allowed after the first extra rows were received
        #expect(dataSource.requestCount == 0)
        _ = try await rowIterator.next()
        #expect(dataSource.requestCount == 1)

        stream.receive([[ByteBuffer(integer: Int64(1))]])

        var expectedRequestCount = 1

        while currentTarget > AdaptiveRowBuffer.defaultBufferMinimum {
            // the buffer is filled up to currentTarget at that point, if we remove one row and add
            // one row it should shrink
            #expect(dataSource.requestCount == expectedRequestCount)
            _ = try await rowIterator.next()
            expectedRequestCount += 1
            #expect(dataSource.requestCount == expectedRequestCount)

            stream.receive([[ByteBuffer(integer: Int64(1))], [ByteBuffer(integer: Int64(1))]])
            let newTarget = currentTarget / 2
            let toDrop = currentTarget + 1 - newTarget

            // consume all messages that are to much.
            for _ in 0..<toDrop {
                _ = try await rowIterator.next()
                #expect(dataSource.requestCount == expectedRequestCount)
            }

            currentTarget = newTarget
        }

        #expect(currentTarget == AdaptiveRowBuffer.defaultBufferMinimum)
    }

    @Test func streamBufferAcceptsNewRowsEvenThoughItDidNotAskForIt() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()
        let stream = OracleRowStream(
            source: .stream([testColumn], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let messagePerChunk = AdaptiveRowBuffer.defaultBufferTarget * 4
        let initialDataRows: [DataRow] = (0..<messagePerChunk).map { [ByteBuffer(integer: Int64($0))] }
        stream.receive(initialDataRows)

        let rowSequence = stream.asyncSequence()
        var rowIterator = rowSequence.makeAsyncIterator()

        #expect(dataSource.requestCount == 0)
        _ = try await rowIterator.next()
        #expect(dataSource.requestCount == 0)

        let finalDataRows: [DataRow] = (0..<messagePerChunk).map { [ByteBuffer(integer: Int64(messagePerChunk + $0))] }
        stream.receive(finalDataRows)
        stream.receive(completion: .success(.init(affectedRows: 0, lastRowID: nil)))

        var counter = 1
        for _ in 0..<(2 * messagePerChunk - 1) {
            let row = try await rowIterator.next()
            #expect(try row?.decode(TestInt.self).value == counter)
            counter += 1
        }

        let emptyRow = try await rowIterator.next()
        #expect(emptyRow == nil)
    }

    @Test func columnsReturnsCorrectColumnInformation() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()

        let sourceColumns = [
            DescribeInfo.Column(
                name: "id",
                dataType: .number,
                dataTypeSize: 1,
                precision: 1,
                scale: 1,
                bufferSize: 1,
                nullsAllowed: false,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            ),
            DescribeInfo.Column(
                name: "name",
                dataType: .varchar,
                dataTypeSize: 1,
                precision: 1,
                scale: 1,
                bufferSize: 12,
                nullsAllowed: false,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            ),
        ]

        let stream = OracleRowStream(
            source: .stream(sourceColumns, dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = stream.asyncSequence()

        var count = 0
        for (index, column) in rowSequence.columns.enumerated() {
            count += 1
            switch index {
            case 0:
                #expect(column.name == "id")
            case 1:
                #expect(column.name == "name")
            default:
                struct OutOfBoundsError: Error {}
                throw OutOfBoundsError()
            }
        }
        #expect(count == 2)
    }

    @Test func columnsWithEmptyColumns() async throws {
        let dataSource = MockRowDataSource()
        let embeddedEventLoop = EmbeddedEventLoop()

        let stream = OracleRowStream(
            source: .stream([], dataSource),
            eventLoop: embeddedEventLoop,
            logger: self.logger,
            affectedRows: nil,
            lastRowID: nil,
            rowCounts: nil,
            batchErrors: nil
        )

        let rowSequence = stream.asyncSequence()
        var columns = rowSequence.columns.makeIterator()

        #expect(columns.next() == nil)
    }
}

final class MockRowDataSource: OracleRowsDataSource {
    var requestCount: Int {
        self._requestCount.load(ordering: .relaxed)
    }

    var cancelCount: Int {
        self._cancelCount.load(ordering: .relaxed)
    }

    private let _requestCount = ManagedAtomic(0)
    private let _cancelCount = ManagedAtomic(0)

    func request(for stream: OracleRowStream) {
        self._requestCount.wrappingIncrement(ordering: .relaxed)
    }

    func cancel(for stream: OracleRowStream) {
        self._cancelCount.wrappingIncrement(ordering: .relaxed)
    }
}

struct TestInt: OracleDecodable {
    let value: Int

    static func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> TestInt {
        guard var buffer else { throw OracleDecodingError.Code.missingData }
        return try self.init(from: &buffer, type: type, context: context)
    }

    init(from buffer: inout ByteBuffer, type: OracleDataType, context: OracleDecodingContext) throws {
        let value = try buffer.throwingReadInteger(as: Int64.self)
        self.value = numericCast(value)
    }
}
