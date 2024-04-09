// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore

extension ByteBuffer {
    /// Internally writes a UInt8 to the buffer.
    mutating func writeOracleMessageID(
        _ messageID: OracleBackendMessage.MessageID
    ) {
        self.writeInteger(messageID.rawValue)
    }
}
