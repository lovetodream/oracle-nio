import NIOCore

struct LogoffRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType
    var functionCode: UInt8 = Constants.TNS_FUNC_LOGOFF
    var currentSequenceNumber: UInt8 = 0

    var onResponsePromise: NIOCore.EventLoopPromise<TNSMessage>?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() throws -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest()
        writeFunctionCode(to: &buffer)
        buffer.endRequest(capabilities: connection.capabilities)
        return [TNSMessage(packet: buffer)]
    }
}
