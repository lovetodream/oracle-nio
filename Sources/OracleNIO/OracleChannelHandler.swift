import NIOCore
import NIOPosix
import Logging

class OracleChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = TNSMessage
    typealias OutboundIn = TNSRequest
    typealias OutboundOut = ByteBuffer

    let logger: Logger

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
        let messages = self.unwrapOutboundIn(data)
        self.queue.append(messages)
        for message in messages.get() {
            context.write(self.wrapOutboundOut(message.packet), promise: nil)
        }
        context.flush()
        logger.trace("Message sent")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("\(error.localizedDescription)")
        context.fireErrorCaught(error)
    }

}

let PACKET_HEADER_SIZE = 8

extension ByteBuffer {
    /// Starts a new request with a placeholder for the header,
    /// which is set at the end of the request via ``ByteBuffer.endRequest``,
    /// and the data flags if they are required.
    mutating func startRequest(packetType: PacketType = .data, dataFlags: UInt16 = 0) {
        self.reserveCapacity(PACKET_HEADER_SIZE)
        self.moveWriterIndex(forwardBy: PACKET_HEADER_SIZE)
        if packetType == PacketType.data {
            self.writeInteger(dataFlags)
        }
    }
}

extension ByteBuffer {
    mutating func endRequest(packetType: PacketType = .data, capabilities: Capabilities) {
        self.sendPacket(packetType: packetType, capabilities: capabilities, final: true)
    }
}

extension ByteBuffer {
    mutating func sendPacket(packetType: PacketType, capabilities: Capabilities, final: Bool) {
        var position = 0
        if capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            self.setInteger(UInt32(self.readableBytes), at: position)
        } else {
            self.setInteger(UInt16(self.readableBytes), at: position)
            self.setInteger(UInt16(0), at: position + MemoryLayout<UInt16>.size)
        }
        position += MemoryLayout<UInt32>.size
        self.setInteger(packetType.rawValue, at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt8(0), at: position)
        position += MemoryLayout<UInt8>.size
        self.setInteger(UInt16(0), at: position)
    }
}
