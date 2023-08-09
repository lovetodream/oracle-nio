import NIOCore
import Crypto

struct OracleFrontendMessageEncoder {
    private enum State {
        case flushed
        case writable
    }

    private var buffer: ByteBuffer
    private var state: State = .writable
    private var capabilities: Capabilities


    init(buffer: ByteBuffer, capabilities: Capabilities) {
        self.buffer = buffer
        self.capabilities = capabilities
    }

    mutating func flush() -> ByteBuffer {
        self.state = .flushed
        return self.buffer
    }

    mutating func encode(_ message: OracleFrontendMessage) {
        self.clearIfNeeded()

        switch message {
        case .connect(let connect):
            Self.createMessage(
                connect, capabilities: self.capabilities, out: &self.buffer
            )
        case .protocol(let `protocol`):
            Self.createMessage(
                `protocol`, capabilities: self.capabilities, out: &self.buffer
            )
        case .dataTypes(let dataTypes):
            Self.createMessage(
                dataTypes, capabilities: self.capabilities, out: &self.buffer
            )
        }
    }

    mutating func marker() {
        self.clearIfNeeded()

        self.buffer.startRequest(packetType: .marker)
        self.buffer.writeMultipleIntegers(
            UInt8(1), UInt8(0), Constants.TNS_MARKER_TYPE_RESET
        )
        self.buffer.endRequest(
            packetType: .marker, capabilities: self.capabilities
        )
    }

    mutating func authenticationPhaseOne(authContext: AuthContext) {
        self.clearIfNeeded()

        // 1. Setup

        let newPassword = authContext.newPassword

        // TODO: DRCP support
        // context: if drcp is used, use purity = NEW as the default purity for
        // standalone connections and purity = SELF for connections that belong
        // to a pool
        // for now just use the value from description

        let authMode = Self.configureAuthMode(
            from: authContext.mode,
            newPassword: newPassword
        )

        // 2. message preparation

        let numberOfPairs: UInt32 = 5

        self.buffer.startRequest()

        Self.writeBasicAuthData(
            authContext: authContext, authPhase: .one, authMode: authMode,
            pairsCount: numberOfPairs, out: &self.buffer
        )

        // 3. write key/value pairs
        Self.writeKeyValuePair(
            key: "AUTH_TERMINAL",
            value: ConnectConstants.default.terminalName,
            out: &self.buffer
        )
        Self.writeKeyValuePair(
            key: "AUTH_PROGRAM_NM",
            value: ConnectConstants.default.programName,
            out: &self.buffer
        )
        Self.writeKeyValuePair(
            key: "AUTH_MACHINE",
            value: ConnectConstants.default.machineName,
            out: &self.buffer
        )
        Self.writeKeyValuePair(
            key: "AUTH_PID",
            value: String(ConnectConstants.default.pid),
            out: &self.buffer
        )
        Self.writeKeyValuePair(
            key: "AUTH_SID",
            value: ConnectConstants.default.username,
            out: &self.buffer
        )

        self.buffer.endRequest(capabilities: self.capabilities)
    }

