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
    mutating func throwingReadBytes(
        length: Int,
        file: String = #fileID,
        line: Int = #line
    ) throws -> [UInt8] {
        guard let result = self.readBytes(length: length) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size * length,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        return result
    }

    mutating func throwingReadSlice(
        length: Int,
        file: String = #fileID,
        line: Int = #line
    ) throws -> ByteBuffer {
        guard let result = self.readSlice(length: length) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size * length,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        return result
    }
}
