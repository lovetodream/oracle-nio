import NIOCore

extension ByteBuffer {
    mutating func sendPacket(packetType: PacketType, capabilities: Capabilities, final: Bool) {
        var position = 0
        if capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            self.setInteger(UInt32(self.readableBytes), at: position)
        } else {
            self.setInteger(UInt16(self.readableBytes), at: position)
            self.setInteger(UInt16(0), at: position + MemoryLayout<UInt16>.size)
        }
        position += MemoryLayout<UInt32>.size
        self.setInteger(packetType.rawValue, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt8(0), at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt16(0), at: position)
        if !final {
            self.moveWriterIndex(to: TNSMessage.headerSize)
            self.writeInteger(UInt16(0)) // add data flags for next packet
        }
    }
}
