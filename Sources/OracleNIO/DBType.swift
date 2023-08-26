enum DatabaseNumericType: Int {
    case float = 0
    case int = 1
    case decimal = 2
    case string = 3
}

@usableFromInline
enum DBTypeNumber: Int, Sendable {
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

public struct DBType: Sendable, Equatable, Hashable {
    @usableFromInline
    var key: UInt16
    @usableFromInline
    var number: DBTypeNumber
    @usableFromInline
    var name: String
    @usableFromInline
    var oracleName: String
    @usableFromInline
    var _oracleType: DataType.Value?
    @usableFromInline
    var defaultSize: Int = 0
    @usableFromInline
    var csfrm: UInt8 = 0
    @usableFromInline
    var bufferSizeFactor: Int = 0

    @usableFromInline
    init(
        number: DBTypeNumber,
        name: String,
        oracleName: String,
        oracleType: DataType.Value? = nil,
        defaultSize: Int = 0,
        csfrm: UInt8 = 0,
        bufferSizeFactor: Int = 0
    ) {
        self.key = UInt16(csfrm) * 256 + UInt16(oracleType?.rawValue ?? 0)
        self.number = number
        self.name = name
        self.oracleName = oracleName
        self._oracleType = oracleType
        self.defaultSize = defaultSize
        self.csfrm = csfrm
        self.bufferSizeFactor = bufferSizeFactor
    }

    @usableFromInline
    static func fromORATypeAndCSFRM(
        typeNumber: UInt8, csfrm: UInt8?
    ) throws -> DBType {
        let key = UInt16(csfrm ?? 0) * 256 + UInt16(typeNumber)
        guard let dbType = supported.first(where: { $0.key == key }) else {
            throw OracleError.ErrorType.oracleTypeNotSupported
        }
        return dbType
    }

