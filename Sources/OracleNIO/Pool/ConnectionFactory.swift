import struct Foundation.Data
import struct Foundation.UUID
import Atomics
import Logging
import NIOConcurrencyHelpers
import NIOCore

final class ConnectionFactory: Sendable {

    struct ConfigCache: Sendable {
        var config: OracleConnection.Configuration
    }

    let configBox: NIOLockedValueBox<ConfigCache>

    let eventLoopGroup: any EventLoopGroup

    let logger: Logger

    /// `true` if the initial connection has been successfully established.
    let isBootstrapped = ManagedAtomic(false)
    let bootstrapLock = NIOLock()

    init(
        config: OracleConnection.Configuration,
        eventLoopGroup: any EventLoopGroup,
        logger: Logger
    ) {
        self.configBox = NIOLockedValueBox(ConfigCache(config: config))
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    func makeConnection(_ connectionID: OracleConnection.ID, pool: OracleClient.Pool) async throws -> OracleConnection {
        let new: Bool
        self.bootstrapLock.lock()
        if self.isBootstrapped.load(ordering: .relaxed) {
            self.bootstrapLock.unlock()
            new = false
        } else {
            defer { self.bootstrapLock.unlock() }
            new = true
        }

        let configuration = self.makeConfiguration(newPool: new)

        var connectionLogger = self.logger
        connectionLogger[oracleMetadataKey: .connectionID] = "\(connectionID)"

        return try await OracleConnection.connect(
            on: self.eventLoopGroup.any(),
            configuration: configuration,
            id: connectionID,
            logger: connectionLogger
        )
    }

    func makeConfiguration(newPool: Bool) -> OracleConnection.Configuration {
        var config = self.configBox.withLockedValue {
            if $0.config.cclass == nil {
                $0.config.cclass = "DBNIO:\(Self.b64UUID())"
            }
            return $0.config
        }


        // - set purity: NEW if this is the pool's first connection, otherwise SELF
        // - set cclass
        // - set drcpEnabled
        // - add drcp specific params to messages
        // - add drcp release message to channel closing

        config.purity = newPool ? .new : .`self`
        config.serverType = "pooled"
        config.drcpEnabled = true
        config.cclass = "DBNIO"

        return config
    }

    static func b64UUID() -> String {
        let uuid = UUID().uuid
        let raw = [
            uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        ]
        return Data(raw).base64EncodedString()
    }
}

