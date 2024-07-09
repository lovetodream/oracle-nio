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
    mutating func readOSON() throws -> ByteBuffer? {
        guard let length = self.readUB4(), length > 0 else {
            return ByteBuffer(bytes: [0])
        }
        self.skipUB8()  // size (unused)
        self.skipUB4()  // chunk size (unused)
        let data = self.readOracleSlice()
        self.skipRawBytesChunked()  // lob locator (unused)
        return data
    }
}
