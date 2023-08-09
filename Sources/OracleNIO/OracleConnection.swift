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
    }
    deinit {
        assert(isClosed, "OracleConnection deinitialized before being closed.")
    }

    func start() -> EventLoopFuture<Void> {
        // 1. configure handlers

        let channelHandler = OracleChannelHandler(
            configuration: configuration,
            logger: logger
        )
        channelHandler.capabilitiesProvider = self

        let eventHandler = OracleEventsHandler(logger: logger)

        // 2. add handlers

        do {
            try self.channel.pipeline.syncOperations.addHandler(eventHandler)
            try self.channel.pipeline.syncOperations.addHandler(
                channelHandler, position: .before(eventHandler)
            )
        } catch {
            return self.eventLoop.makeFailedFuture(error)
        }

        // 3. wait for startup future to succeed.

        return eventHandler.startupDoneFuture
            .flatMapError { error in
                // in case of a startup error, the connection must be closed and
                // after that the originating error should be surfaced
                self.channel.closeFuture.flatMapThrowing { _ in
                    throw error
                }
            }
            .map { context in
                self.serverVersion = context.version
                self.sessionID = context.sessionID
                self.serialNumber = context.serialNumber
                return Void()
            }
    }

    public static func connect(
        using configuration: OracleConnection.Configuration,
        logger: Logger,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<OracleConnection> {
        eventLoop.flatSubmit {
            makeBootstrap(on: eventLoop)
                .connect(to: configuration.address)
                .flatMap { channel -> EventLoopFuture<OracleConnection> in
                let connection = OracleConnection(
                    configuration: configuration,
                    channel: channel,
                    logger: logger
                )
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

extension OracleConnection: CapabilitiesProvider {
    func getCapabilities() -> Capabilities {
        self.capabilities
    }

    func setCapabilities(to capabilities: Capabilities) {
        self.capabilities = capabilities
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
