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

@Suite struct OracleNumericTests {
    private func roundTripInt<T: FixedWidthInteger & LosslessStringConvertible>(
        _ value: T, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(value, into: &buffer)
        let decoded: T = try OracleNumeric.parseInteger(from: &buffer)
        #expect(decoded == value, "\(value)", sourceLocation: sourceLocation)
    }

    private func roundTripFloat(
        _ value: Double, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(value, into: &buffer)
        let decoded: Double = try OracleNumeric.parseFloat(from: &buffer)
        #expect(decoded == value, "\(value)", sourceLocation: sourceLocation)
    }

    @Test func integerRoundTrip() throws {
        let values: [Int] = [
            0, 1, -1, 9, -9, 10, -10, 42, -42, 100, -100,
            1_000_000, -1_000_000, 123_456_789, -987_654_321,
            .max,
        ]
        for value in values {
            try roundTripInt(value)
        }
    }

    // `Int.min`/`Int64.min` are deliberately excluded from `integerRoundTrip` above and
    // tested in isolation here: decoding them currently traps with a signed integer
    // overflow (pre-existing bug in `parseInteger`'s positive-then-negate accumulation,
    // found while adding this test - see the OracleNumeric decode rewrite that fixes it).
    @Test func signedIntegerMinRoundTrip() throws {
        try roundTripInt(Int.min)
        try roundTripInt(Int64.min)
        try roundTripInt(Int8.min)
    }

    @Test func unsignedIntegerRoundTrip() throws {
        try roundTripInt(UInt(0))
        try roundTripInt(UInt64.max)
        try roundTripInt(UInt8.max)
    }

    @Test func negativeUnsignedIntegerThrows() throws {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(-1, into: &buffer)
        #expect(throws: (any Error).self) {
            let _: UInt = try OracleNumeric.parseInteger(from: &buffer)
        }
    }

    @Test func integerWithFractionThrows() throws {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(1.5, into: &buffer)
        #expect(throws: (any Error).self) {
            let _: Int = try OracleNumeric.parseInteger(from: &buffer)
        }
    }

    @Test func floatRoundTrip() throws {
        let values: [Double] = [
            0, 1, -1, 1.001, -1.001, 420.081_500_42, -24.42,
            100.0, -100.0, 1e10, -1e10,
            0.1, -0.1, 9999.9999, 0.000123, -0.000123,
        ]
        for value in values {
            try roundTripFloat(value)
        }
    }

    @Test func zeroEncodesToSingleByte() {
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(Int(0), into: &buffer)
        #expect(buffer.readableBytes == 1)
    }

    // `Double`/`Float` switch `description` to scientific notation (e.g. "1e+20",
    // "1.5e-10") outside roughly 1e-5...1e16. `encodeNumeric`'s exponent parsing used
    // to (a) always compute an exponent of 0 (an off-by-`position` slicing bug) and,
    // even with that fixed, (b) interpret the ASCII exponent digits as raw big-endian
    // bytes instead of decimal digits - silently corrupting every such value on the wire.
    @Test func scientificNotationFloatRoundTrip() throws {
        let values: [Double] = [
            1e20, -1e20, 1e16, 1.5e23, -1.5e23, 1e-5, -1e-5, 1.23e-5, 5e-10, -5e-10,
        ]
        for value in values {
            try roundTripFloat(value)
        }
    }

    @Test func scientificNotationExponentIsParsedAsDecimal() throws {
        // "1e+20" must decode back to 1e20, not to some value derived from
        // interpreting the ASCII bytes "20" as raw binary (0x32, 0x30).
        var buffer = ByteBuffer()
        OracleNumeric.encodeNumeric(1e20, into: &buffer)
        let decoded: Double = try OracleNumeric.parseFloat(from: &buffer)
        #expect(decoded == 1e20)
    }

    // `decimalPointIndex` can be negative (small-magnitude values); Swift's `%`
    // returns a negative remainder for a negative dividend (`-9 % 2 == -1`), so
    // checking `decimalPointIndex % 2 == 1` silently missed every negative-odd case,
    // skipping a needed zero-prepend and making two distinct magnitudes (e.g. 5e-10
    // and 5e-9) collide onto the same wire bytes.
    @Test func negativeOddDecimalPointIndexRoundTrip() throws {
        let values: [Double] = [
            5e-10, 5e-9, 5e-8, 1e-4, 0.01, -0.01, 0.000123, -0.000123,
        ]
        for value in values {
            try roundTripFloat(value)
        }
    }

    @Test func distinctSmallMagnitudesDoNotCollideOnWire() throws {
        var lhsBuffer = ByteBuffer()
        OracleNumeric.encodeNumeric(5e-10, into: &lhsBuffer)
        var rhsBuffer = ByteBuffer()
        OracleNumeric.encodeNumeric(5e-9, into: &rhsBuffer)
        #expect(lhsBuffer != rhsBuffer)
    }
}
