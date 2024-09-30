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

import Logging
import _ConnectionPoolModule

final class OracleClientMetrics: ConnectionPoolObservabilityDelegate {
    typealias ConnectionID = OracleConnection.ID

    let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func startedConnecting(id: OracleConnection.ID) {
        self.logger.debug(
            "Creating new connection",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    /// A connection attempt failed with the given error. After some period of
    /// time ``startedConnecting(id:)`` may be called again.
    func connectFailed(id: OracleConnection.ID, error: Error) {
        self.logger.debug(
            "Connection creation failed",
            metadata: [
                .connectionID: "\(id)",
                .error: "\(String(reflecting: error))",
            ])
    }

    func connectSucceeded(id: OracleConnection.ID) {
        self.logger.debug(
            "Connection established",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    /// The utlization of the connection changed; a stream may have been used, returned or the
    /// maximum number of concurrent streams available on the connection changed.
    func connectionLeased(id: ConnectionID) {
        self.logger.debug(
            "Connection leased",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    func connectionReleased(id: ConnectionID) {
        self.logger.debug(
            "Connection released",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    func keepAliveTriggered(id: ConnectionID) {
        self.logger.debug(
            "run ping pong",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    func keepAliveSucceeded(id: ConnectionID) {}

    func keepAliveFailed(id: OracleConnection.ID, error: Error) {}

    /// The remote peer is quiescing the connection: no new streams will be created on it. The
    /// connection will eventually be closed and removed from the pool.
    func connectionClosing(id: ConnectionID) {
        self.logger.debug(
            "Close connection",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    /// The connection was closed. The connection may be established again in the future (notified
    /// via ``startedConnecting(id:)``).
    func connectionClosed(id: ConnectionID, error: Error?) {
        self.logger.debug(
            "Connection closed",
            metadata: [
                .connectionID: "\(id)"
            ])
    }

    func requestQueueDepthChanged(_ newDepth: Int) {

    }

    func connectSucceeded(id: OracleConnection.ID, streamCapacity: UInt16) {

    }

    func connectionUtilizationChanged(
        id: OracleConnection.ID, streamsUsed: UInt16, streamCapacity: UInt16
    ) {

    }
}
