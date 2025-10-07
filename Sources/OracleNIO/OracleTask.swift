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

import Atomics
import Logging
import NIOConcurrencyHelpers
import NIOCore
import RegexBuilder

enum OracleTask: Sendable {
    case statement(StatementContext)
    case ping(EventLoopPromise<Void>)
    case commit(EventLoopPromise<Void>)
    case rollback(EventLoopPromise<Void>)
    case lobOperation(LOBOperationContext)

    func failWithError(_ error: OracleSQLError) {
        switch self {
        case .statement(let context):
            switch context.type {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise),
                .cursor(_, let promise),
                .plain(let promise):
                promise.fail(error)
            }
        case .ping(let promise), .commit(let promise), .rollback(let promise):
            promise.fail(error)
        case .lobOperation(let context):
            context.promise.fail(error)
        }
    }
}

final class LOBOperationContext: Sendable {
    let sourceLOB: LOB?
    let sourceOffset: UInt64
    let destinationLOB: LOB?
    let destinationOffset: UInt64
    let operation: Constants.LOBOperation
    let sendAmount: Bool
    let amount: UInt64
    let promise: EventLoopPromise<ByteBuffer?>

    private let storage: NIOLockedValueBox<Storage>

    struct Storage {
        var fetchedAmount: Int64?
        var boolFlag: Bool?
        var data: ByteBuffer?
    }

    init(
        sourceLOB: LOB?,
        sourceOffset: UInt64,
        destinationLOB: LOB?,
        destinationOffset: UInt64,
        operation: Constants.LOBOperation,
        sendAmount: Bool,
        amount: UInt64,
        promise: EventLoopPromise<ByteBuffer?>,
        data: ByteBuffer? = nil
    ) {
        self.sourceLOB = sourceLOB
        self.sourceOffset = sourceOffset
        self.destinationLOB = destinationLOB
        self.destinationOffset = destinationOffset
        self.operation = operation
        self.sendAmount = sendAmount
        self.amount = amount
        self.promise = promise
        self.storage = .init(.init(data: data))
    }

    func withLock<R>(_ body: (inout Storage) throws -> R) rethrows -> R {
        return try self.storage.withLockedValue(body)
    }
}

final class StatementContext: Sendable {
    enum StatementType {
        case query(EventLoopPromise<OracleRowStream>)
        case plsql(EventLoopPromise<OracleRowStream>)
        case dml(EventLoopPromise<OracleRowStream>)
        case ddl(EventLoopPromise<OracleRowStream>)
        case cursor(Cursor, EventLoopPromise<OracleRowStream>)
        case plain(EventLoopPromise<OracleRowStream>)

        var isQuery: Bool {
            switch self {
            case .query:
                return true
            case .cursor(let cursor, _):
                return cursor.isQuery
            default:
                return false
            }
        }

        var isPlSQL: Bool {
            switch self {
            case .plsql:
                return true
            default:
                return false
            }
        }

        var isDDL: Bool {
            switch self {
            case .ddl:
                return true
            default:
                return false
            }
        }
    }

    enum Binds {
        case none
        /// Single statement.
        case one(OracleBindings)
        /// Bulk statement, e.g. multiple rows to insert.
        ///
        /// Used in ``OracleConnection/execute(_:binds:encodingContext:options:logger:)``.
        case many(OracleBindingsCollection)

        var count: Int {
            switch self {
            case .none:
                return 0
            case .one(let binds):
                return binds.count
            case .many(let collection):
                return collection.metadata.count
            }
        }

        var metadata: [OracleBindings.Metadata] {
            switch self {
            case .none:
                return []
            case .one(let binds):
                return binds.metadata
            case .many(let collection):
                return collection.metadata
            }
        }

        var hasData: Bool {
            switch self {
            case .none:
                return false
            case .one(let binds):
                return !binds.metadata.isEmpty && (binds.bytes.readableBytes > 0 || binds.longBytes.readableBytes > 0)
            case .many(let collection):
                return collection.hasData
            }
        }
    }

    let type: StatementType
    let keyword: String
    let sql: String
    let binds: Binds
    let options: StatementOptions
    let logger: Logger

    // metadata
    let sqlLength: UInt32
    let cursorID: UInt16
    let isReturning: Bool
    let executionCount: UInt32

    init(
        statement: OracleStatement,
        options: StatementOptions,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) {
        self.logger = logger
        self.sql = statement.sql
        self.binds = .one(statement.binds)
        self.options = options
        self.sqlLength = .init(statement.sql.data(using: .utf8)?.count ?? 0)
        self.cursorID = 0
        self.executionCount = 1
        self.type = Self.determineType(for: statement.keyword, promise: promise)
        self.isReturning = statement.isReturning
        self.keyword = statement.keyword
    }

    init(
        statement: String,
        keyword: String,
        isReturning: Bool,
        bindCollection: OracleBindingsCollection,
        options: StatementOptions,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) {
        self.logger = logger
        self.sql = statement
        self.binds = .many(bindCollection)
        self.options = options
        self.sqlLength = UInt32(statement.utf8.count)
        self.cursorID = 0
        self.executionCount = UInt32(bindCollection.bindings.count)
        self.type = Self.determineType(for: keyword, promise: promise)
        self.isReturning = isReturning
        self.keyword = keyword
    }

    init(
        cursor: Cursor,
        options: StatementOptions,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) {
        self.logger = logger
        self.sql = ""
        self.binds = .none
        self.sqlLength = 0
        self.cursorID = cursor.id
        self.options = options
        self.isReturning = false
        self.executionCount = 1
        self.type = .cursor(cursor, promise)
        self.keyword = "CURSOR"
    }

