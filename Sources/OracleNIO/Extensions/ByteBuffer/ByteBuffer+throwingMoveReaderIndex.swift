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

public import NIOCore

extension ByteBuffer {
    @inlinable
    @inline(__always)
    mutating func throwingMoveReaderIndex(
        forwardBy: Int,
        file: String = #fileID,
        line: Int = #line
    ) throws(OraclePartialDecodingError) {
        if self.readableBytes < forwardBy {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                forwardBy,
                actual: self.readableBytes,
                file: file,
                line: line
            )
        }
        self.moveReaderIndex(forwardBy: forwardBy)
    }
}
