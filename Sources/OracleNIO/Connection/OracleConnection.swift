import NIOCore
import NIOPosix
#if canImport(Network)
import NIOTransportServices
#endif
import NIOSSL
import class Foundation.ProcessInfo

#if DEBUG
import Logging
#endif

public final class OracleConnection: @unchecked Sendable {
    /// A Oracle connection ID, used exclusively for logging.
    public typealias ID = Int

    var capabilities: Capabilities
    let configuration: Configuration
    let channel: Channel
    let logger: Logger

    public var closeFuture: EventLoopFuture<Void> {
        channel.closeFuture
    }

    public var isClosed: Bool {
        !self.channel.isActive
    }

    public let id: ID

    public var eventLoop: EventLoop { channel.eventLoop }

    var drcpEstablishSession = false

    var sessionID: Int?
    var serialNumber: Int?
    var serverVersion: OracleVersion?
    var currentSchema: String?
    var edition: String?

    var noopLogger = Logger(label: "oracle-nio.noop-logger") { _ in
        SwiftLogNoOpLogHandler()
    }

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
        self.capabilities = .init()
        // TODO: disable OOB on Windows, if Windows gets to be a supported platform
        if !configuration.disableOOB ||
            configuration._protocol == .tcps {
            self.capabilities.supportsOOB = true
        }
    }
    deinit {
        assert(isClosed, "OracleConnection deinitialized before being closed.")
    }

    func start(configuration: Configuration) -> EventLoopFuture<Void> {
        // 1. configure handlers

        let sslHandler: NIOSSLClientHandler?
        switch configuration.tls.base {
        case .disable: 
            sslHandler = nil
        case .require(let context):
            do {
                sslHandler = try NIOSSLClientHandler(
                    context: context,
                    serverHostname: configuration.serverNameForTLS
                )
                try channel.pipeline.syncOperations.addHandler(
                    sslHandler!, position: .first
                )
            } catch {
                return self.eventLoop.makeFailedFuture(error)
            }
        }

        let channelHandler = OracleChannelHandler(
            configuration: configuration,
            logger: logger,
            sslHandler: sslHandler
        )
        channelHandler.capabilitiesProvider = self

        let eventHandler = OracleEventsHandler(logger: logger)
        let frontendMessageHandler = OracleFrontendMessagePostProcessor()
        frontendMessageHandler.capabilitiesProvider = self

        // 2. add handlers

        do {
            #if DEBUG
            // This is very useful for sending hex dumps to Oracle to analyze
            // problems in the driver.
            let tracer = Logger(label: "oracle-nio.network-tracing")
            try self.channel.pipeline.syncOperations
                .addHandler(DebugLogHandler(logger: tracer))
            #endif
            try self.channel.pipeline.syncOperations.addHandler(eventHandler)
            try self.channel.pipeline.syncOperations
                .addHandler(channelHandler, position: .before(eventHandler))
            try self.channel.pipeline.syncOperations
                .addHandler(frontendMessageHandler, position: .before(channelHandler))
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
                .connect(host: configuration.host, port: configuration.port)
                .flatMap { channel -> EventLoopFuture<OracleConnection> in
                    let connection = OracleConnection(
                        configuration: configuration,
                        channel: channel,
                        connectionID: connectionID,
                        logger: logger
                    )
                    return connection.start(configuration: configuration).map {
                        _ in connection
                    }
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
            .channelOption(ChannelOptions
                .socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelOption(ChannelOptions
                .socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
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
    ///   - logger: The `Logger` to log into for the query. If none is provided, a no-op logger will be used.
    ///   - file: The file, the query was started in. Used for better error reporting.
    ///   - line: The line, the query was started in. Used for better error reporting.
    /// - Returns: A ``OracleRowSequence`` containing the rows the server sent as the query
    ///            result. The result sequence can be discarded if the query has no result.
    @discardableResult
    public func query(
        _ query: OracleQuery,
        options: QueryOptions = .init(),
        logger: Logger? = nil,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger ?? self.noopLogger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = try ExtendedQueryContext(
            query: query,
            options: options,
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


#if DEBUG
private final class DebugLogHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer

    private var logger: Logger
    private var shouldLog: Bool

    init(logger: Logger, shouldLog: Bool? = nil) {
        if let shouldLog {
            self.shouldLog = shouldLog
        } else {
            let envValue = getenv("ORANIO_TRACE_PACKETS")
                .flatMap { String(cString: $0) }
                .flatMap(Int.init) ?? 0
            self.shouldLog = envValue != 0
        }
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if self.shouldLog {
            let buffer = self.unwrapInboundIn(data)
            self.logger.info(
                "\(buffer.hexDump(format: .detailed))", 
                metadata: ["direction": "incoming"]
            )
        }
        context.fireChannelRead(data)
    }

    func write(
        context: ChannelHandlerContext, 
        data: NIOAny,
        promise: EventLoopPromise<Void>?
    ) {
        if self.shouldLog {
            let buffer = self.unwrapOutboundIn(data)
            self.logger.info(
                "\(buffer.hexDump(format: .detailed))", 
                metadata: ["direction": "outgoing"]
            )
        }
        context.write(data, promise: promise)
    }
}
#endif
