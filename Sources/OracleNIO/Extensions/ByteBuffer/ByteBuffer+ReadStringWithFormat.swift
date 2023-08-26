import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readString(with charset: Int) -> String? {
        checkPreconditions(charset: charset)
        let length = readInteger(as: UInt8.self) ?? 0
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR { return nil }
        return self.readString(length: Int(length))
    }

    private func checkPreconditions(charset: Int) {
        guard charset == Constants.TNS_CS_IMPLICIT else {
            fatalError("UTF-16 is not supported")
        }
    }
}
