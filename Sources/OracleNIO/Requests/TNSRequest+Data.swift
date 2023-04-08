import NIOCore

protocol TNSRequestWithData: TNSRequest, AnyObject {
    var cursor: Cursor? { get set }
    var offset: UInt32 { get }
    var parseOnly: Bool { get }
    var arrayDMLRowCounts: Bool { get }
    var numberOfExecutions: UInt32 { get }
    var inFetch: Bool { get set }
    var flushOutBinds: Bool { get set }
    var bitVector: [UInt8]? { get set }
    var outVariables: [Variable]? { get set }
    func writeColumnMetadata(to buffer: inout ByteBuffer, with bindVariables: [Variable])
    func writeBindParameters(to buffer: inout ByteBuffer, with parameters: [BindInfo])
    func writeBindParameterRow(to buffer: inout ByteBuffer, with parameters: [BindInfo], at position: UInt32)
    func writeBindParameterColumn(to buffer: inout ByteBuffer, variable: Variable, value: Any?)
    func writePiggybacks(to buffer: inout ByteBuffer)
    /// Actions that takes place before query data is processed.
    func preprocessQuery()
}

extension TNSRequestWithData {

    func adjustFetchInfo(previousVariable: Variable, fetchInfo: inout FetchInfo) throws {
        if fetchInfo.dbType.oracleType == .clob && [DataType.Value.char, .varchar, .long].contains(previousVariable.dbType.oracleType) {
            let type = DataType.Value.long
            fetchInfo.dbType = try DBType.fromORATypeAndCSFRM(typeNumber: UInt8(type.rawValue), csfrm: previousVariable.dbType.csfrm)
        } else if fetchInfo.dbType.oracleType == .blob && [DataType.Value.raw, .longRAW].contains(previousVariable.dbType.oracleType) {
            let type = DataType.Value.longRAW
            fetchInfo.dbType = try DBType.fromORATypeAndCSFRM(typeNumber: UInt8(type.rawValue), csfrm: previousVariable.dbType.csfrm)
        }
    }

    // MARK: Write Request

    func writeColumnMetadata(to buffer: inout ByteBuffer, with bindVariables: [Variable]) {
        for variable in bindVariables {
            var oracleType = variable.dbType.oracleType
            var bufferSize = variable.bufferSize
            if oracleType == .rowID || oracleType == .uRowID {
                oracleType = .varchar
                bufferSize = Constants.TNS_MAX_UROWID_LENGTH
            }
            var flag: UInt8 = Constants.TNS_BIND_USE_INDICATORS
            if variable.isArray {
                flag |= Constants.TNS_BIND_ARRAY
            }
            var contFlag: UInt32 = 0
            if oracleType == .blob || oracleType == .clob {
                contFlag = Constants.TNS_LOB_PREFETCH_FLAG
            }
            buffer.writeInteger(UInt8(oracleType?.rawValue ?? 0))
            buffer.writeInteger(flag)
            // precision and scale are always written as zero as the server
            // expects that and complains if any other value is sent!
            buffer.writeInteger(UInt8(0))
            buffer.writeInteger(UInt8(0))
            if bufferSize >= Constants.TNS_MIN_LONG_LENGTH {
                buffer.writeUB4(Constants.TNS_MAX_LONG_LENGTH)
            } else {
                buffer.writeUB4(bufferSize)
            }
            if variable.isArray {
                buffer.writeUB4(variable.numberOfElements)
            } else {
                buffer.writeUB4(0) // max num elemnts
            }
            buffer.writeUB8(UInt64(contFlag))
            if let objectType = variable.objectType {
                // TODO: find out what's done here
                debugPrint(objectType)
            } else {
                buffer.writeUB4(0) // OID
                buffer.writeUB4(0) // version
            }
            if variable.dbType.csfrm != 0 {
                buffer.writeUB4(UInt32(Constants.TNS_CHARSET_UTF8))
            } else {
                buffer.writeUB4(0)
            }
            buffer.writeInteger(variable.dbType.csfrm)
            buffer.writeUB4(0) // max chars (not used)
            if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2 {
                buffer.writeUB4(0) // oaccolid
            }
        }
    }

