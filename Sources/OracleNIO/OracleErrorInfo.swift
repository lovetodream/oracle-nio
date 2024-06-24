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

import protocol Foundation.LocalizedError

struct OracleErrorInfo: Error {
    var number: UInt32
    var cursorID: UInt16?
    var position: UInt16?
    var rowCount: UInt64?
    var isWarning: Bool
    var message: String?
    var rowID: RowID?
    var batchErrors: [OracleError]
}

struct OracleError: Error, Hashable {
    var code: Int
    var offset: Int
    var message: String?

    init(message: String? = nil, code: Int = 0, offset: Int = 0) {
        self.code = code
        self.offset = offset
        self.message = message
    }

    enum ErrorType: Int, Error, LocalizedError {
        // MARK: Error numbers that result in InterfaceError
        case poolHasBusyConnections = 1005

        // MARK: Error numbers that result in ProgrammingError
        case invalidObjectTypeName = 2035
        case invalidCollectionIndexSet = 2039

        // MARK: Error numbers that result in NotSupportedError
        case oracleTypeNotSupported = 3006
        case dbTypeNotSupported = 3007
        case serverVersionNotSupported = 3010
        case nCharCSNotSupported = 3012
        case unsupportedVerifierType = 3015
        case osonNodeTypeNotSupported = 3019
        case osonVersionNotSupported = 3021
        case namedTimeZoneNotSupported = 3022

        // MARK: Error numbers that result in DatabaseError
        case noCredentials = 4001
        case columnTruncated = 4002
        case oracleNumberNoRepresentation = 4003
        case invalidNumber = 4004
        case poolNoConnectionAvailable = 4005
        case arrayDMLRowCountsNotEnabled = 4006
        case wrongNumberOfPositionalBinds = 4009
        case missingBindValue = 4010
        case connectionClosed = 4011
        case numberWithInvalidExponent = 4012
        case numberStringOfZeroLength = 4013
        case numberStringTooLong = 4014
        case numberWithEmptyExponent = 4015
        case contentInvalidAfterNumber = 4016
        case invalidConnectDescriptor = 4017
        case invalidRefCursor = 4025

        // MARK: Error Numbers that result in InternalError
        case typeUnknown = 5000
        case unexpectedData = 5004

        // MARK: Error Numbers that result in OperationalError
        case listenerRefusedConnection = 6000

        var errorDescription: String? {
            switch self {
            case .poolHasBusyConnections:
                return "Connection pool cannot be closed because connections are busy."
            case .invalidObjectTypeName:
                return "Invalid object type name."
            case .invalidCollectionIndexSet:
                return "Given index is out of range."
            case .oracleTypeNotSupported:
                return "Oracle data type is not supported by oracle-nio."
            case .dbTypeNotSupported:
                return "Database type is not supported by oracle-nio."
            case .serverVersionNotSupported:
                return
                    "Connections to this database server version are not supported by oracle-nio."
            case .nCharCSNotSupported:
                return
                    "The national character set used by this database is not supported by oracle-nio."
            case .unsupportedVerifierType:
                return "The configured password verifier type is not supported by oracle-nio."
            case .osonNodeTypeNotSupported:
                return "OSON node type is not supported by oracle-nio."
            case .osonVersionNotSupported:
                return "OSON version is not supported by oracle-nio."
            case .namedTimeZoneNotSupported:
                return "Named Time Zones are not supported by oracle-nio."
            case .noCredentials:
                return "No credentials specified."
            case .columnTruncated:
                return "Column truncated."
            case .oracleNumberNoRepresentation:
                return "Value cannot be represented as an Oracle number."
            case .invalidNumber:
                return "Invalid number."
            case .poolNoConnectionAvailable:
                return "Timed out waiting for the connection pool to return a connection."
            case .arrayDMLRowCountsNotEnabled:
                return "Array DML row counts mode is not enabled."
            case .wrongNumberOfPositionalBinds:
                return "Amount of binds is not matching amount of values."
            case .missingBindValue:
                return "A bind variable is missing in the statement."
            case .connectionClosed:
                return "The database or network closed the connection."
            case .numberWithInvalidExponent:
                return "Invalid number: invalid exponent"
            case .numberStringOfZeroLength:
                return "Invalid number: zero length string."
            case .numberStringTooLong:
                return "Invalid number: string too long."
            case .numberWithEmptyExponent:
                return "Invalid number: empty exponent"
            case .contentInvalidAfterNumber:
                return "Invalid number (content after number)"
            case .invalidConnectDescriptor:
                return "The connect descriptor is not valid."
            case .invalidRefCursor:
                return "Invalid REF cursor: never opened in PL/SQL."
            case .typeUnknown:
                return "Internal error: unknown protocol message type."
            case .unexpectedData:
                return "Unexpected data received."
            case .listenerRefusedConnection:
                return "Cannot connect to database. Listener refused connection."
            }
        }
    }

