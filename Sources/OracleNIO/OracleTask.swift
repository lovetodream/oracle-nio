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

import Logging
import NIOCore
import RegexBuilder

enum OracleTask {
    case statement(StatementContext)
    case ping(EventLoopPromise<Void>)
    case commit(EventLoopPromise<Void>)
    case rollback(EventLoopPromise<Void>)

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
        case .ping(let promise):
            promise.fail(error)
        case .commit(let promise):
            promise.fail(error)
        case .rollback(let promise):
            promise.fail(error)
        }
    }
}

final class StatementContext {
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

    let type: StatementType
    let statement: OracleStatement
    let options: StatementOptions
    let logger: Logger

    // metadata
    let sqlLength: UInt32
    var cursorID: UInt16 = 0
    let requiresFullExecute: Bool = false
    var requiresDefine: Bool = false
    var noPrefetch: Bool = false
    let isReturning: Bool

    var sequenceNumber: UInt8 = 2

    init(
        statement: OracleStatement,
        options: StatementOptions,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) {
        self.logger = logger
        self.statement = statement
        self.options = options
        self.sqlLength = .init(statement.sql.data(using: .utf8)?.count ?? 0)

        // strip single/multiline comments and and strings from the sql
        var sql = statement.sql
        sql = sql.replacing(/\/\*[\S\n ]+?\*\//, with: "")
        sql = sql.replacing(/\--.*(\n|$)/, with: "")
        sql = sql.replacing(/'[^']*'(?=(?:[^']*[^']*')*[^']*$)/, with: "")

        self.isReturning =
            statement.binds.metadata
            .first(where: \.isReturnBind) != nil
        let type = Self.determineStatementType(
            minifiedSQL: sql, promise: promise
        )
        self.type = type
    }

    init(
        cursor: Cursor,
        options: StatementOptions,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) {
        self.logger = logger
        self.statement = ""
        self.sqlLength = 0
        self.cursorID = cursor.id
        self.options = options
        self.isReturning = false
        self.type = .cursor(cursor, promise)
    }

    private static func determineStatementType(
        minifiedSQL sql: String,
        promise: EventLoopPromise<OracleRowStream>
    ) -> StatementType {
        var fragment = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if fragment.first == "(" {
            fragment.removeFirst()
        }
        let tokens = fragment.prefix(10)
            .components(separatedBy: .whitespacesAndNewlines)
        guard let sqlKeyword = tokens.first?.uppercased() else {
            return .plain(promise)
        }
        switch sqlKeyword {
        case "DECLARE", "BEGIN", "CALL":
            return .plsql(promise)
        case "SELECT", "WITH":
            return .query(promise)
        case "INSERT", "UPDATE", "DELETE", "MERGE":
            return .dml(promise)
        case "CREATE", "ALTER", "DROP", "TRUNCATE":
            return .ddl(promise)
        default:
            return .plain(promise)
        }
    }
}

public struct StatementOptions {
    /// Automatically commit every change made to the database.
    ///
    /// This happens on the Oracle server side. So it won't cause additional roundtrips to the database.
    public var autoCommit: Bool = false

    internal var arrayDMLRowCounts: Bool = false
    internal var batchErrors: Bool = false

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
    internal var fetchLOBs = false

    /// Options to pass to a ``OracleStatement`` to tweak its execution.
    /// - Parameters:
    ///   - autoCommit: Automatically commit after execution of the statement without needing an
    ///                 additional roundtrip.
    ///   - prefetchRows: Indicates how many rows should be fetched with the initial response from
    ///                   the database. Refer to ``prefetchRows`` for additional explanation.
    ///   - arraySize: Indicates how many rows will be returned by any subsequent fetch calls to the
    ///                database. Refer to ``arraySize`` for additional explanation.
    public init(
        autoCommit: Bool = false,
        prefetchRows: Int = 2,
        arraySize: Int = 50
    ) {
        self.autoCommit = autoCommit
        self.arrayDMLRowCounts = false
        self.batchErrors = false
        self.prefetchRows = prefetchRows
        self.arraySize = arraySize
        self.fetchLOBs = false
    }
}

final class CleanupContext {
    var cursorsToClose: Set<UInt16> = []

    var tempLOBsTotalSize: Int = 0
    var tempLOBsToClose: [ByteBuffer]? = nil

    init(
        cursorsToClose: Set<UInt16> = [],
        tempLOBsTotalSize: Int = 0,
        tempLOBsToClose: [ByteBuffer]? = nil
    ) {
        self.cursorsToClose = cursorsToClose
        self.tempLOBsTotalSize = tempLOBsTotalSize
        self.tempLOBsToClose = tempLOBsToClose
    }
}
