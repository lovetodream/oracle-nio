import NIOCore

extension OracleFrontendMessage {
    struct `Protocol`: PayloadEncodable, Hashable {
        var packetType: PacketType { .data }

        func encode(
            into buffer: inout NIOCore.ByteBuffer,
            capabilities: Capabilities
        ) {
            buffer.writeInteger(MessageType.protocol.rawValue) // maybe we can move this one layer up?
            buffer.writeInteger(UInt8(6)) // protocol version (8.1 and higher)
            buffer.writeInteger(UInt8(0)) // `array` terminator
            buffer.writeString(Constants.DRIVER_NAME)
            buffer.writeInteger(UInt8(0)) // `NULL` terminator
        }
    }
}
