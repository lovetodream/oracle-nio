// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

/// TNS Message Types
enum MessageType: UInt8, CustomStringConvertible {
    case `protocol` = 1
    case dataTypes = 2
    case function = 3
    case error = 4
    case rowHeader = 6
    case rowData = 7
    case parameter = 8
    case status = 9
    case ioVector = 11
    case lobData = 14
    case warning = 15
    case describeInfo = 16
    case piggyback = 17
    case flushOutBinds = 19
    case bitVector = 21
    case serverSidePiggyback = 23
    case onewayFN = 26
    case implicitResultset = 27
    case renegotiate = 28
    case cookie = 30

    var description: String {
        switch self {
        case .protocol:
            return "PROTOCOL"
        case .dataTypes:
            return "DATA_TYPES"
        case .function:
            return "FUNCTION"
        case .error:
            return "ERROR"
        case .rowHeader:
            return "ROW_HEADER"
        case .rowData:
            return "ROW_DATA"
        case .parameter:
            return "PARAMETER"
        case .status:
            return "STATUS"
        case .ioVector:
            return "IO_VECTOR"
        case .lobData:
            return "LOB_DATA"
        case .warning:
            return "WARNING"
        case .describeInfo:
            return "DESCRIBE_INFO"
        case .piggyback:
            return "PIGGYBACK"
        case .flushOutBinds:
            return "FLUSH_OUT_BINDS"
        case .bitVector:
            return "BIT_VECTOR"
        case .serverSidePiggyback:
            return "SERVER_SIDE_PIGGYBACK"
        case .onewayFN:
            return "ONEWAY_FN"
        case .implicitResultset:
            return "IMPLICIT_RESULTSET"
        case .renegotiate:
            return "RENEGOTIATE"
        case .cookie:
            return "COOKIE"
        }
    }
}
