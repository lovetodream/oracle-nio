import NIOCore

/// Message, which is sent to and received from Oracle.
struct TNSMessage {
    static let headerSize = 8

    let type: PacketType
    let length: Int
    var packet: ByteBuffer

    init?(from buffer: inout ByteBuffer, with capabilities: Capabilities) {
        let length: Int?
        if capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            length = buffer.getInteger(at: 0, as: UInt32.self).map(Int.init(_:))
        } else {
            length = buffer.getInteger(at: 0, as: UInt16.self).map(Int.init(_:))
        }
        guard
            let length,
            buffer.readableBytes >= Self.headerSize,
            let typeByte: UInt8 = buffer.getInteger(at: MemoryLayout<UInt32>.size),
            let type = PacketType(rawValue: typeByte),
            let packet = buffer.readSlice(length: length)
        else {
            return nil
        }
        self.type = type
        self.length = length
        self.packet = packet
    }

    init(type: PacketType = .data, packet: ByteBuffer) {
        self.type = type
        self.length = packet.readableBytes
        self.packet = packet
    }
}
