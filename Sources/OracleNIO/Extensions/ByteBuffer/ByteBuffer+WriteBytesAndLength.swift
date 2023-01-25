import struct NIOCore.ByteBuffer

extension ByteBuffer {
    /// Helper function that writes the length in the format required before writing the bytes.
    mutating func writeBytesAndLength(_ bytes: [UInt8]) {
        var numberOfBytes = bytes.count
        if numberOfBytes <= Constants.TNS_MAX_SHORT_LENGTH {
            self.writeInteger(UInt8(numberOfBytes))
            self.writeBytes(bytes)
        } else {
            self.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            while bytes.count > 0 {
                let chunkLength = min(numberOfBytes, Constants.TNS_CHUNK_SIZE)
                self.writeUB4(UInt32(chunkLength))
                numberOfBytes -= chunkLength
                self.writeBytes(bytes.dropFirst(chunkLength))
            }
            self.writeUB4(0)
        }
    }
}
