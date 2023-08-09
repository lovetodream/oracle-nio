import NIOCore
import class Foundation.ProcessInfo

enum OracleTask { }

protocol CapabilitiesProvider: AnyObject {
    func getCapabilities() -> Capabilities
    func setCapabilities(to capabilities: Capabilities)
}

final class OracleChannelHandler: ChannelDuplexHandler {
    typealias OutboundIn = OracleTask
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let logger: Logger
    private var state: ConnectionStateMachine

    /// A `ChannelHandlerContext` to be used for non channel related events.
    ///
    /// For example: More rows needed.
    /// The context is captured in `handlerAdded` and released in `handlerRemoved`.
    private var handlerContext: ChannelHandlerContext?
    private var rowStream: OracleRowStream?
    private var decoder:
        NIOSingleStepByteToMessageProcessor<OracleBackendMessageDecoder>!
    private var encoder: OracleFrontendMessageEncoder!
    private let configuration: OracleConnection.Configuration

    weak var capabilitiesProvider: CapabilitiesProvider!

    init(configuration: OracleConnection.Configuration, logger: Logger) {
        self.state = ConnectionStateMachine()
        self.configuration = configuration
        self.logger = logger
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
        do {
            try self.decoder.finishProcessing(seenEOF: true) { message in
                self.handleMessage(message, context: context)
            }
        } catch let error as OracleMessageDecodingError {
            let action =
                self.state.errorHappened(.messageDecodingFailure(error))
            self.run(action, with: context)
        } catch {
            preconditionFailure("Expected to only get OracleDecodingErrors from the OracleBackendMessageDecoder")
        }

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
        let buffer = self.unwrapInboundIn(data)

        do {
            try self.decoder.process(buffer: buffer) { message in
                self.handleMessage(message, context: context)
            }
        } catch let error as OracleMessageDecodingError {
            let action = self.state.errorHappened(
                .messageDecodingFailure(error)
            )
            self.run(action, with: context)
        } catch {
            preconditionFailure("Expected to only get OracleDecodingErrors from the OracleBackendMessageDecoder")
        }
    }

    private func handleMessage(
        _ message: OracleBackendMessage,
        context: ChannelHandlerContext
    ) {
        self.logger.trace("Backend message received", metadata: [
            .message: "\(message)"
        ])
        let action: ConnectionStateMachine.ConnectionAction

        switch message {
        case .accept(let accept):
            self.capabilitiesProvider.setCapabilities(
                to: accept.newCapabilities
            )
            self.setCoders(context: context)
            action = self.state.acceptReceived()
        case .dataTypes:
            action = self.state.dataTypesReceived()
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
        case .status:
            action = self.state.statusReceived()
        case .rowDescription(let rowDescription):
            fatalError()
            // action = self.state.rowDescriptionReceived(rowDescription)
        }

        self.run(action, with: context)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        let action = self.state.channelReadComplete()
        self.run(action, with: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        self.logger.trace("User inbound event received", metadata: [
            .userEvent: "\(event)"
        ])
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
            self.encoder.encode(
                .connect(.init(connectString: simpleConnectString()))
            )
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .sendProtocol:
            self.encoder.encode(
                .protocol(.init())
            )
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .sendDataTypes:
            self.encoder.encode(.dataTypes(.init()))
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .provideAuthenticationContext:
            let authContext = AuthContext(
                username: configuration.username,
                password: configuration.password,
                description: .init(serviceName: configuration.serviceName)
            )
            let action = self.state.provideAuthenticationContext(authContext)
            return self.run(action, with: context)
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
        case .sendMarker:
            self.encoder.marker()
            context.writeAndFlush(
                self.wrapOutboundOut(self.encoder.flush()), promise: nil
            )
        case .logoffConnection(let promise):
            if context.channel.isActive {
                // The normal, graceful termination procedure is that the
                // frontend sends a Logoff message and after receiving the
                // response to that, it sends a Close message. On receipt of
                // this message, the backend closes the connection and
                // terminates
                self.encoder.logoff()
                context.writeAndFlush(
                    self.wrapOutboundOut(self.encoder.flush()), promise: nil
                )
            }
        case .closeConnection(let promise):
            if context.channel.isActive {
                self.encoder.close()
                context.writeAndFlush(
                    self.wrapOutboundOut(self.encoder.flush()), promise: nil
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

    private func simpleConnectString() -> String {
        guard
            let ipAddress = configuration.address.ipAddress,
            let port = configuration.address.port
        else {
            preconditionFailure(
                "Configuration Address needs to include ip address and port"
            )
        }
//        return "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=\(configuration.serviceName.uppercased()))(CID=(PROGRAM=\(ProcessInfo.processInfo.processName))(HOST=\(ProcessInfo.processInfo.hostName))(USER=\(ProcessInfo.processInfo.userName))))(ADDRESS=(PROTOCOL=tcp)(HOST=\(ipAddress))(PORT=\(port))))"
        return "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=\(configuration.serviceName))(CID=(PROGRAM=\(ProcessInfo.processInfo.processName))(HOST=\(ProcessInfo.processInfo.hostName))(USER=\(ProcessInfo.processInfo.userName))))(ADDRESS=(PROTOCOL=tcp)(HOST=\(ipAddress))(PORT=\(port))))"
    }

    private func setCoders(context: ChannelHandlerContext) {
        self.decoder = NIOSingleStepByteToMessageProcessor(
            OracleBackendMessageDecoder(
                capabilities: self.capabilitiesProvider.getCapabilities()
            )
        )
        self.encoder = OracleFrontendMessageEncoder(
            buffer: context.channel.allocator.buffer(capacity: 256),
            capabilities: capabilitiesProvider.getCapabilities()
        )
    }
}
