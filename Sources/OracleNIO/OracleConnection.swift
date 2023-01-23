import NIOCore

public class OracleConnection {
    var capabilities = Capabilities()
    let channel: Channel
    let logger: Logger

    var readyForAuthenticationPromise: EventLoopPromise<Void>
    var readyForAuthenticationFuture: EventLoopFuture<Void> {
        self.readyForAuthenticationPromise.futureResult
    }

    private var decoderHandler: ByteToMessageHandler<TNSMessageDecoder>!
    private var channelHandler: OracleChannelHandler

    public var eventLoop: EventLoop { channel.eventLoop }

    var drcpEstablishSession = false

    init(channel: Channel, logger: Logger) {
        self.logger = logger
        self.channel = channel
        self.readyForAuthenticationPromise = self.channel.eventLoop.makePromise(of: Void.self)
        self.channelHandler = OracleChannelHandler(logger: logger)
        self.decoderHandler = ByteToMessageHandler(TNSMessageDecoder(connection: self))
    }

    func start() -> EventLoopFuture<Void> {
        do {
            try channel.pipeline.syncOperations.addHandler(decoderHandler, position: .first)
            try channel.pipeline.syncOperations.addHandlers(channelHandler, position: .after(decoderHandler))
        } catch {
            return self.eventLoop.makeFailedFuture(error)
        }

        connectPhaseOne()

        return readyForAuthenticationFuture.flatMapThrowing { _ in
            self.logger.debug("Server ready for authentication")
            try self.connectPhaseTwo()
        }
    }

    private func connectPhaseOne() {
        let request: ConnectRequest = createRequest()
        channel.write(request, promise: nil)
    }

    private func connectPhaseTwo() throws {
        if capabilities.protocolVersion < Constants.TNS_VERSION_MIN_ACCEPTED {
            throw OracleError.ErrorType.serverVersionNotSupported
        }

        if capabilities.supportsOOB && capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_OOB_CHECK {
            // TODO: Perform OOB Check
        }

        var networkServicesRequest: NetworkServicesRequest = createRequest()
        networkServicesRequest.onResponsePromise = eventLoop.makePromise()
        channel.write(networkServicesRequest, promise: nil)
        networkServicesRequest.onResponsePromise!.futureResult
            .flatMap { _ in
                var protocolRequest: ProtocolRequest = self.createRequest()
                protocolRequest.onResponsePromise = self.eventLoop.makePromise()
                self.channel.write(protocolRequest, promise: nil)
                return protocolRequest.onResponsePromise!.futureResult
            }
            .flatMap { _ in
                var dataTypesRequest: DataTypesRequest = self.createRequest()
                dataTypesRequest.onResponsePromise = self.eventLoop.makePromise()
                self.channel.write(dataTypesRequest, promise: nil)
                return dataTypesRequest.onResponsePromise!.futureResult
            }
            // TODO: authenticate
    }

    public static func connect(to address: SocketAddress, logger: Logger, on eventLoop: EventLoop) -> EventLoopFuture<OracleConnection> {
        eventLoop.flatSubmit {
            makeBootstrap(on: eventLoop).connect(to: address).flatMap { channel -> EventLoopFuture<OracleConnection> in
                let connection = OracleConnection(channel: channel, logger: logger)
                return connection.start().map { _ in connection }
            }
        }
    }

    static func makeBootstrap(on eventLoop: EventLoop) -> ClientBootstrap {
        guard var bootstrap = ClientBootstrap(validatingGroup: eventLoop) else {
            fatalError("No matching bootstrap found")
        }
        bootstrap = bootstrap
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .channelOption(ChannelOptions.connectTimeout, value: .none)
        return bootstrap
    }

    func createRequest<T: TNSRequest>() -> T {
        T.initialize(from: self)
    }
}

extension OracleConnection {
    func resetStatementCache() {
        // TODO: reset cache
    }
}