    func writeBindParameters(to buffer: inout ByteBuffer, with parameters: [BindInfo]) {
        var returningOnly = true
        var allValuesAreNull = true
        var bindVariables = [Variable]()
        for bindInfo in parameters {
            if !bindInfo.isReturnBind {
                returningOnly = false
            }
            if let bindValues = bindInfo.variable?.values {
                for value in bindValues where value != nil {
                    allValuesAreNull = false
                    break
                }
            }
            guard let variable = bindInfo.variable else { continue }
            bindVariables.append(variable)
        }
        self.writeColumnMetadata(to: &buffer, with: bindVariables)

        // plsql batch executions without bind values
        if cursor?.statement.isPlSQL == true && self.numberOfExecutions > 1 && !allValuesAreNull {
            buffer.writeInteger(MessageType.rowData.rawValue)
            buffer.writeInteger(Constants.TNS_ESCAPE_CHAR)
            buffer.writeInteger(UInt8(1))
        }
        // write parameter values unless statement contains only return binds
        else if !returningOnly {
            for i in 0..<numberOfExecutions {
                buffer.writeInteger(MessageType.rowData.rawValue)
                self.writeBindParameterRow(to: &buffer, with: parameters, at: i)
            }
        }
    }

    func writeBindParameterRow(to buffer: inout ByteBuffer, with parameters: [BindInfo], at position: UInt32) {
        let offset = self.offset
        var variable: Variable?
        var numberOfElements: UInt32
        var foundLong = false
        for bindInfo in parameters where !bindInfo.isReturnBind {
            variable = bindInfo.variable
            guard let variable else { continue }
            if variable.isArray {
                numberOfElements = variable.numberOfElementsInArray ?? 0
                buffer.writeUB4(numberOfElements)
                for value in variable.values.prefix(Int(numberOfElements)) {
                    self.writeBindParameterColumn(to: &buffer, variable: variable, value: value)
                }
            } else {
                if variable.bufferSize >= Constants.TNS_MIN_LONG_LENGTH {
                    foundLong = true
                    continue
                }
                self.writeBindParameterColumn(to: &buffer, variable: variable, value: variable.values[Int(position + offset)])
            }
        }

        if foundLong {
            for bindInfo in parameters where !bindInfo.isReturnBind {
                guard let variable = bindInfo.variable, variable.bufferSize >= Constants.TNS_MIN_LONG_LENGTH else { continue }
                self.writeBindParameterColumn(to: &buffer, variable: variable, value: variable.values[Int(position + offset)])
            }
        }
    }

    func writeBindParameterColumn(to buffer: inout ByteBuffer, variable: Variable, value: Any?) {
        // TODO
    }

    func writePiggybacks(to buffer: inout ByteBuffer) {
        // TODO
    }

    // MARK: Process Response

    func preprocess() {
        guard let statement = cursor?.statement else {
            preconditionFailure()
        }
        if statement.isReturning && !parseOnly {
            // TODO
        } else if statement.isQuery {
            self.preprocessQuery()
        }
    }

