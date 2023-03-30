struct Variable {
    var dbType: DBType
    var bufferSize: UInt32
    var isArray: Bool
    var numberOfElements: UInt32
    var numberOfElementsInArray: UInt32
    var objectType: Any? // TODO: find out what this is
    var values: [Any?]
}
