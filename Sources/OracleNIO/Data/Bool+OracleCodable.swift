import NIOCore

extension Bool: OracleEncodable {
    public static var oracleType: DBType { .boolean }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        if self {
            buffer.writeMultipleIntegers(UInt8(2), UInt16(0x0101))
        } else {
            buffer.writeInteger(UInt16(0x0100))
        }
    }
}

extension Bool: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .boolean:
            guard 
                let byte = buffer.getInteger(
                    at: buffer.readableBytes - 1, as: UInt8.self
                )
            else {
                throw OracleDecodingError.Code.missingData
            }
            self = byte == 1
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
