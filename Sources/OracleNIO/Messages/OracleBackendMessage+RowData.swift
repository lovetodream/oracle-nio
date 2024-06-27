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
    struct RowData: PayloadDecodable, Sendable, Hashable {
        /// Row data cannot be decoded in any other way, because the bounds
        /// aren't clear without the information from ``DescribeInfo``.
        /// Because of that the remaining buffer is returned as the row data.
        /// The state machine needs to handle cases in which the buffer contains more messages.
        var slice: ByteBuffer

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> RowData {
            let data = RowData(slice: buffer.slice())
            buffer.moveReaderIndex(to: buffer.readerIndex + buffer.readableBytes)
            return data
        }
    }
}

extension OracleBackendMessage.RowData: CustomDebugStringConvertible {
    var debugDescription: String {
        "RowData(slice: \(self.slice.readableBytes) bytes)"
    }
}
