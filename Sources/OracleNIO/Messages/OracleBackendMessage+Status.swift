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
    struct Status: PayloadDecodable, Hashable {
        let callStatus: UInt32
        let endToEndSequenceNumber: UInt16?

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.Status {
            let callStatus = try buffer.throwingReadUB4()
            let endToEndSequenceNumber = buffer.readUB2()
            return .init(
                callStatus: callStatus,
                endToEndSequenceNumber: endToEndSequenceNumber
            )
        }
    }
}
