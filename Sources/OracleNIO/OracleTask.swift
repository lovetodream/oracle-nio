import NIOCore
import Logging

enum OracleTask {
    case extendedQuery(ExtendedQueryContext)

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
    let cursorID: UInt16
    let requiresFullExecute: Bool
    let requiresDefine: Bool
    let queryVariables: [Variable]

    var sequenceNumber: UInt8 = 2

    init(
        query: OracleQuery,
        options: QueryOptions,
        useCharacterConversion: Bool,
        logger: Logger,
        promise: EventLoopPromise<OracleRowStream>
    ) throws {
        self.logger = logger
        self.query = query
        self.options = options

        if useCharacterConversion {
            self.sqlLength = .init(query.sql.count)
        } else {
            self.sqlLength = .init(query.sql.bytes.count)
        }

        // strip single/multiline comments and and strings from the sql
        var sql = query.sql
        sql = try sql.replacing(Regex(#"/\*[\S\n ]+?\*/"#), with: "")
        sql = try sql.replacing(Regex(#"\--.*(\n|$)"#), with: "")
        sql = try sql.replacing(Regex(#"'[^']*'(?=(?:[^']*[^']*')*[^']*$)"#), with: "")

        let query = try Self.determineStatementType(
            minifiedSQL: sql, promise: promise
        )
        self.statement = query
        
        self.cursorID = 0
        self.requiresFullExecute = false
        self.requiresDefine = false
        self.queryVariables = []
    }

    private static func determineStatementType(
        minifiedSQL sql: String,
        promise: EventLoopPromise<OracleRowStream>
    ) throws -> Statement {
        var fragment = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if fragment.first == "(" {
            fragment.removeFirst()
        }
        let tokens = fragment.prefix(10).split(separator: " ")
        guard let sqlKeyword = tokens.first?.uppercased() else {
            // Throw malformed sql error
            fatalError()
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
            // Throw malformed sql error
            fatalError()
        }
    }
}

struct QueryOptions {
    var autoCommit: Bool = false

    var arrayDMLRowCounts: Bool = false
    var batchErrors: Bool = false

    /// Indicates how many rows will be returned with the initial roundtrip.
    ///
    /// Basically this can be left at `2`. Only if a specific amount of rows is fetched, this can be adjusted
    /// to how many rows are returned `+1` for avoiding an extra roundtrip. The one extra row is required
    /// for the protocol to know there aren't any more rows to fetch. If the extra row is not added, the client
    /// has to make another roundtrip to be sure that there aren't any more rows pending.
    var prefetchRows: Int = 2
}

final class CleanupContext {
    var cursorsToClose: [UInt16]? = nil
    
    var tempLOBsTotalSize: Int = 0
    var tempLOBsToClose: [[UInt8]]? = nil
}
