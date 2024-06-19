//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@preconcurrency import Dispatch
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSL

import class Foundation.ProcessInfo

#if canImport(Network)
    import NIOTransportServices
#endif

/// An Oracle connection. Use it to run queries against an Oracle server.
///
/// ## Creating a connection
///
/// You create a ``OracleConnection`` by first creating a ``OracleConnection/Configuration``
/// struct that you can use to configure the connection.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleConnection", slice: "configuration")
///
/// You can now use your configuration to establish a connection using ``OracleConnection/connect(on:configuration:id:)``.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleConnection", slice: "connect")
///
/// ## Usage
///
/// Now you can use the connection to run queries on your database using
/// ``OracleConnection/execute(_:options:logger:file:line:)``.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleConnection", slice: "use")
///
/// After you're done, close the connection with ``OracleConnection/close()-4ny0f``.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleConnection", slice: "close")
///
/// - Note: If you want to create long running connections, e.g. in a HTTP Server, ``OracleClient``
/// is preferred over ``OracleConnection``. It maintans a pool of connections for you.
///
public final class OracleConnection: Sendable {
    /// A Oracle connection ID, used exclusively for logging.
    public typealias ID = Int

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

    /// The connection's session ID (SID).
    public let sessionID: Int
    let serialNumber: Int
    /// The version of the Oracle server, the connection is established to.
    public let serverVersion: OracleVersion

    static let noopLogger = Logger(label: "oracle-nio.noop-logger") { _ in
        SwiftLogNoOpLogHandler()
    }

    private init(
        configuration: OracleConnection.Configuration,
        channel: Channel,
        connectionID: ID,
        logger: Logger,
        sessionID: Int,
        serialNumber: Int,
        serverVersion: OracleVersion
    ) {
        self.id = connectionID
        self.configuration = configuration
        self.logger = logger
        self.channel = channel
        self.sessionID = sessionID
        self.serialNumber = serialNumber
        self.serverVersion = serverVersion
    }
    deinit {
        assert(isClosed, "OracleConnection deinitialized before being closed.")
    }

