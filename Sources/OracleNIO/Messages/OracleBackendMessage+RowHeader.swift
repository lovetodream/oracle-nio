extension OracleBackendMessage {
    struct RowHeader: PayloadDecodable {

        /// Gets the bit vector from the buffer and stores it for later use by the
        /// row processing code. Since it is possible that the packet buffer may be
        /// overwritten by subsequent packet retrieval, the bit vector must be
        /// copied.
        let bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer, capabilities: Capabilities
        ) throws -> OracleBackendMessage.RowHeader {
            buffer.skipUB1() // flags
            buffer.skipUB2() // number of requests
            buffer.skipUB4() // iteration number
            buffer.skipUB4() // number of iterations
            buffer.skipUB2() // buffer length
            if let bytesCount = buffer.readUB4(), bytesCount > 0 {
                buffer.skipUB1() // skip repeated length
                let bytes = buffer.readBytes(length: Int(bytesCount))
                return .init(bitVector: bytes)
            }
            if let numberOfBytes = buffer.readUB4(), numberOfBytes > 0 {
                buffer.skipRawBytesChunked() // rxhrid
            }
            return .init(bitVector: nil)
        }
    }
}
