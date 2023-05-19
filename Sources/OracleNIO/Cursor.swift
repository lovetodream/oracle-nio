class Cursor {
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

        let dbType = variable.dbType.number
        if !Defaults.fetchLobs {
            if dbType == .blob {
                variable.dbType = .longRAW
            } else if dbType == .clob {
                variable.dbType = .long
            } else if dbType == .nCLOB {
                variable.dbType = .longNVarchar
            }
        }

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

    func bind(values: [Any]) {
        self.bindValues(values: values, rowNumber: 0, numberOfRows: 1)
    }

    private func bindValues(values: [Any], rowNumber: Int, numberOfRows: UInt32) {
        self.bindValuesByPosition(values, rowNumber: rowNumber, numberOfRows: numberOfRows)
    }

    private func bindValuesByPosition(_ values: [Any], rowNumber: Int, numberOfRows: UInt32) { // TODO: type
        for (index, value) in values.enumerated() {
            var bindVariable: BindVariable
            if index < self.bindVariables.count {
                bindVariable = self.bindVariables[index]
            } else {
                bindVariable = BindVariable()
                bindVariable.position = index + 1
                self.bindVariables.append(bindVariable)
            }
            bindVariable.setByValue(value, rowNumber: rowNumber, cursor: self, numberOfElements: numberOfRows)
            self.bindVariables[index] = bindVariable
        }
    }
}

struct BindVariable {
    var position = 0
    var hasValue = false
    var variable: Variable?

    mutating func setByValue(_ value: Any?, rowNumber: Int, cursor: Cursor, numberOfElements: UInt32) {
        // A variable can be set directly in which case nothing further needs to be done
        if let value = value as? Variable {
            self.variable = value
            return
        }

        // If a variable already exists check to see if the value can be set on that variable;
        // an exception is raised if a value has been previously set on that bind variable;
        // otherwise, the variable is replaced with a new one
        if var variable {
            variable.setValue(value, position: rowNumber)
        }

        // A new variable needs to be created; if the value is nil, nothing needs to be done
        if value == nil {
            return
        }

        self.createVariableFromValue(value, cursor: cursor, numberOfElements: numberOfElements)
        self.variable?.setValue(value, position: rowNumber)
        self.hasValue = true
    }

    private mutating func createVariableFromValue(_ value: Any?, cursor: Cursor, numberOfElements: UInt32) {
        var variable = cursor.createVariable()
        if let value = value as? [Any?] {
            variable.isArray = true
            variable.numberOfElements = [numberOfElements, UInt32(value.count)].max()!
            for element in value {
                if element != nil {
                    variable.setTypeInfoFromValue(element, isPlSQL: cursor.statement.isPlSQL)
                }
            }
        } else {
            variable.numberOfElements = numberOfElements
            variable.setTypeInfoFromValue(value, isPlSQL: cursor.statement.isPlSQL)
        }
        variable.finalizeInitialization()
        self.variable = variable
    }
}
