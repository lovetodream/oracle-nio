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

/// `OracleRow` represents a single table row that is received from the server for a statement.
///
/// Its element type is ``OracleCell``.
///
/// - Warning: Please note that random access to cells in a ``OracleRow`` has O(n) time complexity.
///            If you require random access to cells in O(1) create a new
///            ``OracleRandomAccessRow`` with the given row and access it instead.
public struct OracleRow: Sendable {
    @usableFromInline
    let lookupTable: [String: Int]
    @usableFromInline
    let data: DataRow
    @usableFromInline
    let columns: [OracleColumn]
}

extension OracleRow: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        // we don't need to compare the lookup table here,
        // as the looup table is only derived from the column description.
        lhs.data == rhs.data && lhs.columns == rhs.columns
    }
}

extension OracleRow: Sequence {
    public typealias Element = OracleCell

    public struct Iterator: IteratorProtocol {
        public typealias Element = OracleCell

        private(set) var columnIndex: Array<OracleColumn>.Index
        private(set) var columnIterator: Array<OracleColumn>.Iterator
        private(set) var dataIterator: DataRow.Iterator

        init(_ row: OracleRow) {
            self.columnIndex = 0
            self.columnIterator = row.columns.makeIterator()
            self.dataIterator = row.data.makeIterator()
        }

        public mutating func next() -> OracleCell? {
            guard let bytes = self.dataIterator.next() else {
                return nil
            }

            let column = self.columnIterator.next()!

            defer { self.columnIndex += 1 }

            return OracleCell(
                bytes: bytes,
                dataType: column.dataType,
                columnName: column.name,
                columnIndex: columnIndex
            )
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(self)
    }
}

extension OracleRow: Collection {
    public struct Index: Comparable {
        var cellIndex: DataRow.Index
        var columnIndex: Array<OracleColumn>.Index

        // Only needed implementation for comparable.
        // The compiler synthesizes the rest from this.
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.columnIndex < rhs.columnIndex
        }
    }

    public subscript(position: Index) -> OracleCell {
        let column = self.columns[position.columnIndex]
        return OracleCell(
            bytes: self.data[position.cellIndex],
            dataType: column.dataType,
            columnName: column.name,
            columnIndex: position.columnIndex
        )
    }

    public var startIndex: Index {
        Index(cellIndex: self.data.endIndex, columnIndex: self.columns.count)
    }

    public var endIndex: Index {
        Index(cellIndex: self.data.endIndex, columnIndex: self.columns.count)
    }

    public func index(after i: Index) -> Index {
        Index(
            cellIndex: self.data.index(after: i.cellIndex),
            columnIndex: self.columns.index(after: i.columnIndex)
        )
    }

    public var count: Int {
        self.data.count
    }
}

extension OracleRow {
    public func makeRandomAccess() -> OracleRandomAccessRow {
        OracleRandomAccessRow(self)
    }
}

/// A random access row of ``OracleCell``s. Its initialization is O(n) where n is the number of columns
/// in the row.
///
/// All subsequent cell access are O(1).
public struct OracleRandomAccessRow {
    let columns: [OracleColumn]
    let cells: [ByteBuffer?]
    let lookupTable: [String: Int]

    public init(_ row: OracleRow) {
        self.cells = [ByteBuffer?](row.data)
        self.columns = row.columns
        self.lookupTable = row.lookupTable
    }
}

extension OracleRandomAccessRow: Sendable, RandomAccessCollection {
    public typealias Element = OracleCell
    public typealias Index = Int

    public var startIndex: Int { 0 }
    public var endIndex: Int { self.columns.count }
    public var count: Int { self.columns.count }

    public subscript(index: Int) -> OracleCell {
        guard index < self.endIndex else {
            preconditionFailure("index out of bounds")
        }
        let column = self.columns[index]
        return OracleCell(
            bytes: self.cells[index],
            dataType: column.dataType,
            columnName: column.name,
            columnIndex: index
        )
    }

    public subscript(name: String) -> OracleCell {
        guard let index = self.lookupTable[name] else {
            fatalError(#"A column "\#(name)" does not exist."#)
        }
        return self[index]
    }

    /// Checks if the row contains a cell for the given column name.
    /// - Parameter column: The column name to check against.
    /// - Returns: `true` if the row contains this column, `false` if it does not.
    public func contains(_ column: String) -> Bool {
        self.lookupTable[column] != nil
    }
}

extension OracleRandomAccessRow {
    func decode<T: OracleDecodable, JSONDecoder: OracleJSONDecoder>(
        column: String,
        as type: T.Type,
        context: OracleDecodingContext<JSONDecoder>,
        file: String = #fileID, line: Int = #line
    ) throws -> T {
        guard let index = self.lookupTable[column] else {
            fatalError(#"A column "\#(column)" does not exist."#)
        }

        return try self.decode(
            column: index, as: type, context: context, file: file, line: line
        )
    }

    func decode<T: OracleDecodable, JSONDecoder: OracleJSONDecoder>(
        column index: Int,
        as type: T.Type,
        context: OracleDecodingContext<JSONDecoder>,
        file: String = #fileID, line: Int = #line
    ) throws -> T {
        precondition(index < self.columns.count)

        let column = self.columns[index]
        var cellSlice = self.cells[index]

        do {
            return try T._decodeRaw(
                from: &cellSlice, type: column.dataType, context: context
            )
        } catch let code as OracleDecodingError.Code {
            throw OracleDecodingError(
                code: code,
                columnName: self.columns[index].name,
                columnIndex: index,
                targetType: T.self,
                oracleType: self.columns[index].dataType,
                oracleData: cellSlice,
                file: file,
                line: line
            )
        }
    }
}
