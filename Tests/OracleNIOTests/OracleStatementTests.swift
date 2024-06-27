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

final class OracleStatementTests: XCTestCase {
    func testDebugDescriptionWithLongBindDoesNotCrash() {
        let string = "Hello World"
        let null: Int? = nil
        let id: Int? = 1
        let buffer = ByteBuffer(repeating: 150, count: 300)  //  > 255
        let idReturnBind = OracleRef(dataType: .number, isReturnBind: true)

        let query: OracleStatement = """
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

    func testBindsAreStored() throws {
        let bind = ByteBuffer(bytes: [UInt8](repeating: 42, count: 50))

        let query1: OracleStatement = "INSERT INTO table (col) VALUES \(bind)"
        XCTAssertGreaterThan(query1.binds.bytes.readableBytes, 0)
        XCTAssertEqual(query1.binds.longBytes.readableBytes, 0)

        var query2: OracleStatement = "INSERT INTO table (col) VALUES :1"
        query2.binds.appendUnprotected(bind, context: .default, bindName: "1")
        XCTAssertGreaterThan(query2.binds.bytes.readableBytes, 0)
        XCTAssertEqual(query2.binds.longBytes.readableBytes, 0)

        let throwingBind = ThrowingByteBuffer(bind)

        let query3: OracleStatement = try "INSERT INTO table (col) VALUES \(throwingBind)"
        XCTAssertGreaterThan(query3.binds.bytes.readableBytes, 0)
        XCTAssertEqual(query3.binds.longBytes.readableBytes, 0)

        var query4: OracleStatement = "INSERT INTO table (col) VALUES :1"
        try query4.binds.appendUnprotected(throwingBind, context: .default, bindName: "1")
        XCTAssertGreaterThan(query4.binds.bytes.readableBytes, 0)
        XCTAssertEqual(query4.binds.longBytes.readableBytes, 0)

        let bindRef = OracleRef(bind)
        let query5: OracleStatement = "INSERT INTO table (col) VALUES \(bindRef)"
        XCTAssertGreaterThan(query5.binds.bytes.readableBytes, 0)
        XCTAssertEqual(query5.binds.longBytes.readableBytes, 0)
    }

    func testLongValuesAreStoredInDedicatedBuffer() throws {
        let long = ByteBuffer(bytes: [UInt8](repeating: 42, count: 50000))

        let query1: OracleStatement = "INSERT INTO table (col) VALUES \(long)"
        XCTAssertEqual(query1.binds.bytes.readableBytes, 0)
        XCTAssertGreaterThan(query1.binds.longBytes.readableBytes, 0)

        var query2: OracleStatement = "INSERT INTO table (col) VALUES :1"
        query2.binds.appendUnprotected(long, context: .default, bindName: "1")
        XCTAssertEqual(query2.binds.bytes.readableBytes, 0)
        XCTAssertGreaterThan(query2.binds.longBytes.readableBytes, 0)

        let throwingLong = ThrowingByteBuffer(long)

        let query3: OracleStatement = try "INSERT INTO table (col) VALUES \(throwingLong)"
        XCTAssertEqual(query3.binds.bytes.readableBytes, 0)
        XCTAssertGreaterThan(query3.binds.longBytes.readableBytes, 0)

        var query4: OracleStatement = "INSERT INTO table (col) VALUES :1"
        try query4.binds.appendUnprotected(throwingLong, context: .default, bindName: "1")
        XCTAssertEqual(query4.binds.bytes.readableBytes, 0)
        XCTAssertGreaterThan(query4.binds.longBytes.readableBytes, 0)

        let longRef = OracleRef(long)
        let query5: OracleStatement = "INSERT INTO table (col) VALUES \(longRef)"
        XCTAssertEqual(query5.binds.bytes.readableBytes, 0)
        XCTAssertGreaterThan(query5.binds.longBytes.readableBytes, 0)
    }
}

// Testing utility, because we do not have a throwing encodable, luckily :)
struct ThrowingByteBuffer: OracleThrowingDynamicTypeEncodable {
    let oracleType: OracleNIO.OracleDataType = .raw

    var size: UInt32 { UInt32(self.base.readableBytes) }

    private let base: ByteBuffer

    init(_ base: ByteBuffer) {
        self.base = base
    }

    func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) throws {
        self.base._encodeRaw(into: &buffer, context: context)
    }

    func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout NIOCore.ByteBuffer,
        context: OracleNIO.OracleEncodingContext<JSONEncoder>
    ) throws {
        preconditionFailure()
    }
}
