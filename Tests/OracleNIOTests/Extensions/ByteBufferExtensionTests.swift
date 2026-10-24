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
import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct ByteBufferExtensionTests {

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

    @Test func skipRawBytesChunked() {
        var buffer = empty
        #expect(buffer.skipRawBytesChunked() == false)
        buffer = normalLengthMissingBytes
        #expect(buffer.skipRawBytesChunked() == false)
        buffer = zeroLength
        #expect(buffer.skipRawBytesChunked() == true)
        buffer = normalLength
        #expect(buffer.skipRawBytesChunked() == true)

        buffer = longLengthWithoutData
        #expect(buffer.skipRawBytesChunked() == false)
        buffer = longLengthWithoutEnoughData
        #expect(buffer.skipRawBytesChunked() == false)
        buffer = longLengthWithoutEnoughDataOnSecondLength
        #expect(buffer.skipRawBytesChunked() == false)
        buffer = longLengthWithoutEnoughDataAfterSecondLength
        #expect(buffer.skipRawBytesChunked() == false)
        buffer = longLengthData
        #expect(buffer.skipRawBytesChunked() == true)
    }

    @Test func oracleSpecificLengthPrefixedSlice() {
        var buffer = empty
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() == nil)
        buffer = normalLengthMissingBytes
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() == nil)
        buffer = zeroLength
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() != nil)
        buffer = normalLength
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() != nil)

        buffer = longLengthWithoutData
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() == nil)
        buffer = longLengthWithoutEnoughData
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() == nil)
        buffer = longLengthWithoutEnoughDataOnSecondLength
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() == nil)
        buffer = longLengthWithoutEnoughDataAfterSecondLength
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() == nil)
        buffer = longLengthData
        #expect(buffer.readOracleSpecificLengthPrefixedSlice() != nil)
    }

    @Test func throwingOracleSpecificLengthPrefixedSlice() {
        var buffer = empty
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(MemoryLayout<UInt8>.size, actual: 0),
            performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() }
        )
        buffer = normalLengthMissingBytes
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(5, actual: 2),
            performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() }
        )
        buffer = zeroLength
        #expect(throws: Never.self, performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() })
        buffer = normalLength
        #expect(throws: Never.self, performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() })

        buffer = longLengthWithoutData
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(MemoryLayout<UInt8>.size, actual: 0),
            performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() }
        )
        buffer = longLengthWithoutEnoughData
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(300, actual: 260),
            performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() }
        )
        buffer = longLengthWithoutEnoughDataOnSecondLength
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(MemoryLayout<UInt8>.size, actual: 0),
            performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() }
        )
        buffer = longLengthWithoutEnoughDataAfterSecondLength
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(2, actual: 0),
            performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() }

        )
        buffer = longLengthData
        #expect(throws: Never.self, performing: { try buffer.throwingReadOracleSpecificLengthPrefixedSlice() })
    }

    @Test func readOracleSliceReturnsNilOnEmptyBuffer() {
        var buffer = ByteBuffer()
        #expect(buffer.readOracleSlice() == nil)
    }

    @Test func throwingSkipUBShouldThrowOnMissingBytes() {
        var buffer = ByteBuffer(bytes: [1])
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(1, actual: 0),
            performing: { try buffer.throwingSkipUB4() }
        )
    }

    @Test func readOSONFailsAppropriately() {
        var sliceMissingBuffer = ByteBuffer(bytes: [1, 40, 0, 0])
        #expect((try? sliceMissingBuffer.throwingReadOSON()) == nil)  // TODO: refactor to throw
        var locatorMissingBuffer = ByteBuffer(bytes: [1, 40, 0, 0, 0])
        #expect((try? locatorMissingBuffer.throwingReadOSON()) == nil)  // TODO: refactor to throw
    }

    @Test func throwingSkipUBThrowsOnMissingLength() {
        var buffer = ByteBuffer()
        #expect(
            throws: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(1, actual: 0),
            performing: { try buffer.throwingSkipUB4() }
        )
    }

    @Test func readUB8DecodesEveryLengthEncoding() {
        var buffer = ByteBuffer(bytes: [0])
        #expect(buffer.readUB8() == 0)

        // high bit on the length byte is a no-op mask, not a sentinel
        buffer = ByteBuffer(bytes: [0x80])
        #expect(buffer.readUB8() == 0)

        buffer = ByteBuffer(bytes: [1, 0x7A])
        #expect(buffer.readUB8() == 0x7A)

        buffer = ByteBuffer(bytes: [2, 0x12, 0x34])
        #expect(buffer.readUB8() == 0x1234)

        buffer = ByteBuffer(bytes: [3, 0x12, 0x34, 0x56])
        #expect(buffer.readUB8() == 0x12_3456)

        buffer = ByteBuffer(bytes: [4, 0x12, 0x34, 0x56, 0x78])
        #expect(buffer.readUB8() == 0x1234_5678)

        buffer = ByteBuffer(bytes: [8, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        #expect(buffer.readUB8() == 0x0102_0304_0506_0708)
    }

    @Test func readUB8ReturnsNilOnTruncatedInput() {
        var buffer = ByteBuffer()
        #expect(buffer.readUB8() == nil)

        buffer = ByteBuffer(bytes: [1])
        #expect(buffer.readUB8() == nil)

        buffer = ByteBuffer(bytes: [2, 0x12])
        #expect(buffer.readUB8() == nil)

        buffer = ByteBuffer(bytes: [3, 0x12, 0x34])
        #expect(buffer.readUB8() == nil)

        buffer = ByteBuffer(bytes: [4, 0x12, 0x34, 0x56])
        #expect(buffer.readUB8() == nil)

        buffer = ByteBuffer(bytes: [8, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        #expect(buffer.readUB8() == nil)
    }
}
