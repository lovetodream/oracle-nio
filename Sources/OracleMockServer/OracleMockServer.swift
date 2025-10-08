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
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public final class OracleMockServer {
    public static func run(port: Int, continuation: CheckedContinuation<Void, Error>? = nil) async throws {
        let logger = Logger(label: "OracleMockServer")

        var didStart = false

        do {
            let serverChannel = try await ServerBootstrap(group: NIOSingletons.posixEventLoopGroup)
                .serverChannelOption(.backlog, value: 256)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(.maxMessagesPerRead, value: 16)
                .childChannelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
                .bind(host: "127.0.0.1", port: port) { childChannel in
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
                    continuation?.resume()  // server started
                    didStart = true

                    for try await connectionChannel in serverChannelInbound {
                        group.addTask {
                            await singleConnection(
                                logger: logger,
                                idGenerator: idGenerator,
                                connectionChannel: connectionChannel
                            )
                        }
                    }
                }
            }
        } catch {
            if didStart == false {
                continuation?.resume(throwing: error)
            }
            throw error
        }
    }

    static func singleConnection(
        logger: Logger,
        idGenerator: ManagedAtomic<Int>,
        connectionChannel: NIOAsyncChannel<ByteBuffer, ByteBuffer>
    ) async {
        var logger = logger
        do {
            try await connectionChannel.executeThenClose {
                connectionChannelInbound, connectionChannelOutbound in
                let id = idGenerator.wrappingIncrementThenLoad(ordering: .relaxed)

                var state: State = .idle
                var encoder = ServerMessageEncoder(buffer: .init())
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
                        switch header.packetType {
                        case .data:
                            try await handleData(
                                in: &buffer, state: &state,
                                connectionChannelOutbound: connectionChannelOutbound)

                        default:
                            connectionChannelOutbound.finish()
                            return
                        }

                    case .executing(let lastRow):
                        let hasMore = (lastRow + 50) < 10_000
                        encoder.rows(
                            data: .init((lastRow + 1)...min((lastRow + 50), 10_000)),
                            lastRowCount: lastRow,
                            hasMoreRows: hasMore
                        )
                        try await connectionChannelOutbound.write(encoder.flush())
                        if hasMore {
                            state = .executing(lastRow: lastRow + 50)
                        } else {
                            state = .authenticated
                        }

                    case .closed:
                        connectionChannelOutbound.finish()
                    }
                    logger.debug("State changed: \(state)")
                }
            }
        } catch {
            // Handle errors
        }
    }

    static func handleData(
        in buffer: inout ByteBuffer, state: inout State,
        connectionChannelOutbound: NIOAsyncChannelOutboundWriter<ByteBuffer>
    ) async throws {
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
            // since we only support very specific statements, we can check in a lazy way

            // read all bytes until we find SELECT, go back by one byte and grab the length, then cut the select out
            let select = Array("SELECT".utf8)
            var matchingBytesCount = 0
            var statement: String?
            loop: while let byte = buffer.readInteger(as: UInt8.self) {
                switch byte {
                case select[matchingBytesCount]:
                    matchingBytesCount += 1
                    if matchingBytesCount == select.count - 1 {
                        buffer.moveReaderIndex(to: buffer.readerIndex - matchingBytesCount - 1)
                        let length = buffer.readInteger(as: UInt8.self).unsafelyUnwrapped
                        statement = buffer.readString(length: Int(length))
                        break loop
                    }
                default:
                    matchingBytesCount = 0
                }
            }

            guard let statement else {
                // FIXME: fatal for now, handle this in the future
                fatalError("SELECT not found")
            }

            // a few predefined statements
            switch statement {
            case #"SELECT 'hello' FROM dual"#:
                try await connectionChannelOutbound.write(SelectOneFromDualMessage().serialize())
            case #"SELECT to_number(column_value) AS id FROM xmltable ('1 to 10000')"#:
                try await connectionChannelOutbound.write(SelectManyFromDualMessage().serialize())
                state = .executing(lastRow: 2)
            default:
                // FIXME: fatal for now, handle this in the future
                fatalError("SELECT not found")
            }

        case .closeCursors:

            // skip sequence number
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size)


            // skip token number
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size)

            // skip cursor
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size)

            // skip cursors
            let cursors = buffer.readUB4() ?? 0
            for _ in 0..<Int(cursors) {
                _ = buffer.readUB4()
            }

            // actual message
            let messageID = buffer.readInteger(as: UInt8.self).flatMap(MessageID.init)
            assert(messageID == .function)
            try await handleData(in: &buffer, state: &state, connectionChannelOutbound: connectionChannelOutbound)

        default:
            fatalError("unimplemented: \(functionCode)")
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
        case executing(lastRow: Int)
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

        var byte: UInt8 {
            switch self {
            case .connect: 1
            case .accept: 2
            case .refuse: 4
            case .data: 6
            case .resend: 11
            case .marker: 12
            case .control: 14
            case .redirect: 5
            }
        }
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

extension ByteBuffer {
    mutating func readUBLength() -> UInt8? {
        guard var length = self.readInteger(as: UInt8.self) else { return nil }
        if length & 0x80 != 0 {
            length = length & 0x7f
        }
        return length
    }

    mutating func readUB4() -> UInt32? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return self.readInteger(as: UInt8.self).map(UInt32.init(_:))
        case 2:
            return self.readInteger(as: UInt16.self).map(UInt32.init(_:))
        case 3:
            guard let bytes = readBytes(length: Int(length)) else { fatalError() }
            return UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
        case 4:
            return self.readInteger(as: UInt32.self)
        default:
            preconditionFailure()
        }
    }

    mutating func writeUB2(_ integer: UInt16) {
        switch integer {
        case 0:
            self.writeInteger(UInt8(0))
        case 1...UInt16(UInt8.max):
            self.writeInteger(UInt8(1))
            self.writeInteger(UInt8(integer))
        default:
            self.writeInteger(UInt8(2))
            self.writeInteger(integer)
        }
    }

    mutating func writeUB4(_ integer: UInt32) {
        switch integer {
        case 0:
            self.writeInteger(UInt8(0))
        case 1...UInt32(UInt8.max):
            self.writeInteger(UInt8(1))
            self.writeInteger(UInt8(integer))
        case (UInt32(UInt8.max) + 1)...UInt32(UInt16.max):
            self.writeInteger(UInt8(2))
            self.writeInteger(UInt16(integer))
        default:
            self.writeInteger(UInt8(4))
            self.writeInteger(integer)
        }
    }

    mutating func writeUB8(_ integer: UInt64) {
        switch integer {
        case 0:
            self.writeInteger(UInt8(0))
        case 1...UInt64(UInt8.max):
            self.writeInteger(UInt8(1))
            self.writeInteger(UInt8(integer))
        case (UInt64(UInt8.max) + 1)...UInt64(UInt16.max):
            self.writeInteger(UInt8(2))
            self.writeInteger(UInt16(integer))
        case (UInt64(UInt16.max) + 1)...UInt64(UInt32.max):
            self.writeInteger(UInt8(4))
            self.writeInteger(UInt32(integer))
        default:
            self.writeInteger(UInt8(8))
            self.writeInteger(integer)
        }
    }
}
