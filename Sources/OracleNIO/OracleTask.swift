// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import NIOCore
import Logging
import RegexBuilder

enum OracleTask {
    case extendedQuery(ExtendedQueryContext)
    case ping(EventLoopPromise<Void>)
    case commit(EventLoopPromise<Void>)
    case rollback(EventLoopPromise<Void>)

    func failWithError(_ error: OracleSQLError) {
        switch self {
        case .extendedQuery(let context):
            switch context.statement {
            case .ddl(let promise),
                .dml(let promise),
                .plsql(let promise),
                .query(let promise):
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

final class ExtendedQueryContext {
    enum Statement {
        case query(EventLoopPromise<OracleRowStream>)
        case plsql(EventLoopPromise<OracleRowStream>)
        case dml(EventLoopPromise<OracleRowStream>)
        case ddl(EventLoopPromise<OracleRowStream>)

        var isQuery: Bool {
            switch self {
            case .query:
                return true
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

    let statement: Statement
    let query: OracleQuery
    let options: QueryOptions
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
        query: OracleQuery,
        options: QueryOptions,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) throws {
        do {
            self.logger = logger
            self.query = query
            self.options = options
            self.sqlLength = .init(query.sql.data(using: .utf8)?.count ?? 0)

            // strip single/multiline comments and and strings from the sql
            var sql = query.sql
            sql = sql.replacing(/\/\*[\S\n ]+?\*\//, with: "")
            sql = sql.replacing(/\--.*(\n|$)/, with: "")
            sql = sql.replacing(/'[^']*'(?=(?:[^']*[^']*')*[^']*$)/, with: "")

            self.isReturning = query.binds.metadata
                .first(where: \.isReturnBind) != nil
            let query = try Self.determineStatementType(
                minifiedSQL: sql, promise: promise
            )
            self.statement = query
        } catch let error as OracleSQLError {
            promise.fail(error)
            throw error
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    private static func determineStatementType(
        minifiedSQL sql: String,
        promise: EventLoopPromise<OracleRowStream>
    ) throws -> Statement {
        var fragment = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if fragment.first == "(" {
            fragment.removeFirst()
        }
        let tokens = fragment.prefix(10)
            .components(separatedBy: .whitespacesAndNewlines)
        guard let sqlKeyword = tokens.first?.uppercased() else {
            throw OracleSQLError.malformedQuery(minified: sql)
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
            throw OracleSQLError.malformedQuery(minified: sql)
        }
    }
}

public struct QueryOptions {
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

    /// Options to pass to a ``OracleQuery`` to tweak its execution.
    /// - Parameters:
    ///   - autoCommit: Automatically commit after execution of the query without needing an
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
}
