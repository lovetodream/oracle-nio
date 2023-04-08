import NIOCore

extension ByteBuffer {
    mutating func _readRawBytesAndLength() -> (bytes: [UInt8]?, length: UInt8)? {
        guard let length = readUB1() else { return nil }
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return (bytes: [], length: 0)
        }
        return (bytes: readBytes(length: Int(length)), length: length)
    }

    mutating func readBytes() -> [UInt8]? {
        _readRawBytesAndLength()?.bytes
    }
}
