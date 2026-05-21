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
    mutating func throwingReadString(
        length: Int,
        file: String = #fileID,
        line: Int = #line
    ) throws -> String {
        guard let result = self.readString(length: length) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size * length,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        return result
    }

    func throwingGetString(
        at index: Int,
        length: Int,
        file: String = #fileID,
        line: Int = #line
    ) throws -> String {
        guard let result = self.getString(at: index, length: length) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size * length,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        return result
    }
}
