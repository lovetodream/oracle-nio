//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
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

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

#if canImport(Network)
    import NIOTransportServices
#endif

#if DistributedTracingSupport
    import Tracing
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
/// You can now use your configuration to establish a connection using ``OracleConnection/connect(on:configuration:id:logger:)``.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleConnection", slice: "connect")
///
/// ## Usage
///
/// Now you can use the connection to run queries on your database using
/// ``OracleConnection/execute(_:options:logger:file:line:)->OracleRowSequence``.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleConnection", slice: "use")
///
/// After you're done, close the connection with ``OracleConnection/close()``.
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

    var closeFuture: EventLoopFuture<Void> { self.channel.closeFuture }
    var eventLoop: EventLoop { self.channel.eventLoop }

    public var isClosed: Bool {
        !self.channel.isActive
    }

    public let id: ID

    /// The connection's session ID (SID).
    public let sessionID: Int
    let serialNumber: Int
    /// The version of the Oracle server, the connection is established to.
    public let serverVersion: OracleVersion

    @usableFromInline
    static let noopLogger = Logger(label: "oracle-nio.noop-logger") { _ in
        SwiftLogNoOpLogHandler()
    }

    #if DistributedTracingSupport
        let tracer: (any Tracer)?
    #endif

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
        #if DistributedTracingSupport
            self.tracer = configuration.tracing.tracer
        #endif
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
                let tracer = OracleTraceHandler(
                    connectionID: connectionID,
                    logger: Logger(label: "oracle-nio.network-tracing")
                )
                try channel.pipeline.syncOperations.addHandler(tracer)
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
        var mutableLogger = logger
        mutableLogger[oracleMetadataKey: .connectionID] = "\(connectionID)"
        let logger = mutableLogger

        return eventLoop.flatSubmit {
            let connectFuture: EventLoopFuture<Channel>

            switch configuration.endpointInfo {
            case .configureChannel(let channel):
                guard channel.isActive else {
                    return eventLoop.makeFailedFuture(
                        OracleSQLError.connectionError(
                            underlying: ChannelError.alreadyClosed
                        )
                    )
                }
                connectFuture = eventLoop.makeSucceededFuture(channel)
            case .connectTCP(let host, let port):
                connectFuture = makeBootstrap(on: eventLoop, configuration: configuration)
                    .connect(host: host, port: port)
            }

            return connectFuture.flatMap { channel -> EventLoopFuture<OracleConnection> in
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
    private func _close() -> EventLoopFuture<Void> {
        guard !self.isClosed else {
            return self.eventLoop.makeSucceededVoidFuture()
        }

        self.channel.close(mode: .all, promise: nil)
        return self.closeFuture
    }

    /// Sends a ping to the database server.
    private func _ping() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.ping(promise), promise: nil)
        return promise.futureResult
    }

    /// Sends a commit to the database server.
    private func _commit() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.commit(promise), promise: nil)
        return promise.futureResult
    }

    /// Sends a rollback to the database server.
    private func _rollback() -> EventLoopFuture<Void> {
        let promise = self.eventLoop.makePromise(of: Void.self)
        self.channel.write(OracleTask.rollback(promise), promise: nil)
        return promise.futureResult
    }
}

// MARK: Async/Await Interface

extension OracleConnection: OracleConnectionProtocol {