    func preprocessQuery() {
        guard let cursor else {
            preconditionFailure()
        }

        // Set values to indicate the start of a new fetch operation
        self.inFetch = true
        cursor.moreRowsToFetch = true
        cursor.bufferRowCount = 0
        cursor.bufferIndex = 0

        // if no fetch variables exist, nothing further to do at this point.
        // The processing that follows will take the metadata returned by
        // the server and use it to create new fetch variables
        if cursor.fetchVariables.isEmpty { return }

        // TODO
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        switch type {
        case .rowHeader:
            try self.processRowHeader(&message)
        case .rowData:
            fatalError()
//            self.processRowData(message)
        case .flushOutBinds:
            self.flushOutBinds = true
        case .describeInfo:
            message.packet.skipRawBytesChunked()
            try self.processDescribeInfo(&message)
            self.outVariables = self.cursor?.fetchVariables
        case .error:
            fatalError()
//            self.processErrorInfo(message)
        case .bitVector:
            fatalError()
//            self.processBitVector(message)
        case .ioVector:
            fatalError()
//            self.processIOVector(message)
        case .implicitResultset:
            fatalError()
//            self.processImplicitResult(message)
        default:
            try self.defaultProcessResponse(&message, of: type, from: channel)
        }
    }

    func processRowHeader(_ message: inout TNSMessage) throws {
        message.packet.skipUB1() // flags
        message.packet.skipUB2() // number of requests
        message.packet.skipUB4() // iteration number
        message.packet.skipUB4() // number of iterations
        message.packet.skipUB2() // buffer length
        if let numberOfBytes = message.packet.readUB4(), numberOfBytes > 0 {
            message.packet.skipUB1() // skip repeated length
            try self.getBitVector(&message, size: numberOfBytes)
        }
        if let numberOfBytes = message.packet.readUB4(), numberOfBytes > 0 {
            message.packet.skipRawBytesChunked() // rxhrid
        }
    }

    func processDescribeInfo(_ message: inout TNSMessage) throws {
        guard let cursor else { preconditionFailure() }
        message.packet.skipUB4() // max row size
        cursor.numberOfColumns = message.packet.readUB4() ?? 0
        let previousFetchVariables = cursor.fetchVariables
        if cursor.numberOfColumns > 0 {
            message.packet.skipUB1()
        }
        for i in 0..<cursor.numberOfColumns {
            var fetchInfo = try self.processColumnInfo(&message)
            if !previousFetchVariables.isEmpty && i < previousFetchVariables.count {
                try adjustFetchInfo(previousVariable: previousFetchVariables[Int(i)], fetchInfo: &fetchInfo)
            }
            cursor.createFetchVariable(fetchInfo: fetchInfo, position: Int(i))
        }
        let numberOfBytes = message.packet.readUB4()
        if numberOfBytes ?? 0 > 0 {
            message.packet.skipRawBytesChunked() // current date
        }
        message.packet.skipUB4() // dcbflag
        message.packet.skipUB4() // dcbmdbz
        message.packet.skipUB4() // dcbmnpr
        message.packet.skipUB4() // dcbmxpr
        if message.packet.readUB4() ?? 0 > 0 {
            message.packet.skipRawBytesChunked() // dcbqcky
        }
        cursor.statement.fetchVariables = cursor.fetchVariables
        cursor.statement.numberOfColumns = cursor.numberOfColumns
    }

