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

struct OracleBackendMessageDecoder: ByteToMessageDecoder {

    static let headerSize = 8

    struct Container: Equatable {
        var flags: UInt8 = 0
        var messages: TinySequence<OracleBackendMessage>
    }
    typealias InboundOut = TinySequence<Container>

    private let context: Context

    /// Used for message testing, to get expected messages one after another
    /// instead of retrieving random amounts, depending on the stream.
    ///
    /// Does not affect production build performance, as taking this route
    /// is only possible in debug builds.
    private let sendSingleMessages: Bool

    final class Context {
        var capabilities: Capabilities

        private var _statementContext: StatementContext?
        var statementContext: StatementContext? {
            get {
                self._statementContext
            }
            set {
                self._statementContext = newValue
                switch newValue?.type {
                case .cursor(let cursor, _):
                    if cursor.describeInfo != self.describeInfo {
                        self.describeInfo = cursor.describeInfo
                    }
                default: break
                }
            }
        }
        var bitVector: [UInt8]?
        var describeInfo: DescribeInfo?

        var lobContext: LOBOperationContext?

        init(capabilities: Capabilities) {
            self.capabilities = capabilities
        }

        func clearStatementContext() {
            self.statementContext = nil
            self.bitVector = nil
            self.describeInfo = nil
        }
    }

    init(context: Context) {
        self.context = context
        self.sendSingleMessages = false
    }

    #if DEBUG
        /// For testing only!
        init() {
            self.context = .init(capabilities: .init())
            self.sendSingleMessages = true
        }
    #endif

    mutating func decode(
        context: ChannelHandlerContext, buffer: inout ByteBuffer
    ) throws -> DecodingState {
        while let (message, needMoreData) = try decodeMessage(from: &buffer) {
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
            if buffer.readableBytes > 0 || needMoreData {
                return .needMoreData
            } else {
                buffer = buffer.slice()
                return .continue
            }
        }
        return .needMoreData
    }

    /// A remainder of the last package that's been read, needs to be consumed
    /// as part of the next incoming buffer.
    /// [incoming header] + [_partial_] + [incoming packet content]
    var partial: ByteBuffer?

    private mutating func decodeMessage(
        from buffer: inout ByteBuffer
    ) throws -> (InboundOut, needMoreData: Bool)? {
        var msgs: InboundOut?
        var needMoreData = true
        while let (messages, stillNeedMoreData) = try self.decodeMessage0(from: &buffer) {
            needMoreData = stillNeedMoreData
            buffer = buffer.slice()
            if msgs != nil {
                msgs!.append(messages)
            } else {
                msgs = [messages]
            }
        }
        if let msgs {
            return (msgs, needMoreData)
        }
        return nil
    }

    private mutating func decodeMessage0(
        from buffer: inout ByteBuffer
    ) throws -> (Container, needMoreData: Bool)? {
        let startReaderIndex = buffer.readerIndex

        let length: Int?
        if self.context.capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_LARGE_SDU {
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
            var packet = buffer.readSlice(length: length),
            packet.readableBytes >= Self.headerSize
        else {
            return nil
        }

        // skip header
        packet.moveReaderIndex(to: Self.headerSize)

        if let partial, partial.readableBytes > 0 {
            // insert after flags if packet is data
            let skipSize = type == .data ? MemoryLayout<UInt16>.size : 0
            let movable = packet.getSlice(
                at: Self.headerSize + skipSize,
                length: packet.readableBytes - skipSize
            )!  // must work
            packet.reserveCapacity(minimumWritableBytes: partial.readableBytes)
            packet.writeRepeatingByte(0, count: partial.readableBytes)
            let written = packet.setBuffer(partial, at: Self.headerSize + skipSize)
            packet.setBuffer(movable, at: Self.headerSize + skipSize + written)
            self.partial = nil
        }

        do {
            let (messages, lastPacket) = try OracleBackendMessage.decode(
                from: &packet, of: type,
                context: self.context
            )
            return (Container(flags: packetFlags, messages: messages), !lastPacket)
        } catch let error as OracleSQLError {
            throw error
        } catch let error as MissingDataDecodingError {
            packet.moveReaderIndex(to: error.resetToReaderIndex)
            self.partial = packet.slice()
            return (Container(flags: packetFlags, messages: error.decodedMessages), true)
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
