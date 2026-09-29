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

public import NIOCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

private let numberMaxDigits = 40
private let numberAsSingleChars = 172

extension SignedInteger {
    /// Parses a span of ASCII decimal digit bytes into an integer.
    fileprivate init(asciiDigits bytes: Span<UInt8>) {
        var value: Int64 = 0
        for i in bytes.indices {
            value = value * 10 + Int64(bytes[i] - UInt8(ascii: "0"))
        }
        self.init(value)
    }
}


extension StringProtocol {
    var ascii: [UInt8] { Array(utf8) }
}

extension LosslessStringConvertible {
    var string: String { .init(self) }
}

extension Numeric where Self: LosslessStringConvertible {
    @usableFromInline
    var ascii: [UInt8] { string.ascii }
}

extension Span where Element == UInt8 {
    fileprivate var debugBytes: [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for i in indices { bytes.append(self[i]) }
        return bytes
    }
}

@usableFromInline
internal enum OracleNumeric {

    // MARK: Encode

    /// Encodes a numeric value to the Oracle `NUMBER` wire representation.
    /// - Returns: Bytes written to the buffer.
    @usableFromInline
    @discardableResult
    static func encodeNumeric<T>(
        _ value: T, into buffer: inout ByteBuffer
    ) -> Int where T: Numeric, T: LosslessStringConvertible {
        value.ascii.withUnsafeBufferPointer { ascii in
            self.encodeNumeric(Span(_unsafeElements: ascii), into: &buffer)
        }
    }