    mutating func authenticationPhaseTwo(
        authContext: AuthContext, parameters: OracleBackendMessage.Parameter
    ) throws {
        self.clearIfNeeded()

        let verifierType = parameters["AUTH_VFR_DATA"]?.flags

        var numberOfPairs: UInt32 = 3

        // user/password authentication
        numberOfPairs += 2
        var authMode = Self.configureAuthMode(
            from: authContext.mode, newPassword: authContext.newPassword
        )
        authMode |= Constants.TNS_AUTH_MODE_WITH_PASSWORD
        let verifier11g: Bool
        if
            [
                Constants.TNS_VERIFIER_TYPE_11G_1,
                Constants.TNS_VERIFIER_TYPE_11G_2
            ].contains(verifierType) {
            verifier11g = true
        } else if verifierType != Constants.TNS_VERIFIER_TYPE_12C {
            // TODO: refactor error
            throw OracleError.ErrorType.unsupportedVerifierType
        } else {
            verifier11g = false
            numberOfPairs += 1
        }
        let (
            sessionKey, speedyKey, encodedPassword, encodedNewPassword
        ) = try Self.generateVerifier(
            authContext: authContext, parameters: parameters, verifier11g
        )

        // determine which other key/value pairs to write
        if authContext.newPassword != nil {
            numberOfPairs += 1
            authMode |= Constants.TNS_AUTH_MODE_CHANGE_PASSWORD
        }
        if authContext.description.purity != .default {
            numberOfPairs += 1
        }

        self.buffer.startRequest()

        Self.writeBasicAuthData(
            authContext: authContext, authPhase: .two, authMode: authMode,
            pairsCount: numberOfPairs, out: &self.buffer
        )

        Self.writeKeyValuePair(
            key: "AUTH_SESSKEY", value: sessionKey, flags: 1, out: &self.buffer
        )
        Self.writeKeyValuePair(
            key: "AUTH_PASSWORD", value: encodedPassword, out: &self.buffer
        )
        if !verifier11g {
            guard let speedyKey else {
                preconditionFailure("speedy key needs to be generated before running authentication phase two")
            }
            Self.writeKeyValuePair(
                key: "AUTH_PBKDF2_SPEEDY_KEY",
                value: speedyKey,
                out: &self.buffer
            )
        }
        if let encodedNewPassword {
            Self.writeKeyValuePair(
                key: "AUTH_NEWPASSWORD",
                value: encodedNewPassword,
                out: &self.buffer
            )
        }
        Self.writeKeyValuePair(
            key: "SESSION_CLIENT_CHARSET", value: "873", out: &self.buffer
        )
        let driverName = "\(Constants.DRIVER_NAME) thn : \(Constants.VERSION)"
        Self.writeKeyValuePair(
            key: "SESSION_CLIENT_DRIVER_NAME",
            value: driverName,
            out: &self.buffer
        )
        Self.writeKeyValuePair(
            key: "SESSION_CLIENT_VERSION",
            value: "\(Constants.VERSION_CODE)",
            out: &self.buffer
        )
        if authContext.description.purity != .default {
            Self.writeKeyValuePair(
                key: "AUTH_KPPL_PURITY",
                value: String(authContext.description.purity.rawValue),
                flags: 1,
                out: &self.buffer
            )
        }

        self.buffer.endRequest(capabilities: self.capabilities)
    }

    mutating func logoff() {
        self.clearIfNeeded()

        self.buffer.startRequest()

        // write function code
        self.buffer.writeInteger(MessageType.function.rawValue)
        self.buffer.writeInteger(Constants.TNS_FUNC_LOGOFF)
        self.buffer.writeSequenceNumber()

        self.buffer.endRequest(capabilities: self.capabilities)
    }

    mutating func close() {
        self.clearIfNeeded()

        self.buffer.startRequest(
            packetType: .data, dataFlags: Constants.TNS_DATA_FLAGS_EOF
        )
        self.buffer.endRequest(capabilities: self.capabilities)
    }

    // MARK: - Private Methods -

    private mutating func clearIfNeeded() {
        switch self.state {
        case .flushed:
            self.state = .writable
            self.buffer.clear()
        case .writable:
            break
        }
    }

    private static func createMessage(
        _ message: OracleFrontendMessage.PayloadEncodable,
        capabilities: Capabilities,
        out buffer: inout ByteBuffer
    ) {
        buffer.startRequest(packetType: message.packetType)
        message.encode(into: &buffer, capabilities: capabilities)
        buffer.endRequest(
            packetType: message.packetType, capabilities: capabilities
        )
    }
}

// MARK: - Authentication related stuff

extension OracleFrontendMessageEncoder {

