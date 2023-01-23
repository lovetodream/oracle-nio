import NIOCore

struct DataTypesRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType
    var onResponsePromise: EventLoopPromise<TNSMessage>?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest()

        buffer.writeInteger(MessageType.dataTypes.rawValue, as: UInt8.self)
        buffer.writeInteger(Constants.TNS_CHARSET_UTF8, endianness: .little)
        buffer.writeInteger(Constants.TNS_CHARSET_UTF8, endianness: .little)
        buffer.writeUB4(UInt32(connection.capabilities.compileCapabilities.count))
        buffer.writeBytes(connection.capabilities.compileCapabilities)
        buffer.writeInteger(UInt8(connection.capabilities.runtimeCapabilities.count))
        buffer.writeBytes(connection.capabilities.runtimeCapabilities)
        var i = 0
        while true {
            let dataType = DataType.all[i]
            if dataType.dataType == .undefined { break }
            i += 1
            buffer.writeInteger(dataType.dataType.rawValue)
            buffer.writeInteger(dataType.convDataType.rawValue)
            buffer.writeInteger(dataType.representation.rawValue)
            buffer.writeInteger(UInt16(0))
        }
        buffer.writeInteger(UInt16(0))

        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }

    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        // no handling needed
    }
}
