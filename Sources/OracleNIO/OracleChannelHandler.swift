import NIOCore
import NIOPosix
import Logging

class OracleChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
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
        print(data)
        let buffer = self.unwrapInboundIn(data)
        guard var message = TNSMessage(from: buffer) else { return }
        logger.trace("Response received: \(message.type)")
        switch message.type {
        case .resend:
            guard let currentRequest else {
                logger.warning("Received a resend response, but could not resend the last request.")
                return
            }
            print(currentRequest)
            context.channel.write(currentRequest, promise: nil)
        case .accept:
            do {
                try currentRequest?.processResponse(&message, from: context.channel)
            } catch {
                self.errorCaught(context: context, error: error)
            }
        default:
            fatalError("A handler for \(message.type) is not implemented")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        print(data)
        let messages = self.unwrapOutboundIn(data)
        self.queue.append(messages)
        for message in messages.get() {
            context.write(self.wrapOutboundOut(message.packet), promise: nil)
        }
        context.flush()
        logger.trace("Message sent")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print(error)
        context.fireErrorCaught(error)
    }

}

let PACKET_HEADER_SIZE = 8

extension ByteBuffer {
    mutating func startRequest(packetType: PacketType, dataFlags: UInt16 = 0) {
        self.reserveCapacity(PACKET_HEADER_SIZE)
        self.moveWriterIndex(forwardBy: PACKET_HEADER_SIZE) // Placeholder for the header, which is set at the end of an request
        if packetType == PacketType.data {
            self.writeInteger(dataFlags)
        }
    }
}

extension ByteBuffer {
    mutating func endRequest(packetType: PacketType) {
        self.sendPacket(packetType: packetType, final: true)
    }
}

extension ByteBuffer {
    mutating func sendPacket(packetType: PacketType, capabilities: Capabilities? = nil, final: Bool) {
        var position = 0
        if capabilities?.protocolVersion ?? 0 >= Constants.TNS_VERSION_MIN_LARGE_SDU {
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
