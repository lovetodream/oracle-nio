enum DatabaseNumericType: Int {
    case float = 0
    case int = 1
    case decimal = 2
    case string = 3
}

enum DBTypeNumber: Int {
    case bFile = 2020
    case binaryDouble = 2008
    case binaryFloat = 2007
    case binaryInteger = 2009
    case blob = 2019
    case boolean = 2022
    case char = 2003
    case clob = 2017
    case cursor = 2021
    case date = 2011
    case intervalDS = 2015
    case intervalYM = 2016
    case json = 2027
    case longNVarchar = 2031
    case longRAW = 2025
    case longVarchar = 2024
    case nChar = 2004
    case nCLOB = 2018
    case number = 2010
    case nVarchar = 2002
    case object = 2023
    case raw = 2006
    case rowID = 2005
    case timestamp = 2012
    case timestampLTZ = 2014
    case timestampTZ = 2013
    case unknown = 0
    case uRowID = 2030
    case varchar = 2001
}

struct DBType {
    var key: UInt16
    var number: DBTypeNumber
    var name: String
    var oracleName: String
    var oracleType: OracleDataType?
    var defaultSize: Int = 0
    var csfrm: UInt8 = 0
    var bufferSizeFactor: Int = 0

    init(
        number: DBTypeNumber,
        name: String,
        oracleName: String,
        oracleType: OracleDataType? = nil,
        defaultSize: Int = 0,
        csfrm: UInt8 = 0,
        bufferSizeFactor: Int = 0
    ) {
        self.key = UInt16(csfrm) * 256 + UInt16(oracleType?.rawValue ?? 0)
        self.number = number
        self.name = name
        self.oracleName = oracleName
        self.oracleType = oracleType
        self.defaultSize = defaultSize
        self.csfrm = csfrm
        self.bufferSizeFactor = bufferSizeFactor
    }

    static func fromORATypeAndCSFRM(typeNumber: UInt8, csfrm: UInt8?) throws -> DBType {
        let key = UInt16(csfrm ?? 0) * 256 + UInt16(typeNumber)
        guard let dbType = supported.first(where: { $0.key == key }) else {
            throw OracleError.ErrorType.oracleTypeNotSupported
        }
        return dbType
    }

    static let binaryInteger = DBType(number: .binaryInteger, name: "DB_TYPE_BINARY_INTEGER", oracleName: "BINARY_INTEGER", oracleType: .init(rawValue: 3)!, bufferSizeFactor: 22)
    static let blob = DBType(number: .blob, name: "DB_TYPE_BLOB", oracleName: "BLOB", oracleType: .init(rawValue: 113)!, bufferSizeFactor: 112)
    static let boolean = DBType(number: .boolean, name: "DB_TYPE_BOOLEAN", oracleName: "BOOLEAN", oracleType: .init(rawValue: 252)!, bufferSizeFactor: 4)
    static let clob = DBType(number: .clob, name: "DB_TYPE_CLOB", oracleName: "CLOB", oracleType: .init(rawValue: 112)!, csfrm: 1, bufferSizeFactor: 112)
    static let date = DBType(number: .date, name: "DB_TYPE_DATE", oracleName: "DATE", oracleType: .init(rawValue: 12)!, bufferSizeFactor: 7)
    static let intervalDS = DBType(number: .intervalDS, name: "DB_TYPE_INTERVAL_DS", oracleName: "INTERVAL DAY TO SECOND", oracleType: .init(rawValue: 183)!, bufferSizeFactor: 11)
    static let number = DBType(number: .number, name: "DB_TYPE_NUMBER", oracleName: "NUMBER", oracleType: .init(rawValue: 2)!, bufferSizeFactor: 22)
    static let long = DBType(number: .longVarchar, name: "DB_TYPE_LONG", oracleName: "LONG", oracleType: .init(rawValue: 8)!, csfrm: 1, bufferSizeFactor: 2147483647)
    static let longNVarchar = DBType(number: .longNVarchar, name: "DB_TYPE_LONG_NVARCHAR", oracleName: "LONG NVARCHAR", oracleType: .init(rawValue: 8)!, csfrm: 2, bufferSizeFactor: 2147483647)
    static let longRAW = DBType(number: .longRAW, name: "DB_TYPE_LONG_RAW", oracleName: "LONG RAW", oracleType: .init(rawValue: 24)!, bufferSizeFactor: 2147483647)
    static let nCLOB = DBType(number: .nCLOB, name: "DB_TYPE_NCLOB", oracleName: "NCLOB", oracleType: .init(rawValue: 112)!, csfrm: 2, bufferSizeFactor: 112)
    static let raw = DBType(number: .raw, name: "DB_TYPE_RAW", oracleName: "RAW", oracleType: .init(rawValue: 23)!, defaultSize: 4000, bufferSizeFactor: 1)
    static let varchar = DBType(number: .varchar, name: "DB_TYPE_VARCHAR", oracleName: "VARCHAR2", oracleType: .init(rawValue: 1)!, defaultSize: 4000, csfrm: 1, bufferSizeFactor: 4)

