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
    @usableFromInline
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

    @usableFromInline
    internal let backing: Backing

    @inlinable
    internal init(_ backing: Backing) {
        self.backing = backing
    }

    @inlinable
    public static var bFile: Self { .init(.bFile) }

    @inlinable
    public static var binaryDouble: Self { .init(.binaryDouble) }

    @inlinable
    public static var binaryFloat: Self { .init(.binaryFloat) }

    @inlinable
    public static var binaryInteger: Self { .init(.binaryInteger) }

    @inlinable
    public static var blob: Self { .init(.blob) }

    @inlinable
    public static var boolean: Self { .init(.boolean) }

    @inlinable
    public static var char: Self { .init(.char) }

    @inlinable
    public static var clob: Self { .init(.clob) }

    @inlinable
    public static var cursor: Self { .init(.cursor) }

    @inlinable
    public static var date: Self { .init(.date) }

    @inlinable
    public static var intervalDS: Self { .init(.intervalDS) }

    @inlinable
    public static var intervalYM: Self { .init(.intervalYM) }

    @inlinable
    public static var json: Self { .init(.json) }

    @inlinable
    public static var longNVarchar: Self { .init(.longNVarchar) }

    @inlinable
    public static var longRAW: Self { .init(.longRAW) }

    @inlinable
    public static var longVarchar: Self { .init(.longVarchar) }

    @inlinable
    public static var nChar: Self { .init(.nChar) }

    @inlinable
    public static var nCLOB: Self { .init(.nCLOB) }

    @inlinable
    public static var number: Self { .init(.number) }

    @inlinable
    public static var nVarchar: Self { .init(.nVarchar) }

    @inlinable
    public static var object: Self { .init(.object) }

    @inlinable
    public static var raw: Self { .init(.raw) }

    @inlinable
    public static var rowID: Self { .init(.rowID) }

    @inlinable
    public static var timestamp: Self { .init(.timestamp) }

    @inlinable
    public static var timestampLTZ: Self { .init(.timestampLTZ) }

    @inlinable
    public static var timestampTZ: Self { .init(.timestampTZ) }

    @inlinable
    public static var unknown: Self { .init(.unknown) }

    @inlinable
    public static var uRowID: Self { .init(.uRowID) }

    @inlinable
    public static var varchar: Self { .init(.varchar) }

    @inlinable
    public static var vector: Self { .init(.vector) }
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

    @inlinable
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

    @inlinable
    public static var bFile: OracleDataType {
        OracleDataType(
            number: .bFile,
            name: "DB_TYPE_BFILE",
            oracleName: "BFILE",
            oracleType: .init(rawValue: 114).unsafelyUnwrapped
        )
    }

    @inlinable
    public static var binaryDouble: OracleDataType {
        OracleDataType(
            number: .binaryDouble,
            name: "DB_TYPE_BINARY_DOUBLE",
            oracleName: "BINARY_DOUBLE",
            oracleType: .init(rawValue: 101).unsafelyUnwrapped,
            bufferSizeFactor: 8
        )
    }

    @inlinable
    public static var binaryFloat: OracleDataType {
        OracleDataType(
            number: .binaryFloat,
            name: "DB_TYPE_BINARY_FLOAT",
            oracleName: "BINARY_FLOAT",
            oracleType: .init(rawValue: 100).unsafelyUnwrapped,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var binaryInteger: OracleDataType {
        OracleDataType(
            number: .binaryInteger,
            name: "DB_TYPE_BINARY_INTEGER",
            oracleName: "BINARY_INTEGER",
            oracleType: .init(rawValue: 3).unsafelyUnwrapped,
            bufferSizeFactor: 22
        )
    }

    @inlinable
    public static var blob: OracleDataType {
        OracleDataType(
            number: .blob,
            name: "DB_TYPE_BLOB",
            oracleName: "BLOB",
            oracleType: .init(rawValue: 113).unsafelyUnwrapped,
            bufferSizeFactor: 112
        )
    }

    @inlinable
    public static var boolean: OracleDataType {
        OracleDataType(
            number: .boolean,
            name: "DB_TYPE_BOOLEAN",
            oracleName: "BOOLEAN",
            oracleType: .init(rawValue: 252).unsafelyUnwrapped,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var char: OracleDataType {
        OracleDataType(
            number: .char,
            name: "DB_TYPE_CHAR",
            oracleName: "CHAR",
            oracleType: .init(rawValue: 96).unsafelyUnwrapped,
            defaultSize: 2000,
            csfrm: 1,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var clob: OracleDataType {
        OracleDataType(
            number: .clob,
            name: "DB_TYPE_CLOB",
            oracleName: "CLOB",
            oracleType: .init(rawValue: 112).unsafelyUnwrapped,
            csfrm: 1,
            bufferSizeFactor: 112
        )
    }

    @inlinable
    public static var cursor: OracleDataType {
        OracleDataType(
            number: .cursor,
            name: "DB_TYPE_CURSOR",
            oracleName: "CURSOR",
            oracleType: .init(rawValue: 102).unsafelyUnwrapped,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var date: OracleDataType {
        OracleDataType(
            number: .date,
            name: "DB_TYPE_DATE",
            oracleName: "DATE",
            oracleType: .init(rawValue: 12).unsafelyUnwrapped,
            bufferSizeFactor: 7
        )
    }

    @inlinable
    public static var intervalDS: OracleDataType {
        OracleDataType(
            number: .intervalDS,
            name: "DB_TYPE_INTERVAL_DS",
            oracleName: "INTERVAL DAY TO SECOND",
            oracleType: .init(rawValue: 183).unsafelyUnwrapped,
            bufferSizeFactor: 11
        )
    }

    @inlinable
    public static var intervalYM: OracleDataType {
        OracleDataType(
            number: .intervalYM,
            name: "DB_TYPE_INTERVAL_YM",
            oracleName: "INTERVAL YEAR TO MONTH",
            oracleType: .init(rawValue: 182).unsafelyUnwrapped
        )
    }

    @inlinable
    public static var json: OracleDataType {
        OracleDataType(
            number: .json,
            name: "DB_TYPE_JSON",
            oracleName: "JSON",
            oracleType: .init(rawValue: 119).unsafelyUnwrapped
        )
    }

    @inlinable
    public static var long: OracleDataType {
        OracleDataType(
            number: .longVarchar,
            name: "DB_TYPE_LONG",
            oracleName: "LONG",
            oracleType: .init(rawValue: 8).unsafelyUnwrapped,
            csfrm: 1,
            bufferSizeFactor: 2_147_483_647
        )
    }

    @inlinable
    public static var longNVarchar: OracleDataType {
        OracleDataType(
            number: .longNVarchar,
            name: "DB_TYPE_LONG_NVARCHAR",
            oracleName: "LONG NVARCHAR",
            oracleType: .init(rawValue: 8).unsafelyUnwrapped,
            csfrm: 2,
            bufferSizeFactor: 2_147_483_647
        )
    }

    @inlinable
    public static var longRAW: OracleDataType {
        OracleDataType(
            number: .longRAW,
            name: "DB_TYPE_LONG_RAW",
            oracleName: "LONG RAW",
            oracleType: .init(rawValue: 24).unsafelyUnwrapped,
            bufferSizeFactor: 2_147_483_647
        )
    }

    @inlinable
    public static var nChar: OracleDataType {
        OracleDataType(
            number: .nChar,
            name: "DB_TYPE_NCHAR",
            oracleName: "NCHAR",
            oracleType: .init(rawValue: 96).unsafelyUnwrapped,
            defaultSize: 2000,
            csfrm: 2,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var nCLOB: OracleDataType {
        OracleDataType(
            number: .nCLOB,
            name: "DB_TYPE_NCLOB",
            oracleName: "NCLOB",
            oracleType: .init(rawValue: 112).unsafelyUnwrapped,
            csfrm: 2,
            bufferSizeFactor: 112
        )
    }

    @inlinable
    public static var number: OracleDataType {
        OracleDataType(
            number: .number,
            name: "DB_TYPE_NUMBER",
            oracleName: "NUMBER",
            oracleType: .init(rawValue: 2).unsafelyUnwrapped,
            bufferSizeFactor: 22
        )
    }

    @inlinable
    public static var nVarchar: OracleDataType {
        OracleDataType(
            number: .nVarchar,
            name: "DB_TYPE_NVARCHAR",
            oracleName: "NVARCHAR2",
            oracleType: .init(rawValue: 1).unsafelyUnwrapped,
            defaultSize: 4000,
            csfrm: 2,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var object: OracleDataType {
        OracleDataType(
            number: .object,
            name: "DB_TYPE_OBJECT",
            oracleName: "OBJECT",
            oracleType: .init(rawValue: 109).unsafelyUnwrapped
        )
    }

    @inlinable
    public static var raw: OracleDataType {
        OracleDataType(
            number: .raw,
            name: "DB_TYPE_RAW",
            oracleName: "RAW",
            oracleType: .init(rawValue: 23).unsafelyUnwrapped,
            defaultSize: 4000,
            bufferSizeFactor: 1
        )
    }

    @inlinable
    public static var rowID: OracleDataType {
        OracleDataType(
            number: .rowID,
            name: "DB_TYPE_ROWID",
            oracleName: "ROWID",
            oracleType: .init(rawValue: 11).unsafelyUnwrapped,
            bufferSizeFactor: 18
        )
    }

    @inlinable
    public static var timestamp: OracleDataType {
        OracleDataType(
            number: .timestamp,
            name: "DB_TYPE_TIMESTAMP",
            oracleName: "TIMESTAMP",
            oracleType: .init(rawValue: 180).unsafelyUnwrapped,
            bufferSizeFactor: 11
        )
    }

    @inlinable
    public static var timestampLTZ: OracleDataType {
        OracleDataType(
            number: .timestampLTZ,
            name: "DB_TYPE_TIMESTAMP_LTZ",
            oracleName: "TIMESTAMP WITH LOCAL TZ",
            oracleType: .init(rawValue: 231).unsafelyUnwrapped,
            bufferSizeFactor: 11
        )
    }

    @inlinable
    public static var timestampTZ: OracleDataType {
        OracleDataType(
            number: .timestampTZ,
            name: "DB_TYPE_TIMESTAMP_TZ",
            oracleName: "TIMESTAMP WITH TZ",
            oracleType: .init(rawValue: 181).unsafelyUnwrapped,
            bufferSizeFactor: 13
        )
    }

    @inlinable
    public static var unknown: OracleDataType {
        OracleDataType(
            number: .unknown,
            name: "DB_TYPE_UNKNOWN",
            oracleName: "UNKNOWN"
        )
    }

    @inlinable
    public static var uRowID: OracleDataType {
        OracleDataType(
            number: .uRowID,
            name: "DB_TYPE_UROWID",
            oracleName: "UROWID",
            oracleType: .init(rawValue: 208).unsafelyUnwrapped
        )
    }

    @inlinable
    public static var varchar: OracleDataType {
        OracleDataType(
            number: .varchar,
            name: "DB_TYPE_VARCHAR",
            oracleName: "VARCHAR2",
            oracleType: .init(rawValue: 1).unsafelyUnwrapped,
            defaultSize: 4000,
            csfrm: 1,
            bufferSizeFactor: 4
        )
    }

    @inlinable
    public static var vector: OracleDataType {
        OracleDataType(
            number: .vector,
            name: "DB_TYPE_VECTOR",
            oracleName: "VECTOR",
            oracleType: .init(rawValue: 127).unsafelyUnwrapped
        )
    }

    @usableFromInline
    static let supported: [OracleDataType] = [
        .bFile, .binaryDouble, .binaryFloat, .binaryInteger, .blob, .boolean,
        .char, .clob, .cursor, .date, .intervalDS, .intervalYM, .json, .long,
        .longNVarchar, .longRAW, .nChar, .nCLOB, .number, .nVarchar, .object,
        .raw, .rowID, .timestamp, .timestampLTZ, .timestampTZ, .unknown,
        .uRowID, .varchar, .vector,
    ]
}
