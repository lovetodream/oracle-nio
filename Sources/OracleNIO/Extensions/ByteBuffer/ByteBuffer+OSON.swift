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

extension ByteBuffer {
    mutating func readOSON() throws -> Any? {
        guard let length = readUB4(), length > 0 else { return nil }
        skipUB8()  // size (unused)
        skipUB4()  // chunk size (unused)
        let data = try self.readOracleSpecificLengthPrefixedSlice()
        _ = try readOracleSpecificLengthPrefixedSlice()  // lob locator (unused)
        var decoder = OSONDecoder()
        return try decoder.decode(data)
    }
}
