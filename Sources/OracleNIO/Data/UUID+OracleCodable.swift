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
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .raw, .longRAW:
            guard let uuid = Self.readUUIDBytes(from: &buffer) else {
                throw OracleDecodingError.Code.failure
            }
            self = uuid
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

    private static func getUUIDBytes(at index: Int, from buffer: inout ByteBuffer) -> UUID? {
        guard let chunk1 = buffer.getInteger(at: index, as: UInt64.self),
            let chunk2 = buffer.getInteger(at: index + 8, as: UInt64.self)
        else {
            return nil
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

        return UUID(uuid: uuidBytes)
    }

    /// Read a `UUID` from the first 16 bytes in the buffer. Advances the reader index.
    ///
    /// - Returns: The `UUID` or `nil` if the buffer did not contain enough bytes.
    private static func readUUIDBytes(from buffer: inout ByteBuffer) -> UUID? {
        guard let uuid = buffer.getUUIDBytes(at: buffer.readerIndex) else {
            return nil
        }
        buffer.moveReaderIndex(forwardBy: MemoryLayout<uuid_t>.size)
        return uuid
    }
}