    /// Oracle error number cross reference
    private static let oracleErrorXref: [Int: OracleError.ErrorType] = [
        28: .connectionClosed,
        600: .connectionClosed,
        1005: .noCredentials,
        22165: .invalidCollectionIndexSet,
        22303: .invalidObjectTypeName,
        24422: .poolHasBusyConnections,
        24349: .arrayDMLRowCountsNotEnabled,
        24459: .poolNoConnectionAvailable,
        24496: .poolNoConnectionAvailable,
        24338: .invalidRefCursor,
    ]
}

let integrityErrorCodes: [Int32] = [
    1,  // unique constraint violated
    1400,  // cannot insert NULL
    1438,  // value larger than specified precision
    2290,  // check constraint violated
    2291,  // integrity constraint violated - parent key not found
    2292,  // integrity constraint violated - child record found
    21525,  // attribute or collection element violated its constraints
    40479,  // internal JSON serializer error
    0,
]

let interfaceErrorCodes: [Int32] = [
    24422,
    0,
]

let operationalErrorCodes: [Int32] = [
    22,  // invalid session ID; access denied
    378,  // buffer pools cannot be created as specified
    600,  // internal error code
    602,  // internal programming exception
    603,  // ORACLE server session terminated by fatal error
    604,  // error occurred at recursive SQL level
    609,  // could not attach to incoming connection
    1012,  // not logged on
    1013,  // user requested cancel of current operation
    1033,  // ORACLE initialization or shutdown in progress
    1034,  // ORACLE not available
    1041,  // internal error. hostdef extension doesn't exist
    1043,  // user side memory corruption
    1089,  // immediate shutdown or close in progress
    1090,  // shutdown in progress - connection is not permitted
    1092,  // ORACLE instance terminated. Disconnection forced
    3111,  // break received on communication channel
    3113,  // end-of-file on communication channel
    3114,  // not connected to ORACLE
    3122,  // attempt to close ORACLE-side window on user side
    3135,  // connection lost contact
    12153,  // TNS:not connected
    12203,  // TNS:unable to connect to destination
    12500,  // TNS:listener failed to start a dedicated server process
    12571,  // TNS:packet writer failure
    27146,  // post/wait initialization failed
    28511,  // lost RPC connection to heterogeneous remote agent
    0,
]

func isCodeInArray(_ code: Int32, _ array: [Int32]) -> Bool {
    var ix = 0
    while ix < array.count {
        if array[ix] == code {
            return true
        }
        ix += 1
    }
    return false
}

enum OracleErrorType: Error {
    case integrityError
    case operationalError
    case interfaceError
    case databaseError
}

func getExceptionClass(for code: Int32) -> OracleErrorType {
    if isCodeInArray(code, integrityErrorCodes) {
        return .integrityError
    }
    if isCodeInArray(code, operationalErrorCodes) {
        return .operationalError
    }
    if isCodeInArray(code, interfaceErrorCodes) {
        return .interfaceError
    }
    return .databaseError
}
