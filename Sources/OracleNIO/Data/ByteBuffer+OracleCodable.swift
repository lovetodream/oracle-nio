import NIOCore

extension ByteBuffer: OracleEncodable {
    public var oracleType: DBType { .raw }
    
    /// Encodes `self` into wire data starting from the current `readerIndex`.
    ///
    /// - Warning: If you want the full buffer to be read, make sure to move `readerIndex` to `0`
    ///            before encoding.
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        var length = self.readableBytes
        var slice = self.slice()
        if length <= Constants.TNS_MAX_SHORT_LENGTH {
            buffer.writeInteger(UInt8(length))
            buffer.writeBuffer(&slice)
        } else {
            buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            while buffer.readableBytes > 0 {
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
            self = try buffer.readOracleSpecificLengthPrefixedSlice()
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
