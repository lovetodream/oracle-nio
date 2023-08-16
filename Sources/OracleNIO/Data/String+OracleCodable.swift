import NIOCore

extension String: OracleEncodable {
    public func encode<JSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) where JSONEncoder: OracleJSONEncoder {
        buffer.writeBytesAndLength(self.bytes)
    }
    
    public static var oracleType: DBType {
        .varchar
    }

    public var size: UInt32 {
        .init(self.count)
    }
}

extension String: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type.oracleType {
        case .varchar, .char, .long:
            self = buffer.readString(length: buffer.readableBytes)!
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
