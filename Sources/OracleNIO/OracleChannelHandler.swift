import Logging
import NIOCore
import NIOSSL
import NIOTLS
import class Foundation.ProcessInfo

protocol CapabilitiesProvider: AnyObject {
    func getCapabilities() -> Capabilities
    func setCapabilities(to capabilities: Capabilities)
}

final class OracleChannelHandler: ChannelDuplexHandler {
    typealias OutboundIn = OracleTask
    typealias InboundIn = [(flags: UInt8?, OracleBackendMessage)]
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
    private let decoderContext: OracleBackendMessageDecoder.Context = .init()
    private var encoder: OracleFrontendMessageEncoder!
    private let configuration: OracleConnection.Configuration
    private let currentSSLHandler: NIOSSLClientHandler?

    weak var capabilitiesProvider: CapabilitiesProvider!

    let cleanupContext = CleanupContext()

    init(
        configuration: OracleConnection.Configuration, 
        logger: Logger,
        sslHandler: NIOSSLClientHandler?
    ) {
        self.state = ConnectionStateMachine()
        self.configuration = configuration
        self.logger = logger
        self.currentSSLHandler = sslHandler
    }

    // MARK: Handler Lifecycle

    func handlerAdded(context: ChannelHandlerContext) {
        self.handlerContext = context
        self.setCoders(context: context)

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
        self.logger.debug("Channel error caught.", metadata: [
            .error: "\(error)"
        ])
        let action = self.state.errorHappened(
            .connectionError(underlying: error)
        )
        self.run(action, with: context)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let messages = self.unwrapInboundIn(data)
        for message in messages {
            self.handleMessage(
                message.1, flags: message.flags, context: context
            )
        }
    }

