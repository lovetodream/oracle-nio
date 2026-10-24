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
import NIOEmbedded
import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct StatementStateMachineTests {
    @Test func queryWithoutDataRowsHappyPath() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "DELETE FROM table"
        let queryContext = StatementContext(statement: query, promise: promise)

        let result = StatementResult(value: .noRows(affectedRows: 0, lastRowID: nil))
        let backendError = BackendError(
            number: 0, cursorID: 6, position: 0, rowCount: 0, isWarning: false, message: nil,
            rowID: nil, batchErrors: [])

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.backendErrorReceived(backendError) == .succeedStatement(promise, result))
        #expect(state.channelReadComplete() == .wait)
        #expect(state.readEventCaught() == .read)
    }

    @Test func queryWithDataRowsHappyPath() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "SELECT 1 AS id FROM dual"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "ID",
                dataType: .number,
                dataTypeSize: 0,
                precision: 11,
                scale: 127,
                bufferSize: 2,
                nullsAllowed: true,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            )
        ])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = StatementResult(value: .describeInfo(describeInfo.columns))

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)
        #expect(state.rowHeaderReceived(rowHeader) == .succeedStatement(promise, result))
        let row1: DataRow = .makeTestDataRow(1)
        #expect(state.rowDataReceived(.init(1), capabilities: .init()) == .wait)
        #expect(state.queryParameterReceived(.init()) == .wait)
        #expect(
            state.backendErrorReceived(.noData)
                == .forwardStreamComplete([row1], cursorID: 1, affectedRows: 1, lastRowID: nil))
    }

    @Test func queryWithLargeDuplicateWorks() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "SELECT 1 AS id FROM dual"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "ID",
                dataType: .number,
                dataTypeSize: 0,
                precision: 11,
                scale: 127,
                bufferSize: 2,
                nullsAllowed: true,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            )
        ])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = StatementResult(value: .describeInfo(describeInfo.columns))

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)
        #expect(state.rowHeaderReceived(rowHeader) == .succeedStatement(promise, result))
        var largeColumn = ByteBuffer(repeating: UInt8(1), count: Int(UInt8.max) + 25)
        var out = ByteBuffer()
        var length = largeColumn.readableBytes
        out.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
        while largeColumn.readableBytes > 0 {
            let chunkLength = min(length, Constants.TNS_CHUNK_SIZE)
            out.writeInteger(UInt32(chunkLength))
            length -= chunkLength
            var part = largeColumn.readSlice(length: chunkLength)!
            out.writeBuffer(&part)
        }
        out.writeInteger(UInt32(0))
        let row1 = DataRow(columnCount: 1, bytes: out)
        #expect(state.rowDataReceived(.init(columns: [.data(out)]), capabilities: .init()) == .wait)
        #expect(state.rowHeaderReceived(.init(bitVector: [])) == .wait)
        #expect(state.rowDataReceived(.init(columns: [.duplicate(0)]), capabilities: .init()) == .wait)
        #expect(state.queryParameterReceived(.init()) == .wait)
        #expect(
            state.backendErrorReceived(.noData)
                == .forwardStreamComplete([row1, row1], cursorID: 1, affectedRows: 1, lastRowID: nil))
    }

    @Test func cancellationCompletesQueryOnlyOnce() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "SELECT 1 AS id FROM dual"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "ID",
                dataType: .number,
                dataTypeSize: 0,
                precision: 11,
                scale: 0,
                bufferSize: 22,
                nullsAllowed: true,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            )
        ])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = StatementResult(value: .describeInfo(describeInfo.columns))
        let backendError = BackendError(
            number: 1013, cursorID: 3, position: 0, rowCount: 2, isWarning: false,
            message: "ORA-01013: user requested cancel of current operation\n", rowID: nil,
            batchErrors: [])

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)
        #expect(state.rowHeaderReceived(rowHeader) == .succeedStatement(promise, result))
        #expect(state.rowDataReceived(.init(1_024_834), capabilities: .init()) == .wait)
        #expect(state.rowDataReceived(.init(1_024_834), capabilities: .init()) == .wait)
        #expect(state.queryParameterReceived(.init()) == .wait)
        #expect(state.backendErrorReceived(.sendFetch) == .sendFetch(queryContext, cursorID: 3))
        #expect(
            state.cancelStatementStream()
                == .forwardStreamError(.statementCancelled, read: false, cursorID: nil, clientCancelled: true))
        #expect(state.markerReceived() == .sendMarker(read: false))
        #expect(state.backendErrorReceived(backendError) == .fireEventReadyForStatement)
    }

    @Test func cancellationFiresRead() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "SELECT 1 AS id FROM dual"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "ID",
                dataType: .number,
                dataTypeSize: 0,
                precision: 11,
                scale: 0,
                bufferSize: 22,
                nullsAllowed: true,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            )
        ])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = StatementResult(value: .describeInfo(describeInfo.columns))

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)
        #expect(state.rowHeaderReceived(rowHeader) == .succeedStatement(promise, result))
        #expect(state.rowDataReceived(.init(1_024_834), capabilities: .init()) == .wait)
        #expect(state.rowDataReceived(.init(1_024_834), capabilities: .init()) == .wait)
        #expect(state.queryParameterReceived(.init()) == .wait)
        #expect(state.backendErrorReceived(.sendFetch) == .sendFetch(queryContext, cursorID: 3))
        #expect(
            state.cancelStatementStream()
                == .forwardStreamError(
                    .statementCancelled, read: false, cursorID: nil, clientCancelled: true))
        #expect(state.statementStreamCancelled() == .sendMarker(read: true))
    }

    // MARK: - OracleConnection.cancel() / triggerBreak

    /// Cancel via ``OracleConnection/cancel()`` while the statement
    /// is still in `.initialized` (server hasn't responded yet — the
    /// `dbms_session.sleep` repro). The connection sends a TNS
    /// INTERRUPT marker, the server's BREAK ack drives the existing
    /// marker toggle into a follow-up RESET, and the awaiting
    /// promise fails with `.statementCancelled` once `ORA-01013`
    /// arrives.
    @Test func breakCancellationFromInitialized() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)
        let query: OracleStatement = "BEGIN dbms_session.sleep(10); END;"
        let queryContext = StatementContext(statement: query, promise: promise)

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )

        // Trigger the break while still in `.initialized`.
        #expect(state.triggerBreak() == .sendBreak(read: true))

        // Server BREAK ack → existing marker toggle echoes a RESET back.
        #expect(state.markerReceived() == .sendMarker(read: false))

        // ORA-01013 arrives; promise fails with `.statementCancelled`.
        let cancel = state.backendErrorReceived(.userRequestedCancel(cursorID: 0))
        #expect(cancel == .failStatement(promise, with: .statementCancelled, cleanupContext: nil))
    }

    /// Cancel after the server has already streamed `describeInfo`
    /// but before any rows arrived. Same wire-level handshake as the
    /// `.initialized` case.
    @Test func breakCancellationFromDescribeInfoReceived() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)
        let query: OracleStatement = "SELECT 1 AS id FROM dual"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "ID", dataType: .number, dataTypeSize: 0,
                precision: 11, scale: 0, bufferSize: 22,
                nullsAllowed: true, typeScheme: nil, typeName: nil,
                domainSchema: nil, domainName: nil,
                annotations: [:], vectorDimensions: nil, vectorFormat: nil
            )
        ])

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)

        #expect(state.triggerBreak() == .sendBreak(read: true))
        #expect(state.markerReceived() == .sendMarker(read: false))
        let cancel = state.backendErrorReceived(.userRequestedCancel(cursorID: 1))
        #expect(cancel == .failStatement(promise, with: .statementCancelled, cleanupContext: nil))
    }

    /// Cancel via ``OracleConnection/cancel()`` while a row stream
    /// is mid-flight delegates to the existing
    /// ``cancelStatementStream``-equivalent path — the row stream is
    /// failed locally and a single TNS RESET marker is sent.
    @Test func breakCancellationFromStreaming() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)
        let query: OracleStatement = "SELECT level FROM dual CONNECT BY level <= 10000000"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "LEVEL", dataType: .number, dataTypeSize: 0,
                precision: 11, scale: 0, bufferSize: 22,
                nullsAllowed: true, typeScheme: nil, typeName: nil,
                domainSchema: nil, domainName: nil,
                annotations: [:], vectorDimensions: nil, vectorFormat: nil
            )
        ])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = StatementResult(value: .describeInfo(describeInfo.columns))

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)
        #expect(state.rowHeaderReceived(rowHeader) == .succeedStatement(promise, result))
        #expect(state.rowDataReceived(.init(1), capabilities: .init()) == .wait)

        // Trigger break mid-stream — should fail the stream with
        // `.statementCancelled` and `clientCancelled: true`.
        #expect(
            state.triggerBreak()
                == .forwardStreamError(
                    .statementCancelled, read: false, cursorID: nil, clientCancelled: true
                )
        )
        // Connection-level follow-up sends a single RESET marker.
        #expect(state.statementStreamCancelled() == .sendMarker(read: true))
    }

    /// `triggerBreak()` is a no-op when no statement is in flight
    /// (e.g. `.readyForStatement`). The follow-up command can run
    /// immediately.
    @Test func breakOnIdleConnectionIsNoOp() throws {
        var state = ConnectionStateMachine.readyForStatement()
        #expect(state.triggerBreak() == .wait)
    }

    /// A second ``triggerBreak`` while the first is still in flight
    /// is idempotent — it does not double-send markers.
    @Test func breakIsIdempotent() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)
        let query: OracleStatement = "BEGIN dbms_session.sleep(10); END;"
        let queryContext = StatementContext(statement: query, promise: promise)

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.triggerBreak() == .sendBreak(read: true))
        // Second trigger before the server reply must be a no-op.
        #expect(state.triggerBreak() == .wait)
    }

    @Test func cancellationDoesNotCrashOnBitVector() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "SELECT 1 AS id FROM dual"
        let queryContext = StatementContext(statement: query, promise: promise)

        let describeInfo = DescribeInfo(columns: [
            .init(
                name: "ID",
                dataType: .number,
                dataTypeSize: 0,
                precision: 11,
                scale: 0,
                bufferSize: 22,
                nullsAllowed: true,
                typeScheme: nil,
                typeName: nil,
                domainSchema: nil,
                domainName: nil,
                annotations: [:],
                vectorDimensions: nil,
                vectorFormat: nil
            )
        ])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = StatementResult(value: .describeInfo(describeInfo.columns))

        var state = ConnectionStateMachine.readyForStatement()
        #expect(
            state.enqueue(task: .statement(queryContext))
                == .sendExecute(queryContext, nil, cursorID: 0, requiresDefine: false, noPrefetch: false)
        )
        #expect(state.describeInfoReceived(describeInfo) == .wait)
        #expect(state.rowHeaderReceived(rowHeader) == .succeedStatement(promise, result))
        #expect(state.rowDataReceived(.init(1), capabilities: .init()) == .wait)
        #expect(
            state.cancelStatementStream()
                == .forwardStreamError(
                    .statementCancelled, read: false, cursorID: nil, clientCancelled: true))
        #expect(state.bitVectorReceived(.init(columnsCountSent: 1, bitVector: [])) == .wait)
        #expect(state.statementStreamCancelled() == .sendMarker(read: true))
    }
}
