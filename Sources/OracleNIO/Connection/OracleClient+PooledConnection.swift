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

import Logging

extension OracleClient {
    /// A managed version of ``OracleConnection`` that can only be obtained from an ``OracleClient``.
    ///
    /// It cannot be captured nor closed manually.
    public struct PooledConnection {
        /// A Oracle connection ID, used exclusively for logging.
        public typealias ID = OracleConnection.ID

        private let underlying: OracleConnection

        init(_ underlying: OracleConnection) {
            self.underlying = underlying
        }

        public var id: ID {
            self.underlying.id
        }

        /// The connection's session ID (SID).
        public var sessionID: Int {
            self.underlying.sessionID
        }

        /// The version of the Oracle server, the connection is established to.
        public var serverVersion: OracleVersion {
            self.underlying.serverVersion
        }

        /// Sends a ping to the database server.
        public func ping() async throws {
            try await self.underlying.ping()
        }

        /// Sends a commit to the database server.
        public func commit() async throws {
            try await self.underlying.commit()
        }

        /// Sends a rollback to the database server.
        public func rollback() async throws {
            try await self.underlying.rollback()
        }

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
        public func execute(
            _ statement: OracleStatement,
            options: StatementOptions = .init(),
            logger: Logger = OracleConnection.noopLogger,
            file: String = #fileID, line: Int = #line
        ) async throws -> OracleRowSequence {
            try await self.underlying.execute(
                statement,
                options: options,
                logger: logger,
                file: file,
                line: line
            )
        }

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
        public func execute<Statement: OraclePreparedStatement, Row>(
            _ statement: Statement,
            options: StatementOptions = .init(),
            logger: Logger = OracleConnection.noopLogger,
            file: String = #fileID, line: Int = #line
        ) async throws -> AsyncThrowingMapSequence<OracleRowSequence, Row> where Row == Statement.Row {
            try await self.underlying.execute(
                statement,
                options: options,
                logger: logger,
                file: file,
                line: line
            )
        }

        /// Runs a transaction for the provided `closure`.
        ///
        /// The function lends the connection to the user provided closure. The user can modify the database as they wish.
        /// If the user provided closure returns successfully, the function will attempt to commit the changes by running a
        /// `COMMIT` query against the database. If the user provided closure throws an error, the function will attempt to
        /// rollback the changes made within the closure.
        ///
        /// - Parameters:
        ///   - logger: The `Logger` to log into for the transaction. Defaults to logging disabled.
        ///   - file: The file, the transaction was started in. Used for better error reporting.
        ///   - line: The line, the transaction was started in. Used for better error reporting.
        ///   - closure: The user provided code to modify the database. Use the provided connection to run queries.
        /// - Returns: The closure's return value.
        public func withTransaction<Result>(
            logger: Logger = OracleConnection.noopLogger,
            file: String = #file,
            line: Int = #line,
            isolation: isolated (any Actor)? = #isolation,
            _ closure: (inout sending OracleTransactionConnection) async throws -> sending Result
        ) async throws(OracleTransactionError) -> sending Result {
            try await self.underlying.withTransaction(
                logger: logger,
                file: file,
                line: line,
                isolation: isolation,
                closure
            )
        }

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
        public func execute<each Bind: OracleThrowingDynamicTypeEncodable>(
            _ statement: String,
            binds: [(repeat (each Bind)?)],
            encodingContext: OracleEncodingContext = .default,
            options: StatementOptions = .init(),
            logger: Logger = OracleConnection.noopLogger,
            file: String = #fileID, line: Int = #line
        ) async throws -> OracleBatchExecutionResult {
            try await self.underlying.execute(
                statement,
                binds: binds,
                encodingContext: encodingContext,
                options: options,
                logger: logger,
                file: file,
                line: line
            )
        }

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
        public func execute<Statement: OraclePreparedStatement>(
            _ statements: [Statement],
            options: StatementOptions = .init(),
            logger: Logger = OracleConnection.noopLogger,
            file: String = #fileID, line: Int = #line
        ) async throws -> OracleBatchExecutionResult {
            try await self.underlying.execute(
                statements,
                options: options,
                logger: logger,
                file: file,
                line: line
            )
        }
    }
}

@available(*, unavailable)
extension OracleClient.PooledConnection: Sendable {}
