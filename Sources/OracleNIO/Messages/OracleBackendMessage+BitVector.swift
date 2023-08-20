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
            let bitVector = buffer.readBytes(length: Int(columnsCountSent))
            return .init(
                columnsCountSent: columnsCountSent, bitVector: bitVector
            )
        }
    }
}
