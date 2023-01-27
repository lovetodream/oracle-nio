import NIOCore
import class Foundation.ProcessInfo

public class OracleConnection {
    public struct Configuration {
        var address: SocketAddress
        var serviceName: String
        var username: String
        var password: String
        //  "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=XEPDB1)(CID=(PROGRAM=\(ProcessInfo.processInfo.processName))(HOST=\(ProcessInfo.processInfo.hostName))(USER=\(ProcessInfo.processInfo.userName))))(ADDRESS=(PROTOCOL=tcp)(HOST=192.168.1.22)(PORT=1521)))"

        public init(address: SocketAddress, serviceName: String, username: String, password: String) {
            self.address = address
            self.serviceName = serviceName
            self.username = username
            self.password = password
        }
    }

    var capabilities = Capabilities()
    let configuration: Configuration
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

    var sessionID: Int?
    var serialNumber: Int?
    var serverVersion: OracleVersion?

    init(configuration: OracleConnection.Configuration, channel: Channel, logger: Logger) {
        self.configuration = configuration
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
        guard let ipAddress = configuration.address.ipAddress, let port = configuration.address.port else {
            preconditionFailure("Configuration Address needs to include ip address and port")
        }
        var request: ConnectRequest = createRequest()
        request.connectString = "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=\(configuration.serviceName.uppercased()))(CID=(PROGRAM=\(ProcessInfo.processInfo.processName))(HOST=\(ProcessInfo.processInfo.hostName))(USER=\(ProcessInfo.processInfo.userName))))(ADDRESS=(PROTOCOL=tcp)(HOST=\(ipAddress))(PORT=\(port))))"
        channel.write(request, promise: nil)
    }

    private func connectPhaseTwo() throws {
        if capabilities.protocolVersion < Constants.TNS_VERSION_MIN_ACCEPTED {
            throw OracleError.ErrorType.serverVersionNotSupported
        }

        if capabilities.supportsOOB && capabilities.protocolVersion >= Constants.TNS_VERSION_MIN_OOB_CHECK {
            // TODO: Perform OOB Check
        }

        let connectDescription = Description(serviceName: configuration.serviceName)
        var connectParameters = ConnectParameters(defaultDescription: connectDescription, defaultAddress: Address(), descriptionList: DescriptionList(), mode: 0)
        connectParameters.setPassword(configuration.password)

        var protocolRequest: ProtocolRequest = self.createRequest()
        protocolRequest.onResponsePromise = self.eventLoop.makePromise()
        self.channel.write(protocolRequest, promise: nil)
        protocolRequest.onResponsePromise!.futureResult
            .flatMap { _ in
                var dataTypesRequest: DataTypesRequest = self.createRequest()
                dataTypesRequest.onResponsePromise = self.eventLoop.makePromise()
                self.channel.write(dataTypesRequest, promise: nil)
                return dataTypesRequest.onResponsePromise!.futureResult
            }
            .flatMap { _ in
                let authRequest: AuthRequest = self.createRequest()
                authRequest.setParameters(connectParameters, with: connectDescription)
                authRequest.onResponsePromise = self.eventLoop.makePromise()
                self.channel.write(authRequest, promise: nil)
                return authRequest.onResponsePromise!.futureResult.flatMap { message in
                    if authRequest.resend {
                        authRequest.onResponsePromise = self.eventLoop.makePromise()
                        self.channel.write(authRequest, promise: nil)
                    }
                    return authRequest.onResponsePromise!.futureResult
                }
            }
            // TODO: authenticate
    }

    public static func connect(
        using configuration: OracleConnection.Configuration,
        logger: Logger,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<OracleConnection> {
        eventLoop.flatSubmit {
            makeBootstrap(on: eventLoop).connect(to: configuration.address).flatMap { channel -> EventLoopFuture<OracleConnection> in
                let connection = OracleConnection(configuration: configuration, channel: channel, logger: logger)
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
