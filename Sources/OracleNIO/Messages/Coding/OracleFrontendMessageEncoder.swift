//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
import NIOCore

import struct Foundation.Date
import class Foundation.DateFormatter
import struct Foundation.Locale
import struct Foundation.TimeZone

struct OracleFrontendMessageEncoder {
    static let headerSize = 8

    private enum State {
        case flushed
        case writable
    }

    private var buffer: ByteBuffer
    private var state: State = .writable
    var capabilities: Capabilities

    init(buffer: ByteBuffer, capabilities: Capabilities) {
        self.buffer = buffer
        self.capabilities = capabilities
    }

    mutating func flush() -> ByteBuffer {
        self.state = .flushed
        return self.buffer
    }

    mutating func marker() {
        self.clearIfNeeded()

        self.startRequest(packetType: .marker)
        self.buffer.writeMultipleIntegers(
            UInt8(1), UInt8(0), Constants.TNS_MARKER_TYPE_RESET
        )
        self.endRequest(packetType: .marker)
    }

    mutating func ping() {
        self.clearIfNeeded()

        self.startRequest()
        self.writeFunctionCode(messageType: .function, functionCode: .ping)
        self.endRequest()
    }

    mutating func commit() {
        self.clearIfNeeded()

        self.startRequest()
        self.writeFunctionCode(messageType: .function, functionCode: .commit)
        self.endRequest()
    }

    mutating func rollback() {
        self.clearIfNeeded()

        self.startRequest()
        self.writeFunctionCode(messageType: .function, functionCode: .rollback)
        self.endRequest()
    }

    mutating func flushOutBinds() {
        self.clearIfNeeded()

        self.startRequest()
        self.buffer.writeOracleMessageID(.flushOutBinds)
        self.endRequest()
    }

    /// Connect is a special case, because of it's specific packet size limit based on the
    /// `connectString`'s length.
    /// If the length is exceeded, we have to sent two separate messages to the server.
    /// Because of that, we have to return an array of messages, which is sent by the
    /// ``OracleChannelHandler``.
    mutating func connect(connectString: String) -> [ByteBuffer] {
        self.clearIfNeeded()

        var buffers = [ByteBuffer]()

        var serviceOptions = Constants.TNS_GSO_DONT_CARE
        let connectFlags1: UInt32 = 0
        var connectFlags2: UInt32 = 0
        let nsiFlags: UInt8 =
            Constants.TNS_NSI_SUPPORT_SECURITY_RENEG
            | Constants.TNS_NSI_DISABLE_NA
        if capabilities.supportsOOB {
            serviceOptions |= Constants.TNS_GSO_CAN_RECV_ATTENTION
            connectFlags2 |= Constants.TNS_CHECK_OOB
        }
        let connectStringByteLength =
            connectString
            .lengthOfBytes(using: .utf8)

        self.startRequest(packetType: .connect)

        self.buffer.writeInteger(Constants.TNS_VERSION_DESIRED)
        self.buffer.writeInteger(Constants.TNS_VERSION_MINIMUM)
        self.buffer.writeInteger(serviceOptions)
        self.buffer.writeInteger(Constants.TNS_SDU)
        self.buffer.writeInteger(Constants.TNS_SDU)
        self.buffer.writeInteger(Constants.TNS_PROTOCOL_CHARACTERISTICS)
        self.buffer.writeInteger(UInt16(0))  // line turnaround
        self.buffer.writeInteger(UInt16(1))  // value of 1
        self.buffer.writeInteger(UInt16(connectStringByteLength))

        self.buffer.writeMultipleIntegers(
            UInt16(74),  // offset to connect data
            UInt32(0),  // max receivable data
            nsiFlags,
            nsiFlags,
            UInt64(0),  // obsolete
            UInt64(0),  // obsolete
            UInt64(0),  // obsolete
            UInt32(Constants.TNS_SDU),  // SDU (large)
            UInt32(Constants.TNS_SDU),  // SDU (large)
            connectFlags1,
            connectFlags2
        )
        let isConnectStringToLong =
            connectStringByteLength > Constants.TNS_MAX_CONNECT_DATA
        if isConnectStringToLong {
            self.endRequest(packetType: .connect)

            buffers.append(self.buffer)
            self.buffer.clear()

            self.startRequest()
        }
        self.buffer.writeString(connectString)

        self.endRequest(packetType: isConnectStringToLong ? .data : .connect)

        buffers.append(self.buffer)
        self.buffer.clear()
        return buffers
    }

    mutating func fastAuth(authContext: AuthContext) {
        self.clearIfNeeded()

        self.startRequest()

        self.buffer.writeMultipleIntegers(
            OracleFrontendMessageID.fastAuth.rawValue,
            UInt8(1),  // fast auth version
            Constants.TNS_SERVER_CONVERTS_CHARS,  // flag 1
            UInt8(0)  // flag 2
        )

        self.protocol0()

        self.buffer.writeInteger(0, as: UInt16.self)  // server charset (unused)
        self.buffer.writeInteger(0, as: UInt8.self)  // server charset flag (unused)
        self.buffer.writeInteger(0, as: UInt16.self)  // server ncharset (unused)
        self.capabilities.ttcFieldVersion = Constants.TNS_CCAP_FIELD_VERSION_19_1_EXT_1
        self.buffer.writeInteger(self.capabilities.ttcFieldVersion)
        self.dataTypes0()
        self.authenticationPhaseOne0(authContext: authContext)
        self.capabilities.ttcFieldVersion = Constants.TNS_CCAP_FIELD_VERSION_MAX

        self.endRequest()
    }

