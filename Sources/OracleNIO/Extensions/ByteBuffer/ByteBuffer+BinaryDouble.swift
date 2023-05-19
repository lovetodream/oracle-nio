import NIOCore

extension ByteBuffer {
    mutating func readBinaryDouble() -> Double? {
        guard let (bytes, _) = self._readRawBytesAndLength(), let bytes else { return nil }
        return parseBinaryDouble(bytes: bytes)
    }

    mutating func parseBinaryDouble(bytes: [UInt8]) -> Double? {
        var b0 = bytes[0]
        var b1 = bytes[1]
        var b2 = bytes[2]
        var b3 = bytes[3]
        var b4 = bytes[4]
        var b5 = bytes[5]
        var b6 = bytes[6]
        var b7 = bytes[7]
        if (b0 & 0x80) != 0 {
            b0 = b0 & 0x7f
        } else {
            b0 = ~b0
            b1 = ~b1
            b2 = ~b2
            b3 = ~b3
            b4 = ~b4
            b5 = ~b5
            b6 = ~b6
            b7 = ~b7
        }
        let highBits: UInt64 = UInt64(b0 << 24 | b1 << 16 | b2 << 8 | b4)
        let lowBits: UInt64 = UInt64(b4 << 24 | b5 << 16 | b6 << 8 | b7)
        let allBits: UInt64 = highBits << 32 | (lowBits & 0xffffffff)
        let double = Double(bitPattern: allBits)
        return double
    }

    mutating func writeBinaryDouble(_ value: Double) {
        var b0, b1, b2, b3, b4, b5, b6, b7: UInt8
        let allBits = value.bitPattern
        b7 = UInt8(allBits & 0xff)
        b6 = UInt8((allBits >> 8) & 0xff)
        b5 = UInt8((allBits >> 16) & 0xff)
        b4 = UInt8((allBits >> 24) & 0xff)
        b3 = UInt8((allBits >> 32) & 0xff)
        b2 = UInt8((allBits >> 40) & 0xff)
        b1 = UInt8((allBits >> 48) & 0xff)
        b0 = UInt8((allBits >> 56) & 0xff)
        if b0 & 0x80 == 0 {
            b0 = b0 | 0x80
        } else {
            b0 = ~b0
            b1 = ~b1
            b2 = ~b2
            b3 = ~b3
            b4 = ~b4
            b5 = ~b5
            b6 = ~b6
            b7 = ~b7
        }
        var buffer = ByteBuffer(bytes: [b0, b1, b2, b3, b4, b5, b6, b7])
        self.writeInteger(UInt8(8))
        self.writeBuffer(&buffer)
    }
}
