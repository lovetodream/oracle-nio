//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension OracleRow {
    // --- snip TODO: Remove once bug is fixed, that disallows tuples of one
    @inlinable
    public func decode<Column: OracleDecodable>(
        _: Column.Type,
        file: String = #fileID,
        line: Int = #line
    ) throws -> (Column) {
        try self.decode(Column.self, context: .default, file: file, line: line)
    }

    @inlinable
    public func decode<Column: OracleDecodable>(
        _: Column.Type,
        context: OracleDecodingContext<some OracleJSONDecoder>,
        file: String = #fileID,
        line: Int = #line
    ) throws -> (Column) {
        precondition(self.columns.count >= 1)
        let columnIndex = 0
        var cellIterator = self.data.makeIterator()
        var cellData = cellIterator.next().unsafelyUnwrapped
        var columnIterator = self.columns.makeIterator()
        let column = columnIterator.next().unsafelyUnwrapped
        let swiftTargetType: Any.Type = Column.self

        do {
            let r0 = try Column._decodeRaw(
                from: &cellData, type: column.dataType, context: context
            )

            return (r0)
        } catch let code as OracleDecodingError.Code {
            throw OracleDecodingError(
                code: code,
                columnName: column.name,
                columnIndex: columnIndex,
                targetType: swiftTargetType,
                oracleType: column.dataType,
                oracleData: cellData,
                file: file,
                line: line
            )
        }
    }
    // --- snap TODO: Remove once bug is fixed, that disallows tuples of one

    @inlinable
    public func decode<each Column: OracleDecodable>(
        _ columnType: (repeat each Column).Type,
        context: OracleDecodingContext<some OracleJSONDecoder>,
        file: String = #fileID,
        line: Int = #line
    ) throws -> (repeat each Column) {
        let packCount = ComputeParameterPackLength.count(ofPack: repeat (each Column).self)
        precondition(self.columns.count >= packCount)

        var columnIndex = 0
        var cellIterator = self.data.makeIterator()
        var columnIterator = self.columns.makeIterator()

        return
            (repeat try Self.decodeNextColumn(
                (each Column).self,
                cellIterator: &cellIterator,
                columnIterator: &columnIterator,
                columnIndex: &columnIndex,
                context: context,
                file: file,
                line: line
            ))
    }

    @inlinable
    static func decodeNextColumn<Column: OracleDecodable>(
        _ columnType: Column.Type,
        cellIterator: inout IndexingIterator<DataRow>,
        columnIterator: inout IndexingIterator<[OracleColumn]>,
        columnIndex: inout Int,
        context: OracleDecodingContext<some OracleJSONDecoder>,
        file: String,
        line: Int
    ) throws -> Column {
        defer { columnIndex += 1 }

        let column = columnIterator.next().unsafelyUnwrapped
        var cellData = cellIterator.next().unsafelyUnwrapped
        do {
            return try Column._decodeRaw(
                from: &cellData, type: column.dataType, context: context
            )
        } catch let code as OracleDecodingError.Code {
            throw OracleDecodingError(
                code: code,
                columnName: column.name,
                columnIndex: columnIndex,
                targetType: Column.self,
                oracleType: column.dataType,
                oracleData: cellData,
                file: file,
                line: line
            )
        }
    }

    @inlinable
    public func decode<each Column: OracleDecodable>(
        _ columnType: (repeat each Column).Type,
        file: String = #fileID,
        line: Int = #line
    ) throws -> (repeat each Column) {
        try self.decode(columnType, context: .default, file: file, line: line)
    }
}

extension AsyncSequence where Element == OracleRow {
    // --- snip TODO: Remove once bug is fixed, that disallows tuples of one
    @inlinable
    public func decode<Column: OracleDecodable>(
        _: Column.Type,
        context: OracleDecodingContext<some OracleJSONDecoder>,
        file: String = #fileID,
        line: Int = #line
    ) -> AsyncThrowingMapSequence<Self, (Column)> {
        self.map { row in
            try row.decode(Column.self, context: context, file: file, line: line)
        }
    }

    @inlinable
    public func decode<Column: OracleDecodable>(
        _: Column.Type,
        file: String = #fileID,
        line: Int = #line
    ) -> AsyncThrowingMapSequence<Self, (Column)> {
        self.decode(Column.self, context: .default, file: file, line: line)
    }
    // --- snap TODO: Remove once bug is fixed, that disallows tuples of one

    public func decode<each Column: OracleDecodable>(
        _ columnType: (repeat each Column).Type,
        context: OracleDecodingContext<some OracleJSONDecoder>,
        file: String = #fileID,
        line: Int = #line
    ) -> AsyncThrowingMapSequence<Self, (repeat each Column)> {
        self.map { row in
            try row.decode(columnType, context: context, file: file, line: line)
        }
    }

    public func decode<each Column: OracleDecodable>(
        _ columnType: (repeat each Column).Type,
        file: String = #fileID,
        line: Int = #line
    ) -> AsyncThrowingMapSequence<Self, (repeat each Column)> {
        self.decode(columnType, context: .default, file: file, line: line)
    }
}

@usableFromInline
enum ComputeParameterPackLength {
    @usableFromInline
    enum BoolConverter<T> {
        @usableFromInline
        typealias Bool = Swift.Bool
    }

    @inlinable
    static func count<each T>(ofPack t: repeat each T) -> Int {
        MemoryLayout<(repeat BoolConverter<each T>.Bool)>.size / MemoryLayout<Bool>.stride
    }
}
