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
import XCTest

@testable import OracleNIO

private typealias RowData = OracleBackendMessage.RowData

final class RowDataTests: XCTestCase {

    func testProcessVectorColumnDataRequestsMissingData() {
        let type = OracleDataType.vector

        var buffer = ByteBuffer(bytes: [
            1, 1,  // length
            0,  // size
            0,  // chunk size
            1,  // value (partial)
        ])
        XCTAssertThrowsError(
            try RowData.decode(from: &buffer, context: .init(columns: type)),
            expected: MissingDataDecodingError.Trigger()
        )

        buffer = ByteBuffer(bytes: [
            1, 1,  // length
            0,  // size
            0,  // chunk size
            1, 1,  // value
            1,  // locator (partial)
        ])
        XCTAssertThrowsError(
            try RowData.decode(from: &buffer, context: .init(columns: type)),
            expected: MissingDataDecodingError.Trigger()
        )
    }

    func testProcessObjectColumnDataRequestsMissingData() throws {
        let type = OracleDataType.object

        var buffer = ByteBuffer(bytes: [1, 1])  // type oid
        XCTAssertThrowsError(
            try RowData.decode(from: &buffer, context: .init(columns: type)),
            expected: MissingDataDecodingError.Trigger()
        )

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1,  // oid
        ])
        XCTAssertThrowsError(
            try RowData.decode(from: &buffer, context: .init(columns: type)),
            expected: MissingDataDecodingError.Trigger()
        )

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1, 0,  // oid
            1, 1,  // snapshot
        ])
        XCTAssertThrowsError(
            try RowData.decode(from: &buffer, context: .init(columns: type)),
            expected: MissingDataDecodingError.Trigger()
        )

        buffer = ByteBuffer(bytes: [
            1, 1, 0,  // type oid
            1, 1, 0,  // oid
            1, 1, 0,  // snapshot
            0,  // version
            0,  // data length
            0,  // flags
        ])
        XCTAssertNoThrow(
            try RowData.decode(from: &buffer, context: .init(columns: type))
        )
    }

    func testProcessLOBColumnDataRequestsMissingData() throws {
        let type = OracleDataType.blob

        var buffer = ByteBuffer(bytes: [
            1, 1,  // length
            1, 1,  // size
            1, 1,  // chunk size
            2, 0,  // locator (partial)
        ])
        XCTAssertThrowsError(
            try RowData.decode(from: &buffer, context: .init(columns: type)),
            expected: MissingDataDecodingError.Trigger()
        )

        buffer = ByteBuffer(bytes: [
            1, 1,  // length
            1, 1,  // size
            1, 1,  // chunk size
            1, 0,  // locator
        ])
        XCTAssertNoThrow(
            try RowData.decode(from: &buffer, context: .init(columns: type))
        )

        buffer = ByteBuffer(bytes: [0])
        XCTAssertNoThrow(
            try RowData.decode(from: &buffer, context: .init(columns: type))
        )
    }
}