    func processColumnInfo(_ message: inout TNSMessage) throws -> FetchInfo {
        guard let dataType = message.packet.readUB1() else {
            preconditionFailure()
        }
        message.packet.skipUB1() // flags
        let precision = message.packet.readSB1() ?? 0
        let scale: Int16
        if dataType == DataType.Value.number.rawValue || dataType == DataType.Value.intervalDS.rawValue || dataType == DataType.Value.timestamp.rawValue || dataType == DataType.Value.timestampLTZ.rawValue || dataType == DataType.Value.timestampTZ.rawValue {
            scale = message.packet.readSB2() ?? 0
        } else {
            scale = Int16(message.packet.readSB1() ?? 0)
        }
        let bufferSize = message.packet.readUB4() ?? 0
        message.packet.skipUB4() // max number of array elements
        message.packet.skipUB4() // cont flags
        let numberOfBytes = message.packet.readUB1() ?? 0 // OID
        if numberOfBytes > 0 {
            let oid = message.packet.readBytes()
        }
        message.packet.skipUB2() // version
        message.packet.skipUB2() // character set id
        let csfrm = message.packet.readUB1() // character set form
        let dbType = try DBType.fromORATypeAndCSFRM(typeNumber: dataType, csfrm: csfrm)
        let size = message.packet.readUB4() ?? 0
        var fetchInfo = FetchInfo(
            precision: Int16(precision),
            scale: scale,
            bufferSize: bufferSize,
            size: size,
            nullsAllowed: false, // will be populated later
            name: "", // will be populated later
            dbType: dbType
        )
        if dataType == DataType.Value.raw.rawValue {
            fetchInfo.size = fetchInfo.bufferSize
        }
        if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2 {
            message.packet.skipUB4() // oaccolid
        }
        let nullsAllowed = message.packet.readUB1() ?? 0
        fetchInfo.nullsAllowed = nullsAllowed != 0
        message.packet.skipUB1() // v7 length of name
        if message.packet.readUB4() ?? 0 > 0 {
            fetchInfo.name = message.packet.readString(with: Constants.TNS_CS_IMPLICIT) ?? ""
        }
        if message.packet.readUB4() ?? 0 > 0 {
            let schema = message.packet.readString(with: Constants.TNS_CS_IMPLICIT) ?? ""
        }
        if message.packet.readUB4() ?? 0 > 0 {
            let name = message.packet.readString(with: Constants.TNS_CS_IMPLICIT) ?? ""
        }
        message.packet.skipUB2() // column position
        message.packet.skipUB4() // uds flag
        if dataType == DataType.Value.intNamed.rawValue {
            // TODO
            connection.logger.warning("INT NAMED not implemented")
        }
        return fetchInfo
    }

    /// Gets the bit vector from the buffer and stores it for later use by the
    /// row processing code. Since it is possible that the packet buffer may be
    /// overwritten by subsequent packet retrieval, the bit vector must be
    /// copied.
    func getBitVector(_ message: inout TNSMessage, size: UInt32) throws {
        if self.bitVector == nil, let bytes = message.packet.readBytes(length: Int(size)) {
            self.bitVector = bytes
        }
    }
}

final class ExecuteRequest: TNSRequestWithData {

    var connection: OracleConnection
    var messageType: MessageType
    var functionCode: UInt8 = Constants.TNS_FUNC_EXECUTE
    var currentSequenceNumber: UInt8 = 2
    var onResponsePromise: NIOCore.EventLoopPromise<TNSMessage>?

    var cursor: Cursor?
    var offset: UInt32 = 0
    var parseOnly = false
    var batchErrors = false
    var arrayDMLRowCounts = false
    var numberOfExecutions: UInt32 = 0
    var inFetch = false
    var flushOutBinds = false
    var bitVector: [UInt8]? = nil
    var outVariables: [Variable]? = nil

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func get() throws -> [TNSMessage] {
        var buffer = ByteBuffer()
        buffer.startRequest()

        guard let cursor else {
            preconditionFailure()
        }
        let statement = cursor.statement
        if statement.cursorID != 0 && !statement.requiresFullExecute && !self.parseOnly && !statement.isDDL && self.batchErrors {
            if statement.isQuery && !statement.requiresDefine && cursor.prefetchRows > 0 {
                self.functionCode = Constants.TNS_FUNC_REEXECUTE_AND_FETCH
            } else {
                self.functionCode = Constants.TNS_FUNC_REEXECUTE
            }
            self.writeReexecuteMessage(to: &buffer)
        } else {
            self.functionCode = Constants.TNS_FUNC_EXECUTE
            self.writeExecuteMessage(&buffer)
        }

        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }

    // MARK: Response processing

    // MARK: Private methods