    mutating func `protocol`() {
        self.clearIfNeeded()

        self.startRequest()
        self.protocol0()
        self.endRequest()
    }

    private mutating func protocol0() {
        self.buffer.writeOracleMessageID(.protocol)
        self.buffer.writeInteger(UInt8(6))  // protocol version (8.1 and higher)
        self.buffer.writeInteger(UInt8(0))  // `array` terminator
        self.buffer.writeString(Constants.DRIVER_NAME)
        self.buffer.writeInteger(UInt8(0))  // `NULL` terminator
    }

    mutating func dataTypes() {
        self.clearIfNeeded()

        self.startRequest()
        self.dataTypes0()
        self.endRequest()
    }

    private mutating func dataTypes0() {
        self.buffer.writeOracleMessageID(.dataTypes)
        self.buffer.writeInteger(Constants.TNS_CHARSET_UTF8, endianness: .little)
        self.buffer.writeInteger(Constants.TNS_CHARSET_UTF8, endianness: .little)
        self.buffer.writeInteger(
            UInt8(
                Constants.TNS_ENCODING_MULTI_BYTE | Constants.TNS_ENCODING_CONV_LENGTH
            ))
        self.buffer.writeInteger(UInt8(capabilities.compileCapabilities.count))
        self.buffer.writeBytes(capabilities.compileCapabilities)
        self.buffer.writeInteger(UInt8(capabilities.runtimeCapabilities.count))
        self.buffer.writeBytes(capabilities.runtimeCapabilities)

        var i = 0
        while true {
            let dataType = DataType.all[i]
            if dataType.dataType == .undefined { break }
            i += 1

            self.buffer.writeInteger(dataType.dataType.rawValue)
            self.buffer.writeInteger(dataType.convDataType.rawValue)
            self.buffer.writeInteger(dataType.representation.rawValue)
            self.buffer.writeInteger(UInt16(0))
        }

        self.buffer.writeInteger(UInt16(0))
    }

    mutating func authenticationPhaseOne(authContext: AuthContext) {
        self.clearIfNeeded()

        self.startRequest()
        self.authenticationPhaseOne0(authContext: authContext)
        self.endRequest()
    }

    mutating func authenticationPhaseOne0(authContext: AuthContext) {
        // 1. Setup

        let authMode = Self.configureAuthMode(
            from: authContext.mode,
            method: authContext.method
        )

        // 2. message preparation

        let numberOfPairs: UInt32 = 5

        self.writeBasicAuthData(
            authContext: authContext,
            authPhase: .authPhaseOne,
            authMode: authMode,
            pairsCount: numberOfPairs
        )

        // 3. write key/value pairs
        self.writeKeyValuePair(
            key: "AUTH_TERMINAL", value: authContext.terminalName
        )
        self.writeKeyValuePair(
            key: "AUTH_PROGRAM_NM", value: authContext.programName
        )
        self.writeKeyValuePair(
            key: "AUTH_MACHINE", value: authContext.machineName
        )
        self.writeKeyValuePair(
            key: "AUTH_PID", value: String(authContext.pid)
        )
        self.writeKeyValuePair(
            key: "AUTH_SID", value: authContext.processUsername
        )
    }

