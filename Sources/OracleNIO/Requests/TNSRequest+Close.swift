import NIOCore

struct CloseRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType
    var functionCode: UInt8 = 0
    var currentSequenceNumber: UInt8 = 0
    var onResponsePromise: NIOCore.EventLoopPromise<TNSMessage>?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() throws -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest(packetType: .data, dataFlags: Constants.TNS_DATA_FLAGS_EOF)
        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }
}