    private static func determineType(
        for keyword: String,
        promise: EventLoopPromise<OracleRowStream>
    ) -> StatementType {
        switch keyword {
        case "DECLARE", "BEGIN", "CALL":
            return .plsql(promise)
        case "SELECT", "WITH":
            return .query(promise)
        case "INSERT", "UPDATE", "DELETE", "MERGE":
            return .dml(promise)
        case "CREATE", "ALTER", "DROP", "GRANT", "REVOKE", "ANALYZE", "AUDIT", "COMMENT", "TRUNCATE":
            return .ddl(promise)
        default:
            return .plain(promise)
        }
    }
}

public struct StatementOptions: Sendable {
    /// Automatically commit every change made to the database.
    ///
    /// This happens on the Oracle server side. So it won't cause additional roundtrips to the database.
    public var autoCommit: Bool = false

    /// Adds row counts per statement to ``OracleBatchExecutionResult``.
    ///
    /// This means, when running a batch execute with 5 update statements,
    /// ``OracleBatchExecutionResult/affectedRowsPerStatement`` shows how many
    /// rows have been affected by each statement.
    /// ``OracleBatchExecutionResult/affectedRows`` still returns the total
    /// amount of affected rows.
    ///
    /// This setting won't work for normal statement executions.
    public var arrayDMLRowCounts: Bool = false

    /// Indicates how errors will be handled in batch executions.
    ///
    /// If false, batch executions will discard all remaining data sets after an error occurred.
    ///
    /// If true, all data sets will be executed. Data sets with errors are skipped and the corresponding errors are
    /// returned after the full operation is finished.
    ///
    /// This setting won't work for normal statement executions.
    public var batchErrors: Bool = false

    /// Indicates how many rows will be returned with the initial roundtrip.
    ///
    /// Basically this can be left at `2`. Only if a specific amount of rows is fetched, this can be adjusted
    /// to how many rows are returned `+1` for avoiding an extra roundtrip. The one extra row is required
    /// for the protocol to know there aren't any more rows to fetch. If the extra row is not added, the client
    /// has to make another roundtrip to be sure that there aren't any more rows pending.
    ///
    /// Adjusting this is especially useful if you're doing pagination.
    ///
    /// ```
    /// | Number of Rows | prefetchrows | arraysize | Round-trips |
    /// |----------------|--------------|-----------|-------------|
    /// | 20             | 20           | 20        | 2           |
    /// | 20             | 21           | 20        | 1           |
    /// ```
    public var prefetchRows: Int = 2

    /// Indicates how many rows will be returned by any subsequent fetch calls to the database.
    ///
    /// If you're fetching a huge amount of rows, it makes sense to increase this value to reduce roundtrips
    /// to the database.
    ///
    /// ```
    /// | Number of Rows | prefetchRows | arraySize | Round-trips |
    /// |----------------|--------------|-----------|-------------|
    /// | 10000          | 2            | 100       | 101         |
    /// | 10000          | 2            | 1000      | 11          |
    /// | 10000          | 1000         | 1000      | 11          |
    /// ```
    public var arraySize: Int = 100

    /// Defines if LOBs (BLOB, CLOB, NCLOB) should be fetched as LOBs, which requires another
    /// round-trip to the server.
    ///
    /// If this is set to false, LOBs are fetched as bytes and retrieved inline. This doesn't require another
    /// round-trip and should be more performant.
    ///
    /// - Warning: If you have LOBs > 1GB, you need to set this to `true`. Because LOBs of that size
    ///            cannot be fetched inline.
    public var fetchLOBs = false

    /// Options to pass to a ``OracleStatement`` to tweak its execution.
    /// - Parameters:
    ///   - autoCommit: Automatically commit after execution of the statement without needing an
    ///                 additional roundtrip.
    ///   - arrayDMLRowCounts: Adds row counts per statement to ``OracleBatchExecutionResult``.
    ///                        Refer to ``arrayDMLRowCounts`` for additional explanation.
    ///   - batchErrors: Indicates how errors are handled in batch executions. Refer to
    ///                  ``batchErrors`` for additional explanation.
    ///   - prefetchRows: Indicates how many rows should be fetched with the initial response from
    ///                   the database. Refer to ``prefetchRows`` for additional explanation.
    ///   - arraySize: Indicates how many rows will be returned by any subsequent fetch calls to the
    ///                database. Refer to ``arraySize`` for additional explanation.
    ///   - fetchLOBs: Defines if LOBs (BLOB, CLOB, NCLOB) should be fetched as LOBs, which
    ///                requires another round-trip to the server.
    public init(
        autoCommit: Bool = false,
        arrayDMLRowCounts: Bool = false,
        batchErrors: Bool = false,
        prefetchRows: Int = 2,
        arraySize: Int = 50,
        fetchLOBs: Bool = false
    ) {
        self.autoCommit = autoCommit
        self.arrayDMLRowCounts = arrayDMLRowCounts
        self.batchErrors = batchErrors
        self.prefetchRows = prefetchRows
        self.arraySize = arraySize
        self.fetchLOBs = fetchLOBs
    }
}

final class CleanupContext {
    var cursorsToClose: Set<UInt16> = []

    var tempLOBsTotalSize: Int = 0
    var tempLOBsToClose: [[UInt8]]? = nil

    init(
        cursorsToClose: Set<UInt16> = [],
        tempLOBsTotalSize: Int = 0,
        tempLOBsToClose: [[UInt8]]? = nil
    ) {
        self.cursorsToClose = cursorsToClose
        self.tempLOBsTotalSize = tempLOBsTotalSize
        self.tempLOBsToClose = tempLOBsToClose
    }
}
