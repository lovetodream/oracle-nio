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

extension OracleBackendMessage {
    struct RowHeader: PayloadDecodable, Hashable {

        /// Gets the bit vector from the buffer and stores it for later use by the
        /// row processing code. Since it is possible that the packet buffer may be
        /// overwritten by subsequent packet retrieval, the bit vector must be
        /// copied.
        var bitVector: [UInt8]?

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws(OraclePartialDecodingError) -> OracleBackendMessage.RowHeader {
            try buffer.throwingMoveReaderIndex(forwardBy: 1)  // flags
            try buffer.throwingSkipUB2()  // number of requests
            try buffer.throwingSkipUB4()  // iteration number
            try buffer.throwingSkipUB4()  // number of iterations
            try buffer.throwingSkipUB2()  // buffer length
            var bitVector: [UInt8]? = nil
            let byteCount = try buffer.throwingReadUB4()
            if byteCount > 0 {
                try buffer.throwingMoveReaderIndex(forwardBy: 1)  // skip repeated length
                bitVector = try buffer.throwingReadBytes(length: Int(byteCount))
            }
            let numberOfBytes = try buffer.throwingReadUB4()
            if numberOfBytes > 0 {
                // rxhrid
                guard buffer.skipRawBytesChunked() else {
                    throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                        MemoryLayout<UInt8>.size, actual: buffer.readableBytes
                    )
                }
            }
            return .init(bitVector: bitVector)
        }
    }
}
