import RegexBuilder

let BIND_PATTERN = Regex {
    ":"
    Capture {
      OneOrMore(.digit)
    }
  }


/// Pattern used for detecting a DML returning clause.
///
/// Bind variables in the first group are input variables.
/// Bind variables in the second group are output only variables.
let DML_RETURNING_PATTERN = try! Regex("(?si)([)\\s]RETURNING\\s+[\\s\\S]+\\s+INTO\\s+)(.*?$)")

struct BindInfo {
    let bindName: String
    let isReturnBind: Bool

    var numberOfElements: UInt32?
    var oracleTypeNumber: UInt8?
    var bufferSize: UInt32?
    var precision: Int16?
    var bindDir: UInt8?
    var size: UInt32?
    var isArray: Bool?
    var scale: Int16?
    var csfrm: UInt8?
    var variable: Variable?

    init(name: String, isReturnBind: Bool) {
        self.bindName = name
        self.isReturnBind = isReturnBind
    }
}

class Statement {
    var sql: String = ""
    var sqlBytes: [UInt8] = []
    var sqlLength: UInt32 = 0
    var cursorID: UInt16 = 0
    var isQuery = false
    var isPlSQL = false
    var isDML = false
    var isDDL = false
    var isReturning = false
    var bindInfoList: Array<BindInfo> = []
    var requiresFullExecute = false
    var requiresDefine = false
    var fetchVariables: [Variable]?
    var numberOfColumns: UInt32?

    init(_ sql: String = "", characterConversion: Bool) throws {
        self.sql = sql
        try prepare(sql: sql, characterConversion: characterConversion)
    }

    func addBinds(sql: String, isReturnBind: Bool) throws {
        for match in sql.matches(of: BIND_PATTERN) {
            let name = match.1
            let info = BindInfo(name: String(name), isReturnBind: isReturnBind)
            self.bindInfoList.append(info)
        }
    }

    /// Determine the type of the SQL statement by examining the first keyword found in the statement.
    func determineStatementType(sql: String) {
        var fragment = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if fragment.first == "(" {
            fragment.removeFirst()
        }
        let tokens = fragment.prefix(10).split(separator: " ")
        guard let sqlKeyword = tokens.first?.uppercased() else { return }
        switch sqlKeyword {
        case "DECLARE", "BEGIN", "CALL":
            self.isPlSQL = true
        case "SELECT", "WITH":
            self.isQuery = true
        case "INSERT", "UPDATE", "DELETE", "MERGE":
            self.isDML = true
        case "CREATE", "ALTER", "DROP", "TRUNCATE":
            self.isDDL = true
        default:
            return
        }
    }

    /// Prepare the SQL for execution by determining the list of bind names that are found within it. The length of the SQL text is also calculated
    /// at this time. If the character sets of the client and server are identical, the length is calculated in bytes; otherwise, the length is
    /// calculated in characters.
    func prepare(sql: String, characterConversion: Bool) throws {
        // retain normalized SQL (as string and bytes) as well as the length
        var sql = sql
        self.sql = sql
        self.sqlBytes = sql.bytes
        if characterConversion {
            self.sqlLength = UInt32(sql.count)
        } else {
            self.sqlLength = UInt32(sqlBytes.count)
        }

        // create empty list (bind by position) and dict (bind by name)
        self.bindInfoList = []

        // Strip single/multiline comments and strings from the sql statement to ease searching for bind variables.
        sql = try sql.replacing(Regex(#"/\*[\S\n ]+?\*/"#), with: "")
        sql = try sql.replacing(Regex(#"\--.*(\n|$)"#), with: "")
        sql = try sql.replacing(Regex(#"'[^']*'(?=(?:[^']*[^']*')*[^']*$)"#), with: "")
        for match in sql.matches(of: try Regex(#"(:\\s*)?(\"([^\"]*)\")"#)) {
            guard let value = match.output.extractValues(as: String.self) else { continue }
            let startIndex = sql.index(sql.startIndex, offsetBy: match.startIndex)
            let endIndex = sql.index(sql.startIndex, offsetBy: match.endIndex)
            if value.first != ":" {
                sql.replaceSubrange(startIndex...endIndex, with: "")
            }
        }

        self.determineStatementType(sql: sql)

        if self.isQuery || self.isDML || self.isPlSQL {
            var inputSQL = sql
            var returningSQL: String?
            if !self.isPlSQL {
                let match = sql.firstMatch(of: DML_RETURNING_PATTERN)
                if let match, let value = match.output.extractValues(as: String.self) {
                    let position = value.index(sql.startIndex, offsetBy: match.output.startIndex + 2)
                    inputSQL = String(sql.prefix(upTo: position))
                    returningSQL = String(sql.suffix(from: position))
                }
                try self.addBinds(sql: inputSQL, isReturnBind: false)
                if let returningSQL, !returningSQL.isEmpty {
                    self.isReturning = true
                    try self.addBinds(sql: returningSQL, isReturnBind: true)
                }
            }
        }
    }

    func setVariable(bindInfo: inout BindInfo, variable: Variable, cursor: Cursor) throws {
        if variable.dbType.oracleType == .cursor {
            self.requiresFullExecute = true
        }
        if
            (variable.dbType.oracleType?.rawValue ?? 0) != (bindInfo.oracleTypeNumber ?? 0) ||
            variable.size != bindInfo.size ||
            variable.bufferSize != bindInfo.bufferSize ||
            variable.precision != bindInfo.precision ||
            variable.scale != bindInfo.scale ||
            variable.isArray != bindInfo.isArray ||
            variable.numberOfElements != bindInfo.numberOfElements ||
            variable.dbType.csfrm != bindInfo.csfrm
        {
            bindInfo.oracleTypeNumber = UInt8(variable.dbType.oracleType?.rawValue ?? 0)
            bindInfo.csfrm = variable.dbType.csfrm
            bindInfo.isArray = variable.isArray
            bindInfo.numberOfElements = variable.numberOfElements
            bindInfo.size = variable.size
            bindInfo.bufferSize = variable.bufferSize
            bindInfo.precision = variable.precision
            bindInfo.scale = variable.scale
            self.requiresFullExecute = true
        }
        bindInfo.variable = variable
    }
}
