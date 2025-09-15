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

extension Data: OracleEncodable {
    public static var defaultOracleType: OracleDataType { .raw }

    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        preconditionFailure("This should not be called")
    }

    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        var length = self.count
        var position = 0

        buffer.reserveCapacity(minimumWritableBytes: MemoryLayout<UInt8>.size + length)
        if length <= Constants.TNS_MAX_SHORT_LENGTH {
            buffer.writeInteger(UInt8(length))

            var index = buffer.readerIndex
            for region in self.regions {
                region.withUnsafeBytes { bufferPointer in
                    index += buffer.setBytes(bufferPointer, at: index)
                }
            }
        } else {
            buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            while length > 0 {
                let chunkLength = Swift.min(length, Constants.TNS_CHUNK_SIZE)
                buffer.writeUB4(UInt32(chunkLength))
                length -= chunkLength
                let part =
                    self
                    .subdata(in: position..<(position + chunkLength))
                buffer.writeBytes(part)
                position += chunkLength
            }
            buffer.writeUB4(0)
        }
    }
}

extension Data: OracleDecodable {
    public var size: UInt32 { UInt32(self.count) }

    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .raw, .longRAW:
            self = buffer.withUnsafeReadableBytesWithStorageManagement { ptr, storageRef in
                let storage = storageRef.takeUnretainedValue()
                return Data(
                    bytesNoCopy: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                    count: buffer.readableBytes,
                    deallocator: .custom { _, _ in withExtendedLifetime(storage) {} }
                )
            }
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
