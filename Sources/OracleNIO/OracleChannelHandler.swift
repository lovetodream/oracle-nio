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

import Logging
import NIOCore
import NIOSSL
import NIOTLS

import class Foundation.ProcessInfo

final class OracleChannelHandler: ChannelDuplexHandler {
    typealias OutboundIn = OracleTask
    typealias InboundIn = TinySequence<OracleBackendMessageDecoder.Container>
    typealias OutboundOut = ByteBuffer

    private let logger: Logger
    private var state: ConnectionStateMachine

    /// A `ChannelHandlerContext` to be used for non channel related events.
    ///
    /// For example: More rows needed.
    /// The context is captured in `handlerAdded` and released in `handlerRemoved`.
    private var handlerContext: ChannelHandlerContext?
    private var rowStream: OracleRowStream?
    private var decoder: ByteToMessageHandler<OracleBackendMessageDecoder>?
    private let decoderContext: OracleBackendMessageDecoder.Context
    private var encoder: OracleFrontendMessageEncoder!
    private let configuration: OracleConnection.Configuration
    private let currentSSLHandler: NIOSSLClientHandler?

    private let postprocessor: OracleFrontendMessagePostProcessor
    private var capabilities: Capabilities {
        didSet {
            self.decoderContext.capabilities = self.capabilities
            self.encoder.capabilities = self.capabilities
            self.postprocessor.protocolVersion =
                self.capabilities.protocolVersion
            self.postprocessor.maxSize = Int(self.capabilities.sdu)
        }
    }

    let cleanupContext = CleanupContext()

    init(
        configuration: OracleConnection.Configuration,
        logger: Logger,
        sslHandler: NIOSSLClientHandler?,
        postprocessor: OracleFrontendMessagePostProcessor
    ) {
        self.state = ConnectionStateMachine()
        self.configuration = configuration
        self.logger = logger
        self.currentSSLHandler = sslHandler
        self.postprocessor = postprocessor

        var capabilities = Capabilities()
        #if os(Windows)
            capabilities.supportsOOB = false
        #else
            if !configuration.disableOOB || configuration._protocol == .tcps {
                capabilities.supportsOOB = true
            }
        #endif
        self.decoderContext = .init(capabilities: capabilities)
        self.capabilities = capabilities
    }

    // MARK: Handler Lifecycle

