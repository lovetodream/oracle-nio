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
    struct InOutVector: PayloadDecodable, Hashable {
        var bindMetadata: [BindMetadatum]

        struct BindMetadatum: Hashable {
            /// Index of the bind, the metadata belongs to.
            var index: Int
            /// The direction is either IN, OUT or INOUT.
            ///
            /// Can be checked using ``Constants.TNS_BIND_DIR_INPUT``,
            /// ``Constants.TNS_BIND_DIR_OUTPUT``  and
            /// ``Constants.TNS_BIND_DIR_INPUT_OUTPUT``.
            var direction: UInt8
        }

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.InOutVector {
            buffer.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size)  // flag
            let temp16 = try buffer.throwingReadUB2()  // number of requests
            let temp32 = try buffer.throwingReadUB4()  // number of iterations
            let numberOfBinds = Int(temp32 * 256 + UInt32(temp16))
            buffer.skipUB4()  // number of iterations this time
            buffer.skipUB2()  // uac buffer length
            let bytesCount = try buffer.throwingReadUB2()  // bit vector for fast fetch
            if bytesCount > 0 {
                buffer.moveReaderIndex(forwardBy: Int(bytesCount))
            }
            let rowIDLength = try buffer.throwingReadUB2()
            if rowIDLength > 0 {
                buffer.moveReaderIndex(forwardBy: Int(rowIDLength))
            }
            var metadata = [BindMetadatum]()
            metadata.reserveCapacity(numberOfBinds)
            for index in 0..<numberOfBinds {  // iterate through bind directions
                let direction = try buffer.throwingReadInteger(as: UInt8.self)
                metadata.append(.init(index: index, direction: direction))
            }
            return .init(bindMetadata: metadata)
        }
    }
}
