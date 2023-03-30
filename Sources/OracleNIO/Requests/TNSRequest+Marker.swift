import NIOCore

struct MarkerRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType

    var functionCode: UInt8 = 0 // unused
    var currentSequenceNumber: UInt8 = 0 // unused

    var onResponsePromise: NIOCore.EventLoopPromise<TNSMessage>?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() throws -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest(packetType: .marker)
        buffer.writeInteger(UInt8(1))
        buffer.writeInteger(UInt8(0))
        buffer.writeInteger(Constants.TNS_MARKER_TYPE_RESET)
        buffer.endRequest(packetType: .marker, capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }
}
