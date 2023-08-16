import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readString(with charset: Int) -> String? {
        checkPreconditions(charset: charset)
        let length = readInteger(as: UInt8.self) ?? 0
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR { return nil }
        return self.readString(length: Int(length))
    }

    mutating func readStringBytes(with charset: Int) -> ByteBuffer? {
        checkPreconditions(charset: charset)
        guard let length = readInteger(as: UInt8.self).map(Int.init) else {
            return nil
        }
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return nil
        }
        return self.readSlice(length: length)
    }

    mutating func readStringSlice(with charset: Int) -> ByteBuffer? {
        checkPreconditions(charset: charset)
        guard 
            let length = self.getInteger(
                at: self.readerIndex, as: UInt8.self
            ).map(Int.init)
        else {
            return nil
        }
        return self.readSlice(length: Int(length) + MemoryLayout<UInt8>.size)
    }

    private func checkPreconditions(charset: Int) {
        guard charset == Constants.TNS_CS_IMPLICIT else {
            fatalError("UTF-16 is not supported")
        }
    }
}
