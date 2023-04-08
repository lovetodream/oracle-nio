class Cursor {
    var statement: Statement
    var prefetchRows: UInt32
    var fetchArraySize: UInt32
    var fetchVariables: [Variable]
    var moreRowsToFetch = false
    var bufferRowCount = 0
    var bufferIndex = 0
    var numberOfColumns: UInt32 = 0

    init(statement: Statement, prefetchRows: UInt32, fetchArraySize: UInt32, fetchVariables: [Variable]) {
        self.statement = statement
        self.prefetchRows = prefetchRows
        self.fetchArraySize = fetchArraySize
        self.fetchVariables = fetchVariables
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
        if dbType == .number {
            if variable.scale == 0 || (variable.scale == -127 && variable.precision == 0) {
                variable.preferredNumberType = .int
            }
        } else if !Defaults.fetchLobs {
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
}