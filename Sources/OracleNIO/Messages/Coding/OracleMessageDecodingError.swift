// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore

/// An error representing a failure to decode a Oracle wire message to the Swift structure
/// ``OracleBackendMessage``.
///
/// If you encounter a `DecodingError` when using a trusted Oracle server please make sure to file an
/// issue at: [https://github.com/lovetodream/oracle-nio/issues](https://github.com/lovetodream/oracle-nio/issues).
struct OracleMessageDecodingError: Error {

    /// The backend message packet ID byte.
    let packetID: UInt8

    /// The backend message's payload encoded in base64.
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
        let data = messageBytes.hexDump(format: .plain)

        return OracleMessageDecodingError(
            packetID: packetID,
            payload: data,
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
        var buffer = messageBytes
        let data = buffer.readData(length: buffer.readableBytes)!

        return OracleMessageDecodingError(
            packetID: packetID,
            payload: data.base64EncodedString(),
            description: """
            Received a message with packetID '\(packetID)'. There is no \
            packet type associated with this packet identifier.
            """,
            file: file,
            line: line
        )
    }

}
