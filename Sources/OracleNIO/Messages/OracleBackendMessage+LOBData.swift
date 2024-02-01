// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore

extension OracleBackendMessage {
    struct LOBData: PayloadDecodable, Hashable {
        let buffer: ByteBuffer

        static func decode(
            from buffer: inout ByteBuffer, 
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.LOBData {
            let buffer = try buffer.readOracleSpecificLengthPrefixedSlice()
            return .init(buffer: buffer)
        }
    }
}
