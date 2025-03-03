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

#if compiler(>=6.0)
    import NIOCore
    import NIOEmbedded
    import Testing

    @testable import OracleNIO

    @Suite struct StatementStateMachineTests {
        @Test func queryWithoutDataRowsHappyPath() throws {
            let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
            promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
            let query: OracleStatement = "DELETE FROM table"
            let queryContext = StatementContext(statement: query, promise: promise)

            let result = StatementResult(value: .noRows(affectedRows: 0))
            let backendError = OracleBackendMessage.BackendError(
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
                state.backendErrorReceived(.noData) == .forwardStreamComplete([row1], cursorID: 1, affectedRows: 1))
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
            let backendError = OracleBackendMessage.BackendError(
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
            #expect(state.bitVectorReceived(.init(columnsCountSent: 1, bitVector: nil)) == .wait)
            #expect(state.statementStreamCancelled() == .sendMarker(read: true))
        }
    }
#endif
