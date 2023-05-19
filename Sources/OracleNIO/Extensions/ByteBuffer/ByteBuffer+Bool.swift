import NIOCore

extension ByteBuffer {
    mutating func readBool() -> Bool? {
        guard let (bytes, length) = _readRawBytesAndLength(), let bytes else { return nil }
        return bytes[Int(length) - 1] == 1
    }

    mutating func writeBool(_ value: Bool) {
        if value {
            self.writeInteger(UInt8(2))
            self.writeInteger(UInt16(0x0101))
        } else {
            self.writeInteger(UInt16(0x0100))
        }
    }
}
