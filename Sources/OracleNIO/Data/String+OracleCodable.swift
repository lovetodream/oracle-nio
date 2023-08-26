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
            if type.csfrm == Constants.TNS_CS_IMPLICIT {
                self = buffer.readString(length: buffer.readableBytes)!
            } else {
                self = buffer.readString(
                    length: buffer.readableBytes, encoding: .utf16
                )!
            }
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
