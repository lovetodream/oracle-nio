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

        public init(
            address: SocketAddress,
            serviceName: String,
            username: String,
            password: String
        ) {
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
                .connectTimeout(configuration.options.connectTimeout)
        }
        #endif

        guard let bootstrap = ClientBootstrap(validatingGroup: eventLoop) else {
            fatalError("No matching bootstrap found")
        }
        return bootstrap
            .connectTimeout(configuration.options.connectTimeout)
    }

    /// Closes the connection to the database server.
    public func close() -> EventLoopFuture<Void> {
        guard !self.isClosed else {
            return self.eventLoop.makeSucceededVoidFuture()
        }

        self.channel.close(mode: .all, promise: nil)
        return self.closeFuture
    }

    /// Sends a ping to the database server.
    public func ping() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.ping(promise), promise: nil)
        return promise.futureResult
    }

    /// Sends a commit to the database server.
    public func commit() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.commit(promise), promise: nil)
        return promise.futureResult
    }

    /// Sends a rollback to the database server.
    public func rollback() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.rollback(promise), promise: nil)
        return promise.futureResult
    }

    // MARK: Query

    private func queryStream(
        _ query: OracleQuery, options: QueryOptions, logger: Logger
    ) -> EventLoopFuture<OracleRowStream> {
        var logger = logger
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID ?? 0)"

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        do {
            let context = try ExtendedQueryContext(
                query: query,
                options: options,
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

    /// Closes the connection to the database server.
    public func close() async throws {
        try await self.close().get()
    }

    /// Sends a ping to the database server.
    public func ping() async throws {
        try await self.ping().get()
    }

    /// Sends a commit to the database server.
    public func commit() async throws {
        try await self.commit().get()
    }

    /// Sends a rollback to the database server.
    public func rollback() async throws {
        try await self.rollback().get()
    }

    /// Run a query on the Oracle server the connection is connected to.
    ///
    /// - Parameters:
    ///   - query: The ``OracleQuery`` to run.
    ///   - options: A bunch of parameters to optimize the query in different ways. Normally this can
    ///              be ignored, but feel free to experiment based on your needs. Every option and
    ///              its impact is documented.
    ///   - logger: The `Logger` to log into for the query.
    ///   - file: The file, the query was started in. Used for better error reporting.
    ///   - line: The line, the query was started in. Used for better error reporting.
    /// - Returns: A ``OracleRowSequence`` containing the rows the server sent as the query
    ///            result. The result sequence can be discarded if the query has no result.
    @discardableResult
    public func query(
        _ query: OracleQuery,
        options: QueryOptions = .init(),
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
            options: options,
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
