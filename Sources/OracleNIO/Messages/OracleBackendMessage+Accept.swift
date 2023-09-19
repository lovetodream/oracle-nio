import NIOCore
import struct Foundation.UUID

extension OracleBackendMessage {
    struct Accept: PayloadDecodable, Hashable {
        var newCapabilities: Capabilities
        var dbCookieUUID: UUID?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.Accept {
            let protocolVersion =
                try buffer.throwingReadInteger(as: UInt16.self)
            let protocolOptions =
                try buffer.throwingReadInteger(as: UInt16.self)

            let dbUUID: UUID?
            if protocolVersion >= Constants.TNS_VERSION_MIN_UUID {
                buffer.moveReaderIndex(forwardBy: 33)
                dbUUID = buffer.readUUIDBytes()
            } else {
                dbUUID = nil
            }

            let cap = capabilities.adjustedForProtocol(
                version: protocolVersion, options: protocolOptions
            )

            return .init(newCapabilities: cap, dbCookieUUID: dbUUID)
        }
    }
}
