//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

struct OracleBackendMessageDecoder: ByteToMessageDecoder {

    static let headerSize = 8

    struct Container: Equatable {
        var flags: UInt8 = 0
        var message: OracleBackendMessage
    }
    typealias InboundOut = [Container]

    private var capabilities: Capabilities

    private let context: Context
    /// Used for message testing, to get expected messages one after another
    /// instead of retrieving random amounts, depending on the stream.
    ///
    /// Does not affect production build performance, as taking this route
    /// is only possible in debug builds.
    private let sendSingleMessages: Bool

    class Context {
        var performingChunkedRead = false
        var queryOptions: QueryOptions? = nil
        var columnsCount: Int? = nil
    }

    init(capabilities: Capabilities, context: Context) {
        self.capabilities = capabilities
        self.context = context
        self.sendSingleMessages = false
    }

    #if DEBUG
        /// For testing only!
        init() {
            self.capabilities = .init()
            self.context = .init()
            self.sendSingleMessages = true
        }
    #endif

    mutating func decode(
        context: ChannelHandlerContext, buffer: inout ByteBuffer
    ) throws -> DecodingState {
        while let message = try decodeMessage(from: &buffer) {
            #if DEBUG
                if sendSingleMessages {
                    for part in message {
                        context.fireChannelRead(self.wrapInboundOut([part]))
                    }
                } else {
                    context.fireChannelRead(self.wrapInboundOut(message))
                }
            #else
                context.fireChannelRead(self.wrapInboundOut(message))
            #endif
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
        let startReaderIndex = buffer.readerIndex

        let length: Int?
        if self.capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
            length = buffer.getInteger(at: startReaderIndex, as: UInt32.self).map(Int.init)
        } else {
            length = buffer.getInteger(at: startReaderIndex, as: UInt16.self).map(Int.init)
        }

        let packetFlags =
            buffer.getInteger(
                at: startReaderIndex + MemoryLayout<UInt32>.size + MemoryLayout<UInt8>.size,
                as: UInt8.self
            ) ?? 0

        guard
            let length,
            buffer.readableBytes >= startReaderIndex + Self.headerSize,
            let typeByte = buffer.getInteger(
                at: startReaderIndex + MemoryLayout<UInt32>.size,
                as: UInt8.self
            ),
            let type = OracleBackendMessage.ID(rawValue: typeByte),
            var packet = buffer.readSlice(length: length)
        else {
            return nil
        }

        // skip header
        if packet.readerIndex < Self.headerSize && packet.capacity >= Self.headerSize {
            packet.moveReaderIndex(to: Self.headerSize)
        }

        do {
            let messages = try OracleBackendMessage.decode(
                from: &packet, of: type,
                capabilities: self.capabilities,
                context: context
            )
            return messages.map { .init(flags: packetFlags, message: $0) }
        } catch let error as OraclePartialDecodingError {
            buffer.moveReaderIndex(to: startReaderIndex)
            let completeMessage = buffer.readSlice(length: length)!
            throw
                OracleMessageDecodingError
                .withPartialError(
                    error,
                    packetID: type.rawValue,
                    messageBytes: completeMessage
                )
        } catch {
            preconditionFailure(
                "Expected to only see `OraclePartialDecodingError`s here."
            )
        }
    }
}
