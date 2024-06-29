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

final class ByteBufferExtensionTests: XCTestCase {

    let empty = ByteBuffer()
    let zeroLength = ByteBuffer(bytes: [0])
    let normalLengthMissingBytes = ByteBuffer(bytes: [5, 0, 0])
    let normalLength = ByteBuffer(bytes: [3, 0, 0, 0])
    let longLengthWithoutData = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
    let longLengthWithoutEnoughData: ByteBuffer = {
        var buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 260)
        return buffer
    }()
    let longLengthWithoutEnoughDataOnSecondLength: ByteBuffer = {
        var buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 300)
        buffer.writeInteger(UInt8(1))
        return buffer
    }()
    let longLengthWithoutEnoughDataAfterSecondLength: ByteBuffer = {
        var buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 300)
        buffer.writeUB4(2)
        return buffer
    }()
    let longLengthData: ByteBuffer = {
        var buffer = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
        buffer.writeUB4(300)
        buffer.writeRepeatingByte(0, count: 300)
        buffer.writeUB4(0)
        return buffer
    }()

    func testSkipRawBytesChunked() {
        var buffer = empty
        XCTAssertFalse(buffer.skipRawBytesChunked())
        buffer = normalLengthMissingBytes
        XCTAssertFalse(buffer.skipRawBytesChunked())
        buffer = zeroLength
        XCTAssertTrue(buffer.skipRawBytesChunked())
        buffer = normalLength
        XCTAssertTrue(buffer.skipRawBytesChunked())

        buffer = longLengthWithoutData
        XCTAssertFalse(buffer.skipRawBytesChunked())
        buffer = longLengthWithoutEnoughData
        XCTAssertFalse(buffer.skipRawBytesChunked())
        buffer = longLengthWithoutEnoughDataOnSecondLength
        XCTAssertFalse(buffer.skipRawBytesChunked())
        buffer = longLengthWithoutEnoughDataAfterSecondLength
        XCTAssertFalse(buffer.skipRawBytesChunked())
        buffer = longLengthData
        XCTAssertTrue(buffer.skipRawBytesChunked())
    }

    func testOracleSpecificLengthPrefixedSlice() {
        var buffer = empty
        XCTAssertNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = normalLengthMissingBytes
        XCTAssertNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = zeroLength
        XCTAssertNotNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = normalLength
        XCTAssertNotNil(buffer.readOracleSpecificLengthPrefixedSlice())

        buffer = longLengthWithoutData
        XCTAssertNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = longLengthWithoutEnoughData
        XCTAssertNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = longLengthWithoutEnoughDataOnSecondLength
        XCTAssertNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = longLengthWithoutEnoughDataAfterSecondLength
        XCTAssertNil(buffer.readOracleSpecificLengthPrefixedSlice())
        buffer = longLengthData
        XCTAssertNotNil(buffer.readOracleSpecificLengthPrefixedSlice())
    }

    func testThrowingOracleSpecificLengthPrefixedSlice() {
        var buffer = empty
        XCTAssertThrowsError(
            try buffer.throwingReadOracleSpecificLengthPrefixedSlice(),
            expected:
                OraclePartialDecodingError
                .expectedAtLeastNRemainingBytes(MemoryLayout<UInt8>.size, actual: 0)
        )
        buffer = normalLengthMissingBytes
        XCTAssertThrowsError(
            try buffer.throwingReadOracleSpecificLengthPrefixedSlice(),
            expected:
                OraclePartialDecodingError
                .expectedAtLeastNRemainingBytes(5, actual: 2)
        )
        buffer = zeroLength
        XCTAssertNoThrow(try buffer.throwingReadOracleSpecificLengthPrefixedSlice())
        buffer = normalLength
        XCTAssertNoThrow(try buffer.throwingReadOracleSpecificLengthPrefixedSlice())

        buffer = longLengthWithoutData
        XCTAssertThrowsError(
            try buffer.throwingReadOracleSpecificLengthPrefixedSlice(),
            expected:
                OraclePartialDecodingError
                .expectedAtLeastNRemainingBytes(MemoryLayout<UInt8>.size, actual: 0)
        )
        buffer = longLengthWithoutEnoughData
        XCTAssertThrowsError(
            try buffer.throwingReadOracleSpecificLengthPrefixedSlice(),
            expected:
                OraclePartialDecodingError
                .expectedAtLeastNRemainingBytes(300, actual: 260)
        )
        buffer = longLengthWithoutEnoughDataOnSecondLength
        XCTAssertThrowsError(
            try buffer.throwingReadOracleSpecificLengthPrefixedSlice(),
            expected:
                OraclePartialDecodingError
                .expectedAtLeastNRemainingBytes(MemoryLayout<UInt8>.size, actual: 0)
        )
        buffer = longLengthWithoutEnoughDataAfterSecondLength
        XCTAssertThrowsError(
            try buffer.throwingReadOracleSpecificLengthPrefixedSlice(),
            expected:
                OraclePartialDecodingError
                .expectedAtLeastNRemainingBytes(2, actual: 0)
        )
        buffer = longLengthData
        XCTAssertNoThrow(try buffer.throwingReadOracleSpecificLengthPrefixedSlice())
    }
}
