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

extension ByteBuffer {
    mutating func readSB2() -> Int16? {
        self.readSignedMagnitude(maxLength: 2).map { Int16(truncatingIfNeeded: $0) }
    }

    mutating func throwingReadSB2(
        file: String = #fileID, line: Int = #line
    ) throws -> Int16 {
        try self.readSB2().value(
            or: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<Int8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        )
    }

    mutating func readSB4() -> Int32? {
        self.readSignedMagnitude(maxLength: 4).map { Int32(truncatingIfNeeded: $0) }
    }

    mutating func readSB8() -> Int64? {
        self.readSignedMagnitude(maxLength: 8)
    }

    /// Reads a signed integer in Oracle's variable-length encoding: a length byte whose high bit (`0x80`) marks
    /// a negative value, followed by the magnitude in big-endian order in as many bytes as the length says
    /// (any length up to `maxLength`, see `_get_int_length_and_sign` in python-oracledb).
    ///
    /// - Returns: `nil` if more data is required to decode the value.
    private mutating func readSignedMagnitude(maxLength: UInt8) -> Int64? {
        guard let lengthByte = self.readInteger(as: UInt8.self) else { return nil }
        let length = lengthByte & 0x7f
        guard length <= maxLength else {
            preconditionFailure("Invalid length \(length) for a signed integer of at most \(maxLength) bytes")
        }
        guard self.readableBytes >= Int(length) else { return nil }
        var magnitude: UInt64 = 0
        for _ in 0..<length {
            magnitude = magnitude << 8 | UInt64(self.readInteger(as: UInt8.self).unsafelyUnwrapped)
        }
        let value = Int64(truncatingIfNeeded: magnitude)
        return lengthByte & 0x80 != 0 ? 0 &- value : value
    }

    mutating func throwingReadSB8(
        file: String = #fileID, line: Int = #line
    ) throws -> Int64 {
        try self.readSB8().value(
            or: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<Int8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        )
    }

    mutating func throwingSkipSB4(file: String = #fileID, line: Int = #line) throws {
        try throwingSkipBytes(4, file: file, line: line)
    }
}
