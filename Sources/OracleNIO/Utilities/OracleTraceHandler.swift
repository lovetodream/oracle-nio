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

#if _IOTracing
    import Atomics
    import Logging
    import NIOCore
    import NIOPosix

    #if canImport(FoundationEssentials)
        import FoundationEssentials
    #else
        import Foundation
    #endif

    final class OracleTraceHandler: ChannelDuplexHandler, Sendable {
        typealias InboundIn = ByteBuffer
        typealias OutboundIn = ByteBuffer

        private let logger: Logger
        let shouldLog: ManagedAtomic<Bool>
        private let connectionID: OracleConnection.ID

        private let packetCount = ManagedAtomic(0)

        init(connectionID: OracleConnection.ID, logger: Logger, shouldLog: Bool? = nil) {
            if let shouldLog {
                self.shouldLog = ManagedAtomic(shouldLog)
            } else {
                let envValue =
                    getenv("ORANIO_TRACE_PACKETS")
                    .flatMap { String(cString: $0) }
                    .flatMap(Int.init) ?? 0
                self.shouldLog = ManagedAtomic(envValue != 0)
            }
            self.logger = logger
            self.connectionID = connectionID
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if self.shouldLog.load(ordering: .relaxed) {
                let buffer = self.unwrapInboundIn(data)
                let count = self.packetCount.wrappingIncrementThenLoad(ordering: .relaxed)
                self.logger.info(
                    """
                    Receiving packet [op \(count)] on socket \(self.connectionID)
                    \(buffer.oracleHexDump())
                    """
                )
            }
            context.fireChannelRead(data)
        }

        func write(
            context: ChannelHandlerContext,
            data: NIOAny,
            promise: EventLoopPromise<Void>?
        ) {
            if self.shouldLog.load(ordering: .relaxed) {
                let buffer = self.unwrapOutboundIn(data)
                let count = self.packetCount.wrappingIncrementThenLoad(ordering: .relaxed)
                self.logger.info(
                    """
                    Sending packet [op \(count)] on socket \(self.connectionID)
                    \(buffer.oracleHexDump())
                    """
                )
            }
            context.write(data, promise: promise)
        }
    }
#endif
