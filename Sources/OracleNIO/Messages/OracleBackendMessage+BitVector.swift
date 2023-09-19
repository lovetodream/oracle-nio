import NIOCore

extension OracleBackendMessage {
    struct BitVector: PayloadDecodable, Sendable, Hashable {
        let columnsCountSent: UInt16
        let bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.BitVector {
            let columnsCountSent = try buffer.throwingReadUB2()
            guard
                let columnsCount = context.columnsCount.flatMap(Double.init)
            else {
                preconditionFailure(
                    "How can we receive a bit vector without an active query?"
                )
            }
            var length = columnsCount / 8.0
            if columnsCount.truncatingRemainder(dividingBy: 8.0) > 0 {
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
