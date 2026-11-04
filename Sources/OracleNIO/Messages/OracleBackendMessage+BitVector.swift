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
        let columnCountSent: UInt16
        let bitVector: [UInt8]

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.BitVector {
            let columnCountSent = try buffer.throwingReadUB2()
            guard let columnCount = context.describeInfo?.columns.count else {
                preconditionFailure(
                    "How can we receive a bit vector without an active statement?"
                )
            }
            var length = Int((Double(columnCount) / 8.0).rounded(.down))
            if columnCount % 8 > 0 {
                length += 1
            }
            let bitVector = try buffer.throwingReadBytes(length: length)
            return .init(
                columnCountSent: UInt16(columnCountSent),
                bitVector: bitVector
            )
        }
    }
}
