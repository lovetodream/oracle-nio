import NIOCore

/// Message, which is sent to and received from Oracle.
struct TNSMessage {
    let type: PacketType
    var packet: ByteBuffer

    init?(from buffer: ByteBuffer) {
        guard
            buffer.readableBytes >= PACKET_HEADER_SIZE,
            let typeByte: UInt8 = buffer.getInteger(at: MemoryLayout<UInt32>.size),
            let type = PacketType(rawValue: typeByte)
        else {
            return nil
        }
        self.type = type
        self.packet = buffer
    }

    init(type: PacketType, packet: ByteBuffer) {
        self.type = type
        self.packet = packet
    }
}
