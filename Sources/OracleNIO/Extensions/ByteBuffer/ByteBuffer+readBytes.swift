import NIOCore

extension ByteBuffer {
    mutating func _readRawBytesAndLength() -> (
        bytes: [UInt8]?, length: UInt8
    )? {
        guard let length = readUB1() else { return nil }
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return (bytes: [], length: 0)
        }
        return (bytes: readBytes(length: Int(length)), length: length)
    }

    mutating func readBytes() -> [UInt8]? {
        _readRawBytesAndLength()?.bytes
    }

    private mutating func _readSliceAndLength() -> (
        buffer: ByteBuffer?, length: UInt8
    ) {
        guard let length = readUB1() else { preconditionFailure() }
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return (nil, length: 0)
        }
        return (self.readSlice(length: Int(length)), length)
    }

    /// Read a slice of data prefixed with a length byte.
    ///
    /// If not enough data could be read, `nil` will be returned, indicating that another packet must be
    /// read from the channel to complete the operation.
    mutating func readOracleSlice() -> ByteBuffer? {
        guard
            let length = self.getInteger(at: self.readerIndex, as: UInt8.self)
        else {
            preconditionFailure()
        }
        let sliceLength = Int(length) + MemoryLayout<UInt8>.size
        if self.readableBytes < sliceLength {
            return nil // need more data
        }
        return self.readSlice(length: sliceLength)
    }
}
