import NIOCore

private let NUMBER_MAX_DIGITS = 40
private let NUMBER_AS_SINGLE_CHARS = 172

internal enum OracleNumeric {
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
            data.reserveCapacity(NUMBER_AS_SINGLE_CHARS)
            // if the decimal point index is 0 or less, we've received a decimal value
            if decimalPointIndex <= 0 {
                throw OracleDecodingError.Code.decimalPointFound
            }

            // add each of the digits
            for i in 0 ..< numberOfDigits {
                if i > 0, i == decimalPointIndex {
                    throw OracleDecodingError.Code.decimalPointFound
                }
                data.append(digits[i])
            }

            if decimalPointIndex > numberOfDigits {
                for _ in numberOfDigits ..< Int(decimalPointIndex) {
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
            data.reserveCapacity(NUMBER_AS_SINGLE_CHARS)
            // if the decimal point index is 0 or less, add the decimal point and
            // any leading zeroes that are needed
            if decimalPointIndex <= 0 {
                data.append(0) // zero
                data.append(UInt8.max) // decimal point
                for _ in decimalPointIndex ..< 0 {
                    data.append(0) // zero
                }
            }

            // add each of the digits
            for i in 0 ..< numberOfDigits {
                if i > 0, i == decimalPointIndex {
                    data.append(UInt8.max) // decimal point
                }
                data.append(digits[i])
            }

            if decimalPointIndex > numberOfDigits {
                for _ in numberOfDigits ..< Int(decimalPointIndex) {
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
        let allBits: UInt32 = UInt32((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        let float = Float(bitPattern: allBits)
        return float
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
        digits.reserveCapacity(NUMBER_MAX_DIGITS)
        // process the mantissa bytes which are the remaining bytes; each
        // mantissa byte is a base-100 digit
        var numberOfDigits = 0
        for i in 1 ..< length {
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
