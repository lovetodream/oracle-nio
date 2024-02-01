// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import Logging

enum OracleSQLEvent {
    /// The event that is used to inform upstream handlers that ``OracleChannelHandler`` has
    /// established a connection successfully.
    case startupDone(
        version: OracleVersion,
        sessionID: Int,
        serialNumber: Int
    )
    /// The event that is used to inform upstream handlers that ``OracleChannelHandler`` is
    /// currently idle.
    case readyForQuery
}

final class OracleEventsHandler: ChannelInboundHandler {
    typealias InboundIn = Never

    typealias StartupContext = (
        version: OracleVersion, sessionID: Int, serialNumber: Int
    )

    let logger: Logger
    var startupDoneFuture: EventLoopFuture<StartupContext>! {
        self.startupDonePromise!.futureResult
    }

    private enum State {
        case initialized
        case connected
        case readyForStartup
        case authenticated
    }

    private var startupDonePromise: EventLoopPromise<StartupContext>!
    private var state: State = .initialized

    init(logger: Logger) {
        self.logger = logger
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case OracleSQLEvent.startupDone(
            let version, let sessionID, let serialNumber
        ):
            guard case .connected = self.state else {
                preconditionFailure()
            }
            self.state = .readyForStartup
            self.startupDonePromise.succeed((version, sessionID, serialNumber))
        case OracleSQLEvent.readyForQuery:
            switch self.state {
            case .initialized, .connected:
                preconditionFailure(
                    "Expected to get a `readyForStartup` before we get a `readyForQuery` event"
                )
            case .readyForStartup:
                // for the first time, we are ready to query, this means
                // startup/auth was successful
                self.state = .authenticated
            case .authenticated:
                break
            }
        default:
            preconditionFailure()
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
        struct HandlerRemovedConnectionError: Error { }

        if case .initialized = self.state {
            self.startupDonePromise.fail(HandlerRemovedConnectionError())
        }
    }

}
