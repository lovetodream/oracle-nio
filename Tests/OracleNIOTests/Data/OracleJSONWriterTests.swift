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
import Testing

@testable import OracleNIO

import struct Foundation.Date

@Suite struct OracleJSONWriterTests {
    @Test func encodeString() throws {
        // expected
        // 0000 : FF 4A 5A 01 00 10 00 06 |.JZ.....|
        // 0008 : 05 76 61 6C 75 65       |.value  |
        var buffer = ByteBuffer()
        var writer = OracleJSONWriter()
        try writer.encode(.string("value"), into: &buffer, maxFieldNameSize: 255)
        let result = try OracleJSONParser.parse(from: &buffer)
        #expect(result == .string("value"))
    }
}
#endif
