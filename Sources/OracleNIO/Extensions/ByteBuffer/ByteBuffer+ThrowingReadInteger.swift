import NIOCore

extension ByteBuffer {
    mutating func throwingReadInteger<T: FixedWidthInteger>(
        endianness: Endianness = .big,
        as: T.Type = T.self,
        file: String = #fileID,
        line: Int = #line
    ) throws -> T {
        guard let result = self.readInteger(endianness: endianness, as: T.self) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<T>.size,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        return result
    }
}
