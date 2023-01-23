import NIOCore

extension ByteBuffer {
    mutating func endRequest(packetType: PacketType = .data, capabilities: Capabilities) {
        self.sendPacket(packetType: packetType, capabilities: capabilities, final: true)
    }
}
