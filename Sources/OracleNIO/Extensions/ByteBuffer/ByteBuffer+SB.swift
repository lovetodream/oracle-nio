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
    mutating func readSB2() -> Int16? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return readInteger(as: Int8.self).map(Int16.init)
        case 2:
            return readInteger(as: Int16.self)
        default:
            preconditionFailure()
        }
    }

    mutating func throwingReadSB2(
        file: String = #fileID, line: Int = #line
    ) throws -> Int16 {
        try self.readSB2().value(
            or: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<Int8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        )
    }

    mutating func readSB4() -> Int32? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return readInteger(as: Int8.self).map(Int32.init)
        case 2:
            return readInteger(as: Int16.self).map(Int32.init)
        case 4:
            return readInteger(as: Int32.self)
        default:
            preconditionFailure()
        }
    }

    mutating func readSB8() -> Int64? {
        guard let length = readUBLength() else { return nil }
        switch length {
        case 0:
            return 0
        case 1:
            return readInteger(as: Int8.self).map(Int64.init)
        case 2:
            return readInteger(as: Int16.self).map(Int64.init)
        case 4:
            return readInteger(as: Int32.self).map(Int64.init)
        case 8:
            return readInteger(as: Int64.self)
        default:
            preconditionFailure()
        }
    }

    mutating func throwingReadSB8(
        file: String = #fileID, line: Int = #line
    ) throws -> Int64 {
        try self.readSB8().value(
            or: OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<Int8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        )
    }

    mutating func skipSB4() { skipUB4() }
}
