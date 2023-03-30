struct DBType {
    var number: Int
    var name: String
    var defaultSize: Int = 0
    var oracleName: String
    var oracleType: DataType.Value
    var csfrm: UInt8
    var bufferSizeFactor: Int
}
