//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
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

@Suite struct StringTests {
    @Test func decodeUTF16() throws {
        var buffer: ByteBuffer? = ByteBuffer(
            bytes: [
                72, 0, 101, 0, 108, 0, 108, 0, 111, 0,
                44, 0, 32, 0, 119, 0, 111, 0, 114, 0,
                108, 0, 100, 0, 33, 0, 32, 0, 60, 216,
                13, 223, 61, 216, 75, 220,
            ]
        )
        let value = try String._decodeRaw(from: &buffer, type: .nVarchar, context: .default)
        #expect(value == "Hello, world! 🌍👋")
    }
}
