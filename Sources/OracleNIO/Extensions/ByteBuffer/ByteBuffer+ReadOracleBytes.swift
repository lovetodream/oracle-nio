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
    mutating func readOracleSpecificLengthPrefixedSlice(
        file: String = #fileID, line: Int = #line
    ) throws -> ByteBuffer {
        guard let length = self.readInteger(as: UInt8.self).map(Int.init) else {
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                MemoryLayout<UInt8>.size, actual: self.readableBytes,
                file: file, line: line
            )
        }

        if length == Constants.TNS_LONG_LENGTH_INDICATOR {
            var out = ByteBuffer()
            while true {
                guard let chunkLength = self.readUB4(), chunkLength > 0 else {
                    return out
                }
                guard var temp = self.readSlice(length: Int(chunkLength)) else {
                    throw
                        OraclePartialDecodingError
                        .expectedAtLeastNRemainingBytes(
                            Int(chunkLength), actual: self.readableBytes,
                            file: file, line: line
                        )
                }
                out.writeBuffer(&temp)
            }
            return out
        }

        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return .init()  // empty buffer
        }

        return self.readSlice(length: length)!
    }

    /// Read a slice of data prefixed with a length byte.
    ///
    /// If not enough data could be read, `nil` will be returned, indicating that another packet must be
    /// read from the channel to complete the operation.
    mutating func readOracleSlice() -> ByteBuffer? {
        guard
            var length = self.getInteger(at: self.readerIndex, as: UInt8.self)
        else {
            preconditionFailure()
        }
        if length == Constants.TNS_NULL_LENGTH_INDICATOR {
            length = 0
        }

        if length == Constants.TNS_LONG_LENGTH_INDICATOR {
            let startReaderIndex = self.readerIndex
            // skip previously read length
            self.moveReaderIndex(forwardBy: MemoryLayout<UInt8>.size)
            var out = ByteBuffer(integer: Constants.TNS_LONG_LENGTH_INDICATOR)
            while true {
                guard let chunkLength = self.readUB4() else {
                    self.moveReaderIndex(to: startReaderIndex)
                    return nil  // need more data
                }
                guard chunkLength > 0 else {
                    out.writeInteger(0, as: UInt32.self)  // chunk length of zero
                    return out
                }
                guard var temp = self.readSlice(length: Int(chunkLength)) else {
                    self.moveReaderIndex(to: startReaderIndex)
                    return nil  // need more data
                }
                out.writeInteger(chunkLength)
                out.writeBuffer(&temp)
            }
            return out
        }

        let sliceLength = Int(length) + MemoryLayout<UInt8>.size
        if self.readableBytes < sliceLength {
            return nil  // need more data
        }
        return self.readSlice(length: sliceLength)
    }
}
