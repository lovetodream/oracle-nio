import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readChunk() -> [UInt8]? {
        guard let length = self.readInteger(as: UInt8.self), length > 0 else { return nil }
        return self.readBytes(length: Int(length))
    }
}
