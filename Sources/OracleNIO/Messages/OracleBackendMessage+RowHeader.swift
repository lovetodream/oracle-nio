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
        ) throws -> OracleBackendMessage.RowHeader {
            buffer.moveReaderIndex(forwardBy: 1)  // flags
            buffer.skipUB2()  // number of requests
            buffer.skipUB4()  // iteration number
            buffer.skipUB4()  // number of iterations
            buffer.skipUB2()  // buffer length
            var bitVector: [UInt8]? = nil
            if let bytesCount = buffer.readUB4(), bytesCount > 0 {
                buffer.moveReaderIndex(forwardBy: 1)  // skip repeated length
                bitVector = buffer.readBytes(length: Int(bytesCount))
            }
            if let numberOfBytes = buffer.readUB4(), numberOfBytes > 0 {
                buffer.skipRawBytesChunked()  // rxhrid
            }
            return .init(bitVector: bitVector)
        }
    }
}
