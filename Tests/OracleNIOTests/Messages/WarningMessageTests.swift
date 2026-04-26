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
import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct WarningMessageTests {
    // Regression: a warning whose message ends in a newline (e.g. ORA-28098
    // sent for an EXPIRED(GRACE) account) used to leave the trailing byte
    // unread, so the next decode pass interpreted that byte (0x0A) as a bogus
    // messageID '10'. See https://github.com/lovetodream/oracle-nio/issues/113.
    @Test func decodeWarningEndingInNewlineConsumesAllBytes() throws {
        // data flags        : 00 00
        // messageID warning : 0F
        // UB2 number 28098  : 02 6D C2
        // UB2 length 13     : 01 0D
        // UB2 flags         : 01 04
        // chunked length 13 : 0D
        // "ORA-1: hello\n"  : 4F 52 41 2D 31 3A 20 68 65 6C 6C 6F 0A
        var buffer = try ByteBuffer(
            plainHexEncodedBytes:
                "00 00 0F 02 6D C2 01 0D 01 04 0D 4F 52 41 2D 31 3A 20 68 65 6C 6C 6F 0A"
        )

        let (messages, _) = try OracleBackendMessage.decode(
            from: &buffer,
            of: .data,
            context: .init(capabilities: .desired())
        )

        #expect(buffer.readableBytes == 0)
        #expect(messages.count == 1)
        guard case .warning(let warning) = messages.first else {
            Issue.record("expected .warning, got \(String(describing: messages.first))")
            return
        }
        #expect(warning.number == 28098)
        #expect(warning.isWarning)
        #expect(warning.message == "ORA-1: hello")
    }

    // A second message immediately after the warning must still be aligned —
    // catches off-by-one regressions in the warning decoder.
    @Test func decodeWarningFollowedByAnotherMessageAlignsCorrectly() throws {
        // first warning (same payload as above)
        // second warning : 0F  number=1 (01 01) length=0 (00) flags=00
        var buffer = try ByteBuffer(
            plainHexEncodedBytes:
                "00 00 0F 02 6D C2 01 0D 01 04 0D 4F 52 41 2D 31 3A 20 68 65 6C 6C 6F 0A"
                + "0F 01 01 00 00"
        )

        let (messages, _) = try OracleBackendMessage.decode(
            from: &buffer,
            of: .data,
            context: .init(capabilities: .desired())
        )

        #expect(buffer.readableBytes == 0)
        #expect(messages.count == 2)
        guard case .warning(let first) = messages.first else {
            Issue.record("expected .warning, got \(String(describing: messages.first))")
            return
        }
        #expect(first.number == 28098)
        #expect(first.message == "ORA-1: hello")

        guard messages.count == 2, case .warning(let second) = messages[1] else {
            Issue.record("expected second .warning")
            return
        }
        #expect(second.number == 1)
        #expect(second.message == nil)
    }
}
