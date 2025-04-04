//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Atomics
import Logging
import NIOCore
import NIOPosix

/// An incredibly stupid server to mock a connection to an Oracle Database for Benchmarks.
///
/// The server sends a series of predefined messages. It's goal is to respond as quickly as possible, without aiming for correctness.
///
/// _It only works for very specifc usecases._
@available(macOS 14.0, *)
@main
final class OracleMockServer {
    static func main() async throws {
        LoggingSystem.bootstrap { StreamLogHandler.standardOutput(label: $0) }
        var logger = Logger(label: "OracleMockServer")
        logger.logLevel = .debug

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let serverChannel = try await ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)
            .childChannelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .bind(
                host: "127.0.0.1",
                port: 6666
            ) { childChannel in
                // This closure is called for every inbound connection
                childChannel.eventLoop.makeCompletedFuture {
                    try childChannel.pipeline.syncOperations.addHandler(BackPressureHandler())
                    return try NIOAsyncChannel<ByteBuffer, ByteBuffer>(
                        wrappingChannelSynchronously: childChannel
                    )
                }
            }

        let idGenerator = ManagedAtomic(0)

        try await withThrowingDiscardingTaskGroup { group in
            try await serverChannel.executeThenClose { serverChannelInbound in
                for try await connectionChannel in serverChannelInbound {
                    group.addTask {
                        do {
                            try await connectionChannel.executeThenClose {
                                connectionChannelInbound, connectionChannelOutbound in
                                let id = idGenerator.wrappingIncrementThenLoad(ordering: .relaxed)

                                var state: State = .idle
                                var remainder: (header: Header, buffer: ByteBuffer, length: Int)?

                                for try await var inboundData in connectionChannelInbound {
                                    let inboundDataLength = inboundData.readableBytes

                                    logger[metadataKey: "connection_id"] = .stringConvertible(id)

                                    let header: Header
                                    var buffer: ByteBuffer
                                    if let pending = remainder {
                                        remainder?.length = pending.length - inboundDataLength
                                        remainder?.buffer.writeBuffer(&inboundData)
                                        if remainder?.length == 0 {
                                            header = pending.header
                                            buffer = pending.buffer
                                            remainder = nil
                                        } else {
                                            continue
                                        }
                                    } else {
                                        // we need to read the header in order to consume the complete message
                                        guard let newHeader = Header(from: &inboundData, in: state) else {
                                            connectionChannelOutbound.finish()  // close connection
                                            return
                                        }

                                        logger.debug("Received header: \(newHeader)")

                                        if newHeader.length > inboundDataLength {
                                            remainder = (newHeader, inboundData, newHeader.length - inboundDataLength)
                                            continue
                                        } else {
                                            header = newHeader
                                            buffer = inboundData
                                            remainder = nil
                                        }
                                    }

                                    switch state {
                                    case .idle:  // client sent connect
                                        try await connectionChannelOutbound.write(ConnectMessage().serialize())
                                        state = .connecting
                                    case .connecting:  // client sent auth request (phase 1)
                                        try await connectionChannelOutbound.write(
                                            AuthenticationChallengeMessage().serialize())
                                        state = .authenticating
                                    case .authenticating:  // client sent auth data (phase 2)
                                        try await connectionChannelOutbound.write(AuthenticatedMessage().serialize())
                                        state = .authenticated

                                    case .authenticated:  // waiting for client instructions
                                        // TODO: find out if we have a statement or a logoff
                                        switch header.packetType {
                                        case .data(let flags, let messageID):
                                            print(messageID)
                                            let functionCode = buffer.readInteger(as: UInt8.self).flatMap(
                                                FunctionCode.init)
                                            guard let functionCode else {
                                                connectionChannelOutbound.finish()
                                                return
                                            }
                                            switch functionCode {
                                            case .logoff:
                                                try await connectionChannelOutbound.write(CloseMessage().serialize())
                                                state = .closed
                                            case .execute:
                                                // TODO: "parse" query and use appropiate response
                                                fatalError()
                                            default:
                                                fatalError("unimplemented: \(functionCode)")
                                            }
                                        default:
                                            connectionChannelOutbound.finish()
                                            return
                                        }

                                    case .closed:
                                        connectionChannelOutbound.finish()
                                    }
                                    print(inboundData.oracleHexDump())
                                    logger.debug("State changed: \(state)")
                                }
                            }
                        } catch {
                            // Handle errors
                        }
                    }
                }
            }
        }
    }

    static func determineLength(in buffer: inout ByteBuffer, for state: State) -> Int? {
        let length: Int?
        if case .idle = state {
            length = buffer.readInteger(as: UInt16.self).flatMap(Int.init)
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt16>.size)
        } else {
            length = buffer.readInteger(as: UInt32.self).flatMap(Int.init)
        }
        return length
    }

    struct Header {
        let length: Int
        let packetType: PacketType
        let packetFlags: UInt8

        init?(from buffer: inout ByteBuffer, in state: State) {
            let length = determineLength(in: &buffer, for: state)

            let packetType = buffer.readInteger(as: UInt8.self)

            let packetFlags = buffer.readInteger(as: UInt8.self)

            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt16>.size)  // skip checksum

            guard let length, let packetType, let packetFlags else { return nil }

            self.length = length
            self.packetFlags = packetFlags

            switch packetType {
            case 1:
                self.packetType = .connect
            case 2:
                self.packetType = .accept
            case 4:
                self.packetType = .refuse
            case 5:
                self.packetType = .redirect
            case 6:
                let flags = buffer.readInteger(as: UInt16.self)
                let messageID = buffer.readInteger(as: UInt8.self).flatMap(MessageID.init)
                guard let flags, let messageID else { return nil }
                self.packetType = .data(flags: flags, messageID)
            case 11:
                self.packetType = .resend
            case 12:
                self.packetType = .marker
            case 14:
                self.packetType = .control
            default:
                fatalError("TODO")
            }
        }
    }

    enum State {
        case idle
        case connecting
        case authenticating
        case authenticated
        case closed
    }

    enum PacketType {
        case connect
        case accept
        case refuse
        case data(flags: UInt16, MessageID)
        case resend
        case marker
        case control
        case redirect
    }

    enum MessageID: UInt8, Equatable {
        case `protocol` = 1
        case dataTypes = 2
        case function = 3
        case error = 4
        case rowHeader = 6
        case rowData = 7
        case parameter = 8
        case status = 9
        case ioVector = 11
        case lobData = 14
        case warning = 15
        case describeInfo = 16
        case piggyback = 17
        case flushOutBinds = 19
        case bitVector = 21
        case serverSidePiggyback = 23
        case onewayFN = 26
        case endOfRequest = 29
        case fastAuth = 34
    }

    enum FunctionCode: UInt8 {
        case authPhaseOne = 118
        case authPhaseTwo = 115
        case closeCursors = 105
        case commit = 14
        case execute = 94
        case fetch = 5
        case lobOp = 96
        case logoff = 9
        case ping = 147
        case rollback = 15
        case setEndToEndAttr = 135
        case reexecute = 4
        case reexecuteAndFetch = 78
        case sessionGet = 162
        case sessionRelease = 163
        case setSchema = 152
    }
}
