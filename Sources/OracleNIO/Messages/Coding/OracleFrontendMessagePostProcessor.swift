import NIOCore

final class OracleFrontendMessagePostProcessor: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let maxSize = Int(Constants.TNS_SDU)
    private let headerSize = OracleFrontendMessageEncoder.headerSize
    private let dataFlagsSize = MemoryLayout<UInt16>.size

    weak var capabilitiesProvider: CapabilitiesProvider!

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buffer = self.unwrapOutboundIn(data)

        if buffer.readableBytes > maxSize {
            var temporaryBuffer = context.channel.allocator
                .buffer(capacity: maxSize)
            temporaryBuffer.moveWriterIndex(forwardBy: self.headerSize)

            let capabilities = self.capabilitiesProvider.getCapabilities()
            let packetType = buffer
                .getInteger(at: MemoryLayout<UInt32>.size, as: UInt8.self)!
            let packetFlags = buffer
                .getInteger(
                    at: MemoryLayout<UInt32>.size + MemoryLayout<UInt8>.size,
                    as: UInt8.self
                ) ?? 0

            // ignore the header, because we need to create a new one for each 
            // slice with the size of the slice.
            buffer.moveReaderIndex(to: self.headerSize)


            let maxContentSize =
                self.maxSize - self.headerSize - self.dataFlagsSize
            var first = true
            while buffer.readableBytes > 0 {
                var slice: ByteBuffer
                let final: Bool
                if buffer.readableBytes > maxContentSize {
                    slice = buffer.readSlice(
                        length: first ? 
                            maxContentSize + dataFlagsSize : maxContentSize
                    )!
                    final = false
                } else {
                    slice = buffer.readSlice(length: buffer.readableBytes)!
                    final = true
                }
                first = false
                temporaryBuffer.writeBuffer(&slice)
                temporaryBuffer.prepareSend(
                    packetTypeByte: packetType,
                    packetFlags: packetFlags,
                    protocolVersion: capabilities.protocolVersion
                )
                context.writeAndFlush(
                    self.wrapOutboundOut(temporaryBuffer), promise: nil
                )
                if !final {
                    temporaryBuffer.clear(minimumCapacity: maxSize)
                    temporaryBuffer.moveWriterIndex(forwardBy: headerSize)
                    // add data flags for continuation packet
                    temporaryBuffer.writeInteger(UInt16(0))
                }
            }
        }

        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }

}
