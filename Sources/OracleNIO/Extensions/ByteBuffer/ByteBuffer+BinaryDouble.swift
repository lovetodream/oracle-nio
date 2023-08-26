import NIOCore

extension ByteBuffer {
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
}