    @usableFromInline
    static let bFile = DBType(
        number: .bFile,
        name: "DB_TYPE_BFILE",
        oracleName: "BFILE",
        oracleType: .init(rawValue: 114)!
    )
    @usableFromInline
    static let binaryDouble = DBType(
        number: .binaryDouble,
        name: "DB_TYPE_BINARY_DOUBLE",
        oracleName: "BINARY_DOUBLE",
        oracleType: .init(rawValue: 101)!,
        bufferSizeFactor: 8
    )
    @usableFromInline
    static let binaryFloat = DBType(
        number: .binaryFloat,
        name: "DB_TYPE_BINARY_FLOAT",
        oracleName: "BINARY_FLOAT",
        oracleType: .init(rawValue: 100)!,
        bufferSizeFactor: 4
    )
    @usableFromInline
    static let binaryInteger = DBType(
        number: .binaryInteger,
        name: "DB_TYPE_BINARY_INTEGER",
        oracleName: "BINARY_INTEGER",
        oracleType: .init(rawValue: 3)!,
        bufferSizeFactor: 22
    )
    @usableFromInline
    static let blob = DBType(
        number: .blob,
        name: "DB_TYPE_BLOB",
        oracleName: "BLOB",
        oracleType: .init(rawValue: 113)!,
        bufferSizeFactor: 112
    )
    @usableFromInline
    static let boolean = DBType(
        number: .boolean, 
        name: "DB_TYPE_BOOLEAN",
        oracleName: "BOOLEAN", 
        oracleType: .init(rawValue: 252)!,
        bufferSizeFactor: 4
    )
    @usableFromInline
    static let char = DBType(
        number: .char,
        name: "DB_TYPE_CHAR",
        oracleName: "CHAR",
        oracleType: .init(rawValue: 96)!,
        defaultSize: 2000,
        csfrm: 1,
        bufferSizeFactor: 4
    )
    @usableFromInline
    static let clob = DBType(
        number: .clob,
        name: "DB_TYPE_CLOB",
        oracleName: "CLOB",
        oracleType: .init(rawValue: 112)!,
        csfrm: 1,
        bufferSizeFactor: 112
    )
    @usableFromInline
    static let cursor = DBType(
        number: .cursor,
        name: "DB_TYPE_CURSOR", 
        oracleName: "CURSOR",
        oracleType: .init(rawValue: 102)!,
        bufferSizeFactor: 4
    )
    @usableFromInline
    static let date = DBType(
        number: .date,
        name: "DB_TYPE_DATE",
        oracleName: "DATE",
        oracleType: .init(rawValue: 12)!,
        bufferSizeFactor: 7
    )
    @usableFromInline
    static let intervalDS = DBType(
        number: .intervalDS,
        name: "DB_TYPE_INTERVAL_DS",
        oracleName: "INTERVAL DAY TO SECOND",
        oracleType: .init(rawValue: 183)!,
        bufferSizeFactor: 11
    )
    @usableFromInline
    static let intervalYM = DBType(
        number: .intervalYM,
        name: "DB_TYPE_INTERVAL_YM",
        oracleName: "INTERVAL YEAR TO MONTH",
        oracleType: .init(rawValue: 182)!
    )
    @usableFromInline
    static let json = DBType(
        number: .json,
        name: "DB_TYPE_JSON",
        oracleName: "JSON",
        oracleType: .init(rawValue: 119)!
    )
    @usableFromInline
    static let long = DBType(
        number: .longVarchar,
        name: "DB_TYPE_LONG",
        oracleName: "LONG",
        oracleType: .init(rawValue: 8)!,
        csfrm: 1,
        bufferSizeFactor: 2147483647
    )
    @usableFromInline
    static let longNVarchar = DBType(
        number: .longNVarchar,
        name: "DB_TYPE_LONG_NVARCHAR",
        oracleName: "LONG NVARCHAR",
        oracleType: .init(rawValue: 8)!,
        csfrm: 2,
        bufferSizeFactor: 2147483647
    )
    @usableFromInline
    static let longRAW = DBType(
        number: .longRAW,
        name: "DB_TYPE_LONG_RAW",
        oracleName: "LONG RAW",
        oracleType: .init(rawValue: 24)!,
        bufferSizeFactor: 2147483647
    )
    @usableFromInline
    static let nChar = DBType(
        number: .nChar,
        name: "DB_TYPE_NCHAR",
        oracleName: "NCHAR",
        oracleType: .init(rawValue: 96)!,
        defaultSize: 2000,
        csfrm: 2,
        bufferSizeFactor: 4
    )
    @usableFromInline
    static let nCLOB = DBType(
        number: .nCLOB,
        name: "DB_TYPE_NCLOB",
        oracleName: "NCLOB",
        oracleType: .init(rawValue: 112)!,
        csfrm: 2,
        bufferSizeFactor: 112
    )
    @usableFromInline
    static let number = DBType(
        number: .number,
        name: "DB_TYPE_NUMBER",
        oracleName: "NUMBER",
        oracleType: .init(rawValue: 2)!,
        bufferSizeFactor: 22
    )
    @usableFromInline
    static let nVarchar = DBType(
        number: .nVarchar,
        name: "DB_TYPE_NVARCHAR",
        oracleName: "NVARCHAR2",
        oracleType: .init(rawValue: 1)!,
        defaultSize: 4000,
        csfrm: 2,
        bufferSizeFactor: 4
    )
    @usableFromInline
    static let object = DBType(
        number: .object,
        name: "DB_TYPE_OBJECT",
        oracleName: "OBJECT",
        oracleType: .init(rawValue: 109)!
    )
    @usableFromInline
    static let raw = DBType(
        number: .raw,
        name: "DB_TYPE_RAW",
        oracleName: "RAW",
        oracleType: .init(rawValue: 23)!,
        defaultSize: 4000,
        bufferSizeFactor: 1
    )
    @usableFromInline
    static let rowID = DBType(
        number: .rowID,
        name: "DB_TYPE_ROWID",
        oracleName: "ROWID",
        oracleType: .init(rawValue: 11)!,
        bufferSizeFactor: 18
    )
    @usableFromInline
    static let timestamp = DBType(
        number: .timestamp,
        name: "DB_TYPE_TIMESTAMP",
        oracleName: "TIMESTAMP",
        oracleType: .init(rawValue: 180)!,
        bufferSizeFactor: 11
    )
    @usableFromInline
    static let timestampLTZ = DBType(
        number: .timestampLTZ,
        name: "DB_TYPE_TIMESTAMP_LTZ",
        oracleName: "TIMESTAMP WITH LOCAL TZ",
        oracleType: .init(rawValue: 231)!,
        bufferSizeFactor: 11
    )
    @usableFromInline
    static let timestampTZ = DBType(
        number: .timestampTZ,
        name: "DB_TYPE_TIMESTAMP_TZ",
        oracleName: "TIMESTAMP WITH TZ",
        oracleType: .init(rawValue: 181)!,
        bufferSizeFactor: 13
    )
    @usableFromInline
    static let unknown = DBType(
        number: .unknown,
        name: "DB_TYPE_UNKNOWN",
        oracleName: "UNKNOWN"
    )
    @usableFromInline
    static let uRowID = DBType(
        number: .uRowID,
        name: "DB_TYPE_UROWID",
        oracleName: "UROWID",
        oracleType: .init(rawValue: 208)!
    )
    @usableFromInline
    static let varchar = DBType(
        number: .varchar,
        name: "DB_TYPE_VARCHAR",
        oracleName: "VARCHAR2",
        oracleType: .init(rawValue: 1)!,
        defaultSize: 4000,
        csfrm: 1,
        bufferSizeFactor: 4
    )

    @usableFromInline
    static let supported: [DBType] = [
        .bFile, .binaryDouble, .binaryFloat, .binaryInteger, .blob, .boolean,
        .char, .clob, .cursor, .date, .intervalDS, .intervalYM, .json, .long,
        .longNVarchar, .longRAW, .nChar, .nCLOB, .number, .nVarchar, .object,
        .raw, .rowID, .timestamp, .timestampLTZ, .timestampTZ, .unknown,
        .uRowID, .varchar
    ]
}
