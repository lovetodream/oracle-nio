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
        try channel?.writeAndFlush(message.get()).wait()
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
        // todo
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = self.unwrapOutboundIn(data)

    }

}

let PACKET_HEADER_SIZE = 8

extension ByteBuffer {
    mutating func startRequest(packetType: UInt8, dataFlags: UInt16 = 0) {
        if packetType == Constants.TNS_PACKET_TYPE_DATA {
            self.writeInteger(dataFlags)
        }
    }
}

extension ByteBuffer {
    func endRequest() {
        if self.readerIndex > PACKET_HEADER_SIZE {
            self.sendPacket(final: true)
        }
    }
}

extension ByteBuffer {
    func sendPacket(final: Bool) {
        
    }
}
