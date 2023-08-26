import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: MessageType { get }
    var functionCode: Constants.FunctionCode { get }
    var currentSequenceNumber: UInt8 { get set }
    var onResponsePromise: EventLoopPromise<TNSMessage>? { get set }
    init(connection: OracleConnection, messageType: MessageType)
    static func initialize(from connection: OracleConnection) -> Self
}

extension TNSRequest {
    static func initialize(from connection: OracleConnection) -> Self {
        let message = Self.init(connection: connection, messageType: .function)
        return message
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        try defaultProcessResponse(&message, of: type, from: channel)
    }

    func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        connection.logger.trace("Response has message type: \(type)")
        switch type {
        case .status:
            let callStatus = message.packet.readInteger(as: UInt32.self) ?? 0
            let endToEndSequenceNumber = message.packet.readInteger(as: UInt16.self) ?? 0
            connection.logger.debug(
                "Received call status: \(callStatus) with end to end sequence number \(endToEndSequenceNumber)"
            )
        case .serverSidePiggyback:
            self.processServerSidePiggyback(&message)
        default:
            connection.logger.error("Could not process message of type: \(type)")
            throw OracleError.ErrorType.typeUnknown
        }
    }

    func processServerSidePiggyback(_ message: inout TNSMessage) {
        let opCode = ServerPiggybackCode(rawValue: message.packet.readInteger(as: UInt8.self) ?? 0)
        var temp16: UInt16 = 0
        switch opCode {
        case .ltxID:
            let numberOfBytes = message.packet.readInteger(as: UInt32.self) ?? 0
            if numberOfBytes > 0 {
                message.packet.moveReaderIndex(forwardByBytes: Int(numberOfBytes))
            }
        case .queryCacheInvalidation, .traceEvent, .none:
            break
        case .osPidMts:
            temp16 = message.packet.readInteger(as: UInt16.self) ?? 0
            message.skipChunk()
        case .sync:
            message.packet.moveReaderIndex(forwardByBytes: 2) // skip number of DTYs
            message.packet.moveReaderIndex(forwardByBytes: 1) // skip length of DTYs
            let numberOfElements = message.packet.readInteger(as: UInt16.self) ?? 0
            message.packet.moveReaderIndex(forwardByBytes: 1) // skip length
            for _ in 0..<numberOfElements {
                temp16 = message.packet.readInteger(as: UInt16.self) ?? 0
                if temp16 > 0 { // skip key
                    message.skipChunk()
                }
                temp16 = message.packet.readInteger(as: UInt16.self) ?? 0
                if temp16 > 0 { // skip value
                    message.skipChunk()
                }
                message.packet.moveReaderIndex(forwardByBytes: 2) // skip flags
            }
            message.packet.moveReaderIndex(forwardByBytes: 4) // skip overall flags
        case .extSync:
            message.packet.moveReaderIndex(forwardByBytes: 2) // skip number of DTYs
            message.packet.moveReaderIndex(forwardByBytes: 1) // skip length of DTYs
        case .acReplayContext:
            message.packet.moveReaderIndex(forwardByBytes: 2) // skip number of DTYs
            message.packet.moveReaderIndex(forwardByBytes: 1) // skip length of DTYs
            message.packet.moveReaderIndex(forwardByBytes: 4) // skip flags
            message.packet.moveReaderIndex(forwardByBytes: 4) // skip error code
            message.packet.moveReaderIndex(forwardByBytes: 1) // skip queue
            let numberOfBytes = message.packet.readInteger(as: UInt32.self) ?? 0 // skip replay context
            if numberOfBytes > 0 {
                message.packet.moveReaderIndex(forwardByBytes: Int(numberOfBytes))
            }
        case .sessRet:
            message.packet.moveReaderIndex(forwardByBytes: 2)
            message.packet.moveReaderIndex(forwardByBytes: 1)
            let numberOfElements = message.packet.readInteger(as: UInt16.self) ?? 0
            if numberOfElements > 0 {
                message.packet.moveReaderIndex(forwardByBytes: 1)
                for _ in 0..<numberOfElements {
                    temp16 = message.packet.readInteger(as: UInt16.self) ?? 0
                    if temp16 > 0 { // skip key
                        message.skipChunk()
                    }
                    temp16 = message.packet.readInteger(as: UInt16.self) ?? 0
                    if temp16 > 0 { // skip value
                        message.skipChunk()
                    }
                    message.packet.moveReaderIndex(forwardByBytes: 2) // skip flags
                }
            }
            let flags = message.packet.readInteger(as: UInt32.self) ?? 0 // session flags
            if flags & Constants.TNS_SESSGET_SESSION_CHANGED != 0 {
                // TODO: establish drcp session
                if self.connection.drcpEstablishSession {
                    self.connection.resetStatementCache()
                }
            }
            self.connection.drcpEstablishSession = false
            message.packet.moveReaderIndex(forwardByBytes: 4)
            message.packet.moveReaderIndex(forwardByBytes: 2)
        }
    }
}
