import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readString(with charset: Int) -> String? {
        let length = readInteger(as: UInt8.self) ?? 0
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR { return nil }
        guard let bytes = readBytes(length: Int(length)) else { return nil }
        return String(bytes: bytes, encoding: charset == Constants.TNS_CS_IMPLICIT ? .utf8 : .utf16)
    }
}
