import NIOCore

extension OracleBackendMessage {
    struct LOBData: PayloadDecodable, Hashable {
        let buffer: ByteBuffer

        static func decode(
            from buffer: inout ByteBuffer, capabilities: Capabilities
        ) throws -> OracleBackendMessage.LOBData {
            let buffer = try buffer.readOracleSpecificLengthPrefixedSlice()
            return .init(buffer: buffer)
        }
    }
}