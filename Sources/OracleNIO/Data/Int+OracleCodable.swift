import NIOCore

// MARK: UInt8

extension UInt8: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .char, .nChar, .raw, .longRAW, .long:
            guard
                buffer.readableBytes == 1,
                let value = buffer.readInteger(as: UInt8.self)
            else {
                throw OracleDecodingError.Code.failure
            }
            self = value
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int8

extension Int8: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt16

extension UInt16: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int16

extension Int16: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt32

extension UInt32: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int32

extension Int32: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt64

extension UInt64: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout NIOCore.ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int64

extension Int64: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout NIOCore.ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: UInt

extension UInt: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

// MARK: Int

extension Int: OracleEncodable {
    public static var oracleType: DBType { .number }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        // TODO: implement a better version of ByteBuffer.writeOracleNumber
    }
}

extension Int: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .number, .binaryInteger:
            self = try OracleNumeric.parseInteger(from: &buffer)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}

