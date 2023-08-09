import struct NIOCore.ByteBuffer

extension ByteBuffer {
    @available(*, deprecated, renamed: "moveReaderIndex(forwardBy:)")
    mutating func moveReaderIndex(forwardByBytes bytes: Int) {
        self.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size * bytes)
    }
}
