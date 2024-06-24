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

import struct NIOCore.ByteBuffer

extension ByteBuffer {
    mutating func readString(
        with charset: Int = Constants.TNS_CS_IMPLICIT
    ) throws -> String {
        checkPreconditions(charset: charset)
        var stringSlice = try self.readOracleSpecificLengthPrefixedSlice()
        return stringSlice.readString(length: stringSlice.readableBytes)!  // must work
    }

    private func checkPreconditions(charset: Int) {
        guard charset == Constants.TNS_CS_IMPLICIT else {
            fatalError("UTF-16 is not supported")
        }
    }
}
