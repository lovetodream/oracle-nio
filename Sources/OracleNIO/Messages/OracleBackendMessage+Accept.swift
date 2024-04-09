// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import struct Foundation.UUID

extension OracleBackendMessage {
    struct Accept: PayloadDecodable, Hashable {
        var newCapabilities: Capabilities

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.Accept {
            let protocolVersion =
                try buffer.throwingReadInteger(as: UInt16.self)
            let protocolOptions =
                try buffer.throwingReadInteger(as: UInt16.self)

            buffer.moveReaderIndex(forwardBy: 20)
            let sdu = try buffer.throwingReadInteger(as: UInt32.self)

            var caps = capabilities
            if protocolVersion >= Constants.TNS_VERSION_MIN_OOB_CHECK {
                buffer.moveReaderIndex(forwardBy: 5)
                let flags = try buffer.throwingReadInteger(as: UInt32.self)
                if (flags & Constants.TNS_ACCEPT_FLAG_FAST_AUTH) != 0 {
                    caps.supportsFastAuth = true
                }
            }

            caps.sdu = sdu
            caps.adjustForProtocol(
                version: protocolVersion, options: protocolOptions
            )

            return .init(newCapabilities: caps)
        }
    }
}
