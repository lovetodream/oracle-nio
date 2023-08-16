import NIOCore
#if canImport(Network)
import NIOTransportServices
#endif
import class Foundation.ProcessInfo

public class OracleConnection {
    /// A Oracle connection ID, used exclusively for logging.
    public typealias ID = Int

    public struct Configuration {

        /// Describes options affecting how the underlying connection is made.
        public struct Options {
            /// A timeout for connection attempts. Defaults to ten seconds.
            public var connectTimeout: TimeAmount

            /// Create an options structure with default values.
            ///
            /// Most users should not need to adjust the defaults.
            public init() {
                self.connectTimeout = .seconds(10)
            }
        }

        var options: Options = .init()

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

    let id: ID

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

    init(
        configuration: OracleConnection.Configuration,
        channel: Channel,
        connectionID: ID,
        logger: Logger
    ) {
        self.id = connectionID
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
    
    /// Create a new connection to an Oracle server.
    ///
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` the connection shall be created on.
    ///   - configuration: A ``Configuration`` that shall be used for the connection.
    ///   - connectionID: An `Int` id, used for metadata logging.
    ///   - logger: A logger to log background events into.
    /// - Returns: A SwiftNIO `EventLoopFuture` that will provide a ``OracleConnection``
    ///            at a later point in time.
    public static func connect(
        on eventLoop: EventLoop = OracleConnection.defaultEventLoopGroup.any(),
        configuration: OracleConnection.Configuration,
        id connectionID: ID,
        logger: Logger
    ) -> EventLoopFuture<OracleConnection> {
        var logger = logger
        logger[oracleMetadataKey: .connectionID] = "\(connectionID)"

        return eventLoop.flatSubmit {
            makeBootstrap(on: eventLoop, configuration: configuration)
                .connect(to: configuration.address)
                .flatMap { channel -> EventLoopFuture<OracleConnection> in
                let connection = OracleConnection(
                    configuration: configuration,
                    channel: channel,
                    connectionID: connectionID,
                    logger: logger
                )
                return connection.start().map { _ in connection }
            }
        }
    }

    static func makeBootstrap(
        on eventLoop: EventLoop,
        configuration: OracleConnection.Configuration
    ) -> NIOClientTCPBootstrapProtocol {
        #if canImport(Network)
        if let tsBootstrap = 
            NIOTSConnectionBootstrap(validatingGroup: eventLoop)
        {
            return tsBootstrap
                .channelOption(
                    ChannelOptions.socketOption(.so_reuseaddr), value: 1
                )
                .connectTimeout(configuration.options.connectTimeout)
        }
        #endif

        guard let bootstrap = ClientBootstrap(validatingGroup: eventLoop) else {
            fatalError("No matching bootstrap found")
        }
        return bootstrap
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .connectTimeout(configuration.options.connectTimeout)
    }

    public func close() -> EventLoopFuture<Void> {
        guard !self.isClosed else {
            return self.eventLoop.makeSucceededVoidFuture()
        }

        self.channel.close(mode: .all, promise: nil)
        return self.closeFuture
    }

    // MARK: Query

    private func queryStream(
        _ query: OracleQuery, logger: Logger
    ) -> EventLoopFuture<OracleRowStream> {
        var logger = logger
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID ?? 0)"

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        do {
            let context = try ExtendedQueryContext(
                query: query,
                options: .init(),
                useCharacterConversion: self.capabilities.characterConversion,
                logger: logger,
                promise: promise
            )
            self.channel.write(OracleTask.extendedQuery(context), promise: nil)
        } catch {
            promise.fail(error)
        }

        return promise.futureResult
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

// MARK: Async/Await Interface

extension OracleConnection {

    /// Creates a new connection to an Oracle server.
    ///
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` the connection shall be created on.
    ///   - configuration: A ``Configuration`` that shall be used for the connection.
    ///   - connectionID: An `Int` id, used for metadata logging.
    ///   - logger: A logger to log background events into.
    /// - Returns: An established ``OracleConnection`` asynchronously that can be used to run
    ///            queries.
    public static func connect(
        on eventLoop: EventLoop = OracleConnection.defaultEventLoopGroup.any(),
        configuration: OracleConnection.Configuration,
        id connectionID: ID,
        logger: Logger
    ) async throws -> OracleConnection {
        try await self.connect(
            on: eventLoop, 
            configuration: configuration,
            id: connectionID,
            logger: logger
        ).get()
    }

    /// Closes the connection to the server.
    public func close() async throws {
        try await self.close().get()
    }

    /// Run a query on the Oracle server the connection is connected to.
    ///
    /// - Parameters:
    ///   - query: The ``OracleQuery`` to run.
    ///   - logger: The `Logger` to log into for the query.
    ///   - file: The file, the query was started in. Used for better error reporting.
    ///   - line: The line, the query was started in. Used for better error reporting.
    /// - Returns: A ``OracleRowSequence`` containing the rows the server sent as the query
    ///            result. The result sequence can be discarded if the query has no result.
    @discardableResult
    public func query(
        _ query: OracleQuery,
        logger: Logger,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = try ExtendedQueryContext(
            query: query,
            options: .init(),
            useCharacterConversion: self.capabilities.characterConversion,
            logger: logger,
            promise: promise
        )

        self.channel.write(OracleTask.extendedQuery(context), promise: nil)

        do {
            return try await promise.futureResult
                .map({ $0.asyncSequence() })
                .get()
        } catch var error as OracleSQLError {
            error.file = file
            error.line = line
            error.query = query
            throw error // rethrow with more metadata
        }
    }
}

// MARK: EventLoopFuture Interface

extension OracleConnection {
    
