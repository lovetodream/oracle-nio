import NIOCore

extension ByteBuffer {
    /// Starts a new request with a placeholder for the header,
    /// which is set at the end of the request via ``ByteBuffer.endRequest``,
    /// and the data flags if they are required.
    mutating func startRequest(packetType: PacketType = .data, dataFlags: UInt16 = 0) {
        self.reserveCapacity(TNSMessage.headerSize)
        self.moveWriterIndex(forwardBy: TNSMessage.headerSize)
        if packetType == PacketType.data {
            self.writeInteger(dataFlags)
        }
    }
}
