import NIOCore

extension ByteBuffer {
    mutating func readBinaryFloat() -> Float? {
        guard let (bytes, _) = _readRawBytesAndLength(), let bytes else { return nil }
        return parseBinaryFloat(bytes: bytes)
    }

    mutating func parseBinaryFloat(bytes: [UInt8]) -> Float {
        var b0 = bytes[0]
        var b1 = bytes[1]
        var b2 = bytes[2]
        var b3 = bytes[3]
        if (b0 & 0x80) != 0 {
            b0 = b0 & 0x7f
        } else {
            b0 = ~b0
            b1 = ~b1
            b2 = ~b2
            b3 = ~b3
        }
        let allBits: UInt32 = UInt32((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        let float = Float(bitPattern: allBits)
        return float
    }
}
