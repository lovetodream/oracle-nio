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

import Atomics
import Logging
import NIOCore
import ServiceLifecycle
import _ConnectionPoolModule

/// A Oracle client that is backed by an underlying connection pool. Use ``Options`` to change the
/// client's behavior and ``OracleConnection/Configuration`` to configure its connections.
///
/// ## Creating a client
///
/// You create a ``OracleClient`` by first creating a ``OracleConnection/Configuration``
/// struct that you can use to configure the connections, established by the client.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleClient", slice: "configuration")
///
/// You can now create a client with your configuration.
///
/// @Snippet(path: "oracle-nio/Snippets/OracleClient", slice: "makeClient")
///
/// ## Running a client
///
/// ``OracleClient`` relies on structured concurrency. Because of this, it needs a task in which it can
/// schedule all the background work it needs to do in order to manage connections on the users behave.
/// For this reason, developers must provide a task to the client by scheduling the client's run method
/// in a long running task:
///
/// @Snippet(path: "oracle-nio/Snippets/OracleClient", slice: "run")
///
/// ``OracleClient`` can not lease connections, if its ``run()`` method isn't active. Cancelling
/// the ``run()`` method is equivalent to closing the client. Once a client's ``run()`` method has
/// been cancelled, executing queries will fail.
public final class OracleClient: Sendable, Service {
    /// Describes general client behavior options. Those settings are considered advanced options.
    public struct Options: Sendable {
        /// A keep-alive behavior for Oracle connections. The ``frequency`` defines after which time an idle
        /// connection shall run a keep-alive ping.
        public struct KeepAliveBehavior: Sendable {
            /// The amount of time that shall pass before an idle connection runs a keep-alive `ping`.
            public var frequency: Duration

            /// Create a new `KeepAliveBehavior`.
            /// - Parameters:
            ///   - frequency: The amount of time that shall pass before an idle connection runs
            ///                a keep-alive `statement`. Defaults to `30` seconds.
            public init(frequency: Duration = .seconds(30)) {
                self.frequency = frequency
            }
        }

        /// The minimum number of connections that the client shall keep open at any time, even if there is no
        /// demand. Default to `0`.
        ///
        /// If the open connection count becomes less than ``minimumConnections`` new connections
        /// are created immidiatly. Must be greater or equal to zero and less than ``maximumConnections``.
        ///
        /// Idle connections are kept alive using the ``keepAliveBehavior``.
        public var minimumConnections: Int = 0

        /// The maximum number of connections that the client may open to the server at any time. Must be greater
        /// than ``minimumConnections``. Defaults to `20` connections.
        ///
        /// Connections, that are created in response to demand are kept alive for the ``connectionIdleTimeout``
        /// before they are dropped.
        public var maximumConnections: Int = 20

        /// The maximum amount time that a connection that is not part of the ``minimumConnections`` is kept
        /// open without being leased. Defaults to `60` seconds.
        public var connectionIdleTimeout: Duration = .seconds(60)

        /// The ``KeepAliveBehavior-swift.struct`` to ensure that the underlying tcp-connection is still active
        /// for idle connections. `Nil` means that the client shall not run keep alive queries to the server. Defaults to a
        /// keep alive ping every `30` seconds.
        public var keepAliveBehavior: KeepAliveBehavior? = KeepAliveBehavior()

        /// Create an options structure with default values.
        ///
        /// Most users should not need to adjust the defaults.
        public init() {}
    }

    typealias Pool = ConnectionPool<
        OracleConnection,
        OracleConnection.ID,
        ConnectionIDGenerator,
        ConnectionRequest<OracleConnection>,
        ConnectionRequest.ID,
        OracleKeepAliveBehavior,
        OracleClientMetrics,
        ContinuousClock
    >

    let pool: Pool
    let factory: ConnectionFactory
    let runningAtomic = ManagedAtomic(false)
    let backgroundLogger: Logger

    /// Creates a new ``OracleClient``. Don't forget to run ``run()`` the client in a long running task.
    /// - Parameters:
    ///   - configuration: The client's configuration. See ``OracleConnection/Configuration``
    ///   - options: The pool configuration. See ``Options``
    ///   - drcp: Whether the database server supports `DRCP` (Database Resident Connection Pooling) or not.
    ///           Defaults to `true`. More information on `DRCP` can be found
    ///           [here](https://www.oracle.com/docs/tech/drcp-technical-brief.pdf).
    ///   - eventLoopGroup: The underlying NIO `EventLoopGroup`. Defaults to ``defaultEventLoopGroup``.
    public convenience init(
        configuration: OracleConnection.Configuration,
        options: Options = .init(),
        drcp: Bool = true,
        eventLoopGroup: any EventLoopGroup = OracleClient.defaultEventLoopGroup
    ) {
        self.init(
            configuration: configuration,
            options: options,
            drcp: drcp,
            eventLoopGroup: eventLoopGroup,
            backgroundLogger: OracleConnection.noopLogger
        )
    }

