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
    mutating func throwingReadOSON() throws -> ByteBuffer? {
        let length = try self.throwingReadUB4()
        guard length > 0 else {
            return ByteBuffer(bytes: [0])
        }
        try self.throwingSkipUB8()  // size (unused)
        try self.throwingSkipUB4()  // chunk size (unused)
        guard let data = self.readOracleSlice() else {
            return nil
        }
        if !self.skipRawBytesChunked() {  // lob locator (unused)
            return nil
        }
        return data
    }
}
