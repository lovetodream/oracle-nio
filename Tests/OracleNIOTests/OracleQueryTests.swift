//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import XCTest

@testable import OracleNIO

final class OracleQueryTests: XCTestCase {
    func testDebugDescriptionWithLongBindDoesNotCrash() {
        let string = "Hello World"
        let null: Int? = nil
        let id: Int? = 1
        let buffer = ByteBuffer(repeating: 150, count: 300)  //  > 255
        let idReturnBind = OracleRef(dataType: .number, isReturnBind: true)

        let query: OracleQuery = """
            INSERT INTO foo (id, title, something, data) SET (\(id), \(string), \(null), \(buffer)) RETURNING id INTO \(idReturnBind)
            """

        XCTAssertEqual(
            query.sql,
            "INSERT INTO foo (id, title, something, data) SET (:0, :1, :2, :3) RETURNING id INTO :4"
        )

        var expected = ByteBuffer()
        expected.writeInteger(UInt8(2))
        expected.writeBytes([
            193,  // exponent & +/- indicator
            2,  // actual value + 1
        ])

        expected.writeInteger(UInt8(string.utf8.count))
        expected.writeString(string)

        expected.writeInteger(UInt8(0))

        expected.writeInteger(UInt8(254))  // long length indicator
        expected.writeMultipleIntegers(
            UInt8(2),  // Int length
            UInt16(300)
        )  // chunk length
        expected.writeRepeatingByte(150, count: 300)

        expected.writeInteger(UInt8(0))

        //  just check if the string is there
        XCTAssertFalse(String(reflecting: query).isEmpty)
        XCTAssertEqual(query.binds.bytes, expected)
    }
}
