//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging

public protocol OracleConnectionProtocol {
    /// A Oracle connection ID, used exclusively for logging.
    associatedtype ID

    var id: ID { get }

    /// The connection's session ID (SID).
    var sessionID: Int { get }

    /// The version of the Oracle server, the connection is established to.
    var serverVersion: OracleVersion { get }

    /// Run a statement on the Oracle server the connection is connected to.
    ///
    /// - Parameters:
    ///   - statement: The ``OracleStatement`` to run.
    ///   - options: A bunch of parameters to optimize the statement in different ways.
    ///              Normally this can be ignored, but feel free to experiment based on your needs.
    ///              Every option and its impact is documented.
    ///   - logger: The `Logger` to log statement related background events into. Defaults to logging disabled.
    ///   - file: The file, the statement was started in. Used for better error reporting.
    ///   - line: The line, the statement was started in. Used for better error reporting.
    /// - Returns: A ``OracleRowSequence`` containing the rows the server sent as the statement
    ///            result. The result sequence can be discarded if the statement has no result.
    @discardableResult
    func execute(
        _ statement: OracleStatement,
        options: StatementOptions,
        logger: Logger,
        file: String, line: Int
    ) async throws -> OracleRowSequence

    /// Execute a prepared statement.
    /// - Parameters:
    ///   - statement: The statement to be executed.
    ///   - options: A bunch of parameters to optimize the statement in different ways.
    ///              Normally this can be ignored, but feel free to experiment based on your needs.
    ///              Every option and its impact is documented.
    ///   - logger: The `Logger` to log statement related background events into. Defaults to logging disabled.
    ///   - file: The file, the statement was started in. Used for better error reporting.
    ///   - line: The line, the statement was started in. Used for better error reporting.
    /// - Returns: An async sequence of `Row`s. The result sequence can be discarded if the statement has no result.
    @discardableResult
    func execute<Statement: OraclePreparedStatement, Row>(
        _ statement: Statement,
        options: StatementOptions,
        logger: Logger,
        file: String, line: Int
    ) async throws -> AsyncThrowingMapSequence<OracleRowSequence, Row> where Row == Statement.Row

    /// Executes the statement multiple times using the specified bind collections without requiring multiple roundtrips to the database.
    /// - Parameters:
    ///   - statement: The raw SQL statement.
    ///   - binds: A collection of bind parameters to execute the statement with. The statement will execute `binds.count` times.
    ///   - encodingContext: The ``OracleEncodingContext`` used to encode the binds. A default parameter is provided.
    ///   - options: A bunch of parameters to optimize the statement in different ways.
    ///              Normally this can be ignored, but feel free to experiment based on your needs.
    ///              Every option and its impact is documented.
    ///   - logger: The `Logger` to log statement related background events into. Defaults to logging disabled.
    ///   - file: The file, the statement was started in. Used for better error reporting.
    ///   - line: The line, the statement was started in. Used for better error reporting.
    /// - Returns: A ``OracleBatchExecutionResult`` containing the amount of affected rows and other metadata the server sent.
    ///
    /// Batch execution is useful for inserting or updating multiple rows efficiently when working with large data sets. It significally outperforms
    /// repeated calls to ``execute(_:options:logger:file:line:)->OracleRowSequence`` by reducing network transfer costs and database overheads.
    /// It can also be used to execute PL/SQL statements multiple times at once.
    /// ```swift
    /// let binds: [(Int, String, Int)] = [
    ///     (1, "John", 20),
    ///     (2, "Jane", 30),
    ///     (3, "Jack", 40),
    ///     (4, "Jill", 50),
    ///     (5, "Pete", 60),
    /// ]
    /// try await connection.executeBatch(
    ///     "INSERT INTO users (id, name, age) VALUES (:1, :2, :3)",
    ///     binds: binds
    /// )
    /// ```
    @discardableResult
    func execute<each Bind: OracleThrowingDynamicTypeEncodable>(
        _ statement: String,
        binds: [(repeat (each Bind)?)],
        encodingContext: OracleEncodingContext,
        options: StatementOptions,
        logger: Logger,
        file: String, line: Int
    ) async throws -> OracleBatchExecutionResult

    /// Executes the prepared statements without requiring multiple roundtrips to the database.
    /// - Parameters:
    ///   - statements: The prepared statements to execute.
    ///   - options: A bunch of parameters to optimize the statement in different ways.
    ///              Normally this can be ignored, but feel free to experiment based on your needs.
    ///              Every option and its impact is documented.
    ///   - logger: The `Logger` to log statement related background events into. Defaults to logging disabled.
    ///   - file: The file, the statement was started in. Used for better error reporting.
    ///   - line: The line, the statement was started in. Used for better error reporting.
    /// - Returns: A ``OracleBatchExecutionResult`` containing the amount of affected rows and other metadata the server sent.
    ///
    /// Batch execution is useful for inserting or updating multiple rows efficiently when working with large data sets. It significally outperforms
    /// repeated calls to ``execute(_:options:logger:file:line:)->AsyncThrowingMapSequence<OracleRowSequence,Row>`` by reducing network transfer costs and database overheads.
    /// It can also be used to execute PL/SQL statements multiple times at once.
    /// ```swift
    /// try await connection.executeBatch([
    ///     InsertUserStatement(id: 1, name: "John", age: 20),
    ///     InsertUserStatement(id: 2, name: "Jane", age: 30),
    ///     InsertUserStatement(id: 3, name: "Jack", age: 40),
    ///     InsertUserStatement(id: 4, name: "Jill", age: 50),
    ///     InsertUserStatement(id: 5, name: "Pete", age: 60),
    /// ])
    /// ```
    @discardableResult
    func execute<Statement: OraclePreparedStatement>(
        _ statements: [Statement],
        options: StatementOptions,
        logger: Logger,
        file: String, line: Int
    ) async throws -> OracleBatchExecutionResult
}
