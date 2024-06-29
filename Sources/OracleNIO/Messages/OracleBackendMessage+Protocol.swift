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

extension OracleBackendMessage {
    struct `Protocol`: PayloadDecodable, Hashable {
        var newCapabilities: Capabilities

        static func decode(
            from buffer: inout NIOCore.ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.`Protocol` {
            buffer.moveReaderIndex(forwardBy: 2) // skip protocol array
            while true { // skip server banner
                let c = buffer.readInteger(as: UInt8.self) ?? 0
                if c == 0 { break }
            }

            let charsetID = try buffer.throwingReadInteger(
                endianness: .little, as: UInt16.self
            )
            var capabilities = context.capabilities
            capabilities.charsetID = charsetID

            buffer.moveReaderIndex(forwardBy: 1) // skip server flags
            let elementsCount = try buffer.throwingReadInteger(
                endianness: .little, as: UInt16.self
            )
            if elementsCount > 0 { // skip elements
                buffer.moveReaderIndex(forwardBy: Int(elementsCount) * 5)
            }

            let fdoLength = try Int(buffer.throwingReadInteger(as: UInt16.self))
            guard let fdo = buffer.readBytes(length: fdoLength) else {
                throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                    fdoLength, actual: buffer.readableBytes
                )
            }
            let ix = 6 + fdo[5] + fdo[6]
            capabilities.nCharsetID =
                UInt16((fdo[Int(ix) + 3] << 8) + fdo[Int(ix) + 4])

            let serverCompileCapabilities = try buffer
                .throwingReadOracleSpecificLengthPrefixedSlice()
            capabilities.adjustForServerCompileCapabilities(
                serverCompileCapabilities
            )

            let serverRuntimeCapabilities = try buffer
                .throwingReadOracleSpecificLengthPrefixedSlice()
            capabilities.adjustForServerRuntimeCapabilities(
                serverRuntimeCapabilities
            )

            return .init(newCapabilities: capabilities)
        }
    }
}
