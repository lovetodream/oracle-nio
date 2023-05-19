import NIOCore

extension ByteBuffer {
    mutating func readOSON() throws -> Any? {
        guard let length = readUB4(), length > 0 else { return nil }
        skipUB8() // size (unused)
        skipUB4() // chunk size (unused)
        guard let data = readBytes() else { return nil }
        _ = readBytes() // lob locator (unused)
        var decoder = OSONDecoder()
        return try decoder.decode(data)
    }

    mutating func writeOSON() throws {
        throw OracleError.ErrorType.dbTypeNotSupported
    }
}
