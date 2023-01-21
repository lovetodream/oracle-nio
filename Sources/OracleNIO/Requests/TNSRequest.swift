import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: MessageType { get }
    var onResponsePromise: EventLoopPromise<TNSMessage>? { get set }
    init(connection: OracleConnection, messageType: MessageType)
    static func initialize(from connection: OracleConnection) -> Self
    func initializeHooks()
    func get() -> [TNSMessage]
    func preprocess()
    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws
    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws
    func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws
    func postprocess()
    func processError(_ message: inout TNSMessage) -> OracleErrorInfo
    func processReturnParameters(_ message: inout TNSMessage)
    func processWarning(_ message: inout TNSMessage) -> OracleErrorInfo
    func processServerSidePiggyback(_ message: inout TNSMessage)
    /// Set readerIndex for message to prepare for ``processResponse``.
    func setReaderIndex(for message: inout TNSMessage)
}

extension TNSRequest {
    static func initialize(from connection: OracleConnection) -> Self {
        let message = Self.init(connection: connection, messageType: .function)
        message.initializeHooks()
        return message
    }

    func initializeHooks() {}
    func preprocess() {}

    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        preprocess()
        setReaderIndex(for: &message)
        message.packet.moveReaderIndex(forwardBy: 2) // skip data flags
        while message.packet.readableBytes > 0 {
            guard let messageTypeByte = message.packet.readInteger(as: UInt8.self), let messageType = MessageType(rawValue: messageTypeByte) else {
                fatalError("Couldn't read single byte, but readableBytes is still bigger than 0.")
            }
            try self.processResponse(&message, of: messageType, from: channel)
        }
        postprocess()
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        try defaultProcessResponse(&message, of: type, from: channel)
    }

    func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        switch type {
        case .error:
            throw self.processError(&message)
        case .parameter:
            self.processReturnParameters(&message)
        case .status:
            let callStatus = message.packet.readInteger(as: UInt32.self) ?? 0
            let endToEndSequenceNumber = message.packet.readInteger(as: UInt16.self) ?? 0
            connection.logger.log(
                level: .debug,
                "Received call status: \(callStatus) with end to end sequence number \(endToEndSequenceNumber)"
            )
        case .warning:
            let warning = self.processWarning(&message)
            connection.logger.log(
                level: .warning,
                "The oracle server sent a warning",
                metadata: ["message": "\(warning.message ?? "empty")", "code": "\(warning.number)"]
            )
        case .serverSidePiggyback:
            self.processServerSidePiggyback(&message)
        default:
            throw OracleError.ErrorType.typeUnknown
        }
    }

    func postprocess() {}

    func processError(_ message: inout TNSMessage) -> OracleErrorInfo {
        let callStatus = message.packet.readInteger(as: UInt32.self) ?? 0 // end of call status
        connection.logger.log(level: .debug, "Call status received: \(callStatus)")
        message.packet.moveReaderIndex(forwardByBytes: 2) // end to end seq#
        message.packet.moveReaderIndex(forwardByBytes: 4) // current row number
        message.packet.moveReaderIndex(forwardByBytes: 2) // error number
        message.packet.moveReaderIndex(forwardByBytes: 2) // array elem error
        message.packet.moveReaderIndex(forwardByBytes: 2) // array elem error
        let cursorID = message.packet.readInteger(as: UInt16.self) // cursor id
        let errorPosition = message.packet.readInteger(as: UInt16.self) // error position
        message.packet.moveReaderIndex(forwardByBytes: 1) // sql type
        message.packet.moveReaderIndex(forwardByBytes: 1) // fatal?
        message.packet.moveReaderIndex(forwardByBytes: 2) // flags
        message.packet.moveReaderIndex(forwardByBytes: 2) // user cursor options
        message.packet.moveReaderIndex(forwardByBytes: 1) // UDI parameter
        message.packet.moveReaderIndex(forwardByBytes: 1) // warning flag
        let rowID = RowID.read(from: &message)
        message.packet.moveReaderIndex(forwardByBytes: 4) // OS error
        message.packet.moveReaderIndex(forwardByBytes: 1) // statement number
        message.packet.moveReaderIndex(forwardByBytes: 1) // call number
        message.packet.moveReaderIndex(forwardByBytes: 2) // padding
        message.packet.moveReaderIndex(forwardByBytes: 4) // success iters
        let numberOfBytes = message.packet.readInteger(as: UInt32.self) ?? 0 // oerrdd (logical rowID)
        if numberOfBytes > 0 {
            message.skipChunk()
        }

        // batch error codes
        let numberOfCodes = message.packet.readInteger(as: UInt16.self) ?? 0 // batch error codes array
        var batch = [OracleError]()
        if numberOfCodes > 0 {
            let firstByte = message.packet.readInteger(as: UInt8.self) ?? 0
            for _ in 0..<numberOfCodes {
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    message.packet.moveReaderIndex(forwardByBytes: 4) // chunk length ignored
                }
                guard let errorCode = message.packet.readInteger(as: UInt16.self) else { continue }
                batch.append(.init(code: Int(errorCode)))
            }
            if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                message.packet.moveReaderIndex(forwardByBytes: 1) // ignore end marker
            }
        }

        // batch error offsets
        let numberOfOffsets = message.packet.readInteger(as: UInt16.self) ?? 0 // batch error row offset array
        if numberOfOffsets > 0 {
            let firstByte = message.packet.readInteger(as: UInt8.self) ?? 0
            for i in 0..<numberOfOffsets {
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    message.packet.moveReaderIndex(forwardByBytes: 4) // chunked length ignored
                }
                let offset = message.packet.readInteger(as: UInt32.self) ?? 0
                batch[Int(i)].offset = Int(offset)
            }
            if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                message.packet.moveReaderIndex(forwardByBytes: 1) // ignore end marker
            }
        }

        // batch error messages
        let numberOfMessages = message.packet.readInteger(as: UInt16.self) ?? 0 // batch error messages array
        if numberOfMessages > 0 {
            message.packet.moveReaderIndex(forwardByBytes: 1) // ignore packet size
            for i in 0..<numberOfMessages {
                message.packet.moveReaderIndex(forwardByBytes: 2) // skip chunk length
                let errorMessage = message.packet.readString(with: Constants.TNS_CS_IMPLICIT)?.trimmingCharacters(in: .whitespaces)
                batch[Int(i)].message = errorMessage
                message.packet.moveReaderIndex(forwardByBytes: 2) // ignore end marker
            }
        }

        let number = message.packet.readInteger(as: UInt32.self) ?? 0
        let rowCount = message.packet.readInteger(as: UInt64.self)
        let errorMessage: String?
        if number != 0 {
            errorMessage = message.packet.readString(with: Constants.TNS_CS_IMPLICIT)?.trimmingCharacters(in: .whitespaces)
        } else { errorMessage = nil }

        return OracleErrorInfo(number: number, cursorID: cursorID, position: errorPosition, rowCount: rowCount, isWarning: false, message: errorMessage, rowID: rowID, batchErrors: batch)
    }

    func processReturnParameters(_ message: inout TNSMessage) {}

    func processWarning(_ message: inout TNSMessage) -> OracleErrorInfo {
        let number = message.packet.readInteger(as: UInt16.self) ?? 0 // error number
        let numberOfBytes = message.packet.readInteger(as: UInt16.self) ?? 0 // length of error message
        message.packet.moveReaderIndex(forwardByBytes: 2) // flags
        let errorMessage: String?
        if number != 0 && numberOfBytes > 0 {
            errorMessage = message.packet.readString(length: Int(numberOfBytes))
        } else {
            errorMessage = nil
        }
        return OracleErrorInfo(number: UInt32(number), isWarning: true, message: errorMessage, batchErrors: [])
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

    func setReaderIndex(for message: inout TNSMessage) {
        if message.packet.readerIndex < PACKET_HEADER_SIZE && message.packet.capacity >= PACKET_HEADER_SIZE {
            message.packet.moveReaderIndex(to: PACKET_HEADER_SIZE)
        }
    }
}

//struct AuthMessage: TNSRequest {
//
//}
