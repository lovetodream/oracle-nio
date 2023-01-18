//
//  Protocol.swift
//  
//
//  Created by Timo Zacherl on 05.01.23.
//

import NIOCore
import NIOPosix

/// Defining the protocol used by the client when communicating with the database.
public class OracleProtocol {
    let group: MultiThreadedEventLoopGroup
    var channel: Channel?

    public init(group: MultiThreadedEventLoopGroup) {
        self.group = group
    }

    public func connectPhaseOne(connection: OracleConnection, address: SocketAddress) throws {
        try self.connectTCP(address)

        let connectMessage: ConnectMessage = connection.createMessage()
        try self.process(message: connectMessage)
    }

    public func connectPhaseTwo() throws {

    }

    func connectTCP(_ address: SocketAddress) throws {
        let bootstrap = ClientBootstrap(group: group).channelInitializer { channel in
            channel.pipeline.addHandlers([OracleChannelHandler()])
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

class OracleChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer

    struct Response {}
    struct Request {}

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        print(data)
        context.writeAndFlush(data, promise: nil)

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
