import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: Int { get }
    var errorInfo: OracleErrorInfo? { get set }
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

struct NetworkServicesMessage: TNSRequest {
    var connection: OracleConnection
    var messageType: Int
    var errorInfo: OracleErrorInfo?

    init(connection: OracleConnection, messageType: Int) {
        self.connection = connection
        self.messageType = messageType
        self.errorInfo = nil
    }

    func get() -> [TNSMessage] {
        // Calculate package length
        var packetLength = NetworkService.Constants.TNS_NETWORK_HEADER_SIZE
        for service in NetworkService.all {
            packetLength += service.dataSize
        }

        var buffer = ByteBuffer()

        // Write header
        buffer.writeMultipleIntegers(NetworkService.Constants.TNS_NETWORK_MAGIC, UInt16(packetLength), NetworkService.Constants.TNS_NETWORK_VERSION, UInt16(NetworkService.all.count))
        buffer.writeInteger(0) // flags

        // Write service data
        for service in NetworkService.all {
            buffer.writeImmutableBuffer(service.writeData())
        }

        // TODO: find out which type is used here
        return [.init(type: .data, packet: buffer)]
    }

    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        setReaderIndex(for: &message)
        message.packet.moveReaderIndex(forwardBy: 2) // data flags
        let temp32 = message.packet.readInteger(as: UInt32.self) // network magic number
        if temp32 != NetworkService.Constants.TNS_NETWORK_MAGIC {
            throw OracleError.unexpectedData
        }
        message.packet.moveReaderIndex(forwardBy: 2) // length of packet
        message.packet.moveReaderIndex(forwardBy: 4) // version
        guard let numberOfServices = message.packet.readInteger(as: UInt16.self) else {
            throw OracleError.unexpectedData
        }
        message.packet.moveReaderIndex(forwardBy: 1) // error flags
        for _ in 0..<numberOfServices {
            message.packet.moveReaderIndex(forwardBy: 2) // service number
            let numberOfSubPackets = message.packet.readInteger(as: UInt16.self) ?? 0
            let errorNumber = message.packet.readInteger(as: UInt32.self) ?? 0
            if errorNumber != 0 {
                connection.logger.log(level: .error, "Listener refused connection", metadata: ["errorCode": "ORA-\(errorNumber)"])
                throw OracleError.listenerRefusedConnection
            }
            for _ in 0..<numberOfSubPackets {
                let dataLength = Int(message.packet.readInteger(as: UInt16.self) ?? 0)
                message.packet.moveReaderIndex(forwardBy: 2) // data type
                message.packet.moveReaderIndex(forwardBy: dataLength)
            }
        }
    }
}
