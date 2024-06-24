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
    struct ServerSidePiggyback: PayloadDecodable, Hashable {
        /// Indicates if the statement cache should be reset.
        ///
        /// Only applicable if we are currently establishing a DRCP session.
        let resetStatementCache: Bool

        /// Server side piggyback operation code.
        enum Code: UInt8 {
            case queryCacheInvalidation = 1
            case osPidMts = 2
            case traceEvent = 3
            case sessRet = 4
            case sync = 5
            case ltxID = 7
            case acReplayContext = 8
            case extSync = 9
        }

        static func decode(
            from buffer: inout ByteBuffer,
            context: OracleBackendMessageDecoder.Context
        ) throws -> OracleBackendMessage.ServerSidePiggyback {
            let opCode = Code(rawValue: try buffer.throwingReadInteger())
            var temp16: UInt16 = 0
            switch opCode {
            case .ltxID:
                let numberOfBytes = try buffer.throwingReadInteger(
                    as: UInt32.self
                )
                if numberOfBytes > 0 {
                    buffer.moveReaderIndex(forwardBy: Int(numberOfBytes))
                }
            case .queryCacheInvalidation, .traceEvent, .none:
                break
            case .osPidMts:
                temp16 = buffer.readInteger(as: UInt16.self) ?? 0
                buffer.skipRawBytesChunked()
            case .sync:
                buffer.moveReaderIndex(forwardBy: 2)  // skip number of DTYs
                buffer.moveReaderIndex(forwardBy: 1)  // skip length of DTYs
                let numberOfElements = try buffer.throwingReadInteger(
                    as: UInt16.self
                )
                buffer.moveReaderIndex(forwardBy: 1)  // skip length
                for _ in 0..<numberOfElements {
                    temp16 = try buffer.throwingReadInteger(as: UInt16.self)
                    if temp16 > 0 {  // skip key
                        buffer.skipRawBytesChunked()
                    }
                    temp16 = try buffer.throwingReadInteger(as: UInt16.self)
                    if temp16 > 0 {  // skip value
                        buffer.skipRawBytesChunked()
                    }
                    buffer.moveReaderIndex(forwardBy: 2)  // skip flags
                }
                buffer.moveReaderIndex(forwardBy: 4)  // skip overall flags
            case .extSync:
                buffer.moveReaderIndex(forwardBy: 2)  // skip number of DTYs
                buffer.moveReaderIndex(forwardBy: 1)  // skip length of DTYs
            case .acReplayContext:
                buffer.moveReaderIndex(forwardBy: 2)  // skip number of DTYs
                buffer.moveReaderIndex(forwardBy: 1)  // skip length of DTYs
                buffer.moveReaderIndex(forwardBy: 4)  // skip flags
                buffer.moveReaderIndex(forwardBy: 4)  // skip error code
                buffer.moveReaderIndex(forwardBy: 1)  // skip queue
                let numberOfBytes = try buffer.throwingReadInteger(
                    as: UInt32.self
                )  // skip replay context
                if numberOfBytes > 0 {
                    buffer.moveReaderIndex(forwardBy: Int(numberOfBytes))
                }
            case .sessRet:
                buffer.moveReaderIndex(forwardBy: 2)
                buffer.moveReaderIndex(forwardBy: 1)
                let numberOfElements = try buffer.throwingReadInteger(
                    as: UInt16.self
                )
                if numberOfElements > 0 {
                    buffer.moveReaderIndex(forwardBy: 1)
                    for _ in 0..<numberOfElements {
                        temp16 = try buffer.throwingReadInteger(as: UInt16.self)
                        if temp16 > 0 {  // skip key
                            buffer.skipRawBytesChunked()
                        }
                        temp16 = try buffer.throwingReadInteger(as: UInt16.self)
                        if temp16 > 0 {  // skip value
                            buffer.skipRawBytesChunked()
                        }
                        buffer.moveReaderIndex(forwardBy: 2)  // skip flags
                    }
                }
                let flags = try buffer.throwingReadInteger(as: UInt32.self)
                // session flags
                let resetStatementCache = flags & Constants.TNS_SESSGET_SESSION_CHANGED != 0
                buffer.moveReaderIndex(forwardBy: 4)
                buffer.moveReaderIndex(forwardBy: 2)
                return .init(resetStatementCache: resetStatementCache)
            }

            return .init(resetStatementCache: false)
        }
    }
}
