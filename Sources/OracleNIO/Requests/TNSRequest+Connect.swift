import NIOCore

struct ConnectRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: Int
    var errorInfo: OracleErrorInfo?
    var connectString: String

    init(connection: OracleConnection, messageType: Int) {
        self.connection = connection
        self.messageType = messageType
        self.errorInfo = nil
        self.connectString = "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=XEPDB1)(CID=(PROGRAM=xctest)(HOST=MacBook-Pro-von-Timo.local)(USER=timozacherl)))(ADDRESS=(PROTOCOL=tcp)(HOST=192.168.1.22)(PORT=1521)))"
    }

    func get() -> [TNSMessage] {
        var serviceOptions = Constants.TNS_BASE_SERVICE_OPTIONS
        let connectFlags1: UInt32 = 0
        var connectFlags2: UInt32 = 0
        if connection.capabilities.supportsOOB == true {
            serviceOptions |= Constants.TNS_CAN_RECV_ATTENTION
            connectFlags2 |= Constants.TNS_CHECK_OOB
        }
        let connectStringByteLength = self.connectString.lengthOfBytes(using: .utf8)
        var messages = [TNSMessage]()
        var buffer = ByteBuffer()
        buffer.startRequest(packetType: .connect)
        buffer.writeMultipleIntegers(
            Constants.TNS_VERSION_DESIRED,
            Constants.TNS_VERSION_MINIMUM,
            serviceOptions,
            Constants.TNS_SDU,
            Constants.TNS_TDU,
            Constants.TNS_PROTOCOL_CHARACTERISTICS,
            UInt16(0), // line turnaround
            UInt16(1), // value of 1
            UInt16(connectStringByteLength)
        )
        buffer.writeMultipleIntegers(
            UInt16(74), // offset to connect data
            UInt32(0), // max receivable data
            Constants.TNS_CONNECT_FLAGS,
            UInt64(0), // obsolete
            UInt64(0), // obsolete
            UInt64(0), // obsolete
            UInt32(Constants.TNS_SDU), // SDU (large)
            UInt32(Constants.TNS_TDU), // SDU (large)
            connectFlags1,
            connectFlags2
        )
        if connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA {
            // TODO: this does not work yet
            buffer.endRequest(packetType: .connect)
            messages.append(.init(type: .connect, packet: buffer))
            buffer = ByteBuffer()
            buffer.startRequest(packetType: .data)
        }
        buffer.writeString(self.connectString)
        let finalPacketType: Constants.PacketType = connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA ? .data : .connect
        buffer.endRequest(packetType: finalPacketType)
        messages.append(.init(type: finalPacketType, packet: buffer))
        return messages
    }

    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        if message.packet.readerIndex < PACKET_HEADER_SIZE && message.packet.capacity >= PACKET_HEADER_SIZE {
            message.packet.moveReaderIndex(to: PACKET_HEADER_SIZE)
        }
        switch message.type {
        case .resend:
            channel.write(self, promise: nil)
        case .accept:
            guard let protocolVersion = message.packet.readInteger(as: UInt16.self),
                  let protocolOptions = message.packet.readInteger(as: UInt16.self) else {
                throw MessageError.invalidResponse
            }
            connection.capabilities.adjustForProtocol(version: protocolVersion, options: protocolOptions)
            print(connection.capabilities)
        default:
            fatalError("Unexpected response of type '\(message.type)' received for \(String(describing: self))")
        }
    }

    enum MessageError: Error {
        case invalidResponse
    }
}
