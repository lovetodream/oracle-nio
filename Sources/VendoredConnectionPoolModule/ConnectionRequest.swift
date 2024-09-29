
public struct ConnectionRequest<Connection: PooledConnection>: ConnectionRequestProtocol {
    public typealias ID = Int

    public var id: ID

    @usableFromInline
    private(set) var continuation: CheckedContinuation<Connection, any Error>

    @inlinable
    init(
        id: Int,
        continuation: CheckedContinuation<Connection, any Error>
    ) {
        self.id = id
        self.continuation = continuation
    }

    public func complete(with result: Result<Connection, ConnectionPoolError>) {
        self.continuation.resume(with: result)
    }
}

fileprivate let requestIDGenerator = VendoredConnectionPoolModule.ConnectionIDGenerator()

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension ConnectionPool where Request == ConnectionRequest<Connection> {
    public convenience init(
        configuration: ConnectionPoolConfiguration,
        idGenerator: ConnectionIDGenerator = VendoredConnectionPoolModule.ConnectionIDGenerator(),
        keepAliveBehavior: KeepAliveBehavior,
        observabilityDelegate: ObservabilityDelegate,
        clock: Clock = ContinuousClock(),
        connectionFactory: @escaping ConnectionFactory
    ) {
        self.init(
            configuration: configuration,
            idGenerator: idGenerator,
            requestType: ConnectionRequest<Connection>.self,
            keepAliveBehavior: keepAliveBehavior,
            observabilityDelegate: observabilityDelegate,
            clock: clock,
            connectionFactory: connectionFactory
        )
    }

    public func leaseConnection() async throws -> Connection {
        let requestID = requestIDGenerator.next()

        let connection = try await withTaskCancellationHandler {
            if Task.isCancelled {
                throw CancellationError()
            }

            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Connection, Error>) in
                let request = Request(
                    id: requestID,
                    continuation: continuation
                )

                self.leaseConnection(request)
            }
        } onCancel: {
            self.cancelLeaseConnection(requestID)
        }

        return connection
    }

    public func withConnection<Result>(_ closure: (Connection) async throws -> Result) async throws -> Result {
        let connection = try await self.leaseConnection()
        defer { self.releaseConnection(connection) }
        return try await closure(connection)
    }
}
