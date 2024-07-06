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
import XCTest

@testable import OracleNIO

final class StatementStateMachineTests: XCTestCase {
    func testQueryWithoutDataRowsHappyPath() throws {
        let promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        promise.fail(OracleSQLError.uncleanShutdown)  // we don't care about the error at all.
        let query: OracleStatement = "DELETE FROM table"
        let queryContext = StatementContext(statement: query, promise: promise)

        let result = StatementResult(value: .noRows)
        let backendError = OracleBackendMessage.BackendError(
            number: 0, cursorID: 6, position: 0, rowCount: 0, isWarning: false, message: nil,
            rowID: nil, batchErrors: [])

        var state = ConnectionStateMachine.readyForStatement()
        XCTAssertEqual(
            state.enqueue(task: .statement(queryContext)), .sendExecute(queryContext, nil))
        XCTAssertEqual(state.backendErrorReceived(backendError), .succeedStatement(promise, result))
        XCTAssertEqual(state.channelReadComplete(), .wait)
        XCTAssertEqual(state.readEventCaught(), .read)
    }

    func testQueryWithDataRowsHappyPath() throws {
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
        XCTAssertEqual(
            state.enqueue(task: .statement(queryContext)), .sendExecute(queryContext, nil))
        XCTAssertEqual(state.describeInfoReceived(describeInfo), .wait)
        XCTAssertEqual(state.rowHeaderReceived(rowHeader), .succeedStatement(promise, result))
        let row1: DataRow = .makeTestDataRow(1)
        XCTAssertEqual(state.rowDataReceived(.init(1), capabilities: .init()), .wait)
        XCTAssertEqual(state.queryParameterReceived(.init()), .wait)
        XCTAssertEqual(
            state.backendErrorReceived(.noData), .forwardStreamComplete([row1], cursorID: 1))
    }

    func testCancellationCompletesQueryOnlyOnce() throws {
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
        XCTAssertEqual(
            state.enqueue(task: .statement(queryContext)), .sendExecute(queryContext, nil))
        XCTAssertEqual(state.describeInfoReceived(describeInfo), .wait)
        XCTAssertEqual(state.rowHeaderReceived(rowHeader), .succeedStatement(promise, result))
        XCTAssertEqual(
            state.rowDataReceived(.init(1_024_834), capabilities: .init()),
            .wait)
        XCTAssertEqual(
            state.rowDataReceived(.init(1_024_834), capabilities: .init()),
            .wait)
        XCTAssertEqual(state.queryParameterReceived(.init()), .wait)
        XCTAssertEqual(state.backendErrorReceived(.sendFetch), .sendFetch(queryContext))
        XCTAssertEqual(
            state.cancelStatementStream(),
            .forwardStreamError(
                .statementCancelled, read: false, cursorID: nil, clientCancelled: true))
        XCTAssertEqual(state.markerReceived(), .sendMarker(read: false))
        XCTAssertEqual(state.backendErrorReceived(backendError), .fireEventReadyForStatement)
    }

    func testCancellationFiresRead() throws {
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
        XCTAssertEqual(
            state.enqueue(task: .statement(queryContext)), .sendExecute(queryContext, nil))
        XCTAssertEqual(state.describeInfoReceived(describeInfo), .wait)
        XCTAssertEqual(state.rowHeaderReceived(rowHeader), .succeedStatement(promise, result))
        XCTAssertEqual(
            state.rowDataReceived(.init(1_024_834), capabilities: .init()),
            .wait)
        XCTAssertEqual(
            state.rowDataReceived(.init(1_024_834), capabilities: .init()),
            .wait)
        XCTAssertEqual(state.queryParameterReceived(.init()), .wait)
        XCTAssertEqual(state.backendErrorReceived(.sendFetch), .sendFetch(queryContext))
        XCTAssertEqual(
            state.cancelStatementStream(),
            .forwardStreamError(
                .statementCancelled, read: false, cursorID: nil, clientCancelled: true))
        XCTAssertEqual(state.statementStreamCancelled(), .sendMarker(read: true))
    }
}

extension OracleBackendMessage.RowData {
    init<T: OracleEncodable>(_ elements: T...) {
        var columns: [OracleBackendMessage.RowData.ColumnStorage] = []
        for element in elements {
            var buffer = ByteBuffer()
            element._encodeRaw(into: &buffer, context: .default)
            columns.append(.data(buffer))
        }
        self.init(columns: columns)
    }
}

extension OracleBackendMessage.BackendError {
    static let noData = OracleBackendMessage.BackendError(
        number: 1403,
        cursorID: 1,
        position: 20,
        rowCount: 1,
        isWarning: false,
        message: "ORA-01403: no data found\n",
        rowID: nil,
        batchErrors: []
    )

    static let sendFetch = OracleBackendMessage.BackendError(
        number: 0,
        cursorID: 3,
        position: 0,
        rowCount: 2,
        isWarning: false,
        message: nil,
        rowID: nil,
        batchErrors: []
    )
}