    static let supported = [
        DBType(number: .bFile, name: "DB_TYPE_BFILE", oracleName: "BFILE", oracleType: .init(rawValue: 114)!),
        DBType(number: .binaryDouble, name: "DB_TYPE_BINARY_DOUBLE", oracleName: "BINARY_DOUBLE", oracleType: .init(rawValue: 101)!, bufferSizeFactor: 8),
        DBType(number: .binaryFloat, name: "DB_TYPE_BINARY_FLOAT", oracleName: "BINARY_FLOAT", oracleType: .init(rawValue: 100)!, bufferSizeFactor: 4),
        .binaryInteger,
        .blob,
        .boolean,
        DBType(number: .char, name: "DB_TYPE_CHAR", oracleName: "CHAR", oracleType: .init(rawValue: 96)!, defaultSize: 2000, csfrm: 1, bufferSizeFactor: 4),
        .clob,
        DBType(number: .cursor, name: "DB_TYPE_CURSOR", oracleName: "CURSOR", oracleType: .init(rawValue: 102)!, bufferSizeFactor: 4),
        .date,
        .intervalDS,
        DBType(number: .intervalYM, name: "DB_TYPE_INTERVAL_YM", oracleName: "INTERVAL YEAR TO MONTH", oracleType: .init(rawValue: 182)!),
        DBType(number: .json, name: "DB_TYPE_JSON", oracleName: "JSON", oracleType: .init(rawValue: 119)!),
        long, longNVarchar, longRAW,
        DBType(number: .nChar, name: "DB_TYPE_NCHAR", oracleName: "NCHAR", oracleType: .init(rawValue: 96)!, defaultSize: 2000, csfrm: 2, bufferSizeFactor: 4),
        .nCLOB,
        .number,
        DBType(number: .nVarchar, name: "DB_TYPE_NVARCHAR", oracleName: "NVARCHAR2", oracleType: .init(rawValue: 1)!, defaultSize: 4000, csfrm: 2, bufferSizeFactor: 4),
        DBType(number: .object, name: "DB_TYPE_OBJECT", oracleName: "OBJECT", oracleType: .init(rawValue: 109)!),
        .raw,
        DBType(number: .rowID, name: "DB_TYPE_ROWID", oracleName: "ROWID", oracleType: .init(rawValue: 11)!, bufferSizeFactor: 18),
        DBType(number: .timestamp, name: "DB_TYPE_TIMESTAMP", oracleName: "TIMESTAMP", oracleType: .init(rawValue: 180)!, bufferSizeFactor: 11),
        DBType(number: .timestampLTZ, name: "DB_TYPE_TIMESTAMP_LTZ", oracleName: "TIMESTAMP WITH LOCAL TZ", oracleType: .init(rawValue: 231)!, bufferSizeFactor: 11),
        DBType(number: .timestampTZ, name: "DB_TYPE_TIMESTAMP_TZ", oracleName: "TIMESTAMP WITH TZ", oracleType: .init(rawValue: 181)!, bufferSizeFactor: 13),
        DBType(number: .unknown, name: "DB_TYPE_UNKNOWN", oracleName: "UNKNOWN"),
        DBType(number: .uRowID, name: "DB_TYPE_UROWID", oracleName: "UROWID", oracleType: .init(rawValue: 208)!),
        .varchar
    ]
}
