//
//  Protocol.swift
//  
//
//  Created by Timo Zacherl on 05.01.23.
//

import NIOCore
import NIOPosix
import Logging

/// Defining the protocol used by the client when communicating with the database.
public class OracleProtocol {
    let group: MultiThreadedEventLoopGroup
    let logger: Logger
    var channel: Channel?

    public init(group: MultiThreadedEventLoopGroup, logger: Logger) {
        self.group = group
        self.logger = logger
    }

    public func connectPhaseOne(connection: OracleConnection, address: SocketAddress) throws {
        try self.connectTCP(address, logger: logger)

        let connectMessage: ConnectMessage = connection.createMessage()
        try self.process(message: connectMessage)
    }

    public func connectPhaseTwo() throws {

    }

    func connectTCP(_ address: SocketAddress, logger: Logger) throws {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .channelOption(ChannelOptions.connectTimeout, value: .none)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([OracleChannelHandler(logger: logger)])
            }
        self.channel = try bootstrap.connect(to: address).wait()
    }

    private func process(message: Message) throws {
        try channel?.write(message.get()).wait()
//        self.receivePacket()
    }

    private func receivePacket() {

    }
}

struct TNSMessage {
    let type: Constants.PacketType

    init?(from buffer: ByteBuffer) {
        guard
            buffer.readableBytes >= PACKET_HEADER_SIZE,
            let typeByte: UInt8 = buffer.getInteger(at: MemoryLayout<UInt32>.size),
            let type = Constants.PacketType(rawValue: typeByte)
        else {
            return nil
        }
        self.type = type
    }
}

class OracleChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    let logger: Logger

    private var queue: [ByteBuffer]

    var currentRequest: ByteBuffer? {
        self.queue.first
    }

    init(logger: Logger) {
        self.logger = logger
        self.queue = []
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print(data)
        let buffer = self.unwrapInboundIn(data)
        guard let message = TNSMessage(from: buffer) else { return }
        logger.trace("Response received: \(message.type)")
        switch message.type {
        case .resend:
            guard let currentRequest else {
                logger.warning("Received a resend response, but could not resend the last request.")
                return
            }
            print(currentRequest)
            context.writeAndFlush(self.wrapOutboundOut(currentRequest), promise: nil)
        default:
            fatalError("A handler for \(message.type) is not implemented")
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        print(data)
        let buffer = self.unwrapOutboundIn(data)
        self.queue.append(buffer)
        context.writeAndFlush(data, promise: promise)
        logger.trace("Message sent")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print(error)
    }

}

let PACKET_HEADER_SIZE = 8

extension ByteBuffer {
    mutating func startRequest(packetType: Constants.PacketType, dataFlags: UInt16 = 0) {
        self.reserveCapacity(PACKET_HEADER_SIZE)
        self.moveWriterIndex(forwardBy: PACKET_HEADER_SIZE) // Placeholder for the header, which is set at the end of an request
        if packetType == Constants.PacketType.data {
            self.writeInteger(dataFlags)
        }
    }
}

extension ByteBuffer {
    mutating func endRequest(packetType: Constants.PacketType) {
        self.sendPacket(packetType: packetType, final: true)
    }
}

extension ByteBuffer {
    mutating func sendPacket(packetType: Constants.PacketType, capabilities: Capabilities? = nil, final: Bool) {
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
