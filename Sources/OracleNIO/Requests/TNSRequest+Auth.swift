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
                let sessionIDStr = self.sessionData["AUTH_SESSION_ID"],
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
