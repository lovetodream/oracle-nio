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

    mutating func readOracleSlice() -> ByteBuffer? {
        guard
            let length = self.getInteger(at: self.readerIndex, as: UInt8.self)
        else {
            preconditionFailure()
        }
        return self.readSlice(length: Int(length) + MemoryLayout<UInt8>.size)
    }
}
