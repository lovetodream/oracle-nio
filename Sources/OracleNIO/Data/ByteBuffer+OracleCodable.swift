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

extension ByteBuffer: OracleEncodable {
    public static var defaultOracleType: OracleDataType { .raw }

    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        preconditionFailure("This should not be called")
    }

    /// Encodes `self` into wire data starting from `0` without modifying the `readerIndex`.
    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        var slice = self
        slice.moveReaderIndex(to: 0)
        var length = slice.readableBytes
        if length <= Constants.TNS_MAX_SHORT_LENGTH {
            buffer.writeInteger(UInt8(length))
            buffer.writeBuffer(&slice)
        } else {
            buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            while slice.readableBytes > 0 {
                let chunkLength = min(length, Constants.TNS_CHUNK_SIZE)
                buffer.writeUB4(UInt32(chunkLength))
                length -= chunkLength
                var part = slice.readSlice(length: chunkLength)!
                buffer.writeBuffer(&part)
            }
            buffer.writeUB4(0)
        }
    }
}

extension ByteBuffer: OracleDecodable {
    public var size: UInt32 { UInt32(self.readableBytes) }

    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        switch type {
        case .raw, .longRAW:
            self = buffer
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
