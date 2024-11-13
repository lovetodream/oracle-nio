import NIOCore

extension ByteBuffer {
    @inline(__always)
    mutating func throwingMoveReaderIndex(forwardBy: Int, file: String = #fileID, line: Int = #line) throws {
        if self.readableBytes < forwardBy {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                forwardBy,
                actual: self.readableBytes,
                file: file,
                line: line
            )
        }
        self.moveReaderIndex(forwardBy: forwardBy)
    }
}