    private static func start(
        configuration: Configuration,
        connectionID: OracleConnection.ID,
        channel: Channel,
        logger: Logger
    ) -> EventLoopFuture<OracleConnection> {
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
                return channel.eventLoop.makeFailedFuture(error)
            }
        }

        let frontendMessageHandler = OracleFrontendMessagePostProcessor()
        let channelHandler = OracleChannelHandler(
            configuration: configuration,
            logger: logger,
            sslHandler: sslHandler,
            postprocessor: frontendMessageHandler
        )

        let eventHandler = OracleEventsHandler(logger: logger)

        // 2. add handlers

        do {
            #if DEBUG
                // This is very useful for sending hex dumps to Oracle to analyze
                // problems in the driver.
                let tracer = Logger(label: "oracle-nio.network-tracing")
                try channel.pipeline.syncOperations
                    .addHandler(DebugLogHandler(connectionID: connectionID, logger: tracer))
            #endif
            try channel.pipeline.syncOperations.addHandler(eventHandler)
            try channel.pipeline.syncOperations
                .addHandler(channelHandler, position: .before(eventHandler))
            try channel.pipeline.syncOperations
                .addHandler(frontendMessageHandler, position: .before(channelHandler))
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }

        // 3. wait for startup future to succeed.

        return eventHandler.startupDoneFuture
            .flatMapError { error in
                // in case of a startup error, the connection must be closed and
                // after that the originating error should be surfaced
                channel.closeFuture.flatMapThrowing { _ in
                    throw error
                }
            }
            .map { context in
                OracleConnection(
                    configuration: configuration,
                    channel: channel,
                    connectionID: connectionID,
                    logger: logger,
                    sessionID: context.sessionID,
                    serialNumber: context.serialNumber,
                    serverVersion: context.version
                )
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
    private static func connect(
        on eventLoop: EventLoop = OracleConnection.defaultEventLoopGroup.any(),
        configuration: OracleConnection.Configuration,
        id connectionID: ID,
        logger: Logger
    ) -> EventLoopFuture<OracleConnection> {
        var logger = logger
        logger[oracleMetadataKey: .connectionID] = "\(connectionID)"

        return eventLoop.flatSubmit { [logger] in
            makeBootstrap(on: eventLoop, configuration: configuration)
                .connect(host: configuration.host, port: configuration.port)
                .flatMap { channel -> EventLoopFuture<OracleConnection> in
                    return OracleConnection.start(
                        configuration: configuration,
                        connectionID: connectionID,
                        channel: channel,
                        logger: logger
                    )
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
                return
                    tsBootstrap
                    .connectTimeout(configuration.options.connectTimeout)
            }
        #endif

        guard let bootstrap = ClientBootstrap(validatingGroup: eventLoop) else {
            fatalError("No matching bootstrap found")
        }
        return
            bootstrap
            .connectTimeout(configuration.options.connectTimeout)
            .channelOption(
                ChannelOptions
                    .socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1
            )
            .channelOption(
                ChannelOptions
                    .socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
    }

    /// Closes the connection to the database server synchronously.
    ///
    /// - Note: This method blocks the thread indefinitely, prefer using ``close()-4ny0f``.
    @available(
        *, noasync, message: "syncClose() can block indefinitely, prefer close()",
        renamed: "close()"
    )
    public func syncClose() throws {
        guard !self.isClosed else { return }

        if let eventLoop = MultiThreadedEventLoopGroup.currentEventLoop {
            preconditionFailure(
                """
                syncClose() must not be called when on an NIO EventLoop.
                Calling syncClose() on any EventLoop can lead to deadlocks.
                Current eventLoop: \(eventLoop)
                """)
        }

        self.channel.close(mode: .all, promise: nil)

        func close(queue: DispatchQueue, _ callback: @escaping @Sendable (Error?) -> Void) {
            self.closeFuture.whenComplete { result in
                let error: Error? =
                    switch result {
                    case .failure(let error): error
                    case .success: nil
                    }
                queue.async {
                    callback(error)
                }
            }
        }

        let errorStorage = NIOLockedValueBox<Error?>(nil)
        let continuation = DispatchWorkItem {}
        close(queue: DispatchQueue(label: "oracle-nio.close-connection-\(self.id)")) { error in
            if let error {
                errorStorage.withLockedValue { $0 = error }
            }
            continuation.perform()
        }
        continuation.wait()
        try errorStorage.withLockedValue { error in
            if let error { throw error }
        }
    }

    /// Closes the connection to the database server.
    private func close() -> EventLoopFuture<Void> {
        guard !self.isClosed else {
            return self.eventLoop.makeSucceededVoidFuture()
        }

        self.channel.close(mode: .all, promise: nil)
        return self.closeFuture
    }

    /// Sends a ping to the database server.
    private func ping() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.ping(promise), promise: nil)
        return promise.futureResult
    }

    /// Sends a commit to the database server.
    private func commit() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.commit(promise), promise: nil)
        return promise.futureResult
    }

    /// Sends a rollback to the database server.
    private func rollback() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.rollback(promise), promise: nil)
        return promise.futureResult
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
    /// - Returns: An established ``OracleConnection`` asynchronously that can be used to run
    ///            queries.
    public static func connect(
        on eventLoop: EventLoop = OracleConnection.defaultEventLoopGroup.any(),
        configuration: OracleConnection.Configuration,
        id connectionID: ID
    ) async throws -> OracleConnection {
        try await self.connect(
            on: eventLoop,
            configuration: configuration,
            id: connectionID,
            logger: self.noopLogger
        )
    }

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
        var attempts = configuration.retryCount
        while attempts > 0 {
            attempts -= 1
            do {
                return try await self.connect(
                    on: eventLoop,
                    configuration: configuration,
                    id: connectionID,
                    logger: logger
                ).get()
            } catch let error as CancellationError {
                throw error
            } catch {
                // only final attempt throws the error
            }
            if configuration.retryDelay > 0 {
                try await Task.sleep(for: .seconds(configuration.retryDelay))
            }
        }
        return try await self.connect(
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

    /// Run a statement on the Oracle server the connection is connected to.
    ///
    /// - Parameters:
    ///   - statement: The ``OracleStatement`` to run.
    ///   - options: A bunch of parameters to optimize the statement in different ways.
    ///              Normally this can be ignored, but feel free to experiment based on your needs.
    ///              Every option and its impact is documented.
    ///   - logger: The `Logger` to log statement related background events into. Defaults to logging disabled.
    ///   - file: The file, the statement was started in. Used for better error reporting.
    ///   - line: The line, the statement was started in. Used for better error reporting.
    /// - Returns: A ``OracleRowSequence`` containing the rows the server sent as the statement
    ///            result. The result sequence can be discarded if the statement has no result.
    @discardableResult
    public func execute(
        _ statement: OracleStatement,
        options: StatementOptions = .init(),
        logger: Logger? = nil,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger ?? Self.noopLogger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = StatementContext(
            statement: statement,
            options: options,
            logger: logger,
            promise: promise
        )

        self.channel.write(OracleTask.statement(context), promise: nil)

        do {
            return try await promise.futureResult
                .map({ $0.asyncSequence() })
                .get()
        } catch var error as OracleSQLError {
            error.file = file
            error.line = line
            error.statement = statement
            throw error  // rethrow with more metadata
        }
    }

    func execute(
        cursor: Cursor,
        options: StatementOptions = .init(),
        logger: Logger? = nil,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger ?? Self.noopLogger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = StatementContext(
            cursor: cursor,
            options: options,
            logger: logger,
            promise: promise
        )

        self.channel.write(OracleTask.statement(context), promise: nil)

        do {
            return try await promise.futureResult
                .map({ $0.asyncSequence() })
                .get()
        } catch var error as OracleSQLError {
            error.file = file
            error.line = line
            throw error  // rethrow with more metadata
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

        init(connectionID: OracleConnection.ID, logger: Logger, shouldLog: Bool? = nil) {
            if let shouldLog {
                self.shouldLog = shouldLog
            } else {
                let envValue =
                    getenv("ORANIO_TRACE_PACKETS")
                    .flatMap { String(cString: $0) }
                    .flatMap(Int.init) ?? 0
                self.shouldLog = envValue != 0
            }
            var logger = logger
            logger[oracleMetadataKey: .connectionID] = "\(connectionID)"
            self.logger = logger
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if self.shouldLog {
                let buffer = self.unwrapInboundIn(data)
                self.logger.info(
                    "\n\(buffer.hexDump(format: .detailed))",
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
                    "\n\(buffer.hexDump(format: .detailed))",
                    metadata: ["direction": "outgoing"]
                )
            }
            context.write(data, promise: promise)
        }
    }
#endif
