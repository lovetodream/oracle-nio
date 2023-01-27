import NIOCore

struct ConnectRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType
    var connectString: String?
    var onResponsePromise: EventLoopPromise<TNSMessage>?

    var functionCode: UInt8 = 0 // unused
    var currentSequenceNumber: UInt8 = 0 // unused

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() -> [TNSMessage] {
        guard let connectString else { preconditionFailure("ConnectString needs to be set before getting the messages") }
        var serviceOptions = Constants.TNS_GSO_DONT_CARE
        let connectFlags1: UInt32 = 0
        var connectFlags2: UInt32 = 0
        let nsiFlags: UInt8 = Constants.TNS_NSI_SUPPORT_SECURITY_RENEG | Constants.TNS_NSI_DISABLE_NA
        if connection.capabilities.supportsOOB == true {
            serviceOptions |= Constants.TNS_GSO_CAN_RECV_ATTENTION
            connectFlags2 |= Constants.TNS_CHECK_OOB
        }
        let connectStringByteLength = connectString.lengthOfBytes(using: .utf8)
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
            nsiFlags,
            nsiFlags,
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
            buffer.endRequest(packetType: .connect, capabilities: connection.capabilities)
            messages.append(.init(type: .connect, packet: buffer))
            buffer = ByteBuffer()
            buffer.startRequest()
        }
        buffer.writeString(connectString)
        let finalPacketType: PacketType = connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA ? .data : .connect
        buffer.endRequest(packetType: finalPacketType, capabilities: connection.capabilities)
        messages.append(.init(type: finalPacketType, packet: buffer))
        return messages
    }

    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        setReaderIndex(for: &message)
        switch message.type {
        case .resend:
            channel.write(self, promise: nil)
        case .accept:
            guard let protocolVersion = message.packet.readInteger(as: UInt16.self),
                  let protocolOptions = message.packet.readInteger(as: UInt16.self) else {
                throw MessageError.invalidResponse
            }
            connection.capabilities.adjustForProtocol(version: protocolVersion, options: protocolOptions)
            connection.readyForAuthenticationPromise.succeed(Void())
        default:
            fatalError("Unexpected response of type '\(message.type)' received for \(String(describing: self))")
        }
    }

    enum MessageError: Error {
        case invalidResponse
    }
}
