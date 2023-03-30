struct Cursor {
    var statement: Statement
    var prefetchRows: UInt32
    var fetchArraySize: UInt32
    var fetchVariables: [Variable]
}
