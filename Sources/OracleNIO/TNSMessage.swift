import NIOCore

struct TNSMessage {
    let type: Constants.PacketType
    var packet: ByteBuffer

    init?(from buffer: ByteBuffer) {
        guard
            buffer.readableBytes >= PACKET_HEADER_SIZE,
            let typeByte: UInt8 = buffer.getInteger(at: MemoryLayout<UInt32>.size),
            let type = Constants.PacketType(rawValue: typeByte)
        else {
            return nil
        }
        self.type = type
        self.packet = buffer
    }

    init(type: Constants.PacketType, packet: ByteBuffer) {
        self.type = type
        self.packet = packet
    }
}
