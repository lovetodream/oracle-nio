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

#if DistributedTracingSupport
    import Tracing
#endif

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
        var logger = logger
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
        if statements.isEmpty {
            throw OracleSQLError.missingStatement
        }

        var logger = logger
        logger[oracleMetadataKey: .connectionID] = "\(self.id)"
        logger[oracleMetadataKey: .sessionID] = "\(self.sessionID)"

        var collection = OracleBindingsCollection()
        for statement in statements {
            try collection.appendRow(statement.makeBindings())
        }
        return try await _executeBatch(
            statement: Statement.sql,
            collection: collection,
            options: options,
            logger: logger,
            file: file,
            line: line
        )
    }

    private func _executeBatch(
        statement: String,
        collection: OracleBindingsCollection,
        options: StatementOptions,
        logger: Logger,
        file: String,
        line: Int
    ) async throws -> OracleBatchExecutionResult {
        var statementParser = OracleStatement.Parser(currentSQL: statement)
        try? statementParser.continueParsing(with: statement)

        #if DistributedTracingSupport
            let span = self.tracer?.startSpan(statementParser.keyword, ofKind: .client)
            span?.updateAttributes { attributes in
                self.applyCommonAttributes(
                    to: &attributes,
                    querySummary: statementParser.summary.joined(separator: " "),
                    queryText: statement
                )
                attributes[self.configuration.tracing.attributeNames.databaseOperationBatchSize] =
                    collection.bindings.count
            }
            defer { span?.end() }
        #endif

        let promise = self.channel.eventLoop.makePromise(
            of: OracleRowStream.self
        )
        let context = StatementContext(
            statement: statement,
            keyword: statementParser.keyword,
            isReturning: statementParser.isReturning,
            bindCollection: collection,
            options: options,
            logger: logger,
            promise: promise
        )

        self.channel.write(OracleTask.statement(context), promise: nil)

        do {
            let stream = try await promise.futureResult
                .map({ $0.asyncSequence() })
                .get()
            let affectedRows = try await stream.affectedRows
            let affectedRowsPerStatement = options.arrayDMLRowCounts ? stream.rowCounts : nil
            let batchErrors = options.batchErrors ? stream.batchErrors : nil
            let result = OracleBatchExecutionResult(
                affectedRows: affectedRows,
                affectedRowsPerStatement: affectedRowsPerStatement
            )
            if let batchErrors {
                throw OracleBatchExecutionError(
                    result: result,
                    errors: batchErrors,
                    statement: statement,
                    file: file,
                    line: line
                )
            }
            return result
        } catch var error as OracleSQLError {
            error.file = file
            error.line = line
            error.statement = .init(unsafeSQL: statement)
            #if DistributedTracingSupport
                span?.recordError(error)
                span?.setStatus(SpanStatus(code: .error))
                span?.attributes[self.configuration.tracing.attributeNames.errorType] = error.code.description
                if let number = error.serverInfo?.number {
                    span?.attributes[self.configuration.tracing.attributeNames.databaseResponseStatusCode] =
                        "ORA-\(String(number, padding: 5))"
                }
            #endif
            throw error  // rethrow with more metadata
        }
    }
}

/// The result of a batch execution.
public struct OracleBatchExecutionResult: Sendable {
    /// The total amount of affected rows.
    public let affectedRows: Int
    /// The amount of affected rows per statement.
    ///
    /// - Note: Only available if ``StatementOptions/arrayDMLRowCounts`` is set to `true`.
    ///
    /// For example, if five single row `INSERT` statements are executed and the fifth one fails, the following array would be returned.
    /// ```swift
    /// [1, 1, 1, 1, 0]
    /// ```
    public let affectedRowsPerStatement: [Int]?
}

/// An error that is thrown when a batch execution contains both successful and failed statements.
///
/// - Note: This error is only thrown when ``StatementOptions/batchErrors`` is set to `true`.
///         Otherwise ``OracleSQLError`` will be thrown as usual. Be aware that all the statements
///         executed before the error is thrown won't be reverted regardless of this setting.
///         They can still be reverted using a ``OracleConnection/rollback()``.
public struct OracleBatchExecutionError: Error, Sendable {
    /// The result of the partially finished batch execution.
    public let result: OracleBatchExecutionResult
    /// A collection of errors thrown by statements in the batch execution.
    public let errors: [OracleSQLError.BatchError]
    public let statement: String
    public let file: String
    public let line: Int
}
