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

import NIOConcurrencyHelpers
import NIOCore

/// A Oracle SQL statement, that can be executed on a Oracle server.
/// Contains the raw sql string and bindings.
public struct OracleStatement: Sendable, Hashable {
    /// The statement's string.
    public var sql: String
    /// The statement's binds.
    public var binds: OracleBindings

    public init(
        unsafeSQL sql: String,
        binds: OracleBindings = OracleBindings()
    ) {
        self.sql = sql
        self.binds = binds
    }
}

extension OracleStatement: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self.sql = stringInterpolation.sql
        self.binds = stringInterpolation.binds
    }

    public init(stringLiteral value: StringLiteralType) {
        self.sql = value
        self.binds = OracleBindings()
    }
}

extension OracleStatement {
    public struct StringInterpolation: StringInterpolationProtocol {
        public typealias StringLiteralType = String

        @usableFromInline
        var sql: String
        @usableFromInline
        var binds: OracleBindings

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.sql = ""
            self.binds = OracleBindings(capacity: interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            self.sql.append(contentsOf: literal)
        }

        @inlinable
        public mutating func appendInterpolation(
            _ value: some OracleThrowingDynamicTypeEncodable,
            context: OracleEncodingContext = .default
        ) throws {
            let bindName = "\(self.binds.count)"
            try self.binds.append(value, context: context, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation<T: OracleThrowingDynamicTypeEncodable>(
            _ value: T?,
            context: OracleEncodingContext = .default
        ) throws {
            let bindName = "\(self.binds.count)"
            switch value {
            case .none:
                self.binds.appendNull(T.defaultOracleType, bindName: bindName)
            case .some(let value):
                try self.binds
                    .append(value, context: context, bindName: bindName)
            }

            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation(
            _ value: some OracleDynamicTypeEncodable,
            context: OracleEncodingContext = .default
        ) {
            let bindName = "\(self.binds.count)"
            self.binds.append(value, context: context, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation(
            _ value: (some OracleDynamicTypeEncodable)?,
            context: OracleEncodingContext = .default
        ) {
            let bindName = "\(self.binds.count)"
            switch value {
            case .none:
                self.binds.appendNull(value?.oracleType, bindName: bindName)
            case .some(let value):
                self.binds.append(value, context: context, bindName: bindName)
            }

            self.sql.append(contentsOf: ":\(bindName)")
        }

        public mutating func appendInterpolation(_ value: some OracleRef) {
            if let bindName = self.binds.contains(ref: value) {
                self.sql.append(contentsOf: ":\(bindName)")
            } else {
                let bindName = "\(self.binds.count)"
                self.binds.append(value, bindName: bindName)
                self.sql.append(contentsOf: ":\(bindName)")
            }
        }

        /// Adds a list of values as individual binds.
        ///
        /// ```swift
        /// let values = [15, 24, 33]
        /// let statement: OracleStatement = "SELECT id FROM my_table WHERE id IN (\(list: values))"
        /// print(statement.sql)
        /// // SELECT id FROM my_table WHERE id IN (:1, :2, :3)
        /// ```
        @inlinable
        public mutating func appendInterpolation(
            list: [some OracleDynamicTypeEncodable],
            context: OracleEncodingContext = .default
        ) {
            guard !list.isEmpty else { return }
            for value in list {
                self.appendInterpolation(value, context: context)
                self.sql.append(", ")
            }
            self.sql.removeLast(2)
        }

        @inlinable
        public mutating func appendInterpolation(unescaped interpolation: String) {
            self.sql.append(contentsOf: interpolation)
        }
    }
}

extension OracleStatement: CustomStringConvertible {
    public var description: String {
        "\(self.sql) \(self.binds)"
    }
}

extension OracleStatement: CustomDebugStringConvertible {
    public var debugDescription: String {
        "OracleStatement(sql: \(String(describing: self.sql)), binds: \(String(reflecting: self.binds))"
    }
}
