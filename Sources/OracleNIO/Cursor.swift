class CursorDeprecated {
    var statement: Statement
    var prefetchRows: UInt32 = 2
    var arraySize = 100
    var fetchArraySize: UInt32
    var fetchVariables: [Variable]
    var moreRowsToFetch = false
    var bufferRowCount = 0
    var bufferIndex = 0
    var numberOfColumns: UInt32 = 0
    var lastRowIndex = 0
    var dmlRowCounts: [Int] = []
    var rowCount: UInt64?
    var lastRowID: RowID?
    var batchErrors: [OracleError]?
    var bindVariables: [BindVariable] = []

    init(statement: Statement, prefetchRows: UInt32 = 2, fetchArraySize: UInt32, fetchVariables: [Variable]) {
        self.statement = statement
        self.prefetchRows = prefetchRows
        self.fetchArraySize = fetchArraySize
        self.fetchVariables = fetchVariables
    }

    func preprocessExecute(connection: OracleConnection) throws {
        if !bindVariables.isEmpty {
            try self.performBinds(connection: connection)
        }
        for bindInfo in statement.bindInfoList where bindInfo.variable == nil {
            throw OracleError.ErrorType.missingBindValue
        }
    }

    private func performBinds(connection: OracleConnection) throws {
        for (index, bindVariable) in bindVariables.enumerated() {
            var bindVariable = bindVariable
            try bindVariable.variable?.bind(cursor: self, connection: connection, position: UInt32(bindVariable.position))
            bindVariables[index] = bindVariable
        }
    }

    func createFetchVariable(fetchInfo: FetchInfo, position: Int) {
        var variable = Variable(
            dbType: fetchInfo.dbType,
            numberOfElements: fetchArraySize,
            name: fetchInfo.name,
            size: fetchInfo.size,
            precision: fetchInfo.precision,
            scale: fetchInfo.scale,
            nullsAllowed: fetchInfo.nullsAllowed,
            fetchInfo: fetchInfo,
            values: []
        )

        variable.finalizeInitialization()
        if fetchVariables.count > position {
            fetchVariables[position] = variable
        } else if fetchVariables.count == position {
            fetchVariables.append(variable)
        } else {
            preconditionFailure()
        }


    }

    func createVariable() -> Variable {
        return Variable()
    }
}

struct BindVariable {
    var position = 0
    var hasValue = false
    var variable: Variable?
}
