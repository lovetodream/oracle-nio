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
    mutating func throwingReadInteger<T: FixedWidthInteger>(
        endianness: Endianness = .big,
        as: T.Type = T.self,
        file: String = #fileID,
        line: Int = #line
    ) throws -> T {
        guard let result = self.readInteger(endianness: endianness, as: T.self) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<T>.size,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        return result
    }
}