    mutating func authenticationPhaseTwo(
        authContext: AuthContext,
        parameters: OracleBackendMessage.Parameter
    ) throws {
        self.clearIfNeeded()

        let verifierType = parameters["AUTH_VFR_DATA"]?.flags

        var numberOfPairs: UInt32 = 4

        var authMode = Self.configureAuthMode(
            from: authContext.mode, method: authContext.method
        )

        let verifier11g: Bool
        switch authContext.method.base {
        case .token(let token):
            numberOfPairs += 1
            verifier11g = false  // ignored

            switch token {
            case .oAuth2: break
            case .tokenAndPrivateKey: numberOfPairs += 2
            }

        case .usernamePassword(_, _, let newPassword):
            numberOfPairs += 2
            authMode |= Constants.TNS_AUTH_MODE_WITH_PASSWORD

            if [
                Constants.TNS_VERIFIER_TYPE_11G_1,
                Constants.TNS_VERIFIER_TYPE_11G_2,
            ].contains(verifierType) {
                verifier11g = true
            } else if verifierType != Constants.TNS_VERIFIER_TYPE_12C {
                throw OracleSQLError.serverVersionNotSupported
            } else {
                verifier11g = false
                numberOfPairs += 1
            }

            // determine which other key/value pairs to write
            if newPassword != nil {
                numberOfPairs += 1
                authMode |= Constants.TNS_AUTH_MODE_CHANGE_PASSWORD
            }
        }

        if authContext.proxyUser != nil {
            numberOfPairs += 1
        }
        if authContext.description.purity != .default {
            numberOfPairs += 1
        }
        if authContext.jdwpData != nil {
            numberOfPairs += 1
        }

        self.startRequest()

        self.writeBasicAuthData(
            authContext: authContext,
            authPhase: .authPhaseTwo,
            authMode: authMode,
            pairsCount: numberOfPairs
        )


        if let proxyUser = authContext.proxyUser {
            self.writeKeyValuePair(key: "PROXY_CLIENT_NAME", value: proxyUser)
        }

        switch authContext.method.base {
        case .token(let token):
            switch token {
            case .oAuth2(let token):
                self.writeKeyValuePair(key: "AUTH_TOKEN", value: token)
            case .tokenAndPrivateKey(let token, let key):
                self.writeKeyValuePair(key: "AUTH_TOKEN", value: token)
                let now = authHeaderDateFormatter.string(from: .now)
                let hostInfo = """
                    \(authContext.peerAddress?.ipAddress ?? ""):\
                    \(authContext.peerAddress?.port ?? 0)
                    """
                guard
                    case .serviceName(let serviceName) = authContext.service
                else {
                    throw OracleSQLError.sidNotSupported
                }
                let header = """
                    date: \(now)
                    (request-target): \(serviceName)
                    host: \(hostInfo)
                    """
                let signature = try getSignature(key: key, payload: header)
                self.writeKeyValuePair(key: "AUTH_HEADER", value: header)
                self.writeKeyValuePair(key: "AUTH_SIGNATURE", value: signature)
            }

        case .usernamePassword(_, let password, let newPassword):

            let (
                sessionKey, speedyKey, encodedPassword, encodedNewPassword
            ) = try Self.generateVerifier(
                password: password,
                newPassword: newPassword,
                parameters: parameters,
                verifier11g
            )

            self.writeKeyValuePair(
                key: "AUTH_SESSKEY", value: sessionKey, flags: 1
            )
            self.writeKeyValuePair(key: "AUTH_PASSWORD", value: encodedPassword)
            if !verifier11g {
                guard let speedyKey else {
                    preconditionFailure(
                        """
                        speedy key needs to be generated before running \
                        authentication phase two
                        """)
                }
                self.writeKeyValuePair(
                    key: "AUTH_PBKDF2_SPEEDY_KEY", value: speedyKey
                )
            }
            if let encodedNewPassword {
                self.writeKeyValuePair(
                    key: "AUTH_NEWPASSWORD", value: encodedNewPassword
                )
            }
        }
        self.writeKeyValuePair(key: "SESSION_CLIENT_CHARSET", value: "873")
        let driverName = "\(Constants.DRIVER_NAME) thn : \(Constants.VERSION)"
        self.writeKeyValuePair(
            key: "SESSION_CLIENT_DRIVER_NAME", value: driverName
        )
        self.writeKeyValuePair(
            key: "SESSION_CLIENT_VERSION", value: "\(Constants.VERSION_CODE)"
        )
        self.writeKeyValuePair(
            key: "AUTH_ALTER_SESSION",
            value: self._getAlterTimezoneStatement(
                customTimezone: authContext.customTimezone
            ),
            flags: 1
        )

        if authContext.description.purity != .default {
            self.writeKeyValuePair(
                key: "AUTH_KPPL_PURITY",
                value: String(authContext.description.purity.rawValue),
                flags: 1
            )
        }

        self.endRequest()
    }

