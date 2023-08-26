import NIOCore

public struct LOB {
    let size: UInt64
    let chunkSize: UInt32
    let locator: ByteBuffer
    let hasMetadata: Bool
}

extension LOB: OracleEncodable {
    public static var oracleType: DBType { .blob }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        let length = self.locator.readableBytes
        buffer.writeUB4(UInt32(length))
        self.locator.encode(into: &buffer, context: context)
    }
}

extension LOB: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .clob, .blob:
            let size = try buffer.throwingReadUB8()
            let chunkSize = try buffer.throwingReadUB4()
            let locator = try buffer.readOracleSpecificLengthPrefixedSlice()
            self = LOB(
                size: size,
                chunkSize: chunkSize,
                locator: locator,
                hasMetadata: true
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