    /// Run a query on the Oracle server the connection is connected to and collect all rows.
    ///
    /// - Parameters:
    ///   - query: The ``OracleQuery`` to run.
    ///   - logger: The `Logger` to log into for the query.
    ///   - file: The file, the query was started in. Used for better error reporting.
    ///   - line: The line, the query was started in. Used for better error reporting.
    /// - Returns: An `EventLoopFuture`, that allows access to the future
    ///            ``OracleQueryResult``.
    public func query(
        _ query: OracleQuery,
        logger: Logger,
        file: String = #fileID,
        line: Int = #line
    ) -> EventLoopFuture<OracleQueryResult> {
        self.queryStream(query, logger: logger).flatMap { rowStream in
            rowStream.all().flatMapThrowing { rows in
                let metadata = OracleQueryMetadata()
                return OracleQueryResult(metadata: metadata, rows: rows)
            }
        }.enrichOracleError(query: query, file: file, line: line)
    }
    
    /// Run a query on the Oracle server the connection is connected to and iterate the rows in a callback.
    ///
    /// - Note: This API does not support back-pressure. If you need back-pressure please use the
    ///         query API, that supports structured concurrency.
    /// - Parameters:
    ///   - query: The ``OracleQuery`` to run.
    ///   - logger: The `Logger` to log into for the query.
    ///   - file: The file, the query was started in. Used for better error reporting.
    ///   - line: The line, the query was started in. Used for better error reporting.
    ///   - onRow: A closure that is invoked on every row.
    /// - Returns: An EventLoopFuture, that allows access to the future
    ///            ``OracleQueryMetadata``.
    public func query(
        _ query: OracleQuery,
        logger: Logger,
        file: String = #fileID,
        line: Int = #line,
        _ onRow: @escaping (OracleRow) throws -> Void
    ) -> EventLoopFuture<OracleQueryMetadata> {
        self.queryStream(query, logger: logger).flatMap { rowStream in
            rowStream.onRow(onRow).flatMapThrowing { _ in
                let metadata = OracleQueryMetadata()
                return metadata
            }
        }.enrichOracleError(query: query, file: file, line: line)
    }

}

extension EventLoopFuture {
    func enrichOracleError(
        query: OracleQuery, file: String, line: Int
    ) -> EventLoopFuture<Value> {
        return self.flatMapErrorThrowing { error in
            if var error = error as? OracleSQLError {
                error.file = file
                error.line = line
                error.query = query
                throw error
            } else {
                throw error
            }
        }
    }
}

extension OracleConnection {
    /// Returns the default `EventLoopGroup` singleton, automatically selecting the best for the
    /// platform.
    ///
    /// This will select the concrete `EventLoopGroup` depending on which platform this is running on.
    public static var defaultEventLoopGroup: EventLoopGroup {
        #if canImport(Network)
        if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            return NIOTSEventLoopGroup.singleton
        } else {
            return MultiThreadedEventLoopGroup.singleton
        }
        #else
        return MultiThreadedEventLoopGroup.singleton
        #endif
    }
}