    private func writeExecuteMessage(_ buffer: inout ByteBuffer) {
        var options: UInt32 = 0
        var dmlOptions: UInt32 = 0
        var numberOfParameters: UInt32 = 0
        var numberOfIterations: UInt32 = 1
        guard let cursor else {
            preconditionFailure()
        }
        let statement = cursor.statement
        let parameters = statement.bindInfoList

        // determine the options to use for the execute
        if !statement.requiresDefine && !parseOnly && !parameters.isEmpty {
            numberOfParameters = UInt32(parameters.count)
        }
        if statement.requiresDefine {
            options |= Constants.TNS_EXEC_OPTION_DEFINE
        } else if !parseOnly && !statement.sql.isEmpty {
            dmlOptions = Constants.TNS_EXEC_OPTION_IMPLICIT_RESULTSET
            options |= Constants.TNS_EXEC_OPTION_EXECUTE
        }
        if statement.cursorID == 0 || statement.isDDL {
            options |= Constants.TNS_EXEC_OPTION_PARSE
        }
        if statement.isQuery {
            if parseOnly {
                options |= Constants.TNS_EXEC_OPTION_DESCRIBE
            } else {
                if cursor.prefetchRows > 0 {
                    options |= Constants.TNS_EXEC_OPTION_FETCH
                }
                if statement.cursorID == 0 || statement.requiresDefine {
                    numberOfIterations = cursor.prefetchRows
                    cursor.fetchArraySize = numberOfIterations
                    self.cursor?.fetchArraySize = numberOfIterations
                } else {
                    numberOfIterations = cursor.fetchArraySize
                }
            }
        }
        if !statement.isPlSQL {
            options |= Constants.TNS_EXEC_OPTION_NOT_PLSQL
        } else if numberOfParameters > 0 {
            options |= Constants.TNS_EXEC_OPTION_PLSQL_BIND
        }
        if numberOfParameters > 0 {
            options |= Constants.TNS_EXEC_OPTION_BIND
        }
        if self.batchErrors {
            options |= Constants.TNS_EXEC_OPTION_BATCH_ERRORS
        }
        if self.arrayDMLRowCounts {
            dmlOptions = Constants.TNS_EXEC_OPTION_DML_ROWCOUNTS
        }
        if self.connection.autocommit {
            options |= Constants.TNS_EXEC_OPTION_COMMIT
        }

        // write piggybacks, if needed
        self.writePiggybacks(to: &buffer)

        // write body of message
        self.writeFunctionCode(to: &buffer)
        buffer.writeUB4(options) // execute options
        buffer.writeUB4(UInt32(statement.cursorID)) // cursor ID
        if statement.cursorID == 0 || statement.isDDL {
            buffer.writeInteger(UInt8(1)) // pointer (cursor ID)
            buffer.writeUB4(statement.sqlLength)
        } else {
            buffer.writeInteger(UInt8(0)) // pointer (cursor ID)
            buffer.writeUB4(0)
        }
        buffer.writeInteger(UInt8(1)) // pointer (vector)
        buffer.writeUB4(13) // al8i4 array length
        buffer.writeInteger(UInt8(0)) // pointer (al8o4)
        buffer.writeInteger(UInt8(0)) // pointer (al8o4l)
        buffer.writeUB4(0) // prefetch buffer size
        buffer.writeUB4(numberOfIterations) // prefetch number of rows
        buffer.writeUB4(Constants.TNS_MAX_LONG_LENGTH) // maximum long size
        if numberOfParameters == 0 {
            buffer.writeInteger(UInt8(0)) // pointer (binds)
            buffer.writeUB4(0) // number of binds
        } else {
            buffer.writeInteger(UInt8(1)) // pointer (binds)
            buffer.writeUB4(numberOfParameters) // number of binds
        }
        buffer.writeInteger(UInt8(0)) // pointer (al8app)
        buffer.writeInteger(UInt8(0)) // pointer (al8txn)
        buffer.writeInteger(UInt8(0)) // pointer (al8txl)
        buffer.writeInteger(UInt8(0)) // pointer (al8kv)
        buffer.writeInteger(UInt8(0)) // pointer (al8kvl)
        if statement.requiresDefine {
            buffer.writeInteger(UInt8(1)) // pointer (al8doac)
            buffer.writeUB4(UInt32(cursor.fetchVariables.count)) // number of defines
        } else {
            buffer.writeInteger(UInt8(0))
            buffer.writeUB4(0)
        }
        buffer.writeUB4(0) // registration id
        buffer.writeInteger(UInt8(0)) // pointer (al8objlist)
        buffer.writeInteger(UInt8(1)) // pointer (al8objlen)
        buffer.writeInteger(UInt8(0)) // pointer (al8blv)
        buffer.writeUB4(0) // al8blvl
        buffer.writeInteger(UInt8(0)) // pointer (al8dnam)
        buffer.writeUB4(0) // al8dnaml
        buffer.writeUB4(0) // al8regid_msb
        if self.arrayDMLRowCounts {
            buffer.writeInteger(UInt8(1)) // pointer (al8pidmlrc)
            buffer.writeUB4(self.numberOfExecutions) // al8pidmlrcbl
            buffer.writeInteger(UInt8(1)) // pointer (al8pidmlrcl)
        } else {
            buffer.writeInteger(UInt8(0)) // pointer (al8pidmlrc)
            buffer.writeUB4(0) // al8pidmlrcbl
            buffer.writeInteger(UInt8(0)) // pointer (al8pidmlrcl)
        }
        if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2 {
            buffer.writeInteger(UInt8(0)) // pointer (al8sqlsig)
            buffer.writeUB4(0) // SQL signature length
            buffer.writeInteger(UInt8(0)) // pointer (SQL ID)
            buffer.writeUB4(0) // allocated size of SQL ID
            buffer.writeInteger(UInt8(0)) // pointer (length of SQL ID)
            if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2_EXT1 {
                buffer.writeInteger(UInt8(0)) // pointer (chunk ids)
                buffer.writeUB4(0) // number of chunk ids
            }
        }
        if statement.cursorID == 0 || statement.isDDL {
            buffer.writeBytes(statement.sqlBytes)
            buffer.writeUB4(1) // al8i4[0] parse
        } else {
            buffer.writeUB4(0) // al8i4[0] parse
        }
        if statement.isQuery {
            if statement.cursorID == 0 {
                buffer.writeUB4(0) // al8i4[1] execution count
            } else {
                buffer.writeUB4(numberOfIterations)
            }
        } else {
            buffer.writeUB4(self.numberOfExecutions) // al8i4[1] execution count
        }
        buffer.writeUB4(0) // al8i4[2]
        buffer.writeUB4(0) // al8i4[3]
        buffer.writeUB4(0) // al8i4[4]
        buffer.writeUB4(0) // al8i4[5] SCN (part 1)
        buffer.writeUB4(0) // al8i4[6] SCN (part 2)
        buffer.writeUB4(statement.isQuery ? 1 : 0) // al8i4[7] is query
        buffer.writeUB4(0) // al8i4[8]
        buffer.writeUB4(dmlOptions) // al8i4[9] DML row counts/implicit
        buffer.writeUB4(0) // al8i4[10]
        buffer.writeUB4(0) // al8i4[11]
        buffer.writeUB4(0) // al8i4[12]
        if statement.requiresDefine {
            self.writeColumnMetadata(to: &buffer, with: cursor.fetchVariables)
        } else if numberOfParameters > 0 {
            self.writeBindParameters(to: &buffer, with: parameters)
        }
    }

    private func writeReexecuteMessage(to buffer: inout ByteBuffer) {}

    private func writeFunctionCode(to buffer: inout ByteBuffer) {
        buffer.writeInteger(self.messageType.rawValue)
        buffer.writeInteger(self.functionCode)
        buffer.writeSequenceNumber(with: self.currentSequenceNumber)
        self.currentSequenceNumber += 1
    }
}
