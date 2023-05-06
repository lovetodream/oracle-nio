struct Variable {
    var dbType: DBType
    var bufferSize: UInt32 = 0
    var isArray: Bool = false
    var numberOfElements: UInt32
    var numberOfElementsInArray: UInt32?
    var objectType: Any? // TODO: find out what this is
    var name: String
    var size: UInt32
    var precision: Int16
    var scale: Int16
    var nullsAllowed: Bool
    var fetchInfo: FetchInfo? 
    var values: [Any?]
    var bypassDecode: Bool = false
    var lastRawValue: Any?

    mutating func finalizeInitialization() {
        self.values = .init(repeating: nil, count: Int(numberOfElements))
    }
}
