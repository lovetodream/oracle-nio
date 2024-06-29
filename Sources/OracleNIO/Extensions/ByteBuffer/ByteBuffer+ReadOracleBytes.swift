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
    private enum LengthOrBuffer {
        case length(Int)
        case buffer(ByteBuffer)
    }

    private mutating func _readOracleSpecificLengthPrefixedSlice(
        file: String = #fileID, line: Int = #line
    ) -> LengthOrBuffer {
        guard let length = self.readInteger(as: UInt8.self).map(Int.init) else {
            return .length(MemoryLayout<UInt8>.size)
        }

        if length == Constants.TNS_LONG_LENGTH_INDICATOR {
            var out = ByteBuffer()
            while true {
                guard let chunkLength = self.readUB4() else {
                    return .length(MemoryLayout<UInt8>.size)
                }
                guard chunkLength > 0 else { break }
                guard var temp = self.readSlice(length: Int(chunkLength)) else {
                    return .length(Int(chunkLength))
                }
                out.writeBuffer(&temp)
            }
            return .buffer(out)
        }

        if length == 0 || length == Constants.TNS_NULL_LENGTH_INDICATOR {
            return .buffer(.init())  // empty buffer
        }

        guard let slice = self.readSlice(length: length) else {
            return .length(length)
        }
        return .buffer(slice)
    }

    /// - Returns: `nil` if more data is required to decode
    mutating func readOracleSpecificLengthPrefixedSlice(
        file: String = #fileID, line: Int = #line
    ) -> ByteBuffer? {
        switch self._readOracleSpecificLengthPrefixedSlice(file: file, line: line) {
        case .buffer(let buffer):
            return buffer
        case .length:
            return nil
        }
    }

    mutating func throwingReadOracleSpecificLengthPrefixedSlice(
        file: String = #fileID, line: Int = #line
    ) throws -> ByteBuffer {
        switch self._readOracleSpecificLengthPrefixedSlice(file: file, line: line) {
        case .buffer(let buffer):
            return buffer
        case .length(let length):
            throw OraclePartialDecodingError.expectedAtLeastNRemainingBytes(
                length, actual: self.readableBytes, file: file, line: line
            )
        }
    }

    /// Read a slice of data prefixed with a length byte.
    ///
    /// This returns a buffer including the length prefix, use
    /// ``ByteBuffer.readOracleSpecificLengthPrefixedSlice(file:line:)``
    /// if you want to omit length prefixes.
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
