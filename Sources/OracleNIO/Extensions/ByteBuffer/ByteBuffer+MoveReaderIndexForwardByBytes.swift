import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func moveReaderIndex(forwardByBytes bytes: Int) {
        self.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size * bytes)
    }
}
