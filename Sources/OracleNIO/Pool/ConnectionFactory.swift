import Logging
import NIOConcurrencyHelpers
import NIOCore

final class ConnectionFactory: Sendable {

    struct ConfigCache: Sendable {
        var config: OracleClient.Configuration
    }

    let configBox: NIOLockedValueBox<ConfigCache>

    let eventLoopGroup: any EventLoopGroup

    let logger: Logger

    init(
        config: OracleClient.Configuration,
        eventLoopGroup: any EventLoopGroup,
        logger: Logger
    ) {
        self.configBox = NIOLockedValueBox(ConfigCache(config: config))
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    func makeConnection(_ connectionID: OracleConnection.ID, pool: OracleClient.Pool) async throws -> OracleConnection {
        fatalError("TODO: implement pooled connections (DRCP)")
    }
}
