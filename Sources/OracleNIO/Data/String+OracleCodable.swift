import NIOCore

extension String: OracleEncodable {
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        preconditionFailure("This should not be called")
    }

    @inlinable
    public func _encodeRaw<JSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) where JSONEncoder: OracleJSONEncoder {
        ByteBuffer(string: self)
            ._encodeRaw(into: &buffer, context: context)
    }

    public var oracleType: DBType {
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
        switch type {
        case .varchar, .char, .long:
            if type.csfrm == Constants.TNS_CS_IMPLICIT {
                self = buffer.readString(length: buffer.readableBytes)!
            } else {
                self = buffer.readString(
                    length: buffer.readableBytes, encoding: .utf16
                )!
            }
        case .rowID:
            self = RowID(from: &buffer).description
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
