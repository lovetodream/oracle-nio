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

import NIOCore

import struct Foundation.UUID

extension OracleBackendMessage {
    struct Accept: PayloadDecodable, Hashable {
        var newCapabilities: Capabilities

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.Accept {
            let protocolVersion =
                try buffer.throwingReadInteger(as: UInt16.self)

            if protocolVersion < Constants.TNS_VERSION_MIN_ACCEPTED {
                throw OracleSQLError.serverVersionNotSupported
            }

            let protocolOptions =
                try buffer.throwingReadInteger(as: UInt16.self)

            buffer.moveReaderIndex(forwardBy: 20)
            let sdu = try buffer.throwingReadInteger(as: UInt32.self)

            var caps = context.capabilities
            let flags: UInt32
            if protocolVersion >= Constants.TNS_VERSION_MIN_OOB_CHECK {
                buffer.moveReaderIndex(forwardBy: 5)
                flags = try buffer.throwingReadInteger(as: UInt32.self)
            } else {
                flags = 0
            }

            caps.sdu = sdu
            caps.adjustForProtocol(
                version: protocolVersion, options: protocolOptions, flags: flags
            )

            return .init(newCapabilities: caps)
        }
    }
}
