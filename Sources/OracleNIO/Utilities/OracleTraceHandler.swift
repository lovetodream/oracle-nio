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

import Atomics
import Foundation
import Logging
import NIOCore
import NIOPosix

final class OracleTraceHandler: ChannelDuplexHandler, Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer

    private let logger: Logger
    private let shouldLog: Bool
    private let connectionID: OracleConnection.ID

    private let packetCount = ManagedAtomic(0)

    init(connectionID: OracleConnection.ID, logger: Logger, shouldLog: Bool? = nil) {
        if let shouldLog {
            self.shouldLog = shouldLog
        } else {
            let envValue =
                getenv("ORANIO_TRACE_PACKETS")
                .flatMap { String(cString: $0) }
                .flatMap(Int.init) ?? 0
            self.shouldLog = envValue != 0
        }
        self.logger = logger
        self.connectionID = connectionID
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if self.shouldLog {
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
        if self.shouldLog {
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
