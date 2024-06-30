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
        let rowData = try Array(
            hexString:
                "02 c1 02 08 01 06 03 24 13 32 00 01 01 00 00 00 00 01 01 00 01 0b 0b 80 00 00 00 3d 3c 3c 80 00 00 00 01 a3 00 04 01 01 01 37 01 01 02 05 7b 00 00 01 01 01 14 03 00 00 00 00 00 00 00 00 00 00 00 00 03 00 01 01 00 00 00 00 02 05 7b 01 01 00 00 19 4f 52 41 2d 30 31 34 30 33 3a 20 6e 6f 20 64 61 74 61 20 66 6f 75 6e 64 0a"
                .replacingOccurrences(of: " ", with: ""))

        var state = ConnectionStateMachine.readyForStatement()
        XCTAssertEqual(
            state.enqueue(task: .statement(queryContext)), .sendExecute(queryContext, nil))
        XCTAssertEqual(state.describeInfoReceived(describeInfo), .wait)
        XCTAssertEqual(state.rowHeaderReceived(rowHeader), .succeedStatement(promise, result))
        let row1: DataRow = .makeTestDataRow(1)
        XCTAssertEqual(
            state.rowDataReceived(.init(slice: .init(bytes: rowData)), capabilities: .init()),
            .forwardStreamComplete([row1], cursorID: 1))
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
        let rowData = try Array(
            hexString:
                "05 c4 02 03 31 23 07 05 c4 02 03 31 23 08 01 06 04 bd 33 f6 cf 01 0f 01 03 00 00 00 00 01 01 00 01 0b 0b 80 00 00 00 3d 3c 3c 80 00 00 00 01 a3 00 04 01 01 01 04 01 02 00 00 00 01 03 00 03 00 00 00 00 00 00 00 00 00 00 00 00 03 00 01 01 00 00 00 00 00 01 02"
                .replacingOccurrences(of: " ", with: ""))
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
            state.rowDataReceived(.init(slice: .init(bytes: rowData)), capabilities: .init()),
            .sendFetch(queryContext))
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
        let rowData = try Array(
            hexString:
                "05 c4 02 03 31 23 07 05 c4 02 03 31 23 08 01 06 04 bd 33 f6 cf 01 0f 01 03 00 00 00 00 01 01 00 01 0b 0b 80 00 00 00 3d 3c 3c 80 00 00 00 01 a3 00 04 01 01 01 04 01 02 00 00 00 01 03 00 03 00 00 00 00 00 00 00 00 00 00 00 00 03 00 01 01 00 00 00 00 00 01 02"
                .replacingOccurrences(of: " ", with: ""))

        var state = ConnectionStateMachine.readyForStatement()
        XCTAssertEqual(
            state.enqueue(task: .statement(queryContext)), .sendExecute(queryContext, nil))
        XCTAssertEqual(state.describeInfoReceived(describeInfo), .wait)
        XCTAssertEqual(state.rowHeaderReceived(rowHeader), .succeedStatement(promise, result))
        XCTAssertEqual(
            state.rowDataReceived(.init(slice: .init(bytes: rowData)), capabilities: .init()),
            .sendFetch(queryContext))
        XCTAssertEqual(
            state.cancelStatementStream(),
            .forwardStreamError(
                .statementCancelled, read: false, cursorID: nil, clientCancelled: true))
        XCTAssertEqual(state.statementStreamCancelled(), .sendMarker(read: true))
    }

    func testProcessVectorColumnDataRequestsMissingData() {
        let state = StatementStateMachine(
            statementContext: .init(statement: "")
        )
        let type = OracleDataType.vector

        var buffer = ByteBuffer(bytes: [
            1, 1,  // length
            0,  // size
            0,  // chunk size
            1,  // value (partial)
        ])
        try XCTAssertNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            ))

        buffer = ByteBuffer(bytes: [
            1, 1,  // length
            0,  // size
            0,  // chunk size
            1, 1,  // value
            1,  // locator (partial)
        ])
        try XCTAssertNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            ))
    }

    func testProcessObjectColumnDataRequestsMissingData() throws {
        let state = StatementStateMachine(
            statementContext: .init(statement: "")
        )
        let type = OracleDataType.object

        var buffer = ByteBuffer(bytes: [1, 1])  // type oid
        try XCTAssertNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            ))

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1,  // oid
        ])
        try XCTAssertNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            ))

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1, 0,  // oid
            1, 1,  // snapshot
        ])
        try XCTAssertNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            ))

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1, 0,  // oid
            1, 1, 0,  // snapshot
            0,  // version
            0,  // data length
            0,  // flags
        ])
        try XCTAssertNotNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            ))
    }

    func testProcessLOBColumnDataRequestsMissingData() throws {
        let state = StatementStateMachine(
            statementContext: .init(statement: "")
        )
        let type = OracleDataType.blob

        var buffer = ByteBuffer(bytes: [
            1, 1,  // length
            1, 1,  // size
            1, 1,  // chunk size
            2, 0,  // locator (partial)
        ])
        try XCTAssertNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            )
        )

        buffer = ByteBuffer(bytes: [
            1, 1,  // length
            1, 1,  // size
            1, 1,  // chunk size
            1, 0,  // locator
        ])
        try XCTAssertNotNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            )
        )

        buffer = ByteBuffer(bytes: [0])
        try XCTAssertNotNil(
            state.processColumnData(
                from: &buffer,
                oracleType: type._oracleType,
                csfrm: type.csfrm,
                bufferSize: 1,
                capabilities: .init()
            )
        )
    }
}
