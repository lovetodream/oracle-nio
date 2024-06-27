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
    struct BitVector: PayloadDecodable, Sendable, Hashable {
        let columnsCountSent: UInt16
        let bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.BitVector {
            let columnsCountSent = try buffer.throwingReadUB2()
            guard let columnsCount = context.columnsCount else {
                preconditionFailure(
                    "How can we receive a bit vector without an active statement?"
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
