struct ProtocolRequest: TNSRequest {
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
        buffer.writeInteger(MessageType.protocol.rawValue)
        buffer.writeInteger(UInt8(6)) // protocol version (8.1 and higher)
        buffer.writeInteger(UInt8(0)) // "array" terminator
        buffer.writeString(Constants.DRIVER_NAME)
        buffer.writeInteger(UInt8(0)) // NULL terminator
        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        if type == .protocol {
            message.packet.moveReaderIndex(forwardByBytes: 2) // skip protocol array
            while true { // skip server banner
                let c = message.packet.readInteger(as: UInt8.self) ?? 0
                if c == 0 { break }
            }
            let charsetID = message.packet
                .readInteger(endianness: .little, as: UInt16.self) ?? Constants.TNS_CHARSET_UTF8
            connection.capabilities.characterConversion = charsetID != Constants.TNS_CHARSET_UTF8
            message.packet.moveReaderIndex(forwardByBytes: 1) // skip server flags
            let numberOfElements = message.packet.readInteger(endianness: .little, as: UInt16.self) ?? 0
            if numberOfElements > 0 { // skip elements
                message.packet.moveReaderIndex(forwardByBytes: Int(numberOfElements) * 5)
            }
            guard
                let fdoLength = message.packet.readInteger(as: UInt16.self),
                let fdo = message.packet.readBytes(length: Int(fdoLength))
            else { throw OracleError.ErrorType.unexpectedData }
            let ix = 6 + fdo[5] + fdo[6]
            connection.capabilities.nCharsetID = UInt16((fdo[Int(ix) + 3] << 8) + fdo[Int(ix) + 4])
            var temporaryBuffer = message.packet.readChunk()
            if let temporaryBuffer {
                let serverCompileCapabilities = temporaryBuffer
                connection.capabilities.adjustForServerCompileCapabilities(serverCompileCapabilities)
            }
            temporaryBuffer = message.packet.readChunk()
            if let temporaryBuffer {
                let serverRuntimeCapabilities = temporaryBuffer
                connection.capabilities.adjustForServerRuntimeCapabilities(serverRuntimeCapabilities)
            }
        } else {
            try defaultProcessResponse(&message, of: type, from: channel)
        }
    }
}
