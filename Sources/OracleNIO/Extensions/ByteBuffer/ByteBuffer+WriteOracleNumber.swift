import struct NIOCore.ByteBuffer

fileprivate let NUMBER_MAX_DIGITS = 40
fileprivate let NUMBER_AS_TEXT_CHARS = 172

extension ByteBuffer {
    mutating func writeOracleNumber(_ value: [UInt8]) throws {
        var numberOfDigits = 0
        var digits = [UInt8](repeating: 0, count: NUMBER_AS_TEXT_CHARS)
        var isNegative = false
        var exponentIsNegative = false
        var position = 0
        var exponentPosition = 0
        var exponent: Int16 = 0
        var prependZero = false
        var appendSentinel = false

        // zero length string cannot be converted
        let length = value.count
        if length == 0 {
            throw OracleError.ErrorType.numberStringOfZeroLength
        } else if length > NUMBER_AS_TEXT_CHARS {
            throw OracleError.ErrorType.numberStringTooLong
        }

        // check to see if number is negative (first character is '-')
        if value.first == "-".bytes.first {
            isNegative = true
            position += 1
        }

        // scan for digits until the decimal point or exponent indicator found
        while position < length {
            if value[position] == ".".bytes.first || value[position] == "e".bytes.first || value[position] == "E".bytes.first {
                break
            }
            if value[position] < "0".bytes.first! || value[position] > "9".bytes.first! {
                throw OracleError.ErrorType.invalidNumber
            }
            let digit = value[position] - "0".bytes.first!
            position += 1
            if digit == 0 && numberOfDigits == 0 {
                continue
            }
            digits[numberOfDigits] = digit
            numberOfDigits += 1
        }
        var decimalPointIndex = numberOfDigits

        // scan for digits following the decimal point, if applicable
        if position < length || value[position] == ".".bytes.first {
            position += 1
            while position < length {
                if value[position] == "e".bytes.first || value[position] == "E".bytes.first {
                    break
                }
                let digit = value[position] - "0".bytes.first!
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
        if position < length && (value[position] == "e".bytes.first || value[position] == "E".bytes.first) {
            position += 1
            if position < length {
                if value[position] == "-".bytes.first {
                    exponentIsNegative = true
                    position += 1
                } else if value[position] == "+".bytes.first {
                    position += 1
                }
            }
            exponentPosition = position
            while position < length {
                if value[position] < "0".bytes.first! || value[position] > "9".bytes.first! {
                    throw OracleError.ErrorType.numberWithInvalidExponent
                }
                position += 1
            }
            if exponentPosition == position {
                throw OracleError.ErrorType.numberWithEmptyExponent
            }
            exponent = Int16(Array(value.dropFirst(exponentPosition).dropLast(position)))
            if exponentIsNegative {
                exponent = -exponent
            }
            decimalPointIndex += Int(exponent)
        }

        // if there is anything left in the string, that indicates an invalid number as well
        if position < length {
            throw OracleError.ErrorType.contentInvalidAfterNumber
        }

        // skip trailing zeros
        while numberOfDigits > 0 && digits[numberOfDigits - 1] == 0 {
            numberOfDigits -= 1
        }

        // value must be less than 1e126 and greater than 1e-129;
        // the number of digits also cannot exceed the maximum precision of Oracle numbers
        if numberOfDigits > NUMBER_MAX_DIGITS || decimalPointIndex > 126 || decimalPointIndex < -129 {
            throw OracleError.ErrorType.oracleNumberNoRepresentation
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
        if isNegative && numberOfDigits > 0 && numberOfDigits < NUMBER_MAX_DIGITS {
            appendSentinel = true
        }

        // write length of number
        self.writeInteger(UInt8(numberOfPairs + 1 + (appendSentinel ? 1 : 0)))

        // if the number of digits is zero, the value is itself zero since all
        // leading and trailing zeros are removed from the digits string; this is a special case
        if numberOfDigits == 0 {
            self.writeInteger(UInt8(128))
            return
        }

        // write the exponent
        var exponentOnWire: UInt8 = UInt8((decimalPointIndex / 2) + 192)
        if isNegative {
            exponentOnWire = ~exponentOnWire
        }
        self.writeInteger(exponentOnWire)

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
            self.writeInteger(digit)
        }

        // append 102 bytes for negative numbers if the number of digits is less
        // than the maximum allowable
        if appendSentinel {
            self.writeInteger(UInt8(102))
        }
    }
}

extension UnsignedInteger {
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)

        var value: UInt64 = 0

        for byte in bytes {
            value <<= 8
            value |= UInt64(byte)
        }

        self.init(value)
    }
}

extension SignedInteger {
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)

        var value: Int64 = 0

        for byte in bytes {
            value <<= 8
            value |= Int64(byte)
        }

        self.init(value)
    }
}
