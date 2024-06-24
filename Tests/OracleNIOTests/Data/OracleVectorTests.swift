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

final class OracleVectorTests: XCTestCase {
    func testVectorInt8() {
        let vector1 = OracleVectorInt8()
        XCTAssertEqual(vector1, [])
        let vector2: OracleVectorInt8 = [1, 2, 3]
        XCTAssertEqual(vector2.count, 3)
        var vector3 = OracleVectorInt8([1, 2, 2])
        XCTAssertNotEqual(vector2, vector3)
        XCTAssertEqual(vector3[2], 2)
        vector3[2] = 3
        XCTAssertEqual(vector2, vector3)
    }

    func testVectorFloat32() {
        let vector1 = OracleVectorFloat32()
        XCTAssertEqual(vector1, [])
        let vector2: OracleVectorFloat32 = [1.1, 2.2, 3.3]
        XCTAssertEqual(vector2.count, 3)
        var vector3 = OracleVectorFloat32([1.1, 2.2, 3.2])
        XCTAssertNotEqual(vector2, vector3)
        XCTAssertEqual(vector3[2], 3.2)
        vector3[2] = 3.3
        XCTAssertEqual(vector2, vector3)
    }

    func testVectorFloat64() {
        let vector1 = OracleVectorFloat64()
        XCTAssertEqual(vector1, [])
        let vector2: OracleVectorFloat64 = [1.1, 2.2, 3.3]
        XCTAssertEqual(vector2.count, 3)
        var vector3 = OracleVectorFloat64([1.1, 2.2, 3.2])
        XCTAssertNotEqual(vector2, vector3)
        XCTAssertEqual(vector3[2], 3.2)
        vector3[2] = 3.3
        XCTAssertEqual(vector2, vector3)
    }

    func testDecodingMalformedVectors() {
        // not a vector
        var buffer = ByteBuffer(bytes: [0])
        XCTAssertThrowsError(
            try OracleVectorInt8(from: &buffer, type: .raw, context: .default),
            expected: OracleDecodingError.Code.typeMismatch
        )
        XCTAssertThrowsError(
            try OracleVectorInt8(from: &buffer, type: .vector, context: .default),
            expected: OracleDecodingError.Code.typeMismatch
        )

        // invalid version
        buffer = ByteBuffer(bytes: [UInt8(Constants.TNS_VECTOR_MAGIC_BYTE), 42])
        XCTAssertThrowsError(
            try OracleVectorInt8(from: &buffer, type: .vector, context: .default),
            expected: OracleDecodingError.Code.failure
        )

        // wrong type
        buffer = ByteBuffer(bytes: [
            UInt8(Constants.TNS_VECTOR_MAGIC_BYTE),
            UInt8(Constants.TNS_VECTOR_VERSION),
            0, 0,  // flags
            UInt8(Constants.VECTOR_FORMAT_FLOAT64),
        ])
        XCTAssertThrowsError(
            try OracleVectorInt8(from: &buffer, type: .vector, context: .default),
            expected: OracleDecodingError.Code.typeMismatch
        )
    }
}

// swift-format-ignore: AlwaysUseLowerCamelCase
func XCTAssertThrowsError<T, E: Error & Equatable>(
    _ expression: @autoclosure () throws -> T,
    expected: E,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        XCTAssertEqual(error as? E, expected, file: file, line: line)
    }
}
