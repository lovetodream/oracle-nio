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
        let elementLength =
            Int(self.bytes.getInteger(at: index.offset, as: UInt8.self)!)
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
        if 
            elementLength == 0 || 
            elementLength == Constants.TNS_NULL_LENGTH_INDICATOR
        {
            return nil
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
