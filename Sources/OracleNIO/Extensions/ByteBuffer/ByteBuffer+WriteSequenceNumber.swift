import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func writeSequenceNumber(with previousNumber: UInt8 = 0) {
        self.writeInteger(previousNumber + 1)
    }
}
