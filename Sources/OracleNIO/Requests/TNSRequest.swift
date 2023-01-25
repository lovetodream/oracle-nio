import NIOCore

protocol TNSRequest {
    var connection: OracleConnection { get }
    var messageType: MessageType { get }
    var functionCode: UInt8 { get }
    var currentSequenceNumber: UInt8 { get set }
    var onResponsePromise: EventLoopPromise<TNSMessage>? { get set }
    init(connection: OracleConnection, messageType: MessageType)
    static func initialize(from connection: OracleConnection) -> Self
    mutating func initializeHooks()
    mutating func get() throws -> [TNSMessage]
    mutating func preprocess()
    mutating func processResponse(_ message: inout TNSMessage, from channel: Channel) throws
    mutating func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws
    mutating func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws
    mutating func postprocess()
    mutating func processError(_ message: inout TNSMessage) -> OracleErrorInfo
    mutating func processReturnParameters(_ message: inout TNSMessage)
    mutating func processWarning(_ message: inout TNSMessage) -> OracleErrorInfo
    mutating func processServerSidePiggyback(_ message: inout TNSMessage)
    mutating func writeFunctionCode(to buffer: inout ByteBuffer)
    /// Set readerIndex for message to prepare for ``processResponse``.
    func setReaderIndex(for message: inout TNSMessage)
}

extension TNSRequest {
    static func initialize(from connection: OracleConnection) -> Self {
        var message = Self.init(connection: connection, messageType: .function)
        message.initializeHooks()
        return message
    }

    mutating func initializeHooks() {}
    mutating func preprocess() {}

    mutating func processResponse(_ message: inout TNSMessage, from channel: Channel) throws {
        preprocess()
        setReaderIndex(for: &message)
        message.packet.moveReaderIndex(forwardBy: 2) // skip data flags
        if message.packet.readableBytes > 0 {
            guard
                let messageTypeByte = message.packet.readInteger(as: UInt8.self),
                let messageType = MessageType(rawValue: messageTypeByte)
            else {
                fatalError("Couldn't read single byte, but readableBytes is still bigger than 0.")
            }
            try self.processResponse(&message, of: messageType, from: channel)
        }
        postprocess()
    }

