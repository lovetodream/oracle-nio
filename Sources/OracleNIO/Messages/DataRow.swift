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

@usableFromInline
struct DataRow: Sendable, Hashable {
    @usableFromInline
    var columnCount: Int
    @usableFromInline
    var bytes: ByteBuffer
}

extension DataRow: Sequence {
    @usableFromInline
    typealias Element = ByteBuffer?
}

extension DataRow: Collection {

    @usableFromInline
    struct ColumnIndex: Comparable {
        @usableFromInline
        var offset: Int

        @inlinable
        init(_ index: Int) {
            self.offset = index
        }

        // Only needed implementation for comparable.
        // The compiler synthesizes the rest from thsi.
        @inlinable
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    @usableFromInline
    typealias Index = DataRow.ColumnIndex

    @inlinable
    var startIndex: ColumnIndex {
        ColumnIndex(self.bytes.readerIndex)
    }

    @inlinable
    var endIndex: ColumnIndex {
        ColumnIndex(self.bytes.readerIndex + self.bytes.readableBytes)
    }

    @inlinable
    var count: Int {
        Int(self.columnCount)
    }

    @inlinable
    func index(after index: ColumnIndex) -> ColumnIndex {
        guard index < self.endIndex else {
            preconditionFailure("index out of bounds")
        }
        var elementLength =
            Int(self.bytes.getInteger(at: index.offset, as: UInt8.self)!)

        if elementLength == Constants.TNS_NULL_LENGTH_INDICATOR {
            elementLength = 0
        }

        if elementLength == Constants.TNS_LONG_LENGTH_INDICATOR {
            var totalLength = 0
            var readerIndex = index.offset + MemoryLayout<UInt8>.size
            while true {
                let chunkLength = Int(
                    self.bytes.getInteger(
                        at: readerIndex, as: UInt32.self
                    )!)
                totalLength += MemoryLayout<UInt32>.size
                if chunkLength == 0 { break }
                totalLength += chunkLength
                readerIndex += MemoryLayout<UInt32>.size + chunkLength
            }
            elementLength = totalLength
        }

        return ColumnIndex(
            index.offset + MemoryLayout<UInt8>.size + elementLength
        )
    }

    @inlinable
    subscript(index: ColumnIndex) -> Element {
        guard index < self.endIndex else {
            preconditionFailure("index out of bounds")
        }
        let elementLength =
            Int(self.bytes.getInteger(at: index.offset, as: UInt8.self)!)

        if elementLength == 0 || elementLength == Constants.TNS_NULL_LENGTH_INDICATOR {
            return nil
        }

        if elementLength == Constants.TNS_LONG_LENGTH_INDICATOR {
            var out = ByteBuffer()
            var position = index.offset + MemoryLayout<UInt8>.size
            while true {
                let chunkLength =
                    Int(self.bytes.getInteger(at: position, as: UInt32.self)!)
                position += MemoryLayout<UInt32>.size
                if chunkLength == 0 {
                    return out
                }
                var temp = self.bytes.getSlice(
                    at: position, length: chunkLength
                )!
                position += chunkLength
                out.writeBuffer(&temp)
            }
        }

        return self.bytes.getSlice(
            at: index.offset + MemoryLayout<UInt8>.size, length: elementLength
        )!
    }

}

extension DataRow {
    subscript(column index: Int) -> Element {
        guard index < self.columnCount else {
            preconditionFailure("index out of bounds")
        }

        var byteIndex = self.startIndex
        for _ in 0..<index {
            byteIndex = self.index(after: byteIndex)
        }

        return self[byteIndex]
    }
}