    private static func configureAuthMode(
        from mode: UInt32 , newPassword: String? = nil
    ) -> UInt32 {
        var authMode: UInt32 = 0

        // Set authentication mode
        if newPassword == nil {
            authMode = Constants.TNS_AUTH_MODE_LOGON
        }
        if AuthenticationMode.sysDBA.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSDBA
        }
        if AuthenticationMode.sysOPER.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSOPER
        }
        if AuthenticationMode.sysASM.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSASM
        }
        if AuthenticationMode.sysBKP.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSBKP
        }
        if AuthenticationMode.sysDGD.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSDGD
        }
        if AuthenticationMode.sysKMT.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSKMT
        }
        if AuthenticationMode.sysRAC.compare(with: mode) {
            authMode |= Constants.TNS_AUTH_MODE_SYSRAC
        }

        return authMode
    }

    private static func generateVerifier(
        authContext: AuthContext,
        parameters: OracleBackendMessage.Parameter,
        _ verifier11g: Bool
    ) throws -> (
        sessionKey: String,
        speedyKey: String?,
        encodedPassword: String,
        encodedNewPassword: String?
    ) {
        let sessionKey: String
        let speedyKey: String?
        let encodedPassword: String
        let encodedNewPassword: String?

        let password = authContext.password.bytes

        guard let authVFRData = parameters["AUTH_VFR_DATA"] else {
            // TODO: better error handling
            preconditionFailure("AUTH_VFR_DATA needs to be in \(parameters)")
        }
        let verifierData = Self.hexToBytes(string: authVFRData.value)
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
            guard
                let vgenCountStr = parameters["AUTH_PBKDF2_VGEN_COUNT"],
                let vgenCount = Int(vgenCountStr.value)
            else {
                // TODO: better error handling
                preconditionFailure("AUTH_PBKDF2_VGEN_COUNT needs to be in \(parameters)")
            }
            let iterations = vgenCount
            let speedyKey = "AUTH_PBKDF2_SPEEDY_KEY".bytes
            let salt = verifierData + speedyKey
            passwordKey = try getDerivedKey(
                key: password,
                salt: salt, length: 64, iterations: iterations
            )
            var sha = SHA512()
            sha.update(data: passwordKey!)
            sha.update(data: verifierData)
            passwordHash = Array(sha.finalize().prefix(32))
        }

        // decrypt first half of session key
        guard let authSessionKey = parameters["AUTH_SESSKEY"] else {
            // TODO: better error handling
            preconditionFailure("AUTH_SESSKEY needs to be in \(parameters)")
        }
        let encodedServerKey = Self.hexToBytes(string: authSessionKey.value)
        let sessionKeyPartA = try decryptCBC(passwordHash, encodedServerKey)

        // generate second half of session key
        let sessionKeyPartB = [UInt8].random(count: 32)
        let encodedClientKey = try encryptCBC(passwordHash, sessionKeyPartB)
        sessionKey = String(
            encodedClientKey.toHexString().uppercased().prefix(64)
        )

        // create session key from combo key
        guard let cskSalt = parameters["AUTH_PBKDF2_CSK_SALT"] else {
            // TODO: better error handling
            preconditionFailure("AUTH_PBKDF2_CSK_SALT needs to be in \(parameters)")
        }
        let mixingSalt = Self.hexToBytes(string: cskSalt.value)
        guard
            let sderCountStr = parameters["AUTH_PBKDF2_SDER_COUNT"],
            let sderCount = Int(sderCountStr.value)
        else {
            preconditionFailure("AUTH_PBKDF2_SDER_COUNT needs to be in \(parameters)")
        }
        let iterations = sderCount
        let comboKey = Array(
            sessionKeyPartB.prefix(keyLength) +
            sessionKeyPartA.prefix(keyLength)
        )
        let derivedKey = try getDerivedKey(
            key: comboKey.toHexString().uppercased().bytes,
            salt: mixingSalt, length: keyLength, iterations: iterations
        )

        // generate speedy key for 12c verifiers
        if !verifier11g, let passwordKey {
            let salt = [UInt8].random(count: 16)
            let speedyKeyCBC = try encryptCBC(derivedKey, salt + passwordKey)
            speedyKey = Array(speedyKeyCBC.prefix(80))
                .toHexString()
                .uppercased()
        } else {
            speedyKey = nil
        }

        // encrypt password
        let pwSalt = [UInt8].random(count: 16)
        let passwordWithSalt = pwSalt + password
        let encryptedPassword = try encryptCBC(derivedKey, passwordWithSalt)
        encodedPassword = encryptedPassword.toHexString().uppercased()

        // encrypt new password
        if let newPassword = authContext.newPassword?.bytes {
            let newPasswordWithSalt = pwSalt + newPassword
            let encryptedNewPassword = try encryptCBC(derivedKey, newPasswordWithSalt)
            encodedNewPassword = encryptedNewPassword.toHexString().uppercased()
        } else {
            encodedNewPassword = nil
        }

        return (sessionKey, speedyKey, encodedPassword, encodedNewPassword)
    }

    private static func writeKeyValuePair(
        key: String, value: String, flags: UInt32 = 0,
        out buffer: inout ByteBuffer
    ) {
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

    private static func writeBasicAuthData(
        authContext: AuthContext,
        authPhase: Constants.AuthPhase,
        authMode: UInt32,
        pairsCount: UInt32,
        out buffer: inout ByteBuffer
    ) {
        let username = authContext.username.bytes
        let usernameLength = authContext.username.count
        let hasUser: UInt8 = authContext.username.count > 0 ? 1 : 0

        // 1. write function code
        buffer.writeInteger(MessageType.function.rawValue)
        buffer.writeInteger(authPhase.rawValue)
        buffer.writeSequenceNumber(with: authPhase == .one ? 0 : 1)

        // 2. write basic data
        buffer.writeInteger(hasUser) // pointer (authuser)
        buffer.writeUB4(UInt32(usernameLength))
        buffer.writeUB4(authMode) // authentication mode
        buffer.writeInteger(UInt8(1)) // pointer (authiv1)
        buffer.writeUB4(pairsCount) // number of key/value pairs
        buffer.writeInteger(UInt8(1)) // pointer (authovl)
        buffer.writeInteger(UInt8(1)) // pointer (authovln)
        if hasUser != 0 {
            buffer.writeBytes(username)
        }
    }

}