    mutating func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        try defaultProcessResponse(&message, of: type, from: channel)
    }

    mutating func defaultProcessResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        connection.logger.trace("Response has message type: \(type)")
        switch type {
        case .error:
            throw self.processError(&message)
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

    mutating func postprocess() {}

    mutating func processError(_ message: inout TNSMessage) -> OracleErrorInfo {
        let callStatus = message.packet.readInteger(as: UInt32.self) ?? 0 // end of call status
        connection.logger.debug("Call status received: \(callStatus)")
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
                let errorMessage = message.packet
                    .readString(with: Constants.TNS_CS_IMPLICIT)?
                    .trimmingCharacters(in: .whitespaces)
                batch[Int(i)].message = errorMessage
                message.packet.moveReaderIndex(forwardByBytes: 2) // ignore end marker
            }
        }

        let number = message.packet.readInteger(as: UInt32.self) ?? 0
        let rowCount = message.packet.readInteger(as: UInt64.self)
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

    mutating func processReturnParameters(_ message: inout TNSMessage) {
        fatalError("\(#function) has been called, but this should never have happened")
    }

    mutating func processWarning(_ message: inout TNSMessage) -> OracleErrorInfo {
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

    mutating func processServerSidePiggyback(_ message: inout TNSMessage) {
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

    mutating func writeFunctionCode(to buffer: inout ByteBuffer) {
        buffer.writeInteger(self.messageType.rawValue)
        buffer.writeInteger(self.functionCode)
        buffer.writeSequenceNumber(with: self.currentSequenceNumber)
        self.currentSequenceNumber += 1
    }

    func setReaderIndex(for message: inout TNSMessage) {
        if message.packet.readerIndex < TNSMessage.headerSize && message.packet.capacity >= TNSMessage.headerSize {
            message.packet.moveReaderIndex(to: TNSMessage.headerSize)
        }
    }
}

import Crypto

final class AuthRequest: TNSRequest {
    var connection: OracleConnection
    var messageType: MessageType
    var functionCode: UInt8 = Constants.TNS_FUNC_AUTH_PHASE_ONE
    var currentSequenceNumber: UInt8 = 0
    var onResponsePromise: EventLoopPromise<TNSMessage>?

    var resend: Bool = false
    var sessionData: Dictionary<String, String> = [:]
    var sessionKey: String?
    var username: [UInt8]?
    var usernameLength: Int?
    var authMode: UInt32 = 0
    var password: [UInt8]?
    var encodedPassword: String?
    var newPassword: [UInt8]?
    var encodedNewPassword: String?
    var purity: Purity = .default
    var serviceName: String = ""
    var verifierType: UInt32?
    var speedyKey: String?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func initializeHooks() {
        self.functionCode = Constants.TNS_FUNC_AUTH_PHASE_ONE
        self.sessionData = [:]
        if !connection.configuration.username.isEmpty {
            self.username = connection.configuration.username.data(using: .utf8)?.bytes
            self.usernameLength = username?.count
        }
        self.resend = true
    }

    /// Sets the parameters to use for the ``AuthRequest``.
    ///
    /// The user and auth mode are retained in order to avoid duplicating this effort for both trips to the server.
    func setParameters(_ connectParameters: ConnectParameters, with description: Description) {
        self.password = connectParameters.getPassword()
        self.newPassword = connectParameters.getNewPassword()
        self.serviceName = description.serviceName

        // TODO: DRCP support
        // context: if drcp is used, use purity = NEW as the default purity for
        // standalone connections and purity = SELF for connections that belong
        // to a pool
        // for now just use the value from description
        self.purity = description.purity

        // Set authentication mode
        if connectParameters.newPassword == nil {
            self.authMode = Constants.TNS_AUTH_MODE_LOGON
        }
        if AuthenticationMode.sysDBA.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSDBA
        }
        if AuthenticationMode.sysOPER.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSOPER
        }
        if AuthenticationMode.sysASM.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSASM
        }
        if AuthenticationMode.sysBKP.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSBKP
        }
        if AuthenticationMode.sysDGD.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSDGD
        }
        if AuthenticationMode.sysKMT.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSKMT
        }
        if AuthenticationMode.sysRAC.compare(with: connectParameters.mode) {
            self.authMode |= Constants.TNS_AUTH_MODE_SYSRAC
        }
    }

    func get() throws -> [TNSMessage] {
        let usernameLength = self.usernameLength ?? 0
        let hasUser: UInt8 = usernameLength > 0 ? 1 : 0
        var verifier11g = false
        var numberOfPairs: UInt32

        if self.functionCode == Constants.TNS_FUNC_AUTH_PHASE_ONE {
            numberOfPairs = 5
        } else {
            numberOfPairs = 3

            // user/password authentication
            numberOfPairs += 2
            self.authMode |= Constants.TNS_AUTH_MODE_WITH_PASSWORD
            if [Constants.TNS_VERIFIER_TYPE_11G_1, Constants.TNS_VERIFIER_TYPE_11G_2].contains(self.verifierType) {
                verifier11g = true
            } else if self.verifierType != Constants.TNS_VERIFIER_TYPE_12C {
                throw OracleError.ErrorType.unsupportedVerifierType
            } else {
                numberOfPairs += 1
            }
            try self.generateVerifier(verifier11g)

            // determine which other key/value pairs to write
            if self.newPassword != nil {
                numberOfPairs += 1
                self.authMode |= Constants.TNS_AUTH_MODE_CHANGE_PASSWORD
            }
            if self.purity != .default {
                numberOfPairs += 1
            }
        }

        var buffer = ByteBuffer()
        buffer.startRequest()

        // write basic data to packet
        self.writeFunctionCode(to: &buffer)
        buffer.writeInteger(hasUser) // pointer (authuser)
        buffer.writeUB4(UInt32(usernameLength))
        buffer.writeUB4(authMode) // authentication mode
        buffer.writeInteger(UInt8(1)) // pointer (authiv1)
        buffer.writeUB4(numberOfPairs) // number of key/value pairs
        buffer.writeInteger(UInt8(1)) // pointer (authovl)
        buffer.writeInteger(UInt8(1)) // pointer (authovln)
        if hasUser != 0, let username {
            buffer.writeBytes(username)
        }

        // write key/value pairs
        if self.functionCode == Constants.TNS_FUNC_AUTH_PHASE_ONE {
            self.writeKeyValuePair(&buffer, key: "AUTH_TERMINAL", value: ConnectConstants.default.terminalName)
            self.writeKeyValuePair(&buffer, key: "AUTH_PROGRAM_NM", value: ConnectConstants.default.programName)
            self.writeKeyValuePair(&buffer, key: "AUTH_MACHINE", value: ConnectConstants.default.machineName)
            self.writeKeyValuePair(&buffer, key: "AUTH_PID", value: String(ConnectConstants.default.pid))
            self.writeKeyValuePair(&buffer, key: "AUTH_SID", value: ConnectConstants.default.username)
        } else {
            guard let sessionKey, let encodedPassword else {
                preconditionFailure("session key and password needs to be generated before running authentication phase two")
            }
            self.writeKeyValuePair(&buffer, key: "AUTH_SESSKEY", value: sessionKey, flags: 1)
            self.writeKeyValuePair(&buffer, key: "AUTH_PASSWORD", value: encodedPassword)
            if !verifier11g {
                guard let speedyKey else {
                    preconditionFailure("speedy key needs to be generated before running authentication phase two")
                }
                self.writeKeyValuePair(&buffer, key: "AUTH_PBKDF2_SPEEDY_KEY", value: speedyKey)
            }
            if let encodedNewPassword {
                self.writeKeyValuePair(&buffer, key: "AUTH_NEWPASSWORD", value: encodedNewPassword)
            }
            self.writeKeyValuePair(&buffer, key: "SESSION_CLIENT_CHARSET", value: "873")
            let driverName = "\(Constants.DRIVER_NAME) thn : \(Constants.VERSION)"
            self.writeKeyValuePair(&buffer, key: "SESSION_CLIENT_DRIVER_NAME", value: driverName)
            self.writeKeyValuePair(&buffer, key: "SESSION_CLIENT_VERSION", value: "\(Constants.VERSION_CODE)")
            if self.purity != .default {
                self.writeKeyValuePair(&buffer, key: "AUTH_KPPL_PURITY", value: String(self.purity.rawValue), flags: 1)
            }
        }

        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }

    func processReturnParameters(_ message: inout TNSMessage) {
        let numberOfParameters = message.packet.readUB2() ?? 0
        for _ in 0..<numberOfParameters {
            message.packet.skipUB4()
            guard let key = message.packet.readString(with: Constants.TNS_CS_IMPLICIT) else {
                preconditionFailure()
            }
            let numberOfBytes = message.packet.readUB4() ?? 0
            let value: String
            if numberOfBytes > 0 {
                value = message.packet.readString(with: Constants.TNS_CS_IMPLICIT) ?? ""
            } else {
                value = ""
            }
            if key == "AUTH_VFR_DATA" {
                self.verifierType = message.packet.readUB4()
            } else {
                message.packet.skipUB4()
            }
            self.sessionData[key] = value
        }
        if self.functionCode == Constants.TNS_FUNC_AUTH_PHASE_ONE {
            self.functionCode = Constants.TNS_FUNC_AUTH_PHASE_TWO
        } else {
            guard
                let sessionIDStr = self.sessionData["SESSION_ID"],
                let sessionID = Int(sessionIDStr),
                let serialNumberStr = self.sessionData["AUTH_SERIAL_NUM"],
                let serialNumber = Int(serialNumberStr)
            else {
                preconditionFailure()
            }
            self.connection.sessionID = sessionID
            self.connection.serialNumber = serialNumber
            self.connection.serverVersion = self.getVersion()
        }
    }

    func writeFunctionCode(to buffer: inout ByteBuffer) {
        buffer.writeInteger(self.messageType.rawValue)
        buffer.writeInteger(self.functionCode)
        buffer.writeSequenceNumber(with: self.currentSequenceNumber)
        self.currentSequenceNumber += 1
    }

    /// Returns the 5-tuple for the database version. Note that the format changed with Oracle Database 18.
    /// https://www.krenger.ch/blog/oracle-version-numbers/
    ///
    /// Oracle Release Number Format:
    /// ```
    /// 12.1.0.1.0
    ///  ┬ ┬ ┬ ┬ ┬
    ///  │ │ │ │ └───── Platform-Specific Release Number
    ///  │ │ │ └────────── Component-Specific Release Number
    ///  │ │ └─────────────── Fusion Middleware Release Number
    ///  │ └──────────────────── Database Maintenance Release Number
    ///  └───────────────────────── Major Database Release Number
    ///  ```
    private func getVersion() -> OracleVersion {
        guard let fullVersionNumberStr = self.sessionData["AUTH_VERSION_NO"], let fullVersionNumber = Int(fullVersionNumberStr) else {
            preconditionFailure()
        }
        if self.connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_18_1_EXT_1 {
            return OracleVersion(
                majorDatabaseReleaseNumber: (fullVersionNumber >> 24) & 0xff,
                databaseMaintenanceReleaseNumber: (fullVersionNumber >> 16) & 0xff,
                fusionMiddlewareReleaseNumber: (fullVersionNumber >> 12) & 0x0f,
                componentSpecificReleaseNumber: (fullVersionNumber >> 4) & 0xff,
                platformSpecificReleaseNumber: fullVersionNumber & 0x0f
            )
        } else {
            return OracleVersion(
                majorDatabaseReleaseNumber: (fullVersionNumber >> 24) & 0xff,
                databaseMaintenanceReleaseNumber: (fullVersionNumber >> 20) & 0x0f,
                fusionMiddlewareReleaseNumber: (fullVersionNumber >> 12) & 0x0f,
                componentSpecificReleaseNumber: (fullVersionNumber >> 8) & 0x0f,
                platformSpecificReleaseNumber: fullVersionNumber & 0x0f
            )
        }
    }

    private func writeKeyValuePair(_ buffer: inout ByteBuffer, key: String, value: String, flags: UInt32 = 0) {
        let keyBytes = key.bytes
        let keyLength = keyBytes.count
        let valueBytes = value.bytes
        let valueLength = valueBytes.count
        buffer.writeUB4(UInt32(keyLength))
        buffer.writeBytesAndLength(keyBytes)
        buffer.writeUB4(UInt32(valueLength))
        if valueLength > 0 {
            buffer.writeBytesAndLength(valueBytes)
        }
        buffer.writeUB4(flags)
    }

    private func generateVerifier(_ verifier11g: Bool) throws {
        guard let authVFRData = sessionData["AUTH_VFR_DATA"] else {
            preconditionFailure("AUTH_VFR_DATA needs to be in \(sessionData)")
        }
        guard let password else {
            preconditionFailure("A password needs to be set, to use the verifier")
        }
        let verifierData = Self.hexToBytes(string: authVFRData)
        let keyLength: Int

        // create password hash
        let passwordHash: [UInt8]
        let passwordKey: [UInt8]?
        if verifier11g {
            keyLength = 24
            var sha = Insecure.SHA1()
            sha.update(data: password)
            sha.update(data: verifierData)
            passwordHash = sha.finalize() + [UInt8](repeating: 0, count: 4)
            passwordKey = nil
        } else {
            keyLength = 32
            guard let vgenCountStr = self.sessionData["AUTH_PBKDF2_VGEN_COUNT"], let vgenCount = Int(vgenCountStr) else {
                preconditionFailure("AUTH_PBKDF2_VGEN_COUNT needs to be in \(sessionData)")
            }
            let iterations = vgenCount
            let speedyKey = "AUTH_PBKDF2_SPEEDY_KEY".bytes
            let salt = verifierData + speedyKey
            passwordKey = try getDerivedKey(key: password, salt: salt, length: 64, iterations: iterations)
            var sha = SHA512()
            sha.update(data: passwordKey!)
            sha.update(data: verifierData)
            passwordHash = Array(sha.finalize().prefix(32))
        }

        // decrypt first half of session key
        guard let authSessionKey = self.sessionData["AUTH_SESSKEY"] else {
            preconditionFailure("AUTH_SESSKEY needs to be in \(sessionData)")
        }
        let encodedServerKey = Self.hexToBytes(string: authSessionKey)
        let sessionKeyPartA = try decryptCBC(passwordHash, encodedServerKey)

        // generate second half of session key
        let sessionKeyPartB = [UInt8].random(count: 32)
        let encodedClientKey = try encryptCBC(passwordHash, sessionKeyPartB)
        self.sessionKey = String(encodedClientKey.toHexString().uppercased().prefix(64))

        // create session key from combo key
        guard let cskSalt = self.sessionData["AUTH_PBKDF2_CSK_SALT"] else {
            preconditionFailure("AUTH_PBKDF2_CSK_SALT needs to be in \(sessionData)")
        }
        let mixingSalt = Self.hexToBytes(string: cskSalt)
        guard let sderCountStr = self.sessionData["AUTH_PBKDF2_SDER_COUNT"], let sderCount = Int(sderCountStr) else {
            preconditionFailure("AUTH_PBKDF2_SDER_COUNT needs to be in \(sessionData)")
        }
        let iterations = sderCount
        let comboKey = Array(sessionKeyPartB.prefix(keyLength) + sessionKeyPartA.prefix(keyLength))
        let sessionKey = try getDerivedKey(key: comboKey.toHexString().uppercased().bytes, salt: mixingSalt, length: keyLength, iterations: iterations)

        // generate speedy key for 12c verifiers
        if !verifier11g, let passwordKey {
            let salt = [UInt8].random(count: 16)
            let speedyKey = try encryptCBC(sessionKey, salt + passwordKey)
            self.speedyKey = Array(speedyKey.prefix(80)).toHexString().uppercased()
        }

        // encrypt password
        let pwSalt = [UInt8].random(count: 16)
        let passwordWithSalt = pwSalt + password
        let encryptedPassword = try encryptCBC(sessionKey, passwordWithSalt)
        self.encodedPassword = encryptedPassword.toHexString().uppercased()

        // encrypt new password
        if let newPassword {
            let newPasswordWithSalt = pwSalt + newPassword
            let encryptedNewPassword = try encryptCBC(sessionKey, newPasswordWithSalt)
            self.encodedNewPassword = encryptedNewPassword.toHexString().uppercased()
        }
    }

    private static func hexToBytes(string: String) -> [UInt8] {
        let stringArray = Array(string)
        var data = [UInt8]()
        for i in stride(from: 0, to: string.count, by: 2) {
            let pair: String = String(stringArray[i]) + String(stringArray[i+1])
            if let byte = UInt8(pair, radix: 16) {
                data.append(byte)
            } else {
                fatalError("Couldn't create byte from hex value: \(pair)")
            }
        }
        return data
    }
}

/// Oracle Release Number Format:
/// ```
/// 12.1.0.1.0
///  ┬ ┬ ┬ ┬ ┬
///  │ │ │ │ └───── Platform-Specific Release Number
///  │ │ │ └────────── Component-Specific Release Number
///  │ │ └─────────────── Fusion Middleware Release Number
///  │ └──────────────────── Database Maintenance Release Number
///  └───────────────────────── Major Database Release Number
///  ```
struct OracleVersion {
    let majorDatabaseReleaseNumber: Int
    let databaseMaintenanceReleaseNumber: Int
    let fusionMiddlewareReleaseNumber: Int
    let componentSpecificReleaseNumber: Int
    let platformSpecificReleaseNumber: Int

    func formatted() -> String {
        "\(majorDatabaseReleaseNumber)." +
        "\(databaseMaintenanceReleaseNumber)." +
        "\(fusionMiddlewareReleaseNumber)." +
        "\(componentSpecificReleaseNumber)." +
        "\(platformSpecificReleaseNumber)"
    }
}
