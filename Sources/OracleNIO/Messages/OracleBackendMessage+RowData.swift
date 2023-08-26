import NIOCore

extension OracleBackendMessage {
    struct RowData: PayloadDecodable, Sendable, Hashable {
        /// Row data cannot be decoded in any other way, because the bounds
        /// aren't clear without the information from ``DescribeInfo``.
        /// Because of that the remaining buffer is returned as the row data.
        /// The state machine needs to handle cases in which the buffer contains more messages.
        var slice: ByteBuffer

        static func decode(
            from buffer: inout ByteBuffer, capabilities: Capabilities
        ) throws -> RowData { 
            let data = RowData(slice: buffer.slice())
            buffer.moveReaderIndex(to: buffer.readerIndex + buffer.readableBytes)
            return data
        }
    }
}
