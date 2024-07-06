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

    /// Returns a `String` containing a detailed hex dump of this buffer.
    /// Intended to be used internally in ``hexDump(format:)``
    /// - parameters:
    ///     - lineOffset: an offset from the beginning of the outer buffer that is being dumped. It's used to print the line offset in hexdump -C format.
    ///     - paddingBefore: the amount of space to pad before the first byte dumped on this line, used in center and right columns.
    ///     - paddingAfter: the amount of sapce to pad after the last byte on this line, used in center and right columns.
    private func _hexDumpLine(lineOffset: Int, paddingBefore: Int = 0, paddingAfter: Int = 0)
        -> String
    {
        // Each line takes 41 visible characters + \n
        var result = ""
        result.reserveCapacity(42)

        // Left column of the hex dump signifies the offset from the beginning of the dumped buffer
        // and is separated from the next column with two spaces.
        result += String(lineOffset, radix: 10, padding: 4)
        result += " : "

        // Center column consists of:
        // - xxd-compatible dump of the first 8 bytes
        // - space
        // - xxd-compatible dump of the rest 8 bytes
        // If there are not enough bytes to dump, the column is padded with space.

        // If there's any padding on the left, apply that first.
        result += String(repeating: " ", count: paddingBefore * 3)

        // Add the central column
        let bytesInCenterColumn = max(8 - paddingBefore, 0)
        for byte in self.readableBytesView.prefix(bytesInCenterColumn) {
            result += String(byte, radix: 16, padding: 2)
            result += " "
        }

        // Pad the resulting center column line to 31 characters.
        result += String(repeating: " ", count: 31 - result.count)

        // Right column renders the 16 bytes line as ASCII characters, or "." if the character is not printable.
        let printableRange = UInt8(ascii: "!")...UInt8(ascii: "~")
        let printableBytes = self.readableBytesView.map {
            printableRange.contains($0) ? $0 : UInt8(ascii: ".")
        }

        result += "|"
        result += String(repeating: " ", count: paddingBefore)
        result += String(decoding: printableBytes, as: UTF8.self)
        result += String(repeating: " ", count: paddingAfter)
        result += String(repeating: " ", count: 40 - result.count)
        result += "|\n"
        return result
    }

    /// Returns a `String` of hexadecimal digits of bytes in the Buffer,
    /// with formatting compatible with output of `hexdump -C`.
    private func hexdumpDetailed() -> String {
        if self.readableBytes == 0 {
            return ""
        }

        var result = ""
        result.reserveCapacity(self.readableBytes / 16 * 42 + 8)

        var buffer = self

        var lineOffset = 0
        while buffer.readableBytes > 0 {
            // Safe to force-unwrap because we're in a loop that guarantees there's at least one byte to read.
            let slice = buffer.readSlice(length: min(8, buffer.readableBytes))!
            result += slice._hexDumpLine(lineOffset: lineOffset)
            lineOffset += slice.readableBytes
        }

        return result
    }

    /// Returns a hex dump of  this `ByteBuffer` in a format similar to other Oracle drivers.
    func oracleHexDump() -> String {
        return self.hexdumpDetailed()
    }
}

extension String {
    /// Creates a `String` from a given `Int` with a given base (`radix`), padded with zeroes to the provided `padding` size.
    ///
    /// - parameters:
    ///     - radix: radix base to use for conversion.
    ///     - padding: the desired length of the resulting string.
    @inlinable
    internal init<Value>(_ value: Value, radix: Int, padding: Int) where Value: BinaryInteger {
        let formatted = String(value, radix: radix, uppercase: true)
        let padding = padding - formatted.count
        if padding < 0 {
            self = String(formatted.dropFirst(abs(padding)))
        } else {
            self = String(repeating: "0", count: padding) + formatted
        }
    }
}
