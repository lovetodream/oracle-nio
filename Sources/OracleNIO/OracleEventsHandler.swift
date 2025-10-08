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

import Logging
import NIOCore

enum OracleSQLEvent {
    /// The event that is used to inform upstream handlers that ``OracleChannelHandler`` has
    /// established a connection successfully.
    case startupDone(
        StartupContext
    )
    /// The event that is used to inform upstream handlers that ``OracleChannelHandler`` is
    /// currently idle.
    case readyForStatement
    /// The event that is used to inform state about an ongoing TLS renegotiation.
    case renegotiateTLS

    struct StartupContext {
        let version: OracleVersion
        let sessionID: Int
        let serialNumber: Int
        let serviceName: String?
        let databaseName: String?
        let instanceName: String?
    }
}

final class OracleEventsHandler: ChannelInboundHandler {
    typealias InboundIn = Never

    let logger: Logger
    var startupDoneFuture: EventLoopFuture<OracleSQLEvent.StartupContext>! {
        self.startupDonePromise!.futureResult
    }

    private enum State {
        case initialized
        case connected
        case readyForStartup
        case authenticated
    }

    private var startupDonePromise: EventLoopPromise<OracleSQLEvent.StartupContext>!
    private var state: State = .initialized

    init(logger: Logger) {
        self.logger = logger
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case OracleSQLEvent.startupDone(let context):
            guard case .connected = self.state else {
                preconditionFailure()
            }
            self.state = .readyForStartup
            self.startupDonePromise.succeed(context)
        case OracleSQLEvent.readyForStatement:
            switch self.state {
            case .initialized, .connected:
                preconditionFailure(
                    "Expected to get a `readyForStartup` before we get a `readyForStatement` event"
                )
            case .readyForStartup:
                // for the first time, we are ready for statements, this means
                // startup/auth was successful
                self.state = .authenticated
            case .authenticated:
                break
            }
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func handlerAdded(context: ChannelHandlerContext) {
        self.startupDonePromise = context.eventLoop.makePromise()

        if context.channel.isActive, case .initialized = self.state {
            self.state = .connected
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        if case .initialized = self.state {
            self.state = .connected
        }
        context.fireChannelActive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        switch self.state {
        case .initialized:
            preconditionFailure("Unexpected message for state")
        case .connected:
            self.startupDonePromise.fail(error)
        case .readyForStartup:
            self.startupDonePromise.fail(error)
        case .authenticated:
            break
        }

        context.fireErrorCaught(error)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        struct HandlerRemovedConnectionError: Error {}

        if case .initialized = self.state {
            self.startupDonePromise.fail(HandlerRemovedConnectionError())
        }
    }

}
