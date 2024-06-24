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
    struct DataTypes: PayloadDecodable, Sendable, Hashable {
        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.DataTypes {
            while true {
                if try buffer.throwingReadInteger(as: UInt16.self) == 0 {
                    break
                }

                if try buffer.throwingReadInteger(as: UInt16.self) != 0 {
                    buffer.moveReaderIndex(forwardBy: 4)
                }
            }

            return .init()
        }
    }
}