    private func handleMessage(
        _ message: OracleBackendMessage,
        flags: UInt8?,
        context: ChannelHandlerContext
    ) {
        self.logger.trace("Backend message received", metadata: [
            .message: "\(message)"
        ])
        self.decoderContext.performingChunkedRead = false
        let action: ConnectionStateMachine.ConnectionAction

        switch message {
        case .accept(let accept):
            self.capabilitiesProvider.setCapabilities(
                to: accept.newCapabilities
            )
            self.setCoders(context: context)
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
            self.capabilitiesProvider.setCapabilities(
                to: `protocol`.newCapabilities
            )
            self.setCoders(context: context)
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
                data, capabilities: self.capabilitiesProvider.getCapabilities()
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
        case .serverSidePiggyback(let piggybacks):
            // This should only happen if one is using `LOB`s.
            // These are not implemented as of now, so this _should_ never happen.
            fatalError("""
            Received server side piggybacks (\(piggybacks)), this is not \
            implemented and should never happen. Please open an issue here: \
            https://github.com/lovetodream/oracle-nio/issues with a \
            reproduction of the crash.
            """)
        case .lobData(let lobData):
            // This should only happen if one is using `LOB`s.
            // These are not implemented as of now, so this _should_ never happen.
            fatalError("""
            Received LOB data (\(lobData)), this is not implemented and should \
            never happen. Please open an issue here: \
            https://github.com/lovetodream/oracle-nio/issues with a \
            reproduction of the crash.
            """)

        case .chunk(let buffer):
            action = self.state.chunkReceived(
                buffer, 
                capabilities: self.capabilitiesProvider.getCapabilities()
            )
        }

        self.run(action, flags: flags, with: context)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        let action = self.state.channelReadComplete()
        self.run(action, with: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.logger.trace("User inbound event received", metadata: [
            .userEvent: "\(event)"
        ])

        switch event {
        case TLSUserEvent.handshakeCompleted:
            let action = self.state.tlsEstablished()
            self.run(action, with: context)
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
        self.logger.trace("User outbound event received", metadata: [
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
        self.logger.trace("Run action", metadata: [
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
        case .provideAuthenticationContext(let cookie):
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
                .provideAuthenticationContext(authContext, cookie: cookie)
            return self.run(action, with: context)
        case .sendAuthenticationPhaseOne(let authContext, let cookie):
            switch cookie {
            case .none:
                self.sendAuthenticationPhaseOne(
                    authContext: authContext, context: context
                )
            case .some(let cookie):
                self.encoder.cookie(cookie, authContext: authContext)
                context.writeAndFlush(
                    self.wrapOutboundOut(self.encoder.flush()), promise: nil
                )
            }
        case .sendAuthenticationPhaseTwo(let authContext, let parameters):
            self.sendAuthenticationPhaseTwo(
                authContext: authContext,
                parameters: parameters,
                context: context
            )
        case .authenticated(let parameters):
            self.authenticated(parameters: parameters, context: context)

        case .sendExecute(let queryContext, let describeInfo):
            self.sendExecute(
                queryContext: queryContext,
                describeInfo: describeInfo,
                context: context
            )
        case .sendReexecute(let queryContext, let cleanupContext):
            self.sendReexecute(
                queryContext: queryContext,
                cleanupContext: cleanupContext,
                context: context
            )
        case .sendFetch(let queryContext):
            self.sendFetch(queryContext: queryContext, context: context)
        case .succeedQuery(let promise, let result):
            self.succeedQuery(promise, result: result, context: context)
        case .failQuery(let promise, let error, let cleanupContext):
            promise.fail(error)
            if let cleanupContext {
                self.closeConnectionAndCleanup(cleanupContext, context: context)
            }
            self.decoderContext.queryOptions = nil
            self.decoderContext.columnsCount = nil
            self.run(self.state.readyForQueryReceived(), with: context)

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

            self.decoderContext.queryOptions = nil
            self.decoderContext.columnsCount = nil

            if cursorID != 0 {
                self.cleanupContext.cursorsToClose.insert(cursorID)
            }

            self.run(self.state.readyForQueryReceived(), with: context)

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

            self.decoderContext.queryOptions = nil
            self.decoderContext.columnsCount = nil

            if clientCancelled {
                self.run(.sendMarker, with: context)
            } else {
                self.run(self.state.readyForQueryReceived(), with: context)
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
            self.run(self.state.readyForQueryReceived(), with: context)
        case .succeedPing(let promise):
            promise.succeed()
            self.run(self.state.readyForQueryReceived(), with: context)

        case .sendCommit:
            self.encoder.commit()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .failCommit(let promise, let error):
            promise.fail(error)
            self.run(self.state.readyForQueryReceived(), with: context)
        case .succeedCommit(let promise):
            promise.succeed()
            self.run(self.state.readyForQueryReceived(), with: context)

        case .sendRollback:
            self.encoder.rollback()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .failRollback(let promise, let error):
            promise.fail(error)
            self.run(self.state.readyForQueryReceived(), with: context)
        case .succeedRollback(let promise):
            promise.succeed()
            self.run(self.state.readyForQueryReceived(), with: context)

        case .fireEventReadyForQuery:
            context.fireUserInboundEventTriggered(OracleSQLEvent.readyForQuery)

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
                let writePromise = context.eventLoop.makePromise(of: Void.self)
                context.writeAndFlush(
                    self.wrapOutboundOut(self.encoder.flush()),
                    promise: writePromise
                )
                writePromise.futureResult.whenComplete { _ in
                    context.close(mode: .all, promise: promise)
                }
            } else {
            }
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
        if self.configuration._protocol == .tcps &&
            (flags ?? 0) & Constants.TNS_PACKET_FLAG_TLS_RENEG != 0 {
            let promise = context.eventLoop.makePromise(of: Void.self)
            context.pipeline.removeHandler(currentSSLHandler!, promise: promise)
            promise.futureResult.whenComplete { result in
                switch result {
                case .success:

                    do {
                        let sslHandler = try NIOSSLClientHandler(
                            context: self.configuration.tls.sslContext!,
                            serverHostname: self.configuration.serverNameForTLS
                        )
                        try context.pipeline.syncOperations.addHandler(
                            sslHandler, position: .first
                        )
                        self.state.renegotiatingTLS()
                    } catch {
                        let action = self.state
                            .errorHappened(.failedToAddSSLHandler(underlying: error))
                        self.run(action, with: context)
                    }

                case .failure(let error):
                    let action = self.state
                        .errorHappened(.failedToAddSSLHandler(underlying: error))
                    self.run(action, with: context)
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
        context.fireUserInboundEventTriggered(OracleSQLEvent.startupDone(
            version: version,
            sessionID: sessionID,
            serialNumber: serialNumber
        ))
        context.fireUserInboundEventTriggered(OracleSQLEvent.readyForQuery)
    }

    private func sendExecute(
        queryContext: ExtendedQueryContext,
        describeInfo: DescribeInfo?,
        context: ChannelHandlerContext
    ) {
        self.encoder.execute(
            queryContext: queryContext, 
            cleanupContext: self.cleanupContext,
            describeInfo: describeInfo
        )

        self.decoderContext.queryOptions = queryContext.options

        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func sendReexecute(
        queryContext: ExtendedQueryContext,
        cleanupContext: CleanupContext,
        context: ChannelHandlerContext
    ) {
        self.encoder.reexecute(
            queryContext: queryContext, cleanupContext: cleanupContext
        )

        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func sendFetch(
        queryContext: ExtendedQueryContext,
        context: ChannelHandlerContext
    ) {
        self.encoder.fetch(
            cursorID: queryContext.cursorID,
            fetchArraySize: UInt32(queryContext.options.arraySize)
        )

        context.writeAndFlush(
            self.wrapOutboundOut(self.encoder.flush()), promise: nil
        )
    }

    private func succeedQuery(
        _ promise: EventLoopPromise<OracleRowStream>,
        result: QueryResult,
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
            self.run(self.state.readyForQueryReceived(), with: context)
        }

    }

    private func closeConnectionAndCleanup(
        _ cleanup: ConnectionStateMachine.ConnectionAction.CleanUpContext,
        context: ChannelHandlerContext
    ) {
        self.logger.debug(
            "Cleaning up and closing connection.",
            metadata: [.error: "\(cleanup.error)"]
        )

        // 1. fail all tasks
        cleanup.tasks.forEach { task in
            task.failWithError(cleanup.error)
        }

        // 2. fire an error
        if cleanup.error.code != .clientClosedConnection {
            context.fireErrorCaught(cleanup.error)
        }

        // 3. close the connection or fire channel inactive
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

        if
            self.capabilitiesProvider.getCapabilities().ttcFieldVersion >=
                Constants.TNS_CCAP_FIELD_VERSION_18_1_EXT_1
        {
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

    private func setCoders(
        context: ChannelHandlerContext
    ) {
        if let decoder = self.decoder {
            context.pipeline.removeHandler(decoder, promise: nil)
        }
        self.decoder = ByteToMessageHandler(OracleBackendMessageDecoder(
            capabilities: self.capabilitiesProvider.getCapabilities(),
            context: self.decoderContext
        ))
        _ = context.pipeline.addHandler(
            self.decoder!,
            position: .before(self)
        )
        self.encoder = OracleFrontendMessageEncoder(
            buffer: context.channel.allocator.buffer(capacity: 256),
            capabilities: capabilitiesProvider.getCapabilities()
        )
    }
}

extension OracleChannelHandler: OracleRowsDataSource {
    func request(for stream: OracleRowStream) {
        guard  self.rowStream === stream, let handlerContext else {
            return
        }
        let action = self.state.requestQueryRows()
        self.run(action, with: handlerContext)
    }

    func cancel(for stream: OracleRowStream) {
        guard self.rowStream === stream, let handlerContext else {
            return
        }
        let action = self.state.cancelQueryStream()
        self.run(action, with: handlerContext)
    }
}
