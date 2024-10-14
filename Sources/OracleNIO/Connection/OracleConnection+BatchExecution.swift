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

extension OracleConnection {
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
    /// - Returns: A ``OracleRowSequence`` containing the rows the server sent as the statement
    ///            result. The result sequence can be discarded if the statement has no result.
    ///
    /// Batch execution is useful for inserting or updating multiple rows efficiently when working with large data sets. It significally outperforms
    /// repeated calls to ``execute(_:options:logger:file:line:)`` by reducing network transfer costs and database overheads.
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
    public func executeBatch<each Bind: OracleThrowingDynamicTypeEncodable>(
        _ statement: String,
        binds: [(repeat (each Bind)?)],
        encodingContext: OracleEncodingContext = .default,
        options: StatementOptions = .init(),
        logger: Logger? = nil,
        file: String = #fileID, line: Int = #line
    ) async throws -> OracleRowSequence {
        var logger = logger ?? Self.noopLogger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        var collection = OracleBindingsCollection()
        for row in binds {
            try collection.appendRow(repeat each row, context: encodingContext)
        }

        return try await _executeBatch(
            statement: statement,
            collection: collection,
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
    /// - Returns: An async sequence of `Row`s. The result sequence can be discarded if the statement has no result.
    ///
    /// Batch execution is useful for inserting or updating multiple rows efficiently when working with large data sets. It significally outperforms
    /// repeated calls to ``execute(_:options:logger:file:line:)-9uyvp`` by reducing network transfer costs and database overheads.
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
    public func executeBatch<Statement: OraclePreparedStatement, Row>(
        _ statements: [Statement],
        options: StatementOptions = .init(),
        logger: Logger? = nil,
        file: String = #fileID, line: Int = #line
    ) async throws -> AsyncThrowingMapSequence<OracleRowSequence, Row> where Row == Statement.Row {
        if statements.isEmpty {
            throw OracleSQLError.missingStatement
        }

        var logger = logger ?? Self.noopLogger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        var collection = OracleBindingsCollection()
        for statement in statements {
            try collection.appendRow(statement.makeBindings())
        }
        let decoder = statements[0]
        let stream: OracleRowSequence = try await _executeBatch(
            statement: Statement.sql,
            collection: collection,
            options: options,
            logger: logger,
            file: file,
            line: line
        )
        return stream.map { try decoder.decodeRow($0) }
    }

    private func _executeBatch(
        statement: String,
        collection: OracleBindingsCollection,
        options: StatementOptions,
        logger: Logger,
        file: String,
        line: Int
    ) async throws -> OracleRowSequence {
        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = StatementContext(
            statement: statement,
            bindCollection: collection,
            options: options,
            logger: logger,
            promise: promise
        )

        self.channel.write(OracleTask.statement(context), promise: nil)

        do {
            return try await promise.futureResult
                .map({ $0.asyncSequence() })
                .get()
        } catch var error as OracleSQLError {
            error.file = file
            error.line = line
            error.statement = .init(unsafeSQL: statement)
            throw error  // rethrow with more metadata
        }
    }
}
