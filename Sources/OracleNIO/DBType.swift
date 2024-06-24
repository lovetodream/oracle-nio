//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

enum DatabaseNumericType: Int {
    case float = 0
    case int = 1
    case decimal = 2
    case string = 3
}

/// A numeric value used to identify a oracle data type.
public struct OracleDataTypeNumber: Sendable, Hashable {
    internal enum Backing: Int, Sendable {
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
        case vector = 2033
    }

    internal let backing: Backing

    internal init(_ backing: Backing) {
        self.backing = backing
    }

    public static let bFile: Self = .init(.bFile)
    public static let binaryDouble: Self = .init(.binaryDouble)
    public static let binaryFloat: Self = .init(.binaryFloat)
    public static let binaryInteger: Self = .init(.binaryInteger)
    public static let blob: Self = .init(.blob)
    public static let boolean: Self = .init(.boolean)
    public static let char: Self = .init(.char)
    public static let clob: Self = .init(.clob)
    public static let cursor: Self = .init(.cursor)
    public static let date: Self = .init(.date)
    public static let intervalDS: Self = .init(.intervalDS)
    public static let intervalYM: Self = .init(.intervalYM)
    public static let json: Self = .init(.json)
    public static let longNVarchar: Self = .init(.longNVarchar)
    public static let longRAW: Self = .init(.longRAW)
    public static let longVarchar: Self = .init(.longVarchar)
    public static let nChar: Self = .init(.nChar)
    public static let nCLOB: Self = .init(.nCLOB)
    public static let number: Self = .init(.number)
    public static let nVarchar: Self = .init(.nVarchar)
    public static let object: Self = .init(.object)
    public static let raw: Self = .init(.raw)
    public static let rowID: Self = .init(.rowID)
    public static let timestamp: Self = .init(.timestamp)
    public static let timestampLTZ: Self = .init(.timestampLTZ)
    public static let timestampTZ: Self = .init(.timestampTZ)
    public static let unknown: Self = .init(.unknown)
    public static let uRowID: Self = .init(.uRowID)
    public static let varchar: Self = .init(.varchar)
    public static let vector: Self = .init(.vector)
}

/// A data type used by the Oracle Wire Protocol (TNS) and the database.
///
/// It's information is used to encode/decode and send data from and to the database.
public struct OracleDataType: Sendable, Equatable, Hashable {
    @usableFromInline
    var key: UInt16
    @usableFromInline
    var number: OracleDataTypeNumber
    @usableFromInline
    var name: String
    @usableFromInline
    var oracleName: String
    @usableFromInline
    var _oracleType: _TNSDataType?
    @usableFromInline
    var defaultSize: Int = 0
    @usableFromInline
    var csfrm: UInt8 = 0
    @usableFromInline
    var bufferSizeFactor: Int = 0

    public init(
        number: OracleDataTypeNumber,
        name: String,
        oracleName: String,
        oracleType: _TNSDataType? = nil,
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
    ) throws -> OracleDataType {
        let key = UInt16(csfrm ?? 0) * 256 + UInt16(typeNumber)
        guard let dbType = supported.first(where: { $0.key == key }) else {
            throw OracleError.ErrorType.oracleTypeNotSupported
        }
        return dbType
    }

