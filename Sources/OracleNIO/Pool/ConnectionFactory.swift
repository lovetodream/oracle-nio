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

import Atomics
import Logging
import NIOConcurrencyHelpers
import NIOCore

import struct Foundation.Data
import struct Foundation.UUID

final class ConnectionFactory: Sendable {

    struct ConfigCache: Sendable {
        var config: OracleConnection.Configuration
    }

    let configBox: NIOLockedValueBox<ConfigCache>
    let drcp: Bool

    let eventLoopGroup: any EventLoopGroup

    let logger: Logger

    /// `true` if the initial connection has been successfully established.
    let isBootstrapped = ManagedAtomic(false)
    let bootstrapLock = NIOLock()


    init(
        config: OracleConnection.Configuration,
        drcp: Bool,
        eventLoopGroup: any EventLoopGroup,
        logger: Logger
    ) {
        self.configBox = NIOLockedValueBox(ConfigCache(config: config))
        self.drcp = drcp
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    func makeConnection(_ connectionID: OracleConnection.ID, pool: OracleClient.Pool) async throws
        -> OracleConnection
    {
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
        if !self.drcp {
            return self.configBox.withLockedValue { $0.config }
        }

        var config = self.configBox.withLockedValue {
            if $0.config.cclass == nil {
                $0.config.cclass = "DBNIO:\(Self.b64UUID())"
            }
            return $0.config
        }

        // - add drcp release message to channel closing

        config.purity = newPool ? .new : .`self`
        if !newPool {
            config.serverType = "pooled"
            config.drcpEnabled = true
        }

        return config
    }

    static func b64UUID() -> String {
        let uuid = UUID().uuid
        let raw = [
            uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15,
        ]
        return Data(raw).base64EncodedString()
    }
}
