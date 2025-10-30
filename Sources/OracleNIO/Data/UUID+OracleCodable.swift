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

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

extension UUID: OracleDecodable {
    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .raw, .longRAW:
            guard let (chunk1, chunk2) = buffer.readMultipleIntegers(as: (UInt64, UInt64).self) else {
                throw OracleDecodingError.Code.missingData
            }

            let uuidBytes = (
                UInt8(truncatingIfNeeded: chunk1 >> 56),
                UInt8(truncatingIfNeeded: chunk1 >> 48),
                UInt8(truncatingIfNeeded: chunk1 >> 40),
                UInt8(truncatingIfNeeded: chunk1 >> 32),
                UInt8(truncatingIfNeeded: chunk1 >> 24),
                UInt8(truncatingIfNeeded: chunk1 >> 16),
                UInt8(truncatingIfNeeded: chunk1 >> 8),
                UInt8(truncatingIfNeeded: chunk1),
                UInt8(truncatingIfNeeded: chunk2 >> 56),
                UInt8(truncatingIfNeeded: chunk2 >> 48),
                UInt8(truncatingIfNeeded: chunk2 >> 40),
                UInt8(truncatingIfNeeded: chunk2 >> 32),
                UInt8(truncatingIfNeeded: chunk2 >> 24),
                UInt8(truncatingIfNeeded: chunk2 >> 16),
                UInt8(truncatingIfNeeded: chunk2 >> 8),
                UInt8(truncatingIfNeeded: chunk2)
            )

            self = UUID(uuid: uuidBytes)
        case .varchar, .long:
            guard buffer.readableBytes == 36 else {
                throw OracleDecodingError.Code.failure
            }

            guard let uuid = buffer.readString(length: 36).flatMap({ UUID(uuidString: $0) }) else {
                throw OracleDecodingError.Code.failure
            }
            self = uuid
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
