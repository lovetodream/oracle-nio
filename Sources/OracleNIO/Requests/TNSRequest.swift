import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: MessageType { get }
    var functionCode: UInt8 { get }
    var currentSequenceNumber: UInt8 { get set }
    var onResponsePromise: EventLoopPromise<TNSMessage>? { get set }
    init(connection: OracleConnection, messageType: MessageType)
    static func initialize(from connection: OracleConnection) -> Self
    func initializeHooks()
    func get() throws -> [TNSMessage]
    func preprocess()
    func processResponse(_ message: inout TNSMessage, from channel: Channel) throws
    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws
    func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws
    func postprocess()
    func processError(_ message: inout TNSMessage) -> OracleErrorInfo
    func processReturnParameters(_ message: inout TNSMessage)
    func processWarning(_ message: inout TNSMessage) -> OracleErrorInfo
    func processServerSidePiggyback(_ message: inout TNSMessage)
    func didProcessError()
    func hasMoreData(_ message: inout TNSMessage) -> Bool
    /// Set readerIndex for message to prepare for ``processResponse``.
    func setReaderIndex(for message: inout TNSMessage)
    func writeFunctionCode(to buffer: inout ByteBuffer)
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
        while hasMoreData(&message) {
            guard
                let messageTypeByte = message.packet.readInteger(as: UInt8.self)
            else {
                print(message.packet.readableBytes)
                print(message.packet.readString(length: message.packet.readableBytes))
                fatalError("Couldn't read single byte, but readableBytes is still bigger than 0.")
            }
            guard let messageType = MessageType(rawValue: messageTypeByte) else {
                throw OracleError.ErrorType.typeUnknown
            }
            try self.processResponse(&message, of: messageType, from: channel)
        }
        postprocess()
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        try defaultProcessResponse(&message, of: type, from: channel)
    }

    func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        connection.logger.trace("Response has message type: \(type)")
        switch type {
        case .error:
            let error = self.processError(&message)
            connection.logger.warning("Oracle Error occurred: \(error)")
        case .parameter:
            self.processReturnParameters(&message)
        case .status:
            let callStatus = message.packet.readInteger(as: UInt32.self) ?? 0
            let endToEndSequenceNumber = message.packet.readInteger(as: UInt16.self) ?? 0
            connection.logger.debug(
                "Received call status: \(callStatus) with end to end sequence number \(endToEndSequenceNumber)"
            )
        case .warning:
            let warning = self.processWarning(&message)
            connection.logger.warning(
                "The oracle server sent a warning",
                metadata: ["message": "\(warning.message ?? "empty")", "code": "\(warning.number)"]
            )
        case .serverSidePiggyback:
            self.processServerSidePiggyback(&message)
        default:
            connection.logger.error("Could not process message of type: \(type)")
            throw OracleError.ErrorType.typeUnknown
        }
    }

    func postprocess() {}

    func processError(_ message: inout TNSMessage) -> OracleErrorInfo {
        let callStatus = message.packet.readUB4() ?? 0 // end of call status
        connection.logger.debug("Call status received: \(callStatus)")
        message.packet.skipUB2() // end to end seq#
        message.packet.skipUB4() // current row number
        message.packet.skipUB2() // error number
        message.packet.skipUB2() // array elem error
        message.packet.skipUB2() // array elem error
        let cursorID = message.packet.readUB2() // cursor id
        let errorPosition = message.packet.readUB2() // error position
        message.packet.skipUB1() // sql type
        message.packet.skipUB1() // fatal?
        message.packet.skipUB2() // flags
        message.packet.skipUB2() // user cursor options
        message.packet.skipUB1() // UDI parameter
        message.packet.skipUB1() // warning flag
        let rowID = RowID.read(from: &message)
        message.packet.skipUB4() // OS error
        message.packet.skipUB1() // statement number
        message.packet.skipUB1() // call number
        message.packet.skipUB2() // padding
        message.packet.skipUB4() // success iters
        let numberOfBytes = message.packet.readUB4() ?? 0 // oerrdd (logical rowID)
        if numberOfBytes > 0 {
            message.packet.skipRawBytesChunked()
        }
        didProcessError()

        // batch error codes
        let numberOfCodes = message.packet.readUB2() ?? 0 // batch error codes array
        var batch = [OracleError]()
        if numberOfCodes > 0 {
            let firstByte = message.packet.readUB1() ?? 0
            for _ in 0..<numberOfCodes {
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    message.packet.skipUB4() // chunk length ignored
                }
                guard let errorCode = message.packet.readUB2() else { continue }
                batch.append(.init(code: Int(errorCode)))
            }
            if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                message.packet.moveReaderIndex(forwardByBytes: 1) // ignore end marker
            }
        }

        // batch error offsets
        let numberOfOffsets = message.packet.readUB2() ?? 0 // batch error row offset array
        if numberOfOffsets > 0 {
            let firstByte = message.packet.readUB1() ?? 0
            for i in 0..<numberOfOffsets {
                if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                    message.packet.skipUB4() // chunked length ignored
                }
                let offset = message.packet.readUB4() ?? 0
                batch[Int(i)].offset = Int(offset)
            }
            if firstByte == Constants.TNS_LONG_LENGTH_INDICATOR {
                message.packet.moveReaderIndex(forwardByBytes: 1) // ignore end marker
            }
        }

        // batch error messages
        let numberOfMessages = message.packet.readUB2() ?? 0 // batch error messages array
        if numberOfMessages > 0 {
            message.packet.moveReaderIndex(forwardByBytes: 1) // ignore packet size
            for i in 0..<numberOfMessages {
                message.packet.skipUB2() // skip chunk length
                let errorMessage = message.packet
                    .readString(with: Constants.TNS_CS_IMPLICIT)?
                    .trimmingCharacters(in: .whitespaces)
                batch[Int(i)].message = errorMessage
                message.packet.moveReaderIndex(forwardByBytes: 2) // ignore end marker
            }
        }

        let number = message.packet.readUB4() ?? 0
        let rowCount = message.packet.readUB8()
        let errorMessage: String?
        if number != 0 {
            errorMessage = message.packet
                .readString(with: Constants.TNS_CS_IMPLICIT)?
                .trimmingCharacters(in: .whitespaces)
        } else {
            errorMessage = nil
        }

        return OracleErrorInfo(
            number: number,
            cursorID: cursorID,
            position: errorPosition,
            rowCount: rowCount,
            isWarning: false,
            message: errorMessage,
            rowID: rowID,
            batchErrors: batch
        )
    }

    func processReturnParameters(_ message: inout TNSMessage) {
        fatalError("\(#function) has been called, but this should never have happened")
    }

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

    func didProcessError() { }

    func hasMoreData(_ message: inout TNSMessage) -> Bool {
        message.packet.readableBytes > 0
    }

    func setReaderIndex(for message: inout TNSMessage) {
        if message.packet.readerIndex < TNSMessage.headerSize && message.packet.capacity >= TNSMessage.headerSize {
            message.packet.moveReaderIndex(to: TNSMessage.headerSize)
        }
    }

    func writeFunctionCode(to buffer: inout ByteBuffer) {
        buffer.writeInteger(messageType.rawValue)
        buffer.writeInteger(functionCode)
        buffer.writeSequenceNumber()
        if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_23_1_EXT_1 {
            buffer.writeUB8(0) // token number
        }
    }
}
