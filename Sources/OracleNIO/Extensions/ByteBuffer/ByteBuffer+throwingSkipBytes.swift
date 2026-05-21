//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2026 Timo Zacherl and the OracleNIO project authors
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
    mutating func throwingSkipBytes(
        _ maxLength: Int,
        file: String = #fileID,
        line: Int = #line
    ) throws(OraclePartialDecodingError) {
        guard let length = readUBLength().flatMap(Int.init) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size,
                actual: self.readableBytes,
                file: file, line: line
            )
        }
        guard length <= maxLength else { preconditionFailure() }
        try self.throwingMoveReaderIndex(forwardBy: length, file: file, line: line)
    }
}
