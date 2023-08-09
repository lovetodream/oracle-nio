import NIOCore
import NIOPosix
import Logging

@available(*, deprecated, renamed: "OracleChannelHandler")
class OracleChannelHandlerDeprecated: ChannelDuplexHandler {
    typealias InboundIn = TNSMessage
    typealias OutboundIn = TNSRequest
    typealias OutboundOut = ByteBuffer

    let logger: Logger
    var connection: OracleConnection!

    private var queue: [TNSRequest]

    var currentRequest: TNSRequest? {
        self.queue.first
    }

    init(logger: Logger) {
        self.logger = logger
        self.queue = []
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var message = self.unwrapInboundIn(data)
        guard let currentRequest else {
            logger.warning("Received a response, but we couldn't get the current request.")
            return
        }
        logger.trace("Response received: \(message.type)")
        queue.removeFirst()
        logger.trace("Removed current request from queue.")
        switch message.type {
        case .resend:
            context.channel.write(currentRequest, promise: nil)
            currentRequest.onResponsePromise?.succeed(message)
        case .accept, .data:
            do {
                try currentRequest.processResponse(&message, from: context.channel)
                currentRequest.onResponsePromise?.succeed(message)
            } catch {
                self.errorCaught(context: context, error: error)
                currentRequest.onResponsePromise?.fail(error)
            }
        default:
            fatalError("A handler for \(message.type) is not implemented")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        do {
            let messages = self.unwrapOutboundIn(data)
            self.queue.append(messages)
            for message in try messages.get() {
                context.write(self.wrapOutboundOut(message.packet), promise: nil)
            }
            context.flush()
            logger.trace("Message sent")
        } catch {
            logger.error("\(error.localizedDescription)")
            context.fireErrorCaught(error)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("\(error.localizedDescription)")
        context.fireErrorCaught(error)
    }

}
