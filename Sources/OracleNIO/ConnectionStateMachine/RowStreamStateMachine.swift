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

import NIOCore

struct RowStreamStateMachine {

    enum Action {
        case read
        case wait
    }

    private enum State {
        /// The state machines expect further writes to `channelRead`. The writes are appended
        /// to the buffer.
        case waitingForRows([DataRow])
        /// The state machine expect a call to `demandMoreResponseBodyParts` or `read`.
        ///
        /// The buffer is empty. It is preserved for performance reasons.
        case waitingForReadOrDemand([DataRow])
        /// The state machines expect a call to `read`.
        ///
        /// The buffer is empty. It is preserved for performance reasons.
        case waitingForRead([DataRow])
        /// The state machines expect a call to `demandMoreResponseBodyParts`.
        ///
        /// The buffer is empty. It is preserved for performance reasons.
        case waitingForDemand([DataRow])

        case failed

        case modifying
    }

    private var state: State
    private var lastRowFromPreviousBuffer: DataRow?

    init() {
        var buffer = [DataRow]()
        buffer.reserveCapacity(32)
        self.state = .waitingForRows(buffer)
    }

    mutating func receivedRow(_ newRow: DataRow) {
        switch self.state {
        case .waitingForRows(var buffer):
            self.state = .modifying
            buffer.append(newRow)
            self.state = .waitingForRows(buffer)

        // For all the following cases, please note:
        // Normally these code paths should never be hit. However there is
        // one way to trigger this:
        //
        // If the server decides to close a connection, NIO will forward all
        // outstanding `channelRead`s without waiting for a next
        // `context.read` call. For this reason we might receive new rows,
        // when we don't expect them here.
        case .waitingForReadOrDemand(var buffer):
            self.state = .modifying
            buffer.append(newRow)
            self.state = .waitingForReadOrDemand(buffer)

        case .waitingForRead(var buffer):
            self.state = .modifying
            buffer.append(newRow)
            self.state = .waitingForRead(buffer)

        case .waitingForDemand(var buffer):
            self.state = .modifying
            buffer.append(newRow)
            self.state = .waitingForDemand(buffer)

        case .failed:
            // Once the row stream state machine is marked as failed, no further
            // events must be forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func receivedDuplicate(at index: Int) -> ByteBuffer {
        switch self.state {
        case .waitingForRows(let buffer):
            guard
                let previousRow = buffer.last ?? self.lastRowFromPreviousBuffer
            else {
                preconditionFailure()
            }
            let idx = previousRow.index(previousRow.startIndex, offsetBy: index)
            // return empty buffer if duplicate is nil
            return previousRow[idx] ?? .init()

        // For all the following cases, please note:
        // Normally these code paths should never be hit. However there is
        // one way to trigger this:
        //
        // If the server decides to close a connection, NIO will forward all
        // outstanding `channelRead`s without waiting for a next
        // `context.read` call. For this reason we might receive new rows,
        // when we don't expect them here.
        case .waitingForReadOrDemand(let buffer),
            .waitingForRead(let buffer),
            .waitingForDemand(let buffer):
            guard
                let previousRow = buffer.last ?? self.lastRowFromPreviousBuffer
            else {
                preconditionFailure()
            }
            let index = previousRow.index(DataRow.ColumnIndex(0), offsetBy: index)
            // return empty buffer if duplicate is nil
            return previousRow[index] ?? .init()

        case .failed:
            // Once the row stream state machine is marked as failed, no further
            // events must be forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func channelReadComplete() -> [DataRow]? {
        switch self.state {
        case .waitingForRows(let buffer),
            .waitingForRead(let buffer),
            .waitingForDemand(let buffer),
            .waitingForReadOrDemand(let buffer):
            if buffer.isEmpty {
                self.state = .waitingForRead(buffer)
                return nil
            } else {
                var newBuffer = buffer
                newBuffer.removeAll(keepingCapacity: true)
                // safe last row in case we receive a duplicate in row 0 of
                // the next fetch
                self.lastRowFromPreviousBuffer = buffer.last
                self.state = .waitingForReadOrDemand(newBuffer)
                return buffer
            }

        case .failed:
            // Once the row stream state machine is marked as failed, no further
            // events must be forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func demandMoreResponseBodyParts() -> Action {
        switch self.state {
        case .waitingForDemand(let buffer):
            self.state = .waitingForRows(buffer)
            return .read

        case .waitingForReadOrDemand(let buffer):
            self.state = .waitingForRead(buffer)
            return .wait

        case .waitingForRead:
            // If we are `.waitingForRead`, no action needs to be taken. Demand
            // has already been signaled. Once we receive the next `read`, we
            // will forward it right away.
            return .wait

        case .waitingForRows:
            // If we are `.waitingForRows`, no action needs to be taken. As soon
            // as we receive the next `channelReadComplete` we will forward all
            // buffered data
            return .wait

        case .failed:
            // Once the row stream state machine is marked as failed, no further events must be
            // forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func read() -> Action {
        switch self.state {
        case .waitingForRows:
            // This should never happen. But we don't want to precondition this
            // behavior. Let's just pass the read event on.
            return .read

        case .waitingForReadOrDemand(let buffer):
            self.state = .waitingForDemand(buffer)
            return .wait

        case .waitingForRead(let buffer):
            self.state = .waitingForRows(buffer)
            return .read

        case .waitingForDemand:
            // we have already received a read event. We will issue it as soon
            // as we received demand from the consumer
            return .wait

        case .failed:
            // Once the row stream state machine is marked as failed, no further
            // events must be forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func end() -> [DataRow] {
        switch self.state {
        case .waitingForRows(let buffer):
            return buffer

        case .waitingForReadOrDemand(let buffer),
            .waitingForRead(let buffer),
            .waitingForDemand(let buffer):
            // Normally this code path should never be hit. However there is one
            // way to trigger this:
            //
            // If the server decides to close a connection, NIO will forward all
            // outstanding `channelRead`s without waiting for a next
            // `context.read` call. For this reason we might receive a call to
            // `end()`, when we don't expect it here.
            return buffer

        case .failed:
            // Once the row stream state machine is marked as failed, no further
            // events must be forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func fail() -> Action {
        switch self.state {
        case .waitingForRows, .waitingForReadOrDemand, .waitingForRead:
            self.state = .failed
            return .wait

        case .waitingForDemand:
            self.state = .failed
            return .wait

        case .failed:
            // Once the row stream state machine is marked as failed, no further
            // events must be forwarded to it.
            preconditionFailure("Invalid state: \(self.state)")

        case .modifying:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

}
