import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readString(with charset: Int) throws -> String? {
        checkPreconditions(charset: charset)
        var stringSlice = try self.readOracleSpecificLengthPrefixedSlice()
        return stringSlice.readString(length: stringSlice.readableBytes)
    }

    private func checkPreconditions(charset: Int) {
        guard charset == Constants.TNS_CS_IMPLICIT else {
            fatalError("UTF-16 is not supported")
        }
    }
}
