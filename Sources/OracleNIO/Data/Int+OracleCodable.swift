import NIOCore

fileprivate let NUMBER_MAX_DIGITS = 40
fileprivate let NUMBER_AS_TEXT_CHARS = 172

// MARK: Int64

extension Int64: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout NIOCore.ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// TODO: cleanup once Double and Float are implemented
// TODO: might have a lot of room for optimization
private func parseInteger<T: FixedWidthInteger>(
    from buffer: inout ByteBuffer
) throws -> T {
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
    exponent -= 193
    var decimalPointIndex = exponent * 2 + 2

    // a mantissa length of 0 implies a value of 0 (if positive) or a value
    // of -1e126 (if negative)
    if length == 1 {
        if isPositive {
            return 0
        }
        return .init(pow(Double(-10), 126)) // -1.0e126 for floats
    }

    // check for the trailing 102 byte for negative numbers and, if present,
    // reduce the number of mantissa digits
    if !isPositive && buffer.getInteger(at: length - 1, as: UInt8.self) == 102 {
        length -= 1
    }

    var digits = [UInt8](repeating: 0, count: NUMBER_MAX_DIGITS)
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
            digits[numberOfDigits] = 1
            digits[numberOfDigits + 1] = 0
            numberOfDigits += 2
            decimalPointIndex += 1
        } else if digit != 0 || i > 0 {
            digits[numberOfDigits] = digit
            numberOfDigits += 1
        }

        // process the second digit; trailing zeroes are ignored
        digit = byte % 10
        if digit != 0 || i < length - 1 {
            digits[numberOfDigits] = digit
            numberOfDigits += 1
        }
    }

    var data = [UInt8]()
    // if the decimal point index is 0 or less, add the decimal point and
    // any leading zeroes that are needed
    if decimalPointIndex <= 0 {
        data.append(0) // zero
        // decimal point
        for _ in decimalPointIndex..<0 {
            data.append(0) // zero
        }
    }

    // add each of the digits
    for i in 0..<numberOfDigits {
        if i > 0 && i == decimalPointIndex {
            // decimal point
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
            value = value * -1
        } else {
            // TODO: What do we do with negative values and UInt
            fatalError()
        }
    }

    if decimalPointIndex < numberOfDigits {
        // TODO: handle this case if we get a decimal but we want to parse Int
        fatalError()
    }

    return value
}
