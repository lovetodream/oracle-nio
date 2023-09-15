import NIOCore

extension ByteBuffer {
    mutating func prepareSend(
        packetType: PacketType,
        packetFlags: UInt8 = 0,
        protocolVersion: UInt16
    ) {
        self.prepareSend(
            packetTypeByte: packetType.rawValue,
            protocolVersion: protocolVersion
        )
    }

    mutating func prepareSend(
        packetTypeByte: UInt8, 
        packetFlags: UInt8 = 0,
        protocolVersion: UInt16
    ) {
        var position = 0
        if protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            self.setInteger(UInt32(self.readableBytes), at: position)
            position += MemoryLayout<UInt32>.size
        } else {
            self.setInteger(UInt16(self.readableBytes), at: position)
            position += MemoryLayout<UInt16>.size
            self.setInteger(UInt16(0), at: position)
            position += MemoryLayout<UInt16>.size
        }
        self.setInteger(packetTypeByte, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(packetFlags, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt16(0), at: position)
        position += MemoryLayout<UInt16>.size
    }
}
