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
import Testing

@testable import OracleNIO

private typealias BitVector = OracleBackendMessage.BitVector

@Suite(.timeLimit(.minutes(5))) struct BitVectorTests {

    /// Simulates a TNS packet that ends between the bitVector header and its
    /// trailing content byte. With 4 columns the content is `ceil(4 / 8) = 1`
    /// byte; the buffer carries only the `columnsCountSent` UB2 (`01 01`).
    /// Pre-fix this returned silently with `bitVector = nil`; post-fix it
    /// throws `Trigger` so the decoder saves a partial and resumes on the
    /// next packet.
    @Test func decodeRequestsMissingDataWhenContentTruncated() {
        var buffer = ByteBuffer(bytes: [0x01, 0x01])  // columnsCountSent UB2 only
        #expect(
            throws: MissingDataDecodingError.Trigger(),
            performing: {
                try BitVector.decode(
                    from: &buffer,
                    context: .init(columns: .number, .number, .number, .number)
                )
            })
    }
}
