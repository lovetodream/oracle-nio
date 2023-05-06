struct LOB {
    var connection: OracleConnection
    var dbType: DBType
    var locator: [UInt8]
    var size: UInt64 = 0
    var chunkSize: UInt32 = 0
    var hasMetadata = false

    static func create(connection: OracleConnection, dbType: DBType, locator: [UInt8]?) -> LOB {
        if let locator {
            return LOB(connection: connection, dbType: dbType, locator: locator)
        } else {
            fatalError("Not yet implemented") // should only be required for lobs > 1GB
        }
    }

    func encoding() -> String {
        if dbType.csfrm == Constants.TNS_CS_NCHAR || (locator.count >= Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3 && ((locator[Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3] & Constants.TNS_LOB_LOCATOR_VAR_LENGTH_CHARSET) != 0)) {
            return Constants.TNS_ENCODING_UTF16
        }
        return Constants.TNS_ENCODING_UTF8
    }
}
