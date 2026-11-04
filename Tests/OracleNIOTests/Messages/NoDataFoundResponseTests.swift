//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2026 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOEmbedded
import Testing

@testable import OracleNIO

/// Reproducers for an intermittent CI failure (Swift 6.4 + oracle-free:23) where a
/// "ORA-01403: no data found" response failed to decode with
/// `Received a message with messageID '0'`, followed by a crash in
/// `ConnectionStateMachine.readyForStatementReceived()`.
///
/// A response can be spread across multiple TNS packets, and where exactly the packet
/// boundaries fall depends on timing. Splitting a well-formed response at every possible
/// offset used to break decoding at some boundaries:
///
/// - Offsets `1` and `37`: a non-throwing `moveReaderIndex(forwardBy:)` trapped when the packet
///   ended right before it (`RowHeader.decode`, `RowID(fromWire:)`).
/// - Offsets `8` and `9`: `RowHeader.decode` treated missing trailing bytes as "not present"
///   (`if let readUB4()`) instead of asking for more data. The remaining `00` bytes ended up at
///   the start of the next packet and were read as a message id, which is the error seen in CI.
@Suite(.timeLimit(.minutes(5))) struct NoDataFoundResponseTests {
    typealias Container = OracleBackendMessageDecoder.Container

    /// The packet exactly as it was printed in the CI log (`OracleMessageDecodingError.payload`).
    static let capturedPacket: [UInt8] = hex(
        """
        00 00 00 61 06 00 00 00 20 00 06 00 00 01 06 01 01 00 00 00 00 00 04 01 02 01 0c 01 01 02 05 7b \
        00 00 01 06 00 03 00 00 00 00 00 03 01 1e c3 01 18 00 01 3d 00 00 00 09 00 00 00 00 00 00 02 05 \
        7b 01 01 01 03 00 19 4f 52 41 2d 30 31 34 30 33 3a 20 6e 6f 20 64 61 74 61 20 66 6f 75 6e 64 0a 1d
        """
    )

    static let headerSize = 8
    static let dataFlagSize = 2

    /// A complete "no data found" response: a row header followed by the error message and the
    /// end of request marker. Message bytes only, without packet header and data flags.
    static let wellFormedContent: [UInt8] = hex(
        """
        06 00 00 01 06 01 01 00 00 00 \
        04 01 02 01 0c 01 01 02 05 7b 00 00 01 06 00 03 00 00 00 00 00 03 01 1e c3 01 18 00 01 3d 00 00 00 \
        09 00 00 00 00 00 00 02 05 7b 01 01 01 03 00 19 4f 52 41 2d 30 31 34 30 33 3a 20 6e 6f 20 64 61 74 \
        61 20 66 6f 75 6e 64 0a 1d
        """
    )

    // MARK: - Helpers

    static func hex(_ string: String) -> [UInt8] {
        string.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { UInt8($0, radix: 16)! }
    }

    static func packet(flags: UInt16, content: some Sequence<UInt8>) -> ByteBuffer {
        let content = Array(content)
        var buffer = ByteBuffer()
        buffer.writeInteger(UInt32(headerSize + dataFlagSize + content.count))
        buffer.writeInteger(UInt8(6))  // data
        buffer.writeInteger(UInt8(0))  // packet flags
        buffer.writeInteger(UInt16(0))  // checksum
        buffer.writeInteger(flags)
        buffer.writeBytes(content)
        return buffer
    }

    static func decode(_ inputs: [ByteBuffer]) throws -> [OracleBackendMessage] {
        var capabilities = Capabilities()
        capabilities.protocolVersion = Constants.TNS_VERSION_MIN_LARGE_SDU
        capabilities.supportsEndOfRequest = true
        let channel = EmbeddedChannel(
            handler: ByteToMessageHandler(
                OracleBackendMessageDecoder(context: .init(capabilities: capabilities))
            )
        )
        defer { _ = try? channel.finish() }
        var messages = [OracleBackendMessage]()
        for input in inputs {
            try channel.writeInbound(input)
            while let containers = try channel.readInbound(as: TinySequence<Container>.self) {
                for container in containers {
                    messages.append(contentsOf: container.messages)
                }
            }
        }
        return messages
    }

    static func expectNoDataFound(
        _ messages: [OracleBackendMessage], sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard messages.count == 2 else {
            Issue.record("Expected row header and error, got \(messages)", sourceLocation: sourceLocation)
            return
        }
        guard case .rowHeader = messages[0], case .error(let error) = messages[1] else {
            Issue.record("Unexpected messages: \(messages)", sourceLocation: sourceLocation)
            return
        }
        #expect(error.number == 1403, sourceLocation: sourceLocation)
    }

    static func decodeSplit(atContentOffset split: Int) throws -> [OracleBackendMessage] {
        let content = wellFormedContent
        let first = packet(flags: 0, content: content[..<split])
        let second = packet(flags: Constants.TNS_DATA_FLAGS_END_OF_REQUEST, content: content[split...])
        return try decode([first, second])
    }

    // MARK: - Tests

    @Test func wellFormedResponseDecodes() throws {
        let packet = Self.packet(flags: Constants.TNS_DATA_FLAGS_END_OF_REQUEST, content: Self.wellFormedContent)
        Self.expectNoDataFound(try Self.decode([packet]))
    }

    /// TCP does not guarantee message boundaries, a packet can be received in arbitrary pieces.
    @Test func wellFormedResponseDecodesWhenTCPSegmentsAreSplitAtEveryOffset() throws {
        let packet = Self.packet(flags: Constants.TNS_DATA_FLAGS_END_OF_REQUEST, content: Self.wellFormedContent)
        let expected = try Self.decode([packet])
        for split in 1..<packet.readableBytes {
            let head = packet.getSlice(at: 0, length: split)!
            let tail = packet.getSlice(at: split, length: packet.readableBytes - split)!
            #expect(try Self.decode([head, tail]) == expected, "TCP split at offset \(split)")
        }
    }

    /// A response can also be spread across multiple TNS packets, with a message ending up cut
    /// in half. The decoder has to stitch the remainder of the first packet onto the second.
    @Test(.serialized, arguments: 1..<Self.wellFormedContent.count)
    func wellFormedResponseDecodesWhenTNSPacketsAreSplit(atContentOffset split: Int) throws {
        let expected = try Self.decode([
            Self.packet(flags: Constants.TNS_DATA_FLAGS_END_OF_REQUEST, content: Self.wellFormedContent)
        ])
        #expect(try Self.decodeSplit(atContentOffset: split) == expected)
    }

    /// The packet from the CI log, decoded on its own.
    ///
    /// The row header is followed by two `00` bytes before the `04` (error) message. The
    /// decoder reads the first of them as a message id. It is not known where these two bytes
    /// come from, the log only contains the bytes of this one packet.
    @Test func capturedPacketFromCI() throws {
        try withKnownIssue(
            "Two unexplained bytes between row header and error message",
            {
                let packet = ByteBuffer(bytes: Self.capturedPacket)
                Self.expectNoDataFound(try Self.decode([packet]))
            },
            matching: { $0.error is OracleMessageDecodingError }
        )
    }
}
