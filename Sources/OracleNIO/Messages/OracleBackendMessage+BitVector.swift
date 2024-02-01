// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore

extension OracleBackendMessage {
    struct BitVector: PayloadDecodable, Sendable, Hashable {
        let columnsCountSent: UInt16
        let bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.BitVector {
            let columnsCountSent = try buffer.throwingReadUB2()
            guard let columnsCount = context.columnsCount else {
                preconditionFailure(
                    "How can we receive a bit vector without an active query?"
                )
            }
            var length = Int((Double(columnsCount) / 8.0).rounded(.down))
            if columnsCount % 8 > 0 {
                length += 1
            }
            let bitVector = buffer.readBytes(length: length)
            return .init(
                columnsCountSent: UInt16(columnsCountSent),
                bitVector: bitVector
            )
        }
    }
}