    /// Creates a new ``OracleClient``. Don't forget to run ``run()`` the client in a long running task.
    /// - Parameters:
    ///   - configuration: The client's configuration. See ``OracleConnection/Configuration``
    ///   - options: The pool configuration. See ``Options``
    ///   - drcp: Whether the database server supports `DRCP` (Database Resident Connection Pooling) or not.
    ///           Defaults to `true`. More information on `DRCP` can be found
    ///           [here](https://www.oracle.com/docs/tech/drcp-technical-brief.pdf).
    ///   - eventLoopGroup: The underlying NIO `EventLoopGroup`. Defaults to ``defaultEventLoopGroup``.
    ///   - backgroundLogger: A `swift-log` `Logger` to log background messages to. A copy of this logger is also
    ///                       forwarded to the created connections as a background logger.
    public init(
        configuration: OracleConnection.Configuration,
        options: Options = .init(),
        drcp: Bool = true,
        eventLoopGroup: any EventLoopGroup = OracleClient.defaultEventLoopGroup,
        backgroundLogger: Logger
    ) {
        let factory = ConnectionFactory(
            config: configuration, drcp: drcp, eventLoopGroup: eventLoopGroup,
            logger: backgroundLogger)
        self.factory = factory
        self.backgroundLogger = backgroundLogger

        self.pool = ConnectionPool(
            configuration: .init(options),
            idGenerator: ConnectionIDGenerator(),
            requestType: ConnectionRequest<OracleConnection>.self,
            keepAliveBehavior: .init(options.keepAliveBehavior, logger: backgroundLogger),
            observabilityDelegate: .init(logger: backgroundLogger),
            clock: ContinuousClock(),
            connectionFactory: { connectionID, pool in
                let connection = try await factory.makeConnection(connectionID, pool: pool)

                return ConnectionAndMetadata(connection: connection, maximalStreamsOnConnection: 1)
            })
    }


    /// Lease a connection for the provided `closure`'s lifetime.
    ///
    /// - Parameter closure: A closure that uses the passed `OracleConnection`. The closure **must not** capture
    ///                      the provided `OracleConnection`.
    /// - Returns: The closure's return value.
    public func withConnection<Result>(_ closure: (OracleConnection) async throws -> Result)
        async throws -> Result
    {
        let connection = try await self.leaseConnection()

        defer { self.pool.releaseConnection(connection) }

        return try await closure(connection)
    }


    /// The client's run method. Users must call this function in order to start the client's background task processing
    /// like creating and destroying connections and running timers.
    ///
    /// Calls to ``withConnection(_:)`` will emit a `logger` warning, if ``run()`` hasn't been called previously.
    public func run() async {
        let atomicOp = self.runningAtomic.compareExchange(
            expected: false, desired: true, ordering: .relaxed)
        precondition(!atomicOp.original, "OracleClient.run() should just be called once!")

        await cancelWhenGracefulShutdown {
            await self.pool.run()
        }
    }


    // MARK: - Private Methods -

    private func leaseConnection() async throws -> OracleConnection {
        if !self.runningAtomic.load(ordering: .relaxed) {
            self.backgroundLogger.warning(
                "Trying to lease connection from `OracleClient`, but `OracleClient.run()` hasn't been called yet."
            )
        }
        return try await self.pool.leaseConnection()
    }

    /// Returns the default `EventLoopGroup` singleton, automatically selecting the best for the platform.
    ///
    /// This will select the concrete `EventLoopGroup` depending which platform this is running on.
    public static var defaultEventLoopGroup: EventLoopGroup {
        OracleConnection.defaultEventLoopGroup
    }
}


struct OracleKeepAliveBehavior: ConnectionKeepAliveBehavior {
    let behaviour: OracleClient.Options.KeepAliveBehavior?
    let logger: Logger

    init(_ behaviour: OracleClient.Options.KeepAliveBehavior?, logger: Logger) {
        self.behaviour = behaviour
        self.logger = logger
    }

    var keepAliveFrequency: Duration? {
        self.behaviour?.frequency
    }

    func runKeepAlive(for connection: OracleConnection) async throws {
        try await connection.ping()
    }
}

extension ConnectionPoolConfiguration {
    init(_ options: OracleClient.Options) {
        self = ConnectionPoolConfiguration()
        self.minimumConnectionCount = options.minimumConnections
        self.maximumConnectionSoftLimit = options.maximumConnections
        self.maximumConnectionHardLimit = options.maximumConnections
        self.idleTimeout = options.connectionIdleTimeout
    }
}

extension OracleConnection: PooledConnection {
    public func onClose(_ closure: @escaping @Sendable ((Error)?) -> Void) {
        self.closeFuture.whenComplete { _ in closure(nil) }
    }

    public func close() {
        self.channel.close(mode: .all, promise: nil)
    }
}