    mutating func execute(
        statementContext: StatementContext,
        cleanupContext: CleanupContext,
        describeInfo: DescribeInfo?
    ) {
        self.clearIfNeeded()

        let statement = statementContext.statement
        let statementOptions = statementContext.options

        // 1. options
        var options: UInt32 = 0
        var dmlOptions: UInt32 = 0
        var parametersCount: UInt32 = 0
        var iterationsCount: UInt32 = 1

        if !statementContext.requiresDefine && statement.binds.count != 0 {
            parametersCount = .init(statement.binds.count)
        }
        if statementContext.requiresDefine {
            options |= Constants.TNS_EXEC_OPTION_DEFINE
        } else if !statement.sql.isEmpty {
            dmlOptions = Constants.TNS_EXEC_OPTION_IMPLICIT_RESULTSET
            options |= Constants.TNS_EXEC_OPTION_EXECUTE
        }
        if statementContext.cursorID == 0 || statementContext.type.isDDL {
            options |= Constants.TNS_EXEC_OPTION_PARSE
        }
        if statementContext.type.isQuery {
            if statementContext.cursorID == 0 || statementContext.requiresDefine {
                iterationsCount = UInt32(statementOptions.prefetchRows)
            } else {
                iterationsCount = UInt32(statementOptions.arraySize)
            }
            if iterationsCount > 0 && !statementContext.noPrefetch {
                options |= Constants.TNS_EXEC_OPTION_FETCH
            }
        }
        if !statementContext.type.isPlSQL {
            options |= Constants.TNS_EXEC_OPTION_NOT_PLSQL
        } else if statementContext.type.isPlSQL && parametersCount > 0 {
            options |= Constants.TNS_EXEC_OPTION_PLSQL_BIND
        }
        if parametersCount > 0 {
            options |= Constants.TNS_EXEC_OPTION_BIND
        }
        if statementContext.options.batchErrors {
            options |= Constants.TNS_EXEC_OPTION_BATCH_ERRORS
        }
        if statementContext.options.arrayDMLRowCounts {
            options |= Constants.TNS_EXEC_OPTION_DML_ROWCOUNTS
        }
        if statementOptions.autoCommit {
            options |= Constants.TNS_EXEC_OPTION_COMMIT
        }

        self.startRequest()

        // 2. write piggybacks, if needed
        self.writePiggybacks(context: cleanupContext)

        // 3 write function code
        self.writeFunctionCode(
            messageType: .function,
            functionCode: .execute,
            sequenceNumber: &statementContext.sequenceNumber
        )

        // 4. write body of message
        self.buffer.writeUB4(options)  // execute options
        self.buffer.writeUB4(UInt32(statementContext.cursorID))  // cursor ID
        if statementContext.cursorID == 0 || statementContext.type.isDDL {
            self.buffer.writeInteger(UInt8(1))  // pointer (cursor ID)
            self.buffer.writeUB4(statementContext.sqlLength)
        } else {
            self.buffer.writeInteger(UInt8(0))  // pointer (cursor ID)
            self.buffer.writeUB4(0)
        }
        self.buffer.writeInteger(UInt8(1))  // pointer (vector)
        self.buffer.writeUB4(13)  // al8i4 array length
        self.buffer.writeInteger(UInt8(0))  // pointer (al8o4)
        self.buffer.writeInteger(UInt8(0))  // pointer (al8o4l)
        self.buffer.writeUB4(0)  // prefetch buffer size
        self.buffer.writeUB4(iterationsCount)  // prefetch number of rows
        self.buffer.writeUB4(Constants.TNS_MAX_LONG_LENGTH)  // maximum long size
        if parametersCount == 0 {
            self.buffer.writeInteger(UInt8(0))  // pointer (binds)
            self.buffer.writeUB4(0)  // number of binds
        } else {
            self.buffer.writeInteger(UInt8(1))  // pointer (binds)
            self.buffer.writeUB4(parametersCount)  // number of binds
        }
        self.buffer.writeInteger(UInt8(0))  // pointer (al8app)
        self.buffer.writeInteger(UInt8(0))  // pointer (al8txn)
        self.buffer.writeInteger(UInt8(0))  // pointer (al8txl)
        self.buffer.writeInteger(UInt8(0))  // pointer (al8kv)
        self.buffer.writeInteger(UInt8(0))  // pointer (al8kvl)
        if statementContext.requiresDefine {
            self.buffer.writeInteger(UInt8(1))  // pointer (al8doac)
            self.buffer.writeUB4(
                UInt32(describeInfo?.columns.count ?? 0)
            )  // number of defines
        } else {
            self.buffer.writeInteger(UInt8(0))
            self.buffer.writeUB4(0)
        }
        self.buffer.writeUB4(0)  // registration id
        self.buffer.writeInteger(UInt8(0))  // pointer (al8objlist)
        self.buffer.writeInteger(UInt8(1))  // pointer (al8objlen)
        self.buffer.writeInteger(UInt8(0))  // pointer (al8blv)
        self.buffer.writeUB4(0)  // al8blvl
        self.buffer.writeInteger(UInt8(0))  // pointer (al8dnam)
        self.buffer.writeUB4(0)  // al8dnaml
        self.buffer.writeUB4(0)  // al8regid_msb
        if statementOptions.arrayDMLRowCounts {
            self.buffer.writeInteger(UInt8(1))  // pointer (al8pidmlrc)
            self.buffer.writeUB4(1)  // al8pidmlrcbl / numberOfExecutions
            self.buffer.writeInteger(UInt8(1))  // pointer (al8pidmlrcl)
        } else {
            self.buffer.writeInteger(UInt8(0))  // pointer (al8pidmlrc)
            self.buffer.writeUB4(0)  // al8pidmlrcbl
            self.buffer.writeInteger(UInt8(0))  // pointer (al8pidmlrcl)
        }
        if self.capabilities.ttcFieldVersion
            >= Constants.TNS_CCAP_FIELD_VERSION_12_2
        {
            self.buffer.writeInteger(UInt8(0))  // pointer (al8sqlsig)
            self.buffer.writeUB4(0)  // SQL signature length
            self.buffer.writeInteger(UInt8(0))  // pointer (SQL ID)
            self.buffer.writeUB4(0)  // allocated size of SQL ID
            self.buffer.writeInteger(UInt8(0))  // pointer (length of SQL ID)
            if self.capabilities.ttcFieldVersion
                >= Constants.TNS_CCAP_FIELD_VERSION_12_2_EXT1
            {
                self.buffer.writeInteger(UInt8(0))  // pointer (chunk ids)
                self.buffer.writeUB4(0)  // number of chunk ids
            }
        }
        if statementContext.cursorID == 0 || statementContext.type.isDDL {
            statementContext.statement.sql
                ._encodeRaw(into: &self.buffer, context: .default)
            self.buffer.writeUB4(1)  // al8i4[0] parse
        } else {
            self.buffer.writeUB4(0)  // al8i4[0] parse
        }
        if statementContext.type.isQuery {
            if statementContext.cursorID == 0 {
                self.buffer.writeUB4(0)  // al8i4[1] execution count
            } else {
                self.buffer.writeUB4(iterationsCount)
            }
        } else {
            self.buffer.writeUB4(1)  // al8i4[1] execution count
        }
        self.buffer.writeUB4(0)  // al8i4[2]
        self.buffer.writeUB4(0)  // al8i4[3]
        self.buffer.writeUB4(0)  // al8i4[4]
        self.buffer.writeUB4(0)  // al8i4[5] SCN (part 1)
        self.buffer.writeUB4(0)  // al8i4[6] SCN (part 2)
        self.buffer.writeUB4(
            statementContext.type.isQuery ? 1 : 0
        )  // al8i4[7] is query
        self.buffer.writeUB4(0)  // al8i4[8]
        self.buffer.writeUB4(dmlOptions)  // al8i4[9] DML row counts/implicit
        self.buffer.writeUB4(0)  // al8i4[10]
        self.buffer.writeUB4(0)  // al8i4[11]
        self.buffer.writeUB4(0)  // al8i4[12]
        if statementContext.requiresDefine {
            guard let columns = describeInfo?.columns else {
                preconditionFailure()
            }

            self.writeColumnMetadata(columns)
        } else if parametersCount > 0 {
            self.writeBindParameters(statementContext.statement.binds)
        }

        self.endRequest()
    }

