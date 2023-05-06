import NIOCore

extension ByteBuffer {
    mutating func readBool() -> Bool? {
        guard let (bytes, length) = _readRawBytesAndLength(), let bytes else { return nil }
        return bytes[Int(length) - 1] == 1
    }
}
