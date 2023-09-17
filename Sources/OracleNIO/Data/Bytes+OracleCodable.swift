import NIOCore

extension OracleEncodable where Self: Collection, Self.Element == UInt8 {
    public var oracleType: DBType { .raw }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        preconditionFailure("This should not be called")
    }

    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        var length = self.count
        var position = 0
        if length <= Constants.TNS_MAX_SHORT_LENGTH {
            buffer.writeInteger(UInt8(length))
            buffer.writeBytes(self)
        } else {
            buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            while length > 0 {
                let chunkLength = Swift.min(length, Constants.TNS_CHUNK_SIZE)
                buffer.writeUB4(UInt32(chunkLength))
                length -= chunkLength
                let startIndex = self.index(self.startIndex, offsetBy: position)
                let endIndex = self.index(startIndex, offsetBy: chunkLength)
                let part = self[startIndex..<endIndex]
                buffer.writeBytes(part)
                position += chunkLength
            }
            buffer.writeUB4(0)
        }
    }
}
