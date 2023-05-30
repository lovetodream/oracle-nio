import NIOCore
import class Foundation.ProcessInfo

public class OracleConnection {
    public struct Configuration {
        var address: SocketAddress
        var serviceName: String
        var username: String
        var password: String
        var autocommit: Bool
        //  "(DESCRIPTION=(CONNECT_DATA=(SERVICE_NAME=XEPDB1)(CID=(PROGRAM=\(ProcessInfo.processInfo.processName))(HOST=\(ProcessInfo.processInfo.hostName))(USER=\(ProcessInfo.processInfo.userName))))(ADDRESS=(PROTOCOL=tcp)(HOST=192.168.1.22)(PORT=1521)))"

        public init(address: SocketAddress, serviceName: String, username: String, password: String, autocommit: Bool = false) {
            self.address = address
            self.serviceName = serviceName
            self.username = username
            self.password = password
            self.autocommit = autocommit
        }
    }

    var autocommit: Bool { configuration.autocommit }

    var capabilities = Capabilities()
    let configuration: Configuration
    let channel: Channel
    let logger: Logger

    public var closeFuture: EventLoopFuture<Void> {
        channel.closeFuture
    }

    public var isClosed: Bool {
        !self.channel.isActive
    }

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
    var currentSchema: String?
    var edition: String?
    var tempLOBsTotalSize = 0
    var tempLOBsToClose: [[UInt8]]? = nil

    var cursorsToClose: [UInt16]?

    init(configuration: OracleConnection.Configuration, channel: Channel, logger: Logger) {
        self.configuration = configuration
        self.logger = logger
        self.channel = channel
        self.readyForAuthenticationPromise = self.channel.eventLoop.makePromise(of: Void.self)
        self.channelHandler = OracleChannelHandler(logger: logger)
        self.decoderHandler = ByteToMessageHandler(TNSMessageDecoder(connection: self))
    }
    deinit {
        assert(isClosed, "OracleConnection deinitialized before being closed.")
    }

    func start() -> EventLoopFuture<Void> {
        channelHandler.connection = self
        do {
            try channel.pipeline.syncOperations.addHandler(decoderHandler, position: .first)
            try channel.pipeline.syncOperations.addHandlers(channelHandler, position: .after(decoderHandler))
        } catch {
            return self.eventLoop.makeFailedFuture(error)
        }

        connectPhaseOne()

        return readyForAuthenticationFuture.flatMapWithEventLoop { _, eventLoop in
            self.logger.debug("Server ready for authentication")
            do {
                return try self.connectPhaseTwo()
            } catch {
                return eventLoop.makeFailedFuture(error)
            }
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

    private func connectPhaseTwo() throws -> EventLoopFuture<Void> {
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
        return protocolRequest.onResponsePromise!.futureResult
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
            .flatMap { _ in
                self.eventLoop.makeSucceededVoidFuture()
            }
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

    public func close() -> EventLoopFuture<Void> {
        guard !isClosed else { return eventLoop.makeSucceededVoidFuture() }

        channel.close(mode: .all, promise: nil)
        return closeFuture
    }

    func createRequest<T: TNSRequest>() -> T {
        T.initialize(from: self)
    }

    public func query(_ sql: String, binds: [Any] = []) throws {
        let cursor = try Cursor(statement: Statement(sql, characterConversion: capabilities.characterConversion), prefetchRows: 2, fetchArraySize: 0, fetchVariables: [])
        if !binds.isEmpty {
            cursor.bind(values: binds)
        }
        try cursor.preprocessExecute(connection: self)
        let request: ExecuteRequest = createRequest()
        request.numberOfExecutions = 1
        request.cursor = cursor
        request.onResponsePromise = eventLoop.makePromise()
        channel.write(request, promise: nil)
        cursor.statement.requiresFullExecute = false
        request.onResponsePromise!.futureResult.map { _ in
            self.fetchMoreRows(cursor: cursor)
        }
    }

    func fetchMoreRows(cursor: Cursor) {
        print(cursor.statement.cursorID)
        print(cursor.fetchVariables)
        if cursor.moreRowsToFetch {
            if cursor.statement.requiresFullExecute {
                let request: ExecuteRequest = self.createRequest()
                request.cursor = cursor
                request.onResponsePromise = self.eventLoop.makePromise()
                self.channel.write(request, promise: nil)
                cursor.statement.requiresFullExecute = false
                request.onResponsePromise!.futureResult.map { _ in
                    self.fetchMoreRows(cursor: cursor)
                }
            } else {
                let request: FetchRequest = self.createRequest()
                request.cursor = cursor
                request.onResponsePromise = self.eventLoop.makePromise()
                self.channel.write(request, promise: nil)
                request.onResponsePromise!.futureResult.map { _ in
                    self.fetchMoreRows(cursor: cursor)
                }
            }
        } else {
            return
        }
    }
}

extension OracleConnection {
    func resetStatementCache() {
        // TODO: reset cache
    }

    func addCursorToClose(_ statement: Statement) throws {
        if cursorsToClose?.count == Constants.TNS_MAX_CURSORS_TO_CLOSE {
            throw CursorCloseError.tooManyCursorsToClose
        }
        cursorsToClose?.append(statement.cursorID)
    }

    enum CursorCloseError: Error {
        case tooManyCursorsToClose
    }
}
