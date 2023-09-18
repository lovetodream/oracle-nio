import NIOCore

extension OracleBackendMessage {
    struct BitVector: PayloadDecodable, Sendable, Hashable {
        let columnsCountSent: UInt16
        let bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities
        ) throws -> OracleBackendMessage.BitVector {
            let columnsCountSent = try Double(buffer.throwingReadUB2())
            var length = Double(columnsCountSent) / 8.0
            if columnsCountSent.truncatingRemainder(dividingBy: 8.0) > 0 {
                length += 1
            }
            let bitVector = buffer.readBytes(length: Int(length.rounded()))
            return .init(
                columnsCountSent: UInt16(columnsCountSent),
                bitVector: bitVector
            )
        }
    }
}
