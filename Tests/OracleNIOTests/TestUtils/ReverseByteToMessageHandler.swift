//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// This is a reverse ``NIOCore/ByteToMessageHandler``. Instead of creating messages from incoming bytes
/// as the normal `ByteToMessageHandler` does, this `ReverseByteToMessageHandler` creates messages
/// from outgoing bytes. This is only important for testing in `EmbeddedChannel`s.
class ReverseByteToMessageHandler<Decoder: NIOSingleStepByteToMessageDecoder>:
    ChannelOutboundHandler
{
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = Decoder.InboundOut

    let processor: NIOSingleStepByteToMessageProcessor<Decoder>

    init(_ decoder: Decoder) {
        self.processor = .init(decoder, maximumBufferSize: nil)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)

        do {
            var messages = [Decoder.InboundOut]()
            try self.processor.process(buffer: buffer) { message in
                messages.append(message)
            }

            for (index, message) in messages.enumerated() {
                if index == messages.index(before: messages.endIndex) {
                    context.write(self.wrapOutboundOut(message), promise: promise)
                } else {
                    context.write(self.wrapOutboundOut(message), promise: nil)
                }
            }
        } catch {
            context.fireErrorCaught(error)
        }
    }
}
