struct NetworkServicesRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType
    var onResponsePromise: EventLoopPromise<TNSMessage>?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() -> [TNSMessage] {
        // Calculate package length
        var packetLength = NetworkService.Constants.TNS_NETWORK_HEADER_SIZE
        for service in NetworkService.all {
            packetLength += service.dataSize
        }

        var buffer = ByteBuffer()

        buffer.startRequest()

        // Write header
        buffer.writeMultipleIntegers(
            NetworkService.Constants.TNS_NETWORK_MAGIC,
            UInt16(packetLength), NetworkService.Constants.TNS_NETWORK_VERSION,
            UInt16(NetworkService.all.count)
        )
        buffer.writeInteger(UInt8(0)) // flags

        // Write service data
        for service in NetworkService.all {
            buffer.writeImmutableBuffer(service.writeData())
        }

        buffer.endRequest(capabilities: connection.capabilities)

        return [.init(packet: buffer)]
    }

    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        setReaderIndex(for: &message)
        message.packet.moveReaderIndex(forwardBy: 2) // data flags
        let temp32 = message.packet.readInteger(as: UInt32.self) // network magic number
        if temp32 != NetworkService.Constants.TNS_NETWORK_MAGIC {
            throw OracleError.ErrorType.unexpectedData
        }
        message.packet.moveReaderIndex(forwardBy: 2) // length of packet
        message.packet.moveReaderIndex(forwardBy: 4) // version
        guard let numberOfServices = message.packet.readInteger(as: UInt16.self) else {
            throw OracleError.ErrorType.unexpectedData
        }
        message.packet.moveReaderIndex(forwardBy: 1) // error flags
        for _ in 0..<numberOfServices {
            message.packet.moveReaderIndex(forwardBy: 2) // service number
            let numberOfSubPackets = message.packet.readInteger(as: UInt16.self) ?? 0
            let errorNumber = message.packet.readInteger(as: UInt32.self) ?? 0
            if errorNumber != 0 {
                connection.logger.error("Listener refused connection", metadata: ["errorCode": "ORA-\(errorNumber)"])
                throw OracleError.ErrorType.listenerRefusedConnection
            }
            for _ in 0..<numberOfSubPackets {
                let dataLength = Int(message.packet.readInteger(as: UInt16.self) ?? 0)
                message.packet.moveReaderIndex(forwardBy: 2) // data type
                message.packet.moveReaderIndex(forwardBy: dataLength)
            }
        }
    }
}