    /// Encodes a `FixedWidthInteger` value to the Oracle `NUMBER` wire representation,
    /// deriving the ASCII digit bytes directly from the binary value instead of
    /// round-tripping through `String` (as the generic `encodeNumeric(_:into:)` overload
    /// above does via `LosslessStringConvertible`).
    /// - Returns: Bytes written to the buffer.
    @usableFromInline
    @discardableResult
    static func encodeFixedWidthInteger<T: FixedWidthInteger>(
        _ value: T, into buffer: inout ByteBuffer
    ) -> Int {
        // 20 digits covers `UInt64.max`, plus one byte for a sign.
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 21) { ascii in
            let isNegative = value < 0
            var magnitude = value.magnitude
            var position = ascii.count
            repeat {
                position -= 1
                ascii[position] = UInt8(magnitude % 10) &+ UInt8(ascii: "0")
                magnitude /= 10
            } while magnitude != 0
            if isNegative {
                position -= 1
                ascii[position] = UInt8(ascii: "-")
            }
            return self.encodeNumeric(Span(_unsafeElements: ascii.extracting(position...)), into: &buffer)
        }
    }

    /// Encodes a numeric value to the Oracle `NUMBER` wire representation.
    /// - Returns: Bytes written to the buffer.
    @usableFromInline
    @discardableResult
    static func encodeNumeric(
        _ value: Span<UInt8>, into buffer: inout ByteBuffer
    ) -> Int {
        // scratch space for the parsed decimal digits, backed by stack (or otherwise
        // non-heap-allocated) memory rather than a freshly-allocated `Array` per call.
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: numberAsSingleChars) { digits in
            var writtenBytes = 0

            var numberOfDigits = 0
            var isNegative = false
            var exponentIsNegative = false
            var position = 0
            var exponentPosition = 0
            var exponent: Int16 = 0
            var prependZero = false
            var appendSentinel = false

            let length = value.count

            // check to see if number is negative (first character is '-')
            if length > 0 && value[0] == UInt8(ascii: "-") {
                isNegative = true
                position += 1
            }

            // scan for digits until the decimal point or exponent indicator found
            while position < length {
                if value[position] == UInt8(ascii: ".") || value[position] == UInt8(ascii: "e")
                    || value[position] == UInt8(ascii: "E")
                {
                    break
                }
                if value[position] < UInt8(ascii: "0") || value[position] > UInt8(ascii: "9") {
                    preconditionFailure("\(value.debugBytes) can't logically be a numeric")
                }
                let digit = value[position] - UInt8(ascii: "0")
                position += 1
                if digit == 0 && numberOfDigits == 0 {
                    continue
                }
                digits[numberOfDigits] = digit
                numberOfDigits += 1
            }
            var decimalPointIndex = numberOfDigits

            // scan for digits following the decimal point, if applicable
            if position < length && value[position] == UInt8(ascii: ".") {
                position += 1
                while position < length {
                    if value[position] == UInt8(ascii: "e") || value[position] == UInt8(ascii: "E") {
                        break
                    }
                    let digit = value[position] - UInt8(ascii: "0")
                    position += 1
                    if digit == 0 && numberOfDigits == 0 {
                        decimalPointIndex -= 1
                        continue
                    }
                    digits[numberOfDigits] = digit
                    numberOfDigits += 1
                }
            }

            // handle exponent, if applicable
            if position < length
                && (value[position] == UInt8(ascii: "e") || value[position] == UInt8(ascii: "E"))
            {
                position += 1
                if position < length {
                    if value[position] == UInt8(ascii: "-") {
                        exponentIsNegative = true
                        position += 1
                    } else if value[position] == UInt8(ascii: "+") {
                        position += 1
                    }
                }
                exponentPosition = position
                while position < length {
                    if value[position] < UInt8(ascii: "0") || value[position] > UInt8(ascii: "9") {
                        preconditionFailure("\(value.debugBytes) can't logically be a numeric")
                    }
                    position += 1
                }
                if exponentPosition == position {
                    preconditionFailure("\(value.debugBytes) can't logically be a numeric")
                }
                exponent = Int16(asciiDigits: value.extracting(exponentPosition..<position))
                if exponentIsNegative {
                    exponent = -exponent
                }
                decimalPointIndex += Int(exponent)
            }

            // if there is anything left in the string, that indicates an
            // invalid number as well
            if position < length {
                preconditionFailure("\(value.debugBytes) can't logically be a numeric")
            }

            // skip trailing zeros
            while numberOfDigits > 0 && digits[numberOfDigits - 1] == 0 {
                numberOfDigits -= 1
            }

            // value must be less than 1e126 and greater than 1e-129;
            // the number of digits also cannot exceed the maximum precision of
            // Oracle numbers
            if numberOfDigits > numberMaxDigits || decimalPointIndex > 126 || decimalPointIndex < -129 {
                preconditionFailure("\(value.debugBytes) can't logically be a numeric")
            }

            // if the exponent is odd, prepend a zero; `decimalPointIndex` can be
            // negative, and Swift's `%` returns a negative remainder for negative
            // operands (`-9 % 2 == -1`), so check for non-zero rather than `== 1`.
            if decimalPointIndex % 2 != 0 {
                prependZero = true
                if numberOfDigits > 0 {
                    digits[numberOfDigits] = 0
                    numberOfDigits += 1
                    decimalPointIndex += 1
                }
            }

            // determine the number of digit pairs; if the number of digits is odd,
            // append a zero to make the number of digits even
            if numberOfDigits % 2 == 1 {
                digits[numberOfDigits] = 0
                numberOfDigits += 1
            }
            let numberOfPairs = numberOfDigits / 2

            // append a sentinel 102 byte for negative numbers if there is room
            if isNegative && numberOfDigits > 0 && numberOfDigits < numberMaxDigits {
                appendSentinel = true
            }

            // if the number of digits is zero, the value is itself zero since all
            // leading and trailing zeros are removed from the digits string; this
            // is a special case
            if numberOfDigits == 0 {
                writtenBytes += buffer.writeInteger(UInt8(128))
                return writtenBytes
            }

            // write the exponent
            var exponentOnWire: UInt8 = UInt8((decimalPointIndex / 2) + 192)
            if isNegative {
                exponentOnWire = ~exponentOnWire
            }
            writtenBytes += buffer.writeInteger(exponentOnWire)

            // write the mantissa bytes
            var digitsPosition = 0
            for pair in 0..<numberOfPairs {
                var digit: UInt8
                if pair == 0 && prependZero {
                    digit = digits[digitsPosition]
                    digitsPosition += 1
                } else {
                    digit = digits[digitsPosition] * 10 + digits[digitsPosition + 1]
                    digitsPosition += 2
                }
                if isNegative {
                    digit = 101 - digit
                } else {
                    digit += 1
                }
                writtenBytes += buffer.writeInteger(digit)
            }

            // append 102 bytes for negative numbers if the number of digits is less
            // than the maximum allowable
            if appendSentinel {
                writtenBytes += buffer.writeInteger(UInt8(102))
            }

            return writtenBytes
        }
    }


    // MARK: Decode

    @usableFromInline
    static func parseInteger<T: FixedWidthInteger>(
        from buffer: inout ByteBuffer
    ) throws -> T {
        switch try self.parseHeader(from: &buffer) {
        case .return0:
            return 0

        case .returnMagic:
            return .init(pow(Double(-10), 126))

        case .header(let header):
            return try withUnsafeTemporaryAllocation(
                of: UInt8.self, capacity: numberAsSingleChars
            ) { digits in
                var decimalPointIndex = header.decimalPointIndex
                let numberOfDigits = try self.collectDigits(
                    from: &buffer,
                    isPositive: header.isPositive,
                    length: header.length,
                    decimalPointIndex: &decimalPointIndex,
                    into: digits
                )

                // if the decimal point index is 0 or less, we've received a decimal value
                if decimalPointIndex <= 0 {
                    throw OracleDecodingError.Code.decimalPointFound
                }

                var magnitude: T.Magnitude = 0
                for i in 0..<numberOfDigits {
                    if i > 0, i == decimalPointIndex {
                        throw OracleDecodingError.Code.decimalPointFound
                    }
                    let (multiplied, multiplyOverflow) = magnitude.multipliedReportingOverflow(
                        by: 10
                    )
                    let (added, addOverflow) = multiplied.addingReportingOverflow(
                        T.Magnitude(digits[i])
                    )
                    guard !multiplyOverflow, !addOverflow else {
                        throw OracleDecodingError.Code.failure
                    }
                    magnitude = added
                }

                if decimalPointIndex > numberOfDigits {
                    for _ in numberOfDigits..<Int(decimalPointIndex) {
                        let (multiplied, overflow) = magnitude.multipliedReportingOverflow(by: 10)
                        guard !overflow else {
                            throw OracleDecodingError.Code.failure
                        }
                        magnitude = multiplied
                    }
                }

                let value: T
                if !header.isPositive {
                    guard T.isSigned else {
                        throw OracleDecodingError.Code.signedIntegerFound
                    }
                    // the valid negative range extends one further than `T.max`
                    // (down to `T.min`, whose magnitude is `T.max + 1`)
                    guard magnitude <= T.Magnitude(T.max) &+ 1 else {
                        throw OracleDecodingError.Code.failure
                    }
                    value = 0 &- T(truncatingIfNeeded: magnitude)
                } else {
                    guard let positive = T(exactly: magnitude) else {
                        throw OracleDecodingError.Code.failure
                    }
                    value = positive
                }

                if decimalPointIndex < numberOfDigits {
                    throw OracleDecodingError.Code.decimalPointFound
                }

                return value
            }
        }
    }

    @usableFromInline
    static func parseFloat<T: BinaryFloatingPoint>(
        from buffer: inout ByteBuffer
    ) throws -> T {
        switch try self.parseHeader(from: &buffer) {
        case .return0:
            return 0

        case .returnMagic:
            return -1.0e126

        case .header(let header):
            return try withUnsafeTemporaryAllocation(
                of: UInt8.self, capacity: numberAsSingleChars
            ) { digits in
                var decimalPointIndex = header.decimalPointIndex
                let numberOfDigits = try self.collectDigits(
                    from: &buffer,
                    isPositive: header.isPositive,
                    length: header.length,
                    decimalPointIndex: &decimalPointIndex,
                    into: digits
                )

                return try withUnsafeTemporaryAllocation(
                    of: UInt8.self, capacity: numberAsSingleChars
                ) { data in
                    var dataCount = 0
                    var decimalMarkerPosition: Int? = nil

                    func append(_ byte: UInt8) throws {
                        guard dataCount < data.count else {
                            throw OracleDecodingError.Code.failure
                        }
                        data[dataCount] = byte
                        dataCount += 1
                    }

                    // if the decimal point index is 0 or less, add the decimal point
                    // and any leading zeroes that are needed
                    if decimalPointIndex <= 0 {
                        try append(0)  // zero
                        decimalMarkerPosition = dataCount
                        try append(.max)  // decimal point
                        for _ in decimalPointIndex..<0 {
                            try append(0)  // zero
                        }
                    }

                    // add each of the digits
                    for i in 0..<numberOfDigits {
                        if i > 0, i == decimalPointIndex {
                            decimalMarkerPosition = dataCount
                            try append(.max)  // decimal point
                        }
                        try append(digits[i])
                    }

                    if decimalPointIndex > numberOfDigits {
                        for _ in numberOfDigits..<Int(decimalPointIndex) {
                            try append(0)
                        }
                    }

                    var value: T = 0
                    for i in 0..<dataCount {
                        let digit = data[i]
                        if digit == .max {
                            continue
                        }
                        value = value * 10 + T(digit)
                    }

                    if !header.isPositive {
                        value *= -1
                    }

                    if let decimalMarkerPosition {
                        let power = Double(dataCount - 1 - decimalMarkerPosition)
                        value /= T(pow(10.0, power))
                    }

                    return value
                }
            }
        }
    }

    @usableFromInline
    static func parseBinaryFloat(
        from buffer: inout ByteBuffer
    ) throws -> Float {
        var b0 = try buffer.throwingReadInteger(as: UInt8.self)
        var b1 = try buffer.throwingReadInteger(as: UInt8.self)
        var b2 = try buffer.throwingReadInteger(as: UInt8.self)
        var b3 = try buffer.throwingReadInteger(as: UInt8.self)
        if (b0 & 0x80) != 0 {
            b0 = b0 & 0x7f
        } else {
            b0 = ~b0
            b1 = ~b1
            b2 = ~b2
            b3 = ~b3
        }
        let allBits = UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3)
        let float = Float(bitPattern: allBits)
        return float
    }

    @usableFromInline
    static func parseBinaryDouble(
        from buffer: inout ByteBuffer
    ) throws -> Double {
        var b0 = try buffer.throwingReadInteger(as: UInt8.self)
        var b1 = try buffer.throwingReadInteger(as: UInt8.self)
        var b2 = try buffer.throwingReadInteger(as: UInt8.self)
        var b3 = try buffer.throwingReadInteger(as: UInt8.self)
        var b4 = try buffer.throwingReadInteger(as: UInt8.self)
        var b5 = try buffer.throwingReadInteger(as: UInt8.self)
        var b6 = try buffer.throwingReadInteger(as: UInt8.self)
        var b7 = try buffer.throwingReadInteger(as: UInt8.self)
        if (b0 & 0x80) != 0 {
            b0 = b0 & 0x7f
        } else {
            b0 = ~b0
            b1 = ~b1
            b2 = ~b2
            b3 = ~b3
            b4 = ~b4
            b5 = ~b5
            b6 = ~b6
            b7 = ~b7
        }
        let highBits = UInt64(b0) << 24 | UInt64(b1) << 16 | UInt64(b2) << 8 | UInt64(b3)
        let lowBits = UInt64(b4) << 24 | UInt64(b5) << 16 | UInt64(b6) << 8 | UInt64(b7)
        let allBits = highBits << 32 | (lowBits & 0xffff_ffff)
        let double = Double(bitPattern: allBits)
        return double
    }

    /// Parses the exponent byte of the Oracle `NUMBER` wire format and determines
    /// how many mantissa bytes follow (trimming the trailing negative-number
    /// sentinel byte, if present).
    private static func parseHeader(
        from buffer: inout ByteBuffer
    ) throws -> HeaderResult {
        var length = buffer.readableBytes
        // the first byte is the exponent; positive numbers have the highest
        // order bit set, whereas negative numbers have the highest order bit
        // cleared and the bits inverted
        guard var exponent = buffer.getInteger(at: 0, as: UInt8.self) else {
            throw OracleDecodingError.Code.missingData
        }
        let isPositive = (exponent & 0x80) != 0
        if !isPositive {
            exponent = ~exponent
        }
        exponent &-= 193
        let exp = Int8(bitPattern: exponent)
        let decimalPointIndex = Int16(exp) * 2 + 2

        // a mantissa length of 0 implies a value of 0 (if positive) or a value
        // of -1e126 (if negative)
        if length == 1 {
            if isPositive {
                return .return0
            }
            return .returnMagic
        }

        // check for the trailing 102 byte for negative numbers and, if present,
        // reduce the number of mantissa digits
        if !isPositive,
            buffer.getInteger(at: length - 1, as: UInt8.self) == 102
        {
            length -= 1
        }

        return .header(
            NumberHeader(isPositive: isPositive, decimalPointIndex: decimalPointIndex, length: length)
        )
    }

    /// Processes the mantissa bytes (the remaining bytes after the exponent byte);
    /// each mantissa byte is a base-100 digit, decoded into 1-2 base-10 digits
    /// written into `digits`. Returns the number of digits written.
    ///
    /// `decimalPointIndex` may be adjusted for leading zeroes / carries encountered
    /// while processing the mantissa, mirroring the adjustments `encodeNumeric` made
    /// while encoding.
    private static func collectDigits(
        from buffer: inout ByteBuffer,
        isPositive: Bool,
        length: Int,
        decimalPointIndex: inout Int16,
        into digits: UnsafeMutableBufferPointer<UInt8>
    ) throws -> Int {
        var numberOfDigits = 0

        func append(_ digit: UInt8) throws {
            guard numberOfDigits < digits.count else {
                throw OracleDecodingError.Code.failure
            }
            digits[numberOfDigits] = digit
            numberOfDigits += 1
        }

        for i in 1..<length {
            // positive numbers have 1 added to them; negative numbers are
            // subtracted from the value 101
            guard var byte = buffer.getInteger(at: i, as: UInt8.self) else {
                throw OracleDecodingError.Code.missingData
            }
            if isPositive {
                byte -= 1
            } else {
                byte = 101 - byte
            }

            // process the first digit; leading zeroes are ignored
            var digit = byte / 10
            if digit == 0 && numberOfDigits == 0 {
                decimalPointIndex -= 1
            } else if digit == 10 {
                try append(1)
                try append(0)
                decimalPointIndex += 1
            } else if digit != 0 || i > 0 {
                try append(digit)
            }

            // process the second digit; trailing zeroes are ignored
            digit = byte % 10
            if digit != 0 || i < length - 1 {
                try append(digit)
            }
        }

        return numberOfDigits
    }

    private struct NumberHeader {
        var isPositive: Bool
        var decimalPointIndex: Int16
        var length: Int
    }

    private enum HeaderResult {
        /// Return 0.
        case return0
        ///  Return `.init(pow(Double(-10), 126))` for `FixedWithInteger` and
        ///  `-1.0e126` for `FloatingPointNumber`.
        case returnMagic
        case header(NumberHeader)
    }
}