    mutating func reexecute(
        statementContext: StatementContext, cleanupContext: CleanupContext
    ) {
        self.clearIfNeeded()

        self.startRequest()

        let functionCode: Constants.FunctionCode
        if statementContext.type.isQuery && !statementContext.requiresDefine
            && statementContext.options.prefetchRows > 0
        {
            functionCode = .reexecuteAndFetch
        } else {
            functionCode = .reexecute
        }
        let parameters = statementContext.statement.binds
        var executionFlags1: UInt32 = 0
        var executionFlags2: UInt32 = 0
        var numberOfIterations: UInt32 = 0
        let numberOfExecutions = 1

        if functionCode == .reexecuteAndFetch {
            executionFlags1 |= Constants.TNS_EXEC_OPTION_EXECUTE
            numberOfIterations = UInt32(statementContext.options.prefetchRows)
        } else {
            if statementContext.options.autoCommit {
                executionFlags2 |= Constants.TNS_EXEC_OPTION_COMMIT_REEXECUTE
            }
            numberOfIterations = UInt32(numberOfExecutions)
        }

        self.writePiggybacks(context: cleanupContext)
        self.writeFunctionCode(
            messageType: .function, functionCode: functionCode
        )
        self.buffer.writeUB4(UInt32(statementContext.cursorID))
        self.buffer.writeUB4(numberOfIterations)
        self.buffer.writeUB4(executionFlags1)
        self.buffer.writeUB4(executionFlags2)
        if !parameters.metadata.isEmpty {
            self.buffer.writeOracleMessageID(.rowData)
            self.writeBindParameterRow(bindings: parameters)
        }
        self.endRequest()
    }

    mutating func fetch(cursorID: UInt16, fetchArraySize: UInt32) {
        self.clearIfNeeded()

        self.startRequest()
        self.writeFunctionCode(messageType: .function, functionCode: .fetch)
        self.buffer.writeUB4(UInt32(cursorID))
        self.buffer.writeUB4(fetchArraySize)
        self.endRequest()
    }

    mutating func lobOperation(
        sourceLOB: LOB?, sourceOffset: UInt64,
        destinationLOB: LOB?, destinationOffset: UInt64,
        operation: Constants.LOBOperation, sendAmount: Bool, amount: Int64,
        data: ByteBuffer?
    ) throws {
        self.clearIfNeeded()

        self.startRequest()
        self.writeFunctionCode(messageType: .function, functionCode: .lobOp)
        if let sourceLOB {
            sourceLOB.locator.moveReaderIndex(to: 0)
            self.buffer.writeInteger(UInt8(1))  // source pointer
            self.buffer.writeUB4(UInt32(sourceLOB.locator.readableBytes))
        } else {
            self.buffer.writeInteger(UInt8(0))  // source pointer
            self.buffer.writeInteger(UInt8(0))  // source length
        }
        if let destinationLOB {
            destinationLOB.locator.moveReaderIndex(to: 0)
            self.buffer.writeInteger(UInt8(1))  // destination pointer
            self.buffer.writeUB4(UInt32(destinationLOB.locator.readableBytes))
        } else {
            self.buffer.writeInteger(UInt8(0))  // destination pointer
            self.buffer.writeInteger(UInt8(0))  // destination length
        }
        self.buffer.writeUB4(0)  // short source offset
        self.buffer.writeUB4(0)  // short destination offset
        self.buffer.writeInteger(UInt8(operation == .createTemp ? 1 : 0))
        // pointer (character set)
        self.buffer.writeInteger(UInt8(0))  // pointer (short amount)
        if operation == .createTemp || operation == .isOpen {
            self.buffer.writeInteger(UInt8(1))  // pointer (NULL LOB)
        } else {
            self.buffer.writeInteger(UInt8(0))  // pointer (NULL LOB)
        }
        self.buffer.writeUB4(operation.rawValue)
        self.buffer.writeInteger(UInt8(0))  // pointer (SCN array)
        self.buffer.writeInteger(UInt8(0))  // SCN array length
        self.buffer.writeUB8(sourceOffset)
        self.buffer.writeUB8(destinationOffset)
        self.buffer.writeInteger(UInt8(sendAmount ? 1 : 0))  // pointer (amount)
        for _ in 0..<3 {
            self.buffer.writeInteger(UInt16(0))  // array LOB (not used)
        }
        if let sourceLOB {
            self.buffer.writeBuffer(&sourceLOB.locator)
        }
        if let destinationLOB {
            self.buffer.writeBuffer(&destinationLOB.locator)
        }
        if operation == .createTemp {
            if let sourceLOB, sourceLOB.dbType.csfrm == Constants.TNS_CS_NCHAR {
                try self.capabilities.checkNCharsetID()
                self.buffer.writeUB4(UInt32(Constants.TNS_CHARSET_UTF16))
            } else {
                self.buffer.writeUB4(UInt32(Constants.TNS_CHARSET_UTF8))
            }
        }
        if let data {
            self.buffer.writeOracleMessageID(.lobData)
            data._encodeRaw(into: &self.buffer, context: .default)
        }
        if sendAmount {
            self.buffer.writeUB8(UInt64(amount))  // LOB amount
        }
        self.endRequest()
    }

