import NIOCore

extension ByteBuffer {
    mutating func readLOBWithLength(connection: OracleConnection, dbType: DBType) -> LOB? {
        let length = readUB4() ?? 0
        guard length > 0 else { return nil }
        let size = readUB8() ?? 0
        let chunkSize = readUB4() ?? 0
        let locator = readBytes()
        var lob = LOB.create(connection: connection, dbType: dbType, locator: locator)
        lob.size = size
        lob.chunkSize = chunkSize
        lob.hasMetadata = true
        return lob
    }
}