    func handlerAdded(context: ChannelHandlerContext) {
        self.handlerContext = context
        self.decoder = ByteToMessageHandler(
            OracleBackendMessageDecoder(context: self.decoderContext))
        self.encoder = OracleFrontendMessageEncoder(
            buffer: context.channel.allocator.buffer(capacity: 256),
            capabilities: self.capabilities
        )
        do {
            try context.pipeline.syncOperations
                .addHandler(self.decoder!, position: .before(self))
        } catch {
            context.fireErrorCaught(error)
            return
        }

        if context.channel.isActive {
            self.connected(context: context)
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.handlerContext = nil
    }

    // MARK: Channel handler incoming

    func channelActive(context: ChannelHandlerContext) {
        // `fireChannelActive` needs to be called BEFORE we set the state
        // machine to connected, since we want to make sure that upstream
        // handlers know about the active connection before it receives a
        context.fireChannelActive()

        self.connected(context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.logger.trace("Channel inactive.")
        let action = self.state.closed()
        self.run(action, with: context)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.logger.debug(
            "Channel error caught.",
            metadata: [
                .error: "\(error)"
            ])
        let action =
            if let error = error as? OracleSQLError {
                self.state.errorHappened(error)
            } else {
                self.state.errorHappened(.connectionError(underlying: error))
            }
        self.run(action, with: context)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let containers = self.unwrapInboundIn(data)
        for container in containers {
            for message in container.messages {
                self.handleMessage(
                    message, flags: container.flags, context: context
                )
            }
        }
    }

    private func handleMessage(
        _ message: OracleBackendMessage,
        flags: UInt8?,
        context: ChannelHandlerContext
    ) {
        self.logger.trace(
            "Backend message received",
            metadata: [
                .message: "\(message)"
            ])
        self.decoderContext.performingChunkedRead = false
        let action: ConnectionStateMachine.ConnectionAction

        switch message {
        case .accept(let accept):
            self.capabilities = accept.newCapabilities
            action = self.state.acceptReceived(
                accept, description: configuration.getDescription()
            )
        case .bitVector(let bitVector):
            action = self.state.bitVectorReceived(bitVector)
        case .dataTypes:
            action = self.state.dataTypesReceived()
        case .error(let error):
            action = self.state.backendErrorReceived(error)
        case .marker:
            action = self.state.markerReceived()
        case .parameter(let parameter):
            action = self.state.parameterReceived(parameters: parameter)
        case .protocol(let `protocol`):
            self.capabilities = `protocol`.newCapabilities
            action = self.state.protocolReceived()
        case .resend:
            action = self.state.resendReceived()
        case .status(let status):
            action = self.state.statusReceived(status)
        case .describeInfo(let describeInfo):
            action = self.state.describeInfoReceived(describeInfo)
        case .rowHeader(let header):
            action = self.state.rowHeaderReceived(header)
        case .rowData(let data):
            action = self.state.rowDataReceived(
                data, capabilities: self.capabilities
            )
        case .queryParameter(let parameter):
            action = self.state.queryParameterReceived(parameter)
        case .warning(let warning):
            // TODO: maybe we need to inform state about this event in the future
            self.logger.info(
                "The oracle server sent a warning, everything should be fine",
                metadata: [.warning: "\(warning)"]
            )
            action = .wait
        case .ioVector(let vector):
            action = self.state.ioVectorReceived(vector)
        case .flushOutBinds:
            action = self.state.flushOutBindsReceived()

        case .serverSidePiggyback(let piggybacks):
            // This should only happen if one is using `LOB`s.
            // These are not implemented as of now, so this _should_ never happen.
            fatalError(
                """
                Received server side piggybacks (\(piggybacks)), this is not \
                implemented and should never happen. Please open an issue here: \
                https://github.com/lovetodream/oracle-nio/issues with a \
                reproduction of the crash.
                """)
        case .lobData(let lobData):
            // This should only happen if one is using `LOB`s.
            // These are not implemented as of now, so this _should_ never happen.
            fatalError(
                """
                Received LOB data (\(lobData)), this is not implemented and should \
                never happen. Please open an issue here: \
                https://github.com/lovetodream/oracle-nio/issues with a \
                reproduction of the crash.
                """)

        case .chunk(let buffer):
            action = self.state.chunkReceived(
                buffer, capabilities: self.capabilities
            )
        }

        self.run(action, flags: flags, with: context)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.logger.trace("Channel read complete")
        let action = self.state.channelReadComplete()
        self.run(action, with: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.logger.trace(
            "User inbound event received",
            metadata: [
                .userEvent: "\(event)"
            ])

        switch event {
        case TLSUserEvent.handshakeCompleted:
            let action = self.state.tlsEstablished()
            self.run(action, with: context)
        case OracleSQLEvent.renegotiateTLS:
            self.state.renegotiatingTLS()
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    // MARK: Channel handler outgoing

    func read(context: ChannelHandlerContext) {
        self.logger.trace("Channel read event received")
        let action = self.state.readEventCaught()
        self.run(action, with: context)
    }

    func write(
        context: ChannelHandlerContext,
        data: NIOAny,
        promise: EventLoopPromise<Void>?
    ) {
        let task = self.unwrapOutboundIn(data)
        let action = self.state.enqueue(task: task)
        self.run(action, with: context)
    }

    func close(
        context: ChannelHandlerContext,
        mode: CloseMode,
        promise: EventLoopPromise<Void>?
    ) {
        self.logger.trace("Close triggered by upstream")
        guard mode == .all else {
            promise?.fail(ChannelError.operationUnsupported)
            return
        }

        if self.configuration.drcpEnabled {
            self.encoder.releaseSession()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        }
        let action = self.state.close(promise)
        self.run(action, with: context)
    }

    func triggerUserOutboundEvent(
        context: ChannelHandlerContext,
        event: Any,
        promise: EventLoopPromise<Void>?
    ) {
        self.logger.trace(
            "User outbound event received",
            metadata: [
                .userEvent: "\(event)"
            ])

        switch event {
        default:
            context.triggerUserOutboundEvent(event, promise: promise)
        }
    }

    // MARK: Channel handler actions

    func run(
        _ action: ConnectionStateMachine.ConnectionAction,
        flags: UInt8? = nil,
        with context: ChannelHandlerContext
    ) {
        self.logger.trace(
            "Run action",
            metadata: [
                .connectionAction: "\(action)"
            ])

        switch action {
        case .read:
            context.read()
        case .wait:
            break
        case .sendConnect:
            self.sendConnect(withFlags: flags, context: context)
        case .sendProtocol:
            self.encoder.protocol()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .sendDataTypes:
            self.encoder.dataTypes()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .provideAuthenticationContext(let fastAuth):
            let authMethod = self.configuration.authenticationMethod()
            let peerAddress = context.remoteAddress
            let authContext = AuthContext(
                method: authMethod,
                service: configuration.service,
                terminalName: configuration._terminalName,
                programName: configuration.programName,
                machineName: configuration.machineName,
                pid: configuration.pid,
                processUsername: configuration.processUsername,
                proxyUser: configuration.proxyUser,
                peerAddress: peerAddress,
                customTimezone: configuration.customTimezone,
                mode: configuration.mode,
                description: configuration.getDescription()
            )
            let action = self.state
                .provideAuthenticationContext(authContext, fastAuth: fastAuth)
            return self.run(action, with: context)
        case .sendFastAuth(let authContext):
            self.encoder.fastAuth(authContext: authContext)
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .sendAuthenticationPhaseOne(let authContext):
            self.sendAuthenticationPhaseOne(
                authContext: authContext, context: context
            )
        case .sendAuthenticationPhaseTwo(let authContext, let parameters):
            self.sendAuthenticationPhaseTwo(
                authContext: authContext,
                parameters: parameters,
                context: context
            )
        case .authenticated(let parameters):
            self.authenticated(parameters: parameters, context: context)

        case .sendExecute(let statementContext, let describeInfo):
            self.sendExecute(
                statementContext: statementContext,
                describeInfo: describeInfo,
                context: context
            )
        case .sendReexecute(let statementContext, let cleanupContext):
            self.sendReexecute(
                statementContext: statementContext,
                cleanupContext: cleanupContext,
                context: context
            )
        case .sendFetch(let statementContext):
            self.sendFetch(statementContext: statementContext, context: context)
        case .sendFlushOutBinds:
            self.encoder.flushOutBinds()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .succeedStatement(let promise, let result):
            self.succeedStatement(promise, result: result, context: context)
        case .failStatement(let promise, let error, let cleanupContext):
            promise.fail(error)
            if let cleanupContext {
                self.closeConnectionAndCleanup(cleanupContext, context: context)
            }
            self.decoderContext.statementOptions = nil
            self.decoderContext.columnsCount = nil
            self.run(self.state.readyForStatementReceived(), with: context)

        case .needMoreData:
            self.decoderContext.performingChunkedRead = true
            context.read()

        case .forwardRows(let rows):
            self.rowStream!.receive(rows)
        case .forwardStreamComplete(let buffer, let cursorID):
            guard let rowStream else {
                // if the stream was cancelled we don't have it here anymore.
                return
            }
            self.rowStream = nil
            if buffer.count > 0 {
                rowStream.receive(buffer)
            }
            rowStream.receive(completion: .success(()))

            self.decoderContext.statementOptions = nil
            self.decoderContext.columnsCount = nil

            if cursorID != 0 {
                self.cleanupContext.cursorsToClose.insert(cursorID)
            }

            self.run(self.state.readyForStatementReceived(), with: context)

        case .forwardStreamError(
            let error, let read, let cursorID, let clientCancelled
        ):
            self.rowStream!.receive(completion: .failure(error))
            self.rowStream = nil
            if let cursorID {
                cleanupContext.cursorsToClose.insert(cursorID)
            } else if read {
                context.read()
            }

            self.decoderContext.statementOptions = nil
            self.decoderContext.columnsCount = nil

            if clientCancelled {
                self.run(self.state.statementStreamCancelled(), with: context)
            } else {
                self.run(self.state.readyForStatementReceived(), with: context)
            }

        case .sendMarker:
            self.encoder.marker()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )

        case .sendPing:
            self.encoder.ping()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .failPing(let promise, let error):
            promise.fail(error)
            self.run(self.state.readyForStatementReceived(), with: context)
        case .succeedPing(let promise):
            promise.succeed()
            self.run(self.state.readyForStatementReceived(), with: context)

        case .sendCommit:
            self.encoder.commit()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .failCommit(let promise, let error):
            promise.fail(error)
            self.run(self.state.readyForStatementReceived(), with: context)
        case .succeedCommit(let promise):
            promise.succeed()
            self.run(self.state.readyForStatementReceived(), with: context)

        case .sendRollback:
            self.encoder.rollback()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .failRollback(let promise, let error):
            promise.fail(error)
            self.run(self.state.readyForStatementReceived(), with: context)
        case .succeedRollback(let promise):
            promise.succeed()
            self.run(self.state.readyForStatementReceived(), with: context)

        case .fireEventReadyForStatement:
            context
                .fireUserInboundEventTriggered(OracleSQLEvent.readyForStatement)

        case .closeConnectionAndCleanup(let cleanup):
            self.closeConnectionAndCleanup(cleanup, context: context)

        case .logoffConnection:
            if context.channel.isActive {
                // The normal, graceful termination procedure is that the
                // frontend sends a Logoff message and after receiving the
                // response to that, it sends a Close message. On receipt of
                // this message, the backend closes the connection and
                // terminates
                self.encoder.logoff(cleanupContext: self.cleanupContext)
                context.writeAndFlush(
                    self.wrapOutboundOut(self.encoder.flush()), promise: nil
                )
            }
        case .closeConnection(let promise):
            if context.channel.isActive {
                self.encoder.close()
                context.writeAndFlush(
                    self.wrapOutboundOut(self.encoder.flush()),
                    promise: nil
                )
            }
            context.close(mode: .all, promise: promise)
        case .fireChannelInactive:
            context.fireChannelInactive()
        }
    }

    // MARK: - Private Methods -

    private func connected(context: ChannelHandlerContext) {
        let action = self.state.connected()
        self.run(action, with: context)
    }

    private func sendConnect(
        withFlags flags: UInt8?,
        context: ChannelHandlerContext
    ) {
        // Renegotiate TLS if needed
        if self.configuration._protocol == .tcps
            && (flags ?? 0) & Constants.TNS_PACKET_FLAG_TLS_RENEG != 0
        {
            let promise = context.eventLoop.makePromise(of: Void.self)
            let sslContext = self.configuration.tls.sslContext!
            let hostname = self.configuration.serverNameForTLS
            let pipeline = context.pipeline
            pipeline.removeHandler(currentSSLHandler!, promise: promise)
            promise.futureResult.whenComplete { result in
                switch result {
                case .success:
                    do {
                        let sslHandler = try NIOSSLClientHandler(
                            context: sslContext,
                            serverHostname: hostname
                        )
                        try pipeline.syncOperations.addHandler(
                            sslHandler, position: .first
                        )
                        pipeline.fireUserInboundEventTriggered(OracleSQLEvent.renegotiateTLS)
                    } catch {
                        pipeline.fireErrorCaught(
                            OracleSQLError.failedToAddSSLHandler(underlying: error))
                    }

                case .failure(let error):
                    pipeline.fireErrorCaught(
                        OracleSQLError.failedToAddSSLHandler(underlying: error))
                }
            }

            return
        }


        let messages = self.encoder.connect(
            connectString: self.configuration.getConnectString()
        )
        for message in messages {
            context.writeAndFlush(
                self.wrapOutboundOut(message), promise: nil
            )
        }
    }

    private func sendAuthenticationPhaseOne(
        authContext: AuthContext, context: ChannelHandlerContext
    ) {
        self.encoder.authenticationPhaseOne(authContext: authContext)
        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func sendAuthenticationPhaseTwo(
        authContext: AuthContext, parameters: OracleBackendMessage.Parameter,
        context: ChannelHandlerContext
    ) {
        do {
            try self.encoder.authenticationPhaseTwo(
                authContext: authContext, parameters: parameters
            )
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        } catch {
            context.fireErrorCaught(error)
        }
    }

    private func authenticated(
        parameters: OracleBackendMessage.Parameter,
        context: ChannelHandlerContext
    ) {
        // Did finish starting and authenticating
        let (
            version, sessionID, serialNumber
        ) = getVersionInfo(from: parameters)
        context.fireUserInboundEventTriggered(
            OracleSQLEvent.startupDone(
                version: version,
                sessionID: sessionID,
                serialNumber: serialNumber
            ))
        context.fireUserInboundEventTriggered(OracleSQLEvent.readyForStatement)
    }

    private func sendExecute(
        statementContext: StatementContext,
        describeInfo: DescribeInfo?,
        context: ChannelHandlerContext
    ) {
        self.encoder.execute(
            statementContext: statementContext,
            cleanupContext: self.cleanupContext,
            describeInfo: describeInfo
        )

        self.decoderContext.statementOptions = statementContext.options

        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func sendReexecute(
        statementContext: StatementContext,
        cleanupContext: CleanupContext,
        context: ChannelHandlerContext
    ) {
        self.encoder.reexecute(
            statementContext: statementContext, cleanupContext: cleanupContext
        )

        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func sendFetch(
        statementContext: StatementContext,
        context: ChannelHandlerContext
    ) {
        self.encoder.fetch(
            cursorID: statementContext.cursorID,
            fetchArraySize: UInt32(statementContext.options.arraySize)
        )

        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func succeedStatement(
        _ promise: EventLoopPromise<OracleRowStream>,
        result: StatementResult,
        context: ChannelHandlerContext
    ) {
        let rows: OracleRowStream
        switch result.value {
        case .describeInfo(let describeInfo):
            rows = OracleRowStream(
                source: .stream(describeInfo, self),
                eventLoop: context.channel.eventLoop,
                logger: result.logger
            )
            self.rowStream = rows
            promise.succeed(rows)

        case .noRows:
            rows = OracleRowStream(
                source: .noRows(.success(())),
                eventLoop: context.channel.eventLoop,
                logger: result.logger
            )
            promise.succeed(rows)
            self.run(self.state.readyForStatementReceived(), with: context)
        }

    }

    private func closeConnectionAndCleanup(
        _ cleanup: ConnectionStateMachine.ConnectionAction.CleanUpContext,
        context: ChannelHandlerContext
    ) {
        self.logger.debug(
            "Cleaning up and closing connection.",
            metadata: [.error: "\(String(reflecting: cleanup.error))"]
        )

        // 1. fail all tasks
        for task in cleanup.tasks {
            task.failWithError(cleanup.error)
        }

        // 2. fire an error
        if cleanup.error.code != .clientClosedConnection {
            context.fireErrorCaught(cleanup.error)
        }

        // 3. read remaining data if needed
        if cleanup.read {
            context.read()
        }

        // 4. close the connection or fire channel inactive
        switch cleanup.action {
        case .close:
            let action = self.state.close(cleanup.closePromise)
            self.run(action, with: context)
        case .fireChannelInactive:
            cleanup.closePromise?.succeed()
            context.fireChannelInactive()
        }
    }

    // MARK: - Utility

    private func getVersionInfo(
        from parameters: OracleBackendMessage.Parameter
    ) -> (OracleVersion, Int, Int) {
        let version = getVersion(from: parameters)
        guard
            let sessionID = (parameters["AUTH_SESSION_ID"]?.value)
                .flatMap(Int.init),
            let serialNumber = (parameters["AUTH_SERIAL_NUM"]?.value)
                .flatMap(Int.init)
        else {
            preconditionFailure()
        }
        return (version, sessionID, serialNumber)
    }

    /// Returns the 5-tuple for the database version. Note that the format changed with Oracle Database 18.
    /// https://www.krenger.ch/blog/oracle-version-numbers/
    ///
    /// Oracle Release Number Format:
    /// ```
    /// 12.1.0.1.0
    ///  ┬ ┬ ┬ ┬ ┬
    ///  │ │ │ │ └───── Platform-Specific Release Number
    ///  │ │ │ └────────── Component-Specific Release Number
    ///  │ │ └─────────────── Fusion Middleware Release Number
    ///  │ └──────────────────── Database Maintenance Release Number
    ///  └───────────────────────── Major Database Release Number
    ///  ```
    private func getVersion(
        from parameters: OracleBackendMessage.Parameter
    ) -> OracleVersion {
        guard
            let fullVersionNumber = (parameters["AUTH_VERSION_NO"]?.value)
                .flatMap(Int.init)
        else {
            preconditionFailure()
        }

        if self.capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_18_1_EXT_1 {
            return OracleVersion(
                majorDatabaseReleaseNumber: (fullVersionNumber >> 24) & 0xff,
                databaseMaintenanceReleaseNumber: (fullVersionNumber >> 16) & 0xff,
                fusionMiddlewareReleaseNumber: (fullVersionNumber >> 12) & 0x0f,
                componentSpecificReleaseNumber: (fullVersionNumber >> 4) & 0xff,
                platformSpecificReleaseNumber: fullVersionNumber & 0x0f
            )
        }

        return OracleVersion(
            majorDatabaseReleaseNumber: (fullVersionNumber >> 24) & 0xff,
            databaseMaintenanceReleaseNumber: (fullVersionNumber >> 20) & 0x0f,
            fusionMiddlewareReleaseNumber: (fullVersionNumber >> 12) & 0x0f,
            componentSpecificReleaseNumber: (fullVersionNumber >> 8) & 0x0f,
            platformSpecificReleaseNumber: fullVersionNumber & 0x0f
        )
    }
}

extension OracleChannelHandler: OracleRowsDataSource {
    func request(for stream: OracleRowStream) {
        guard self.rowStream === stream, let handlerContext else {
            return
        }
        let action = self.state.requestStatementRows()
        self.run(action, with: handlerContext)
    }

    func cancel(for stream: OracleRowStream) {
        guard self.rowStream === stream, let handlerContext else {
            return
        }
        let action = self.state.cancelStatementStream()
        self.run(action, with: handlerContext)
    }
}