    public static let bFile = OracleDataType(
        number: .bFile,
        name: "DB_TYPE_BFILE",
        oracleName: "BFILE",
        oracleType: .init(rawValue: 114)!
    )
    public static let binaryDouble = OracleDataType(
        number: .binaryDouble,
        name: "DB_TYPE_BINARY_DOUBLE",
        oracleName: "BINARY_DOUBLE",
        oracleType: .init(rawValue: 101)!,
        bufferSizeFactor: 8
    )
    public static let binaryFloat = OracleDataType(
        number: .binaryFloat,
        name: "DB_TYPE_BINARY_FLOAT",
        oracleName: "BINARY_FLOAT",
        oracleType: .init(rawValue: 100)!,
        bufferSizeFactor: 4
    )
    public static let binaryInteger = OracleDataType(
        number: .binaryInteger,
        name: "DB_TYPE_BINARY_INTEGER",
        oracleName: "BINARY_INTEGER",
        oracleType: .init(rawValue: 3)!,
        bufferSizeFactor: 22
    )
    public static let blob = OracleDataType(
        number: .blob,
        name: "DB_TYPE_BLOB",
        oracleName: "BLOB",
        oracleType: .init(rawValue: 113)!,
        bufferSizeFactor: 112
    )
    public static let boolean = OracleDataType(
        number: .boolean,
        name: "DB_TYPE_BOOLEAN",
        oracleName: "BOOLEAN",
        oracleType: .init(rawValue: 252)!,
        bufferSizeFactor: 4
    )
    public static let char = OracleDataType(
        number: .char,
        name: "DB_TYPE_CHAR",
        oracleName: "CHAR",
        oracleType: .init(rawValue: 96)!,
        defaultSize: 2000,
        csfrm: 1,
        bufferSizeFactor: 4
    )
    public static let clob = OracleDataType(
        number: .clob,
        name: "DB_TYPE_CLOB",
        oracleName: "CLOB",
        oracleType: .init(rawValue: 112)!,
        csfrm: 1,
        bufferSizeFactor: 112
    )
    public static let cursor = OracleDataType(
        number: .cursor,
        name: "DB_TYPE_CURSOR",
        oracleName: "CURSOR",
        oracleType: .init(rawValue: 102)!,
        bufferSizeFactor: 4
    )
    public static let date = OracleDataType(
        number: .date,
        name: "DB_TYPE_DATE",
        oracleName: "DATE",
        oracleType: .init(rawValue: 12)!,
        bufferSizeFactor: 7
    )
    public static let intervalDS = OracleDataType(
        number: .intervalDS,
        name: "DB_TYPE_INTERVAL_DS",
        oracleName: "INTERVAL DAY TO SECOND",
        oracleType: .init(rawValue: 183)!,
        bufferSizeFactor: 11
    )
    public static let intervalYM = OracleDataType(
        number: .intervalYM,
        name: "DB_TYPE_INTERVAL_YM",
        oracleName: "INTERVAL YEAR TO MONTH",
        oracleType: .init(rawValue: 182)!
    )
    public static let json = OracleDataType(
        number: .json,
        name: "DB_TYPE_JSON",
        oracleName: "JSON",
        oracleType: .init(rawValue: 119)!
    )
    public static let long = OracleDataType(
        number: .longVarchar,
        name: "DB_TYPE_LONG",
        oracleName: "LONG",
        oracleType: .init(rawValue: 8)!,
        csfrm: 1,
        bufferSizeFactor: 2_147_483_647
    )
    public static let longNVarchar = OracleDataType(
        number: .longNVarchar,
        name: "DB_TYPE_LONG_NVARCHAR",
        oracleName: "LONG NVARCHAR",
        oracleType: .init(rawValue: 8)!,
        csfrm: 2,
        bufferSizeFactor: 2_147_483_647
    )
    public static let longRAW = OracleDataType(
        number: .longRAW,
        name: "DB_TYPE_LONG_RAW",
        oracleName: "LONG RAW",
        oracleType: .init(rawValue: 24)!,
        bufferSizeFactor: 2_147_483_647
    )
    public static let nChar = OracleDataType(
        number: .nChar,
        name: "DB_TYPE_NCHAR",
        oracleName: "NCHAR",
        oracleType: .init(rawValue: 96)!,
        defaultSize: 2000,
        csfrm: 2,
        bufferSizeFactor: 4
    )
    public static let nCLOB = OracleDataType(
        number: .nCLOB,
        name: "DB_TYPE_NCLOB",
        oracleName: "NCLOB",
        oracleType: .init(rawValue: 112)!,
        csfrm: 2,
        bufferSizeFactor: 112
    )
    public static let number = OracleDataType(
        number: .number,
        name: "DB_TYPE_NUMBER",
        oracleName: "NUMBER",
        oracleType: .init(rawValue: 2)!,
        bufferSizeFactor: 22
    )
    public static let nVarchar = OracleDataType(
        number: .nVarchar,
        name: "DB_TYPE_NVARCHAR",
        oracleName: "NVARCHAR2",
        oracleType: .init(rawValue: 1)!,
        defaultSize: 4000,
        csfrm: 2,
        bufferSizeFactor: 4
    )
    public static let object = OracleDataType(
        number: .object,
        name: "DB_TYPE_OBJECT",
        oracleName: "OBJECT",
        oracleType: .init(rawValue: 109)!
    )
    public static let raw = OracleDataType(
        number: .raw,
        name: "DB_TYPE_RAW",
        oracleName: "RAW",
        oracleType: .init(rawValue: 23)!,
        defaultSize: 4000,
        bufferSizeFactor: 1
    )
    public static let rowID = OracleDataType(
        number: .rowID,
        name: "DB_TYPE_ROWID",
        oracleName: "ROWID",
        oracleType: .init(rawValue: 11)!,
        bufferSizeFactor: 18
    )
    public static let timestamp = OracleDataType(
        number: .timestamp,
        name: "DB_TYPE_TIMESTAMP",
        oracleName: "TIMESTAMP",
        oracleType: .init(rawValue: 180)!,
        bufferSizeFactor: 11
    )
    public static let timestampLTZ = OracleDataType(
        number: .timestampLTZ,
        name: "DB_TYPE_TIMESTAMP_LTZ",
        oracleName: "TIMESTAMP WITH LOCAL TZ",
        oracleType: .init(rawValue: 231)!,
        bufferSizeFactor: 11
    )
    public static let timestampTZ = OracleDataType(
        number: .timestampTZ,
        name: "DB_TYPE_TIMESTAMP_TZ",
        oracleName: "TIMESTAMP WITH TZ",
        oracleType: .init(rawValue: 181)!,
        bufferSizeFactor: 13
    )
    public static let unknown = OracleDataType(
        number: .unknown,
        name: "DB_TYPE_UNKNOWN",
        oracleName: "UNKNOWN"
    )
    public static let uRowID = OracleDataType(
        number: .uRowID,
        name: "DB_TYPE_UROWID",
        oracleName: "UROWID",
        oracleType: .init(rawValue: 208)!
    )
    public static let varchar = OracleDataType(
        number: .varchar,
        name: "DB_TYPE_VARCHAR",
        oracleName: "VARCHAR2",
        oracleType: .init(rawValue: 1)!,
        defaultSize: 4000,
        csfrm: 1,
        bufferSizeFactor: 4
    )
    public static let vector = OracleDataType(
        number: .vector,
        name: "DB_TYPE_VECTOR",
        oracleName: "VECTOR",
        oracleType: .init(rawValue: 127)
    )

    @usableFromInline
    static let supported: [OracleDataType] = [
        .bFile, .binaryDouble, .binaryFloat, .binaryInteger, .blob, .boolean,
        .char, .clob, .cursor, .date, .intervalDS, .intervalYM, .json, .long,
        .longNVarchar, .longRAW, .nChar, .nCLOB, .number, .nVarchar, .object,
        .raw, .rowID, .timestamp, .timestampLTZ, .timestampTZ, .unknown,
        .uRowID, .varchar, .vector,
    ]
}
