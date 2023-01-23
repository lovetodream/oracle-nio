import NIOCore

struct TNSMessageDecoder: ByteToMessageDecoder {
    typealias InboundOut = TNSMessage

    let connection: OracleConnection

    init(connection: OracleConnection) {
        self.connection = connection
    }

    func decode(context: NIOCore.ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        /// Clarification about `.continue` and `.needMoreData`:
        /// https://forums.swift.org/t/pipeline-handler-ordering-and-other-questions/24874/4
        while let message = TNSMessage(from: &buffer, with: connection.capabilities) {
            context.fireChannelRead(wrapInboundOut(message))
            return .continue
        }
        return .needMoreData
    }
}
