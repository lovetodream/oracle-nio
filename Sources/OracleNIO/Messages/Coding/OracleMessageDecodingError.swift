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

/// An error representing a failure to decode a Oracle wire message to the Swift structure
/// ``OracleBackendMessage``.
///
/// If you encounter a `DecodingError` when using a trusted Oracle server please make sure to file an
/// issue at: [https://github.com/lovetodream/oracle-nio/issues](https://github.com/lovetodream/oracle-nio/issues).
struct OracleMessageDecodingError: Error {

    /// The backend message packet ID byte.
    let packetID: UInt8

    /// The backend message's payload as a hex dump.
    let payload: String

    /// A textual description of the error.
    let description: String

    /// The file this error was thrown in.
    let file: String

    /// The line in ``file`` this error was thrown in.
    let line: Int

    static func withPartialError(
        _ partialError: OraclePartialDecodingError,
        packetID: UInt8,
        messageBytes: ByteBuffer
    ) -> Self {
        return OracleMessageDecodingError(
            packetID: packetID,
            payload: messageBytes.hexDump(format: .plain),
            description: partialError.description,
            file: partialError.file,
            line: partialError.line
        )
    }

    static func unknownPacketIDReceived(
        packetID: UInt8,
        packetType: UInt8,
        messageBytes: ByteBuffer,
        file: String = #fileID,
        line: Int = #line
    ) -> Self {
        return OracleMessageDecodingError(
            packetID: packetID,
            payload: messageBytes.hexDump(format: .plain),
            description: """
                Received a message with packetID '\(packetID)'. There is no \
                packet type associated with this packet identifier.
                """,
            file: file,
            line: line
        )
    }

}
