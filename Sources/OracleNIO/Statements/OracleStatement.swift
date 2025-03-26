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

    /// Creates an OracleStatement from a static SQL string and it's corresponding binds.
    /// - Parameters:
    ///   - sql: A static SQL string.
    ///   - binds: A collection of binds.
    ///
    /// The amount of binds must match the number of variables in the SQL string.
    ///
    /// ```swift
    /// let sql = "INSERT INTO my_table (content, initial_content, user_id) VALUES (:0, :0, :1)"
    /// var binds = OracleBindings(capacity: 2) // 2 due to :0 and :1 being the variables in the statement.
    /// binds.append("hello there")
    /// binds.append(1)
    /// let statement = OracleStatement(unsafeSQL: sql, binds: binds)
    /// ```
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

    /// Creates a SQL statement from a _raw string_ without binds.
    /// - Parameter value: An unescaped String without binds.
    ///
    /// This initializer should only be used with static SQL statements that do not include variables.
    ///
    /// Here is an example of using the initializer, that might lead to SQL injection.
    ///
    /// ```swift
    /// let input = "user_input"
    /// let unsafeStatement = "INSERT INTO my_table (content) VALUES ('\(input)')"
    /// print(OracleStatement(stringLiteral: unsafeStatement))
    /// // -> INSERT INTO my_table (content) VALUES ('user_input') [ ]
    /// // Potential SQL injection on unsanitized input!
    /// ```
    ///
    /// - Warning: Use this initializer with extreme caution. String interpolations won't be recognized as such, and therefor binds are not created for them.
    ///            Prefer using ``StringInterpolation`` or ``init(unsafeSQL:binds:)`` whenever possible.
    ///
    /// There are multiple ways to prevent SQL injection.
    ///
    /// ## StringInterpolation
    ///
    /// To create a ``OracleStatement`` with ``StringInterpolation``, all you need to do is add a type annotation to the statement.
    /// This is the "magic" of string interpolation.
    ///
    /// ```swift
    /// let input = "user_input"
    /// let safeStatement: OracleStatement = "INSERT INTO my_table (content) VALUES (\(input))"
    /// print(safeStatement)
    /// // -> INSERT INTO my_table (content) VALUES (:0) [ **** ]
    /// // The variable did now get correctly recognized as a bind.
    /// ```
    ///
    /// ## Bind declaration
    ///
    /// Creating the binds manually is also possible, albeit more inconvinient.
    ///
    /// ```swift
    /// let rawStatement = "INSERT INTO my_table (content) VALUES (:0)"
    /// var binds = OracleBindings(capacity: 1)
    /// binds.append(input)
    /// print(OracleStatement(unsafeSQL: rawStatement, binds: binds))
    /// // -> INSERT INTO my_table (content) VALUES (:0) [ **** ]
    /// ```
    public init(stringLiteral value: String) {
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

        /// Adds an unescaped string to the statement.
        /// - Parameter interpolation: The string that should be added to the statement.
        ///
        /// Useful when dynamically building a statement.
        ///
        /// ```swift
        /// let ascending: Bool = true
        /// let orderClause = if ascending {
        ///     "ASC"
        /// } else {
        ///     "DESC"
        /// }
        /// let statement: OracleStatement = "SELECT name FROM table ORDER BY id \(unescaped: orderClause)"
        /// print(statement)
        /// // -> SELECT name FROM table ORDER BY id ASC [ ]
        /// ```
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
