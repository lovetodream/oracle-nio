import NIOCore
import struct Foundation.Date

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
    var processedError: Bool { get set }
    var rowIndex: UInt32 { get set }
    var numberOfColumnsSent: UInt16? { get set }
    func writeColumnMetadata(to buffer: inout ByteBuffer, with bindVariables: [Variable])
    func writeBindParameters(to buffer: inout ByteBuffer, with parameters: [BindInfo]) throws
    func writeBindParameterRow(to buffer: inout ByteBuffer, with parameters: [BindInfo], at position: UInt32) throws
    func writeBindParameterColumn(to buffer: inout ByteBuffer, variable: Variable, value: Any?) throws
    func writePiggybacks(to buffer: inout ByteBuffer)
    /// Actions that takes place before query data is processed.
    func preprocessQuery()
}

extension TNSRequestWithData {

    func didProcessError() {
        processedError = true
    }

    func hasMoreData(_ message: inout TNSMessage) -> Bool {
        !processedError && !flushOutBinds
    }

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
            var lobPrefetchLength: UInt32 = 0
            if oracleType == .blob || oracleType == .clob {
                contFlag = Constants.TNS_LOB_PREFETCH_FLAG
            } else if oracleType == .json {
                contFlag = Constants.TNS_LOB_PREFETCH_FLAG
                bufferSize = Constants.TNS_JSON_MAX_LENGTH
                lobPrefetchLength = Constants.TNS_JSON_MAX_LENGTH
            }
            buffer.writeInteger(UInt8(oracleType?.rawValue ?? 0))
            buffer.writeInteger(flag)
            // precision and scale are always written as zero as the server
            // expects that and complains if any other value is sent!
            buffer.writeInteger(UInt8(0))
            buffer.writeInteger(UInt8(0))
            if bufferSize > connection.capabilities.maxStringSize {
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
            buffer.writeUB4(lobPrefetchLength) // max chars (LOB prefetch)
            if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2 {
                buffer.writeUB4(0) // oaccolid
            }
        }
    }

    func writeBindParameters(to buffer: inout ByteBuffer, with parameters: [BindInfo]) throws {
        var hasData = false
        var bindVariables = [Variable]()
        for bindInfo in parameters {
            if !bindInfo.isReturnBind {
                hasData = true
            }
            guard let variable = bindInfo.variable else { continue }
            bindVariables.append(variable)
        }
        self.writeColumnMetadata(to: &buffer, with: bindVariables)

        // write parameter values unless statement contains only return binds
        if hasData {
            for i in 0..<numberOfExecutions {
                buffer.writeInteger(MessageType.rowData.rawValue)
                try self.writeBindParameterRow(to: &buffer, with: parameters, at: i)
            }
        }
    }

    func writeBindParameterRow(to buffer: inout ByteBuffer, with parameters: [BindInfo], at position: UInt32) throws {
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
                    try self.writeBindParameterColumn(to: &buffer, variable: variable, value: value)
                }
            } else {
                if self.cursor?.statement.isPlSQL == false && variable.bufferSize > connection.capabilities.maxStringSize {
                    foundLong = true
                    continue
                }
                try self.writeBindParameterColumn(to: &buffer, variable: variable, value: variable.values[Int(position + offset)])
            }
        }

        if foundLong {
            for bindInfo in parameters where !bindInfo.isReturnBind {
                guard let variable = bindInfo.variable, variable.bufferSize > connection.capabilities.maxStringSize else { continue }
                try self.writeBindParameterColumn(to: &buffer, variable: variable, value: variable.values[Int(position + offset)])
            }
        }
    }

    func writeBindParameterColumn(to buffer: inout ByteBuffer, variable: Variable, value: Any?) throws {
        if value == nil {
            if variable.dbType.oracleType == .boolean {
                buffer.writeInteger(Constants.TNS_ESCAPE_CHAR)
                buffer.writeInteger(UInt8(1))
            } else if variable.dbType.oracleType == .intNamed {
                buffer.writeUB4(0) // TOID
                buffer.writeUB4(0) // OID
                buffer.writeUB4(0) // snapshot
                buffer.writeUB4(0) // version
                buffer.writeUB4(0) // packed data length
                buffer.writeUB4(Constants.TNS_OBJ_TOP_LEVEL) // flags
            } else {
                buffer.writeInteger(UInt8(0))
            }
        } else if [.varchar, .char, .long].contains(variable.dbType.oracleType), let value = value as? String {
            let tmpBytes: [UInt8]
            if variable.dbType.csfrm == Constants.TNS_CS_IMPLICIT {
                tmpBytes = value.bytes
            } else {
                try connection.capabilities.checkNCharsetID()
                tmpBytes = value.data(using: .utf16)?.bytes ?? []
            }
            buffer.writeBytesAndLength(tmpBytes)
        } else if [.raw, .longRAW].contains(variable.dbType.oracleType), let value = value as? [UInt8] {
            buffer.writeBytesAndLength(value)
        } else if [.number, .binaryInteger].contains(variable.dbType.oracleType) {
            let tmpBytes: [UInt8]
            if let value = value as? Bool {
                tmpBytes = [value ? 1 : 0]
            } else {
                tmpBytes = String(value as! Int).bytes // TODO: more robust
            }
            try buffer.writeOracleNumber(tmpBytes)
        } else if [.date, .timestamp, .timestampTZ, .timestampLTZ].contains(variable.dbType.oracleType), let value = value as? Date {
            buffer.writeOracleDate(value, length: UInt8(variable.dbType.bufferSizeFactor))
        } else if variable.dbType.oracleType == .binaryDouble, let value = value as? Double {
            buffer.writeBinaryDouble(value)
        } else if variable.dbType.oracleType == .binaryFloat, let value = value as? Float {
            buffer.writeBinaryFloat(value)
        } else if variable.dbType.oracleType == .cursor, let value = value as? Cursor {
            if value.statement.cursorID == 0 {
                buffer.writeInteger(UInt8(1))
                buffer.writeInteger(UInt8(0))
            } else {
                buffer.writeUB4(1)
                buffer.writeUB4(UInt32(value.statement.cursorID))
            }
        } else if variable.dbType.oracleType == .boolean, let value = value as? Bool {
            buffer.writeBool(value)
        } else if variable.dbType.oracleType == .intervalDS, let value = value as? Double {
            buffer.writeIntervalDS(value)
        } else if [.blob, .clob].contains(variable.dbType.oracleType), let value = value as? LOB {
            buffer.writeLOBWithLength(value)
        } else if [.rowID, .uRowID].contains(variable.dbType.oracleType), let value = value as? String {
            let tempBytes = value.bytes
            buffer.writeBytesAndLength(tempBytes)
        } else if variable.dbType.oracleType == .intNamed {
            throw OracleError.ErrorType.dbTypeNotSupported
        } else if variable.dbType.oracleType == .json {
            try buffer.writeOSON()
        } else {
            throw OracleError.ErrorType.dbTypeNotSupported
        }
    }

    func writePiggybacks(to buffer: inout ByteBuffer) {
        if self.connection.cursorsToClose?.isEmpty == false, !connection.drcpEstablishSession {
            self.writeCloseCursorsPiggyback(to: &buffer)
        }
        if self.connection.tempLOBsTotalSize > 0 {
            self.writeCloseTempLOBsPiggyback(to: &buffer)
        }
    }

    func writePiggybackCode(to buffer: inout ByteBuffer, code: UInt8) {
        buffer.writeInteger(UInt8(MessageType.piggyback.rawValue))
        buffer.writeInteger(UInt8(code))
        buffer.writeSequenceNumber()
        if connection.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_23_1_EXT_1 {
            buffer.writeUB8(0) // token number
        }
    }

    func writeCloseCursorsPiggyback(to buffer: inout ByteBuffer) {
        self.writePiggybackCode(to: &buffer, code: Constants.TNS_FUNC_CLOSE_CURSORS)
        buffer.writeInteger(UInt8(1)) // pointer
        buffer.writeUB4(UInt32(self.connection.cursorsToClose!.count))
        guard let cursorIDs = self.connection.cursorsToClose else { return }
        for cursorID in cursorIDs {
            buffer.writeUB4(UInt32(cursorID))
        }
        self.connection.cursorsToClose = nil
    }

    func writeCloseTempLOBsPiggyback(to buffer: inout ByteBuffer) {
        guard let lobs = self.connection.tempLOBsToClose else {
            self.connection.tempLOBsTotalSize = 0
            return
        }

        self.writePiggybackCode(to: &buffer, code: Constants.TNS_FUNC_LOB_OP)
        let opCode = Constants.TNS_LOB_OP_FREE_TEMP | Constants.TNS_LOB_OP_ARRAY

        // temp lob data
        buffer.writeInteger(UInt8(1)) // pointer
        buffer.writeUB4(UInt32(self.connection.tempLOBsTotalSize))
        buffer.writeInteger(UInt8(0)) // destination lob locator
        buffer.writeUB4(0)
        buffer.writeUB4(0) // source lob locator
        buffer.writeUB4(0)
        buffer.writeInteger(UInt8(0)) // source lob offset
        buffer.writeInteger(UInt8(0)) // destination lob offset
        buffer.writeInteger(UInt8(0)) // charset
        buffer.writeUB4(opCode)
        buffer.writeInteger(UInt8(0)) // scn
        buffer.writeUB4(0) // losbscn
        buffer.writeUB8(0) // lobscnl
        buffer.writeUB8(0)
        buffer.writeInteger(UInt8(0))

        // array lob fields
        buffer.writeInteger(UInt8(0))
        buffer.writeUB4(0)
        buffer.writeInteger(UInt8(0))
        buffer.writeUB4(0)
        buffer.writeInteger(UInt8(0))
        buffer.writeUB4(0)

        for lob in lobs {
            buffer.writeBytes(lob)
        }

        // reset values
        self.connection.tempLOBsToClose = nil
        self.connection.tempLOBsTotalSize = 0
    }

    // MARK: Process Response

    func preprocess() {
        guard let statement = cursor?.statement else {
            preconditionFailure()
        }
        if statement.isReturning && !parseOnly {
            self.outVariables = []
            for bindInfo in statement.bindInfoList where bindInfo.isReturnBind {
                guard let variable = bindInfo.variable else { continue }
                self.outVariables?.append(variable)
            }
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

        // the list of output variables is equivalent to the fetch variables
        self.outVariables = cursor.fetchVariables

        // resize fetch variables, if necessary, to allow room in each variable for the fetch array size
        outVariables?.updateEach { variable in
            guard variable.numberOfElements < cursor.fetchArraySize else { return }
            let numberOfValues = cursor.fetchArraySize - variable.numberOfElements
            variable.numberOfElements = cursor.fetchArraySize
            variable.values.append(contentsOf: [Any?](repeating: nil, count: Int(numberOfValues)))
        }
    }

    func processResponse(_ message: inout TNSMessage, of type: MessageType, from channel: Channel) throws {
        switch type {
        case .rowHeader:
            try self.processRowHeader(&message)
        case .rowData:
            try self.processRowData(&message)
        case .flushOutBinds:
            self.flushOutBinds = true
        case .describeInfo:
            message.packet.skipRawBytesChunked()
            try self.processDescribeInfo(&message)
            self.outVariables = self.cursor?.fetchVariables
        case .error:
            if let error = try self.processErrorInfo(&message) {
                connection.logger.warning("Oracle Error occurred: \(error)")
            }
        case .bitVector:
            try self.processBitVector(&message)
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

    func processDescribeInfo(_ message: inout TNSMessage, cursor: Cursor? = nil) throws {
        guard let cursor = cursor ?? self.cursor else { preconditionFailure() }
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

    func processRowData(_ message: inout TNSMessage) throws {
        guard let cursor else { preconditionFailure() }
        var value: Any?
        var values: [Any?] = []
        try self.outVariables?.updateEachEnumeratedThrowing { index, variable in
            if variable.isArray {
                variable.numberOfElementsInArray = message.packet.readUB4() ?? 0
                for position in 0..<variable.numberOfElementsInArray! {
                    value = try self.processColumnData(&message, variable: variable, position: position)
                    variable.values[Int(position)] = value
                }
            } else if cursor.statement.isReturning == true {
                let numberOfRows = message.packet.readUB4() ?? 0
                values = [Any?](repeating: nil, count: Int(numberOfRows))
                for i in 0..<numberOfRows {
                    values[Int(i)] = try processColumnData(&message, variable: variable, position: i)
                }
                variable.values[Int(rowIndex)] = value
            } else if isDuplicateData(columnNumber: UInt32(index)) {
                if rowIndex == 0 {
                    value = variable.lastRawValue
                } else {
                    value = variable.values[cursor.lastRowIndex]
                }
                variable.values[Int(rowIndex)] = value
            } else {
                value = try self.processColumnData(&message, variable: variable, position: rowIndex)
            }
            variable.values[Int(rowIndex)] = value
        }
        rowIndex += 1
        if inFetch {
            cursor.lastRowIndex = Int(rowIndex - 1)
            cursor.bufferRowCount = Int(rowIndex)
            bitVector = nil
        }
    }

    func processColumnData(_ message: inout TNSMessage, variable: Variable, position: UInt32) throws -> Any? {
        var oracleType: DataType.Value?
        let csfrm: UInt8
        let bufferSize: UInt32
        if let fetchInfo = variable.fetchInfo {
            oracleType = fetchInfo.dbType.oracleType
            csfrm = fetchInfo.dbType.csfrm
            bufferSize = fetchInfo.bufferSize
        } else {
            oracleType = variable.dbType.oracleType
            csfrm = variable.dbType.csfrm
            bufferSize = variable.bufferSize
        }
        if variable.bypassDecode {
            oracleType = .raw
        }
        var columnValue: Any? // TODO: Create type for this
        if bufferSize == 0 && inFetch && ![DataType.Value.long, .longRAW, .uRowID].contains(oracleType) {
            columnValue = nil
        } else if [DataType.Value.varchar, .char, .long].contains(oracleType) {
            if csfrm == Constants.TNS_CS_NCHAR {
                try connection.capabilities.checkNCharsetID()
            }
            columnValue = message.packet.readString(with: Int(csfrm))
        } else if [DataType.Value.raw, .longRAW].contains(oracleType) {
            columnValue = message.packet.readBytes()
        } else if oracleType == .number {
            columnValue = message.packet.readOracleNumber()
        } else if [DataType.Value.date, .timestamp, .timestampLTZ, .timestampTZ].contains(oracleType) {
            columnValue = try message.packet.readDate()
        } else if oracleType == .rowID {
            if !inFetch {
                columnValue = message.packet.readString(with: Constants.TNS_CS_IMPLICIT)
            } else {
                let length = message.packet.readUB1() ?? 0
                if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
                    columnValue = nil
                } else {
                    columnValue = message.packet.readRowID()
                }
            }
        } else if oracleType == .uRowID {
            if !inFetch {
                columnValue = message.packet.readString(with: Constants.TNS_CS_IMPLICIT)
            } else {
                columnValue = message.packet.readUniversalRowID()
            }
        } else if oracleType == .binaryDouble {
            columnValue = message.packet.readBinaryDouble()
        } else if oracleType == .binaryFloat {
            columnValue = message.packet.readBinaryFloat()
        } else if oracleType == .binaryInteger {
            columnValue = message.packet.readOracleNumber().map(Int.init(_:))
        } else if oracleType == .cursor {
            message.packet.skipUB1() // length (fixed value)
            if !inFetch {
                columnValue = variable.values[Int(position)]
            }
            let cursor = try createCursorFromDescribe(&message)
            cursor.statement.cursorID = message.packet.readUB2() ?? 0
            columnValue = cursor
        } else if oracleType == .boolean {
            columnValue = message.packet.readBool()
        } else if oracleType == .intervalDS {
            columnValue = message.packet.readIntervalDS()
        } else if [DataType.Value.clob, .blob].contains(oracleType) {
            columnValue = message.packet.readLOBWithLength(connection: connection, dbType: variable.dbType)
        } else if oracleType == .json {
            columnValue = try message.packet.readOSON()
        } else {
            throw OracleError.ErrorType.dbTypeNotSupported
        }

        if !inFetch {
            let actualNumberOfBytes = message.packet.readSB4()
            if let actualNumberOfBytes, actualNumberOfBytes < 0, oracleType == .boolean {
                columnValue = nil
            } else if actualNumberOfBytes != 0 && columnValue != nil {
                throw OracleError.ErrorType.columnTruncated
            }
        } else if oracleType == .long || oracleType == .longRAW {
            message.packet.skipSB4() // null indicator
            message.packet.skipUB4() // return code
        }
        return columnValue
    }

    func processReturnParameters(_ message: inout TNSMessage) {
        var numberOfParameters = message.packet.readUB2() ?? 0 // al8o4l (ignored)
        for _ in 0..<numberOfParameters {
            message.packet.skipUB4()
        }
        var numberOfBytes = message.packet.readUB2() ?? 0 // al8txl (ignored)
        if numberOfBytes > 0 {
            message.packet.moveReaderIndex(forwardByBytes: Int(numberOfBytes))
        }
        numberOfParameters = message.packet.readUB2() ?? 0 // number of key/value pairs
        for _ in 0..<numberOfParameters {
            var numberOfBytes = message.packet.readUB2() ?? 0 // key
            var keyValue: [UInt8]? = nil
            if numberOfBytes > 0 {
                keyValue = message.packet.readBytes()
            }
            numberOfBytes = message.packet.readUB2() ?? 0 // value
            if numberOfBytes > 0 {
                message.packet.skipRawBytesChunked()
            }
            let keywordNumber = message.packet.readUB2() ?? 0 // keyword number
            if keywordNumber == Constants.TNS_KEYWORD_NUM_CURRENT_SCHEMA, let keyValue {
                connection.currentSchema = String(cString: keyValue)
            } else if keywordNumber == Constants.TNS_KEYWORD_NUM_EDITION, let keyValue {
                connection.edition = String(cString: keyValue)
            }
        }
        numberOfBytes = message.packet.readUB2() ?? 0
        if numberOfBytes > 0 {
            message.packet.moveReaderIndex(forwardByBytes: Int(numberOfBytes))
        }
        if arrayDMLRowCounts {
            let numberOfRows = message.packet.readUB4() ?? 0
            var rowCounts = [UInt64]()
            cursor?.dmlRowCounts = []
            for _ in 0..<numberOfRows {
                let rowCount = message.packet.readUB8() ?? 0
                rowCounts.append(rowCount)
            }
        }
    }

    func processErrorInfo(_ message: inout TNSMessage) throws -> OracleErrorInfo? {
        guard let cursor else { preconditionFailure() }
        var errorOccured = true
        var error = processError(&message)
        cursor.statement.cursorID = error.cursorID ?? 0
        if !cursor.statement.isPlSQL && !inFetch {
            cursor.rowCount = error.rowCount
        }
        cursor.lastRowID = error.rowID
        cursor.batchErrors = error.batchErrors
        if error.number == Constants.TNS_ERR_NO_DATA_FOUND {
            error.number = 0
            cursor.moreRowsToFetch = false
            errorOccured = false
        } else if error.number == Constants.TNS_ERR_ARRAY_DML_ERRORS {
            error.number = 0
            cursor.moreRowsToFetch = false
            errorOccured = false
        } else if error.number == Constants.TNS_ERR_VAR_NOT_IN_SELECT_LIST {
            try connection.addCursorToClose(cursor.statement)
            cursor.statement.cursorID = 0
        } else if error.number != 0 && error.cursorID != 0 {
            let exception = getExceptionClass(for: Int32(error.number))
            if exception != .integrityError {
                try connection.addCursorToClose(cursor.statement)
                cursor.statement.cursorID = 0
            }
        }
        if errorOccured {
            return error
        }
        return nil
    }

    func processBitVector(_ message: inout TNSMessage) throws {
        guard let cursor else {
            preconditionFailure()
        }
        self.numberOfColumnsSent = message.packet.readUB2()
        var numberOfBytes = cursor.numberOfColumns / 8
        if cursor.numberOfColumns % 8 > 0 {
            numberOfBytes += 1
        }
        try self.getBitVector(&message, size: numberOfBytes)
    }

    func postprocess() {
        guard let outVariables else { return }
        self.cursor?.fetchVariables = outVariables
    }

    // MARK: Helper

    /// Gets the bit vector from the buffer and stores it for later use by the
    /// row processing code. Since it is possible that the packet buffer may be
    /// overwritten by subsequent packet retrieval, the bit vector must be
    /// copied.
    func getBitVector(_ message: inout TNSMessage, size: UInt32) throws {
        if self.bitVector == nil, let bytes = message.packet.readBytes(length: Int(size)) {
            self.bitVector = bytes
        }
    }

    private func createCursorFromDescribe(_ message: inout TNSMessage) throws -> Cursor {
        let cursor = try Cursor(statement: Statement(characterConversion: connection.capabilities.characterConversion), fetchArraySize: 0, fetchVariables: [])
        try self.processDescribeInfo(&message, cursor: cursor)
        cursor.fetchArraySize = UInt32(cursor.arraySize) + cursor.prefetchRows
        cursor.moreRowsToFetch = true
        cursor.statement.isQuery = true
        cursor.statement.requiresFullExecute = true
        return cursor
    }

    /// Returns a boolean indicating if the given column contains data
    /// duplicated from the previous row. When duplicate data exists, the
    /// server sends a bit vector. Bits that are set indicate that data is sent
    /// with the row data; bits that are not set indicate that data should be
    /// duplicated from the previous row.
    private func isDuplicateData(columnNumber: UInt32) -> Bool {
        guard let bitVector else { return false }
        let byteNumber = columnNumber / 8
        let bitNumber = columnNumber % 8
        return bitVector[Int(byteNumber)] & (1 << bitNumber) == 0
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
    var processedError = false
    var rowIndex: UInt32 = 0
    var numberOfColumnsSent: UInt16?

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
            try self.writeReexecuteMessage(to: &buffer)
        } else {
            self.functionCode = Constants.TNS_FUNC_EXECUTE
            try self.writeExecuteMessage(&buffer)
        }

        buffer.endRequest(capabilities: connection.capabilities)
        return [.init(packet: buffer)]
    }

    // MARK: Response processing

    // MARK: Private methods

    private func writeExecuteMessage(_ buffer: inout ByteBuffer) throws {
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
        if !statement.isPlSQL && !parseOnly {
            options |= Constants.TNS_EXEC_OPTION_NOT_PLSQL
        } else if statement.isPlSQL && numberOfParameters > 0 {
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
            try self.writeBindParameters(to: &buffer, with: parameters)
        }
    }

    private func writeReexecuteMessage(to buffer: inout ByteBuffer) throws {
        guard let cursor else {
            preconditionFailure()
        }
        var parameters = cursor.statement.bindInfoList
        var executionFlags1: UInt32 = 0
        var executionFlags2: UInt32 = 0
        var numberOfIterations: UInt32 = 0

        if !parameters.isEmpty {
            if !cursor.statement.isQuery {
                self.outVariables = parameters.compactMap {
                    guard ($0.bindDir ?? 0) != Constants.TNS_BIND_DIR_INPUT else { return nil }
                    return $0.variable
                }
            }

            parameters = parameters.filter { info in
                (info.bindDir ?? 0) != Constants.TNS_BIND_DIR_OUTPUT && !info.isReturnBind
            }
        }

        if self.functionCode == Constants.TNS_FUNC_REEXECUTE_AND_FETCH {
            executionFlags1 |= Constants.TNS_EXEC_OPTION_EXECUTE
            numberOfIterations = cursor.prefetchRows
            cursor.fetchArraySize = numberOfIterations
        } else {
            if self.connection.autocommit {
                executionFlags2 |= Constants.TNS_EXEC_OPTION_COMMIT_REEXECUTE
            }
            numberOfIterations = self.numberOfExecutions
        }

        self.writePiggybacks(to: &buffer)
        self.writeFunctionCode(to: &buffer)
        buffer.writeUB4(UInt32(cursor.statement.cursorID))
        buffer.writeUB4(numberOfIterations)
        buffer.writeUB4(executionFlags1)
        buffer.writeUB4(executionFlags2)
        if !parameters.isEmpty {
            for i in 0..<numberOfExecutions {
                buffer.writeInteger(MessageType.rowData.rawValue)
                try self.writeBindParameterRow(to: &buffer, with: parameters, at: i)
            }
        }
    }

    func writeFunctionCode(to buffer: inout ByteBuffer) {
        buffer.writeInteger(self.messageType.rawValue)
        buffer.writeInteger(self.functionCode)
        buffer.writeSequenceNumber(with: self.currentSequenceNumber)
        self.currentSequenceNumber += 1
    }
}

final class FetchRequest: TNSRequestWithData {
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
    var processedError = false
    var rowIndex: UInt32 = 0
    var numberOfColumnsSent: UInt16?

    init(connection: OracleConnection, messageType: MessageType) {
        self.connection = connection
        self.messageType = messageType
    }

    func initializeHooks() {
        self.functionCode = Constants.TNS_FUNC_FETCH
    }

    func get() throws -> [TNSMessage] {
        guard let cursor else {
            preconditionFailure()
        }

        var buffer = ByteBuffer()
        buffer.startRequest()
        self.writeFunctionCode(to: &buffer)
        buffer.writeUB4(UInt32(cursor.statement.cursorID))
        buffer.writeUB4(cursor.fetchArraySize)
        buffer.endRequest(capabilities: connection.capabilities)

        return [TNSMessage(packet: buffer)]
    }
}


extension MutableCollection {
    mutating func updateEach(_ update: (inout Element) ->  Void) {
        for i in indices {
            update(&self[i])
        }
    }

    mutating func updateEachThrowing(_ update: (inout Element) throws ->  Void) throws {
        for i in indices {
            try update(&self[i])
        }
    }

    mutating func updateEachEnumerated(_ update: (Index, inout Element) -> Void) {
        for i in indices {
            update(i, &self[i])
        }
    }

    mutating func updateEachEnumeratedThrowing(_ update: (Index, inout Element) throws -> Void) throws {
        for i in indices {
            try update(i, &self[i])
        }
    }
}
