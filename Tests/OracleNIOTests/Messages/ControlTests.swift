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

#if compiler(>=6.0)
import NIOCore
import NIOTestUtils
import Testing

@testable import OracleNIO

@Suite struct ControlTests {
    @Test func resetOOB() throws {
        var message = try ByteBuffer(plainHexEncodedBytes: "00 09")
        let result = try OracleBackendMessage.decode(
            from: &message,
            of: .control,
            context: .init(capabilities: .desired())
        )
        #expect(result.0 == [.resetOOB])
    }

    @Test func unknown() throws {
        var message = try ByteBuffer(plainHexEncodedBytes: "01 09")
        #expect(throws: OraclePartialDecodingError.unknownControlType(controlType: 0x0109), performing: {
            try OracleBackendMessage.decode(
                from: &message,
                of: .control,
                context: .init(capabilities: .desired())
            )
        })
    }
}
#endif
