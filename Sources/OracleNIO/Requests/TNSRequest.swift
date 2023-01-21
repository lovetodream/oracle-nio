import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: Int { get }
    var errorInfo: OracleErrorInfo? { get set }
    var onResponsePromise: EventLoopPromise<TNSMessage>? { get set }
    init(connection: OracleConnection, messageType: Int)
    static func initialize(from connection: OracleConnection) -> Self
    func initializeHooks()
    func get() -> [TNSMessage]
    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws
    /// Set readerIndex for message to prepare for ``processResponse``.
    func setReaderIndex(for message: inout TNSMessage)
}

extension TNSRequest {
    static func initialize(from connection: OracleConnection) -> Self {
        let message = Self.init(connection: connection, messageType: Constants.TNS_MSG_TYPE_FUNCTION)
        message.initializeHooks()
        return message
    }

    func initializeHooks() {}
    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {}
    func setReaderIndex(for message: inout TNSMessage) {
        if message.packet.readerIndex < PACKET_HEADER_SIZE && message.packet.capacity >= PACKET_HEADER_SIZE {
            message.packet.moveReaderIndex(to: PACKET_HEADER_SIZE)
        }
    }
}

//struct AuthMessage: TNSRequest {
//
//}

struct ProtocolRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: Int
    var errorInfo: OracleErrorInfo?
    var onResponsePromise: EventLoopPromise<TNSMessage>?

    init(connection: OracleConnection, messageType: Int) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest()
        buffer.writeInteger(Constants.TNS_MSG_TYPE_PROTOCOL)
        buffer.writeInteger(UInt8(6)) // protocol version (8.1 and higher)
        buffer.writeInteger(UInt8(0)) // "array" terminator
        buffer.writeString(Constants.DRIVER_NAME)
        buffer.writeInteger(UInt8(0)) // NULL terminator
        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }


}
