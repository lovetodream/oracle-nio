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

/// A prepared statement.
///
/// Structs conforming to this protocol have to provide an SQL statement to send to the server,
/// a way of creating bindings and a way to decode the results.
///
/// As an example, consider this struct:
/// ```swift
/// struct Example: OraclePreparedStatement {
///     static let sql = "SELECT id, name, age FROM users WHERE :1 < age"
///     typealias Row = (Int, String, Int)
///
///     var age: Int
///
///     func makeBindings() -> OracleBindings {
///         var bindings = OracleBindings()
///         bindings.append(age, context: .default, bindName: "1")
///         return bindings
///     }
///
///     func decodeRow(_ row: OracleRow) throws -> Row {
///         try row.decode(Row.self)
///     }
/// }
/// ```
///
/// Conformance to this protocol can also be implemented with the ``Statement(_:)`` macro.
///
/// Structs conforming to this protocol can be used with ``OracleConnection/execute(_:options:logger:file:line:)-9uyvp``.
public protocol OraclePreparedStatement: Sendable {
    /// The prepared statements name.
    ///
    /// > Note: There is a default implementation that returns the implementor's name.
    static var name: String { get }

    /// The type rows returned by the statement will be decoded into.
    associatedtype Row

    /// The SQL statement to prepare on the database server.
    static var sql: String { get }

    /// Make the bindings to provide concrete values to use when executing the prepared SQL statement.
    func makeBindings() throws -> OracleBindings

    /// Decode a row returned by the database into an instance of ``OraclePreparedStatement/Row``.
    func decodeRow(_ row: OracleRow) throws -> Row
}


extension OraclePreparedStatement {
    public static var name: String { String(reflecting: self) }
}

/// A parsable String literal for the ``Statement(_:)`` macro. It doesn't store anything and is completely useless outside of the ``Statement(_:)`` declaration.
///
/// ```swift
/// @Statement("SELECT \("id", Int.self), \("name", String.self), \("age", Int.self) FROM users")
/// struct UsersStatement {}
/// ```
public struct _OracleStatementString: ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {}

    public init(stringInterpolation: StringInterpolation) {}

    public struct StringInterpolation: StringInterpolationProtocol {
        public typealias StringLiteralType = String

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {}

        /// Adds a column, e.g. inside a `SELECT` statement.
        /// - Parameters:
        ///   - name: The column name in SQL.
        ///   - type: The type used to represent the column data in Swift.
        ///   - as: An optional alias for the column. It will be used in as an alias in SQL and the declaration Swifts ``OraclePreparedStatement/Row`` struct.
        ///
        /// ```swift
        ///"SELECT \("id", Int.self) FROM users"
        ///// -> SQL:   SELECT id FROM users
        ///// -> Swift: struct Row { var id: Int }
        ///
        ///"SELECT \("user_id", Int.self, as: userID) FROM users"
        ///// -> SQL:   SELECT id as userID FROM users
        ///// -> SWIFT: struct Row { var userID: Int }
        /// ```
        public mutating func appendInterpolation(
            _ name: String,
            _ type: (some OracleThrowingDynamicTypeEncodable).Type,
            as: String? = nil
        ) {}

        /// Adds a bind variable.
        /// - Parameters:
        ///   - bind: The name of the bind variable in Swift.
        ///   - type: The Swift type of the bind variable.
        public mutating func appendInterpolation(
            bind: String,
            _ type: (some OracleDecodable).Type
        ) {}
    }
}

/// Defines and implements conformance of the OraclePreparedStatement protocol for Structs.
///
/// For example, the following code applies the `Statement` macro to the type `UsersStatement`:
/// ```swift
/// @Statement("SELECT \("id", Int.self), \("name", String.self), \("age", Int.self) FROM users WHERE \(bind: "age", OracleNumber.self) < age")
/// struct UsersStatement {}
/// ```
///
/// You can send Statements to an Oracle Database server
/// with ``OracleConnection/execute(_:options:logger:file:line:)-9uyvp``.
@attached(member, names: arbitrary)
@attached(extension, conformances: OraclePreparedStatement)
public macro Statement(_ statement: _OracleStatementString) =
    #externalMacro(module: "OracleNIOMacros", type: "OracleStatementMacro")
