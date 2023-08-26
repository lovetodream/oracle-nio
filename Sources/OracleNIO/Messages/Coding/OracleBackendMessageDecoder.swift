import NIOCore

struct OracleBackendMessageDecoder: ByteToMessageDecoder {

    static let headerSize = 8

    typealias InboundOut = [OracleBackendMessage]

    private var capabilities: Capabilities

    private let context: Context

    class Context {
        var performingChunkedRead = false
        var queryOptions: QueryOptions? = nil
    }

    init(capabilities: Capabilities, context: Context) {
        self.capabilities = capabilities
        self.context = context
    }

    mutating func decode(
        context: ChannelHandlerContext, buffer: inout ByteBuffer
    ) throws -> DecodingState {
        while let message = try decodeMessage(from: &buffer) {
            context.fireChannelRead(self.wrapInboundOut(message))
            if buffer.readableBytes > 0 {
                return .needMoreData
            } else {
                buffer = buffer.slice()
                return .continue
            }
        }
        return .needMoreData
    }

    private func decodeMessage(from buffer: inout ByteBuffer) throws -> InboundOut? {
        var msgs: InboundOut?
        while let messages = try self.decodeMessage0(from: &buffer) {
            buffer = buffer.slice()
            if msgs != nil {
                msgs!.append(contentsOf: messages)
            } else {
                msgs = messages
            }
        }
        return msgs
    }

    private func decodeMessage0(
        from buffer: inout ByteBuffer
    ) throws -> InboundOut? {
        let length: Int?
        if self.capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            length = buffer.getInteger(at: 0, as: UInt32.self).map(Int.init)
        } else {
            length = buffer.getInteger(at: 0, as: UInt16.self).map(Int.init)
        }
        guard
            let length,
            buffer.readableBytes >= Self.headerSize,
            let typeByte = buffer.getInteger(
                at: MemoryLayout<UInt32>.size,
                as: UInt8.self
            ),
            let type = OracleBackendMessage.ID(rawValue: typeByte),
            var packet = buffer.readSlice(length: length)
        else {
            return nil
        }

        // skip header
        if
            packet.readerIndex < Self.headerSize &&
            packet.capacity >= Self.headerSize
        {
            packet.moveReaderIndex(to: Self.headerSize)
        }

        let messages = try OracleBackendMessage.decode(
            from: &packet, of: type,
            capabilities: self.capabilities,
            queryOptions: self.context.queryOptions,
            isChunkedRead: self.context.performingChunkedRead
        )
        return messages
    }
}