    mutating func releaseSession(deauthenticate: Bool = false) {
        self.clearIfNeeded()

        self.startRequest()

        self.writeFunctionCode(
            messageType: .onewayFN, functionCode: .sessionRelease
        )
        self.buffer.writeInteger(UInt8(0))  // pointer (tag name)
        self.buffer.writeInteger(UInt8(0))  // tag name length
        self.buffer.writeUB4(deauthenticate ? Constants.DRCP_DEAUTHENTICATE : 0)
        self.endRequest()
    }

    mutating func logoff(cleanupContext: CleanupContext) {
        self.clearIfNeeded()

        self.startRequest()
        self.writePiggybacks(context: cleanupContext)
        self.writeFunctionCode(messageType: .function, functionCode: .logoff)
        self.endRequest()
    }

    mutating func close() {
        self.clearIfNeeded()

        self.startRequest(dataFlags: Constants.TNS_DATA_FLAGS_EOF)
        self.endRequest()
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


    /// Starts a new request with a placeholder for the header, which is set at the end of the request via
    /// ``endRequest``, and the data flags if they are required.
    mutating func startRequest(
        packetType: PacketType = .data, dataFlags: UInt16 = 0
    ) {
        self.buffer.reserveCapacity(Self.headerSize)
        self.buffer.moveWriterIndex(forwardBy: Self.headerSize)
        if packetType == PacketType.data {
            self.buffer.writeInteger(dataFlags)
        }
    }

    private mutating func endRequest(
        packetType: PacketType = .data
    ) {
        self.buffer.prepareSend(
            packetType: packetType,
            protocolVersion: self.capabilities.protocolVersion
        )
    }

    private mutating func writeFunctionCode(
        messageType: OracleFrontendMessageID,
        functionCode: Constants.FunctionCode
    ) {
        var sequenceNumber: UInt8 = 0
        self.writeFunctionCode(
            messageType: messageType,
            functionCode: functionCode,
            sequenceNumber: &sequenceNumber
        )
    }

    private mutating func writeFunctionCode(
        messageType: OracleFrontendMessageID,
        functionCode: Constants.FunctionCode,
        sequenceNumber: inout UInt8
    ) {
        self.buffer.writeInteger(messageType.rawValue)
        self.buffer.writeInteger(functionCode.rawValue)
        sequenceNumber += 1
        self.buffer.writeInteger(sequenceNumber)
        if self.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_23_1_EXT_1 {
            buffer.writeUB8(0)  // token number
        }
    }
}

// MARK: - Authentication related stuff

extension OracleFrontendMessageEncoder {

    private static func configureAuthMode(
        from mode: AuthenticationMode,
        method: OracleAuthenticationMethod
    ) -> UInt32 {
        let newPassword: String?
        if case .usernamePassword(_, _, let newPW) = method.base {
            newPassword = newPW
        } else {
            newPassword = nil
        }

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
        password: String,
        newPassword: String?,
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

        let password = password.data(using: .utf8) ?? .init()

        guard let authVFRData = parameters["AUTH_VFR_DATA"] else {
            throw OracleSQLError.missingParameter(
                expected: "AUTH_VFR_DATA", in: parameters
            )
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
                throw OracleSQLError.missingParameter(
                    expected: "AUTH_PBKDF2_VGEN_COUNT", in: parameters
                )
            }
            let iterations = vgenCount
            let speedyKey = "AUTH_PBKDF2_SPEEDY_KEY".data(using: .utf8) ?? .init()
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
            throw OracleSQLError.missingParameter(
                expected: "AUTH_SESSKEY", in: parameters
            )
        }
        let encodedServerKey = Self.hexToBytes(string: authSessionKey.value)
        let sessionKeyPartA = try decryptCBC(passwordHash, encodedServerKey)

        // generate second half of session key
        let sessionKeyPartB = [UInt8].random(count: 32)
        let encodedClientKey = try encryptCBC(passwordHash, sessionKeyPartB)
        sessionKey = String(
            encodedClientKey.hexString.uppercased().prefix(64)
        )

        // create session key from combo key
        guard let cskSalt = parameters["AUTH_PBKDF2_CSK_SALT"] else {
            throw OracleSQLError.missingParameter(
                expected: "AUTH_PBKDF2_CSK_SALT", in: parameters
            )
        }
        let mixingSalt = Self.hexToBytes(string: cskSalt.value)
        guard
            let sderCountStr = parameters["AUTH_PBKDF2_SDER_COUNT"],
            let sderCount = Int(sderCountStr.value)
        else {
            throw OracleSQLError.missingParameter(
                expected: "AUTH_PBKDF2_SDER_COUNT", in: parameters
            )
        }
        let iterations = sderCount
        let comboKey = Array(
            sessionKeyPartB.prefix(keyLength) + sessionKeyPartA.prefix(keyLength)
        )
        let derivedKey = try getDerivedKey(
            key: comboKey.hexString.uppercased().data(using: .utf8) ?? .init(),
            salt: mixingSalt, length: keyLength, iterations: iterations
        )

        // generate speedy key for 12c verifiers
        if !verifier11g, let passwordKey {
            let salt = [UInt8].random(count: 16)
            let speedyKeyCBC = try encryptCBC(derivedKey, salt + passwordKey)
            speedyKey = speedyKeyCBC.prefix(80).hexString.uppercased()
        } else {
            speedyKey = nil
        }

        // encrypt password
        let pwSalt = [UInt8].random(count: 16)
        let passwordWithSalt = pwSalt + password
        let encryptedPassword = try encryptCBC(derivedKey, passwordWithSalt)
        encodedPassword = encryptedPassword.hexString.uppercased()

