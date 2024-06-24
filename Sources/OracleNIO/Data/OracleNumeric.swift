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

import func Foundation.pow

private let numberMaxDigits = 40
private let numberAsSingleChars = 172

extension SignedInteger {
    fileprivate init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)

        var value: Int64 = 0

        for byte in bytes {
            value <<= 8
            value |= Int64(byte)
        }

        self.init(value)
    }
}


extension StringProtocol {
    var ascii: [UInt8] { compactMap(\.asciiValue) }
}

extension LosslessStringConvertible {
    var string: String { .init(self) }
}

extension Numeric where Self: LosslessStringConvertible {
    var ascii: [UInt8] { string.ascii }
}

internal enum OracleNumeric {

    // MARK: Encode

    static func encodeNumeric<T>(
        _ value: T, into buffer: inout ByteBuffer
    ) where T: Numeric, T: LosslessStringConvertible {
        self.encodeNumeric(value.ascii, into: &buffer)
    }

    static func encodeNumeric(
        _ value: [UInt8], into buffer: inout ByteBuffer
    ) {
        var numberOfDigits = 0
        var digits = [UInt8](repeating: 0, count: numberAsSingleChars)
        var isNegative = false
        var exponentIsNegative = false
        var position = 0
        var exponentPosition = 0
        var exponent: Int16 = 0
        var prependZero = false
        var appendSentinel = false

        let length = value.count

        // check to see if number is negative (first character is '-')
        if value.first == "-".ascii.first {
            isNegative = true
            position += 1
        }

        // scan for digits until the decimal point or exponent indicator found
        while position < length {
            if value[position] == ".".ascii.first || value[position] == "e".ascii.first
                || value[position] == "E".ascii.first
            {
                break
            }
            if value[position] < "0".ascii.first! || value[position] > "9".ascii.first! {
                preconditionFailure("\(value) can't logically be a numeric")
            }
            let digit = value[position] - "0".ascii.first!
            position += 1
            if digit == 0 && numberOfDigits == 0 {
                continue
            }
            digits[numberOfDigits] = digit
            numberOfDigits += 1
        }
        var decimalPointIndex = numberOfDigits

        // scan for digits following the decimal point, if applicable
        if position < length && value[position] == ".".ascii.first {
            position += 1
            while position < length {
                if value[position] == "e".ascii.first || value[position] == "E".ascii.first {
                    break
                }
                let digit = value[position] - "0".ascii.first!
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
            && (value[position] == "e".ascii.first || value[position] == "E".ascii.first)
        {
            position += 1
            if position < length {
                if value[position] == "-".ascii.first {
                    exponentIsNegative = true
                    position += 1
                } else if value[position] == "+".ascii.first {
                    position += 1
                }
            }
            exponentPosition = position
            while position < length {
                if value[position] < "0".ascii.first! || value[position] > "9".ascii.first! {
                    preconditionFailure("\(value) can't logically be a numeric")
                }
                position += 1
            }
            if exponentPosition == position {
                preconditionFailure("\(value) can't logically be a numeric")
            }
            exponent = Int16(
                value.dropFirst(exponentPosition).dropLast(position)
            )
            if exponentIsNegative {
                exponent = -exponent
            }
            decimalPointIndex += Int(exponent)
        }

        // if there is anything left in the string, that indicates an
        // invalid number as well
        if position < length {
            preconditionFailure("\(value) can't logically be a numeric")
        }

        // skip trailing zeros
        while numberOfDigits > 0 && digits[numberOfDigits - 1] == 0 {
            numberOfDigits -= 1
        }

        // value must be less than 1e126 and greater than 1e-129;
        // the number of digits also cannot exceed the maximum precision of
        // Oracle numbers
        if numberOfDigits > numberMaxDigits || decimalPointIndex > 126 || decimalPointIndex < -129 {
            preconditionFailure("\(value) can't logically be a numeric")
        }

        // if the exponent is odd, prepend a zero
        if decimalPointIndex % 2 == 1 {
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
            buffer.writeInteger(UInt8(128))
            return
        }

        // write the exponent
        var exponentOnWire: UInt8 = UInt8((decimalPointIndex / 2) + 192)
        if isNegative {
            exponentOnWire = ~exponentOnWire
        }
        buffer.writeInteger(exponentOnWire)

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
            buffer.writeInteger(digit)
        }

        // append 102 bytes for negative numbers if the number of digits is less
        // than the maximum allowable
        if appendSentinel {
            buffer.writeInteger(UInt8(102))
        }
    }


    // MARK: Decode

    static func parseInteger<T: FixedWidthInteger>(
        from buffer: inout ByteBuffer
    ) throws -> T {
        switch try self.parsePartial(from: &buffer) {
        case .return0:
            return 0

        case .returnMagic:
            return .init(pow(Double(-10), 126))

        case .continue(
            let digits,
            let numberOfDigits,
            let decimalPointIndex,
            let isPositive
        ):
            var data = [UInt8]()
            data.reserveCapacity(numberAsSingleChars)
            // if the decimal point index is 0 or less, we've received a decimal value
            if decimalPointIndex <= 0 {
                throw OracleDecodingError.Code.decimalPointFound
            }

            // add each of the digits
            for i in 0..<numberOfDigits {
                if i > 0, i == decimalPointIndex {
                    throw OracleDecodingError.Code.decimalPointFound
                }
                data.append(digits[i])
            }

            if decimalPointIndex > numberOfDigits {
                for _ in numberOfDigits..<Int(decimalPointIndex) {
                    data.append(0)
                }
            }

            var value: T = data.reduce(0) { partialResult, digit in
                partialResult * 10 + T(digit)
            }

            if !isPositive {
                if T.self is any SignedInteger.Type {
                    value *= -1
                } else {
                    throw OracleDecodingError.Code.signedIntegerFound
                }
            }

            if decimalPointIndex < numberOfDigits {
                throw OracleDecodingError.Code.decimalPointFound
            }

            return value
        }
    }

    static func parseFloat<T: BinaryFloatingPoint>(
        from buffer: inout ByteBuffer
    ) throws -> T {
        switch try self.parsePartial(from: &buffer) {
        case .return0:
            return 0

        case .returnMagic:
            return -1.0e126

        case .continue(
            let digits,
            let numberOfDigits,
            let decimalPointIndex,
            let isPositive
        ):
            var data = [UInt8]()
            data.reserveCapacity(numberAsSingleChars)
            // if the decimal point index is 0 or less, add the decimal point and
            // any leading zeroes that are needed
            if decimalPointIndex <= 0 {
                data.append(0)  // zero
                data.append(UInt8.max)  // decimal point
                for _ in decimalPointIndex..<0 {
                    data.append(0)  // zero
                }
            }

            // add each of the digits
            for i in 0..<numberOfDigits {
                if i > 0, i == decimalPointIndex {
                    data.append(UInt8.max)  // decimal point
                }
                data.append(digits[i])
            }

            if decimalPointIndex > numberOfDigits {
                for _ in numberOfDigits..<Int(decimalPointIndex) {
                    data.append(0)
                }
            }

            var hasDecimalPoint = false
            var value: T = data.reduce(0) { partialResult, digit in
                if digit == .max {
                    hasDecimalPoint = true
                    return partialResult
                }

                return partialResult * 10 + T(digit)
            }

            if !isPositive {
                value *= -1
            }

            if hasDecimalPoint {
                let power = Double(data.count - 1 - data.firstIndex(of: 255)!)
                value /= T(pow(10.0, power))
            }

            return value
        }
    }

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

    private static func parsePartial(
        from buffer: inout ByteBuffer
    ) throws -> PartialResult {
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
        var decimalPointIndex = Int16(exp) * 2 + 2

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

        var digits = [UInt8]()
        digits.reserveCapacity(numberMaxDigits)
        // process the mantissa bytes which are the remaining bytes; each
        // mantissa byte is a base-100 digit
        var numberOfDigits = 0
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
                digits.append(1)
                digits.append(0)
                numberOfDigits += 2
                decimalPointIndex += 1
            } else if digit != 0 || i > 0 {
                digits.append(digit)
                numberOfDigits += 1
            }

            // process the second digit; trailing zeroes are ignored
            digit = byte % 10
            if digit != 0 || i < length - 1 {
                digits.append(digit)
                numberOfDigits += 1
            }
        }

        return .continue(
            digits: digits,
            numberOfDigits: numberOfDigits,
            decimalPointIndex: decimalPointIndex,
            isPositive: isPositive
        )
    }

    private enum PartialResult {
        /// Return 0.
        case return0
        ///  Return `.init(pow(Double(-10), 126))` for `FixedWithInteger` and
        ///  `-1.0e126` for `FloatingPointNumber`.
        case returnMagic
        case `continue`(
            digits: [UInt8],
            numberOfDigits: Int,
            decimalPointIndex: Int16,
            isPositive: Bool
        )
    }
}
