// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore

extension OracleBackendMessage {
    struct Status: PayloadDecodable, Hashable {
        let callStatus: UInt32
        let endToEndSequenceNumber: UInt16?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
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
