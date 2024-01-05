import NIOCore

extension ByteBuffer: OracleEncodable {
    public var oracleType: OracleDataType { .raw }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        preconditionFailure("This should not be called")
    }

    /// Encodes `self` into wire data starting from `0` without modifying the `readerIndex`.
    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        var slice = self
        slice.moveReaderIndex(to: 0)
        var length = slice.readableBytes
        if length <= Constants.TNS_MAX_SHORT_LENGTH {
            buffer.writeInteger(UInt8(length))
            buffer.writeBuffer(&slice)
        } else {
            buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            while slice.readableBytes > 0 {
                let chunkLength = min(length, Constants.TNS_CHUNK_SIZE)
                buffer.writeUB4(UInt32(chunkLength))
                length -= chunkLength
                var part = slice.readSlice(length: chunkLength)!
                buffer.writeBuffer(&part)
            }
            buffer.writeUB4(0)
        }
    }
}

extension ByteBuffer: OracleDecodable {
    public var size: UInt32 { UInt32(self.readableBytes) }

    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .raw, .longRAW:
            self = buffer
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
