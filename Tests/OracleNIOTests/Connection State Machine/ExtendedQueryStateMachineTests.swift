// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import XCTest
import NIOCore
import NIOEmbedded
@testable import OracleNIO

final class ExtendedQueryStateMachineTests: XCTestCase {
    var promise: EventLoopPromise<OracleRowStream>!
    var queryContext: ExtendedQueryContext!

    override func setUp() {
        super.setUp()

        self.promise = EmbeddedEventLoop().makePromise(of: OracleRowStream.self)
        self.queryContext = .init(query: "SELECT 1 AS id FROM DUAL", options: .init(), logger: .oracleTest, promise: promise)
    }

    func testCancellationOnlyOnce() throws {
        let describeInfo = DescribeInfo(columns: [.init(
            name: "ID",
            dataType: .number,
            dataTypeSize: 0,
            precision: 11,
            scale: 0,
            bufferSize: 22,
            nullsAllowed: true
        )])
        let rowHeader = OracleBackendMessage.RowHeader()
        let result = QueryResult(value: .describeInfo(describeInfo.columns), logger: .oracleTest)
        let rowData = try Array(hexString: "05 c4 02 03 31 23 07 05 c4 02 03 31 23 08 01 06 04 bd 33 f6 cf 01 0f 01 03 00 00 00 00 01 01 00 01 0b 0b 80 00 00 00 3d 3c 3c 80 00 00 00 01 a3 00 04 01 01 01 04 01 02 00 00 00 01 03 00 03 00 00 00 00 00 00 00 00 00 00 00 00 03 00 01 01 00 00 00 00 00 01 02".replacingOccurrences(of: " ", with: ""))
        let backendError = OracleBackendMessage.BackendError(number: 1013, cursorID: 3, position: 0, rowCount: 2, isWarning: false, message: "ORA-01013: user requested cancel of current operation\n", rowID: nil, batchErrors: [])

        var state = ConnectionStateMachine.readyForQuery()
        XCTAssertEqual(state.enqueue(task: .extendedQuery(self.queryContext)), .sendExecute(self.queryContext, nil))
        XCTAssertEqual(state.describeInfoReceived(describeInfo), .wait)
        XCTAssertEqual(state.rowHeaderReceived(rowHeader), .succeedQuery(self.promise, result))
        XCTAssertEqual(state.rowDataReceived(.init(slice: .init(bytes: rowData)), capabilities: .init()), .sendFetch(self.queryContext))
        XCTAssertEqual(state.cancelQueryStream(), .forwardStreamError(.queryCancelled, read: false, cursorID: nil, clientCancelled: true))
        XCTAssertEqual(state.markerReceived(), .sendMarker)
        XCTAssertEqual(state.backendErrorReceived(backendError), .fireEventReadyForQuery)
    }
}