    /// Creates a new connection to an Oracle server.
    ///
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` the connection shall be created on.
    ///   - configuration: A ``Configuration`` that shall be used for the connection.
    ///   - connectionID: An `Int` id, used for metadata logging.
    ///   - logger: A logger to log background events into. Defaults to logging disabled
    /// - Returns: An established ``OracleConnection`` asynchronously that can be used to run
    ///            queries.
    public static func connect(
        on eventLoop: EventLoop = OracleConnection.defaultEventLoopGroup.any(),
        configuration: OracleConnection.Configuration,
        id connectionID: ID,
        logger: Logger = OracleConnection.noopLogger
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
        try await self._close().get()
    }

    /// Sends a ping to the database server.
    public func ping() async throws {
        try await self._ping().get()
    }

    /// Sends a commit to the database server.
    public func commit() async throws {
        try await self._commit().get()
    }

    /// Sends a rollback to the database server.
    public func rollback() async throws {
        try await self._rollback().get()
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
        logger: Logger = OracleConnection.noopLogger,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        #if DistributedTracingSupport
            let span = self.tracer?.startSpan(statement.keyword, ofKind: .client)
            span?.updateAttributes { attributes in
                self.applyCommonAttributes(to: &attributes, querySummary: statement.summary, queryText: statement.sql)
            }
            defer { span?.end() }
        #endif

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = try StatementContext(
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
            #if DistributedTracingSupport
                span?.recordError(error)
                span?.setStatus(SpanStatus(code: .error))
                span?.attributes[self.configuration.tracing.attributeNames.errorType] = error.code.description
                if let number = error.serverInfo?.number {
                    span?.attributes[self.configuration.tracing.attributeNames.databaseResponseStatusCode] =
                        "ORA-\(String(number, padding: 5))"
                }
            #endif
            throw error  // rethrow with more metadata
        }
    }

    /// Execute a prepared statement.
    /// - Parameters:
    ///   - statement: The statement to be executed.
    ///   - options: A bunch of parameters to optimize the statement in different ways.
    ///              Normally this can be ignored, but feel free to experiment based on your needs.
    ///              Every option and its impact is documented.
    ///   - logger: The `Logger` to log statement related background events into. Defaults to logging disabled.
    ///   - file: The file, the statement was started in. Used for better error reporting.
    ///   - line: The line, the statement was started in. Used for better error reporting.
    /// - Returns: An async sequence of `Row`s. The result sequence can be discarded if the statement has no result.
    @discardableResult
    public func execute<Statement: OraclePreparedStatement, Row>(
        _ statement: Statement,
        options: StatementOptions = .init(),
        logger: Logger = OracleConnection.noopLogger,
        file: String = #fileID, line: Int = #line
    ) async throws -> AsyncThrowingMapSequence<OracleRowSequence, Row> where Row == Statement.Row {
        let sendableStatement = try OracleStatement(
            unsafeSQL: Statement.sql, binds: statement.makeBindings())
        let stream: OracleRowSequence = try await execute(
            sendableStatement, options: options, logger: logger, file: file, line: line)
        return stream.map { try statement.decodeRow($0) }
    }

    func execute(
        cursor: Cursor,
        options: StatementOptions = .init(),
        logger: Logger,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        #if DistributedTracingSupport
            let span = self.tracer?.startSpan("CURSOR", ofKind: .client)
            span?.updateAttributes { attributes in
                self.applyCommonAttributes(
                    to: &attributes,
                    querySummary: "CURSOR",
                    queryText: "CURSOR \(cursor.describeInfo.columns.map(\.name).joined(separator: ", "))"
                )
            }
            defer { span?.end() }
        #endif

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
            #if DistributedTracingSupport
                span?.recordError(error)
                span?.setStatus(SpanStatus(code: .error))
                span?.attributes[self.configuration.tracing.attributeNames.errorType] = error.code.description
                if let number = error.serverInfo?.number {
                    span?.attributes[self.configuration.tracing.attributeNames.databaseResponseStatusCode] =
                        "ORA-\(String(number, padding: 5))"
                }
            #endif
            throw error  // rethrow with more metadata
        }
    }

    /// Runs a transaction for the provided `closure`.
    ///
    /// The function lends the connection to the user provided closure. The user can modify the database as they wish.
    /// If the user provided closure returns successfully, the function will attempt to commit the changes by running a
    /// `COMMIT` query against the database. If the user provided closure throws an error, the function will attempt to
    /// rollback the changes made within the closure.
    ///
    /// - Parameters:
    ///   - logger: The `Logger` to log into for the transaction. Defaults to logging disabled.
    ///   - file: The file, the transaction was started in. Used for better error reporting.
    ///   - line: The line, the transaction was started in. Used for better error reporting.
    ///   - closure: The user provided code to modify the database. Use the provided connection to run queries.
    ///              The connection must stay in the transaction mode. Otherwise this method will throw!
    /// - Returns: The closure's return value.
    public func withTransaction<Result>(
        logger: Logger = OracleConnection.noopLogger,
        file: String = #file,
        line: Int = #line,
        isolation: isolated (any Actor)? = #isolation,
        _ closure: (inout sending OracleTransactionConnection) async throws -> sending Result
    ) async throws(OracleTransactionError) -> sending Result {
        var closureHasFinished: Bool = false
        do {
            var conn = OracleTransactionConnection(self)
            let value = try await closure(&conn)
            closureHasFinished = true
            try await self.commit()
            return value
        } catch {
            var transactionError = OracleTransactionError(file: file, line: line)
            if !closureHasFinished {
                transactionError.closureError = error
            } else {
                transactionError.commitError = error
            }
            do {
                try await self.rollback()
            } catch {
                transactionError.rollbackError = error
            }

            throw transactionError
        }
    }
}

extension OracleConnection {
    /// Returns the default `EventLoopGroup` singleton, automatically selecting the best for the
    /// platform.
    ///
    /// This will select the concrete `EventLoopGroup` depending on which platform this is running on.
    @usableFromInline
    static var defaultEventLoopGroup: EventLoopGroup {
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

#if DistributedTracingSupport
    extension OracleConnection {
        @usableFromInline
        func applyCommonAttributes(
            to attributes: inout SpanAttributes,
            querySummary: String,
            queryText: String
        ) {
            // TODO: check if we can get |database_name and |instance_name without roundtrip, maybe via config?
            attributes[self.configuration.tracing.attributeNames.databaseNamespace] =
                "\(configuration.service.serviceName)"
            attributes[self.configuration.tracing.attributeNames.databaseQuerySummary] = querySummary
            attributes[self.configuration.tracing.attributeNames.databaseQueryText] = queryText
            attributes[self.configuration.tracing.attributeNames.serverAddress] = configuration.host
            attributes[self.configuration.tracing.attributeNames.serverPort] = configuration.port
        }
    }
#endif