        // encrypt new password
        if let newPassword = newPassword?.data(using: .utf8) {
            let newPasswordWithSalt = pwSalt + newPassword
            let encryptedNewPassword = try encryptCBC(derivedKey, newPasswordWithSalt)
            encodedNewPassword = encryptedNewPassword.hexString.uppercased()
        } else {
            encodedNewPassword = nil
        }

        return (sessionKey, speedyKey, encodedPassword, encodedNewPassword)
    }

    private mutating func writeKeyValuePair(
        key: String, value: String, flags: UInt32 = 0
    ) {
        let keyBytes = ByteBuffer(string: key)
        let keyLength = keyBytes.readableBytes
        let valueBytes = ByteBuffer(string: value)
        let valueLength = valueBytes.readableBytes
        self.buffer.writeUB4(UInt32(keyLength))
        keyBytes._encodeRaw(into: &self.buffer, context: .default)
        self.buffer.writeUB4(UInt32(valueLength))
        if valueLength > 0 {
            valueBytes._encodeRaw(into: &buffer, context: .default)
        }
        self.buffer.writeUB4(flags)
    }

    private static func hexToBytes(string: String) -> [UInt8] {
        let stringArray = Array(string)
        var data = [UInt8]()
        for i in stride(from: 0, to: string.count, by: 2) {
            let pair: String = String(stringArray[i]) + String(stringArray[i + 1])
            if let byte = UInt8(pair, radix: 16) {
                data.append(byte)
            } else {
                fatalError("Couldn't create byte from hex value: \(pair)")
            }
        }
        return data
    }

    private mutating func writeBasicAuthData(
        authContext: AuthContext,
        authPhase: Constants.FunctionCode,
        authMode: UInt32,
        pairsCount: UInt32
    ) {
        let username: String
        let usernameLength: Int
        switch authContext.method.base {
        case .usernamePassword(let user, _, _):
            username = user
            usernameLength = user.data(using: .utf8)?.count ?? 0
        case .token:
            username = ""
            usernameLength = 0
        }
        let hasUser: UInt8 = usernameLength > 0 ? 1 : 0

        // 1. write function code
        var sequenceNumber: UInt8 = authPhase == .authPhaseOne ? 0 : 1
        self.writeFunctionCode(
            messageType: .function,
            functionCode: authPhase,
            sequenceNumber: &sequenceNumber
        )

        // 2. write basic data
        self.buffer.writeInteger(hasUser)  // pointer (authuser)
        self.buffer.writeUB4(UInt32(usernameLength))
        self.buffer.writeUB4(authMode)  // authentication mode
        self.buffer.writeInteger(UInt8(1))  // pointer (authiv1)
        self.buffer.writeUB4(pairsCount)  // number of key/value pairs
        self.buffer.writeInteger(UInt8(1))  // pointer (authovl)
        self.buffer.writeInteger(UInt8(1))  // pointer (authovln)
        if hasUser != 0 {
            username._encodeRaw(into: &self.buffer, context: .default)
        }
    }

}

// MARK: Data/Statement related stuff

extension OracleFrontendMessageEncoder {
    private mutating func writePiggybacks(context: CleanupContext) {
        if !context.cursorsToClose.isEmpty {
            self.writeCloseCursorsPiggyback(context.cursorsToClose)
            context.cursorsToClose.removeAll()
        }
        if context.tempLOBsTotalSize > 0 {
            if let tempLOBsToClose = context.tempLOBsToClose {
                self.writeCloseTempLOBsPiggyback(
                    tempLOBsToClose, totalSize: context.tempLOBsTotalSize
                )
                context.tempLOBsToClose = nil
            }
            context.tempLOBsTotalSize = 0
        }
    }

    private mutating func writePiggybackCode(code: Constants.FunctionCode) {
        self.writeFunctionCode(
            messageType: .piggyback,
            functionCode: code
        )
    }

    private mutating func writeCloseCursorsPiggyback(
        _ cursorsToClose: Set<UInt16>
    ) {
        self.writePiggybackCode(code: .closeCursors)
        self.buffer.writeInteger(UInt8(1))  // pointer
        self.buffer.writeUB4(UInt32(cursorsToClose.count))
        for cursorID in cursorsToClose {
            self.buffer.writeUB4(UInt32(cursorID))
        }
    }

    private mutating func writeCloseTempLOBsPiggyback(
        _ tempLOBsToClose: [ByteBuffer],
        totalSize tempLOBsTotalSize: Int
    ) {
        self.writePiggybackCode(code: .lobOp)
        let opCode =
            Constants.LOBOperation.freeTemp.rawValue
            | Constants.LOBOperation.array.rawValue

        // temp lob data
        self.buffer.writeInteger(UInt8(1))  // pointer
        self.buffer.writeUB4(UInt32(tempLOBsTotalSize))
        self.buffer.writeInteger(UInt8(0))  // destination lob locator
        self.buffer.writeUB4(0)
        self.buffer.writeUB4(0)  // source lob locator
        self.buffer.writeUB4(0)
        self.buffer.writeInteger(UInt8(0))  // source lob offset
        self.buffer.writeInteger(UInt8(0))  // destination lob offset
        self.buffer.writeInteger(UInt8(0))  // charset
        self.buffer.writeUB4(opCode)
        self.buffer.writeInteger(UInt8(0))  // scn
        self.buffer.writeUB4(0)  // losbscn
        self.buffer.writeUB8(0)  // lobscnl
        self.buffer.writeUB8(0)
        self.buffer.writeInteger(UInt8(0))

        // array lob fields
        self.buffer.writeInteger(UInt8(0))
        self.buffer.writeUB4(0)
        self.buffer.writeInteger(UInt8(0))
        self.buffer.writeUB4(0)
        self.buffer.writeInteger(UInt8(0))
        self.buffer.writeUB4(0)

        for lob in tempLOBsToClose {
            buffer.writeImmutableBuffer(lob)
        }
    }

