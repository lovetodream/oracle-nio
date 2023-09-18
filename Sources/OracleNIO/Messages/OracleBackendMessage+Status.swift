import NIOCore

extension OracleBackendMessage {
    struct Status: PayloadDecodable, Hashable {
        let callStatus: UInt32
        let endToEndSequenceNumber: UInt16?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.Status {
            let callStatus = try buffer.throwingReadInteger(as: UInt32.self)
            let endToEndSequenceNumber = buffer.readInteger(as: UInt16.self)
            return .init(
                callStatus: callStatus,
                endToEndSequenceNumber: endToEndSequenceNumber
            )
        }
    }
}
