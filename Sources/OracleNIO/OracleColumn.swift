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

/// Describes the metadata of a table's column on an Oracle server.
public struct OracleColumn: Hashable, Sendable {
    let underlying: DescribeInfo.Column

    /// The field name.
    public var name: String { self.underlying.name }
}

public struct OracleColumns: Sequence {
    public typealias Element = OracleColumn

    var underlying: [DescribeInfo.Column]

    @usableFromInline
    init(underlying: [DescribeInfo.Column]) {
        self.underlying = underlying
    }

    public func makeIterator() -> Iterator {
        Iterator(underlying: self.underlying.makeIterator())
    }

    public struct Iterator: IteratorProtocol {
        var underlying: [DescribeInfo.Column].Iterator

        public mutating func next() -> OracleColumn? {
            guard let element = self.underlying.next() else {
                return nil
            }
            return OracleColumn(underlying: element)
        }
    }
}
