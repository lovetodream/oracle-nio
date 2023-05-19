// TODO: add a lot of missing stuff and try to move this to struct again
class LOB {
    var connection: OracleConnection
    var dbType: DBType
    var locator: [UInt8]
    var size: UInt64 = 0
    var chunkSize: UInt32 = 0
    var hasMetadata = false

    init(connection: OracleConnection, dbType: DBType, locator: [UInt8]) {
        self.connection = connection
        self.dbType = dbType
        self.locator = locator
    }
    deinit { freeLOB() }

    static func create(connection: OracleConnection, dbType: DBType, locator: [UInt8]? = nil) -> LOB {
        if let locator {
            return LOB(connection: connection, dbType: dbType, locator: locator)
        } else {
            let locator = [UInt8](repeating: 0, count: 40)
            let lob = LOB(connection: connection, dbType: dbType, locator: locator)
            let request: LOBOperationRequest = connection.createRequest()
            request.operation = Constants.TNS_LOB_OP_CREATE_TEMP
            request.amount = Constants.TNS_DURATION_SESSION
            request.sendAmount = true
            request.sourceLOB = lob
            request.sourceOffset = UInt64(dbType.csfrm)
            request.destinationOffset = UInt64(dbType.oracleType?.rawValue ?? 0)
            connection.channel.writeAndFlush(.init(request), promise: nil)
            return lob
        }
    }

    func encoding() -> String {
        if dbType.csfrm == Constants.TNS_CS_NCHAR || (locator.count >= Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3 && ((locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3] & Constants.TNS_LOB_LOCATOR_VAR_LENGTH_CHARSET) != 0)) {
            return Constants.TNS_ENCODING_UTF16
        }
        return Constants.TNS_ENCODING_UTF8
    }

    func write(_ value: Any, offset: UInt64) { // TODO: value either string, bytes, buffer
        let request: LOBOperationRequest = connection.createRequest()
        request.operation = Constants.TNS_LOB_OP_WRITE
        request.sourceLOB = self
        request.sourceOffset = offset
        if self.dbType.oracleType == .blob, let value = value as? [UInt8] {
            request.data = value
        } else if let value = value as? String {
            request.data = value.data(using: encoding() == Constants.TNS_ENCODING_UTF16 ? .utf16 : .utf8)?.bytes
        } else {
            fatalError("Invalid value, can be either string or bytes")
        }
        self.connection.channel.writeAndFlush(.init(request), promise: nil)
        self.hasMetadata = false
    }

    func freeLOB() {
        let flags1 = self.locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_1]
        let flags4 = self.locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_4]
        if flags1 & Constants.TNS_LOB_LOCATOR_FLAGS_ABSTRACT != 0 || flags4 & Constants.TNS_LOB_LOCATOR_FLAGS_TEMP != 0 {
            if self.connection.tempLOBsToClose == nil {
                self.connection.tempLOBsToClose = []
            }
            self.connection.tempLOBsToClose?.append(self.locator)
            self.connection.tempLOBsTotalSize += self.locator.count
        }
    }
}
