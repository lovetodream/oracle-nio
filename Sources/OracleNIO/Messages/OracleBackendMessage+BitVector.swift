import NIOCore

extension OracleBackendMessage {
    struct BitVector: PayloadDecodable, Sendable, Hashable {
        let columnsCountSent: UInt16
        let bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities
        ) throws -> OracleBackendMessage.BitVector {
            let columnsCountSent = try buffer.throwingReadUB2()
            var length = Int(columnsCountSent) / 8
            if columnsCountSent % 8 > 0 {
                length += 1
            }
            let bitVector = buffer.readBytes(length: length)
            return .init(
                columnsCountSent: columnsCountSent, bitVector: bitVector
            )
        }
    }
}
