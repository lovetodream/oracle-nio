import NIOCore

public class OracleConnection {
    var capabilities = Capabilities()
    let channel: Channel
    let logger: Logger

    var readyForAuthenticationPromise: EventLoopPromise<Void>
    var readyForAuthenticationFuture: EventLoopFuture<Void> {
        self.readyForAuthenticationPromise.futureResult
    }

    public var eventLoop: EventLoop { channel.eventLoop }


    init(channel: Channel, logger: Logger) {
        self.logger = logger
        self.channel = channel
        self.readyForAuthenticationPromise = self.channel.eventLoop.makePromise(of: Void.self)
    }

    func start() -> EventLoopFuture<Void> {
        let channelHandler = OracleChannelHandler(logger: logger)

        do {
            try channel.pipeline.syncOperations.addHandlers(channelHandler)
        } catch {
            return self.eventLoop.makeFailedFuture(error)
        }

        connectPhaseOne()

        return readyForAuthenticationFuture.flatMapThrowing { _ in
            self.logger.log(level: .debug, "Server ready for authentication")
            try self.connectPhaseTwo()
        }
    }

    private func connectPhaseOne() {
        let connectMessage: ConnectRequest = createMessage()
        channel.write(connectMessage, promise: nil)
    }

    private func connectPhaseTwo() throws {
        if capabilities.protocolVersion < Constants.TNS_VERSION_MIN_ACCEPTED {
            throw OracleError.serverVersionNotSupported
        }

        if capabilities.supportsOOB && capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_OOB_CHECK {
            // TODO: Perform OOB Check
        }

        let networkServicesMessage: NetworkServicesMessage = createMessage()
        channel.write(networkServicesMessage, promise: nil)
//        let protocolMessage = connection.createMessage(ProtocolMessage)
//        let dataTypesMessage = connection.createMessage(DataTypesMessage)
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

    func createMessage<T: TNSRequest>() -> T {
        T.initialize(from: self)
    }
}
