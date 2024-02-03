// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import NIOConcurrencyHelpers
import struct Foundation.UUID

final class ConnectionCookieManager: Sendable {
    static let shared = ConnectionCookieManager()

    private let store: NIOLockedValueBox<[String: ConnectionCookie]> = .init([:])

    private init() { }

    func get(
        by uuid: UUID, description: Description
    ) -> ConnectionCookie? {
        let suffix: String
        switch description.service {
        case .serviceName(let serviceName):
            suffix = serviceName
        case .sid(let sid):
            suffix = sid
        }
        let key = uuid.uuidString + suffix
        return self.store.withLockedValue { $0[key] }
    }

    func set() {
        // TOOD
    }
}

struct ConnectionCookie: Sendable {
    var protocolVersion: UInt8
    var serverBanner: ByteBuffer
    var charsetID: UInt16
    var nationalCharsetID: UInt16
    var flags: UInt8
    var compileCapabilities: ByteBuffer
    var runtimeCapabilities: ByteBuffer
    var populated: Bool
}