    private mutating func writeBindParameters(_ binds: OracleBindings) {
        self.writeColumnMetadata(binds.metadata)

        // write parameter values unless statement contains only return binds
        if !binds.metadata.isEmpty {
            self.buffer.writeOracleMessageID(.rowData)
            self.writeBindParameterRow(bindings: binds)
        }
    }

    private mutating func writeColumnMetadata(
        _ metadata: [ColumnMetadata]
    ) {
        for info in metadata {
            var oracleType = info.dataType._oracleType
            var bufferSize = info.bufferSize
            if [.rowID, .uRowID].contains(oracleType) {
                oracleType = .varchar
                bufferSize = Constants.TNS_MAX_UROWID_LENGTH
            }
            var flag: UInt8 = Constants.TNS_BIND_USE_INDICATORS
            if info.isArray {
                flag |= Constants.TNS_BIND_ARRAY
            }
            var contFlag: UInt32 = 0
            var lobPrefetchLength: UInt32 = 0
            if [.blob, .clob].contains(oracleType) {
                contFlag = Constants.TNS_LOB_PREFETCH_FLAG
            } else if oracleType == .json {
                contFlag = Constants.TNS_LOB_PREFETCH_FLAG
                bufferSize = Constants.TNS_JSON_MAX_LENGTH
                lobPrefetchLength = Constants.TNS_JSON_MAX_LENGTH
            } else if oracleType == .vector {
                contFlag = Constants.TNS_LOB_PREFETCH_FLAG
                bufferSize = Constants.TNS_VECTOR_MAX_LENGTH
                lobPrefetchLength = Constants.TNS_VECTOR_MAX_LENGTH
            }
            self.buffer.writeInteger(UInt8(oracleType?.rawValue ?? 0))
            self.buffer.writeInteger(flag)
            // precision and scale are always written as zero as the server
            // expects that and complains if any other value is sent!
            self.buffer.writeInteger(UInt8(0))
            self.buffer.writeInteger(UInt8(0))
            if bufferSize > self.capabilities.maxStringSize {
                self.buffer.writeUB4(Constants.TNS_MAX_LONG_LENGTH)
            } else {
                self.buffer.writeUB4(bufferSize)
            }
            if info.isArray {
                self.buffer.writeUB4(UInt32(info.maxArraySize))
            } else {
                self.buffer.writeUB4(0)  // max num elements
            }
            self.buffer.writeUB8(UInt64(contFlag))
            self.buffer.writeUB4(0)  // OID
            self.buffer.writeUB2(0)  // version
            if info.dataType.csfrm != 0 {
                self.buffer.writeUB2(Constants.TNS_CHARSET_UTF8)
            } else {
                self.buffer.writeUB2(0)
            }
            self.buffer.writeInteger(info.dataType.csfrm)
            self.buffer.writeUB4(lobPrefetchLength)  // max chars (LOB prefetch)
            if self.capabilities.ttcFieldVersion
                >= Constants.TNS_CCAP_FIELD_VERSION_12_2
            {
                self.buffer.writeUB4(0)  // oaccolid
            }
        }
    }

    private mutating func writeBindParameterRow(bindings: OracleBindings) {
        self.buffer.writeImmutableBuffer(bindings.bytes)
        if bindings.longBytes.readableBytes > 0 {
            self.buffer.writeImmutableBuffer(bindings.longBytes)
        }
    }

    /// Returns the statement required to change the session time zone
    /// to match the time zone in use by the client (us).
    ///
    /// _Not private due to tests._
    internal func _getAlterTimezoneStatement(customTimezone: TimeZone?, atDate date: Date = .init())
        -> String
    {
        let timezone = customTimezone ?? TimeZone.current
        let offset = timezone.secondsFromGMT(for: date)
        let tzHour = abs(offset / 3600)
        let tzMinute = (abs(offset) % 3600) / 60
        let sign = offset >= 0 ? "+" : "-"
        let tzRepresentation = """
            \(sign)\(String(format: "%02d", tzHour))\
            :\(String(format: "%02d", tzMinute))
            """
        return "ALTER SESSION SET TIME_ZONE='\(tzRepresentation)'\0"
    }

}

private protocol ColumnMetadata {
    var dataType: OracleDataType { get }
    var bufferSize: UInt32 { get }
    var isArray: Bool { get }
    var maxArraySize: Int { get }
}

extension OracleBindings.Metadata: ColumnMetadata {}

extension OracleColumn: ColumnMetadata {
    var isArray: Bool { false }
    var maxArraySize: Int { 0 }
}

enum OracleFrontendMessageID: UInt8 {
    case function = 3
    case piggyback = 17
    case onewayFN = 26
    case fastAuth = 34
}

private let authHeaderDateFormatter: DateFormatter = {
    let format = "E, dd MMM yyyy HH:mm:ss 'GMT'"
    let formatter = DateFormatter()
    formatter.dateFormat = format
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(abbreviation: "GMT")
    return formatter
}()
