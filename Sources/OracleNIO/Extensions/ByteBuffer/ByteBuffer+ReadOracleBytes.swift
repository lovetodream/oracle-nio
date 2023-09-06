import NIOCore

extension ByteBuffer {
    mutating func readOracleSpecificLengthPrefixedSlice(
        file: String = #fileID, line: Int = #line
    ) throws -> ByteBuffer {
        guard let length = self.readInteger(as: UInt8.self).map(Int.init) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        }
        
        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return .init() // empty buffer
        }

        return self.readSlice(length: length)!
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
