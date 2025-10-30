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

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

@usableFromInline
enum OracleJSONStorage: Sendable, Equatable {
    /// Containers
    case container([String: OracleJSONStorage])
    case array([OracleJSONStorage])
    case none

    /// Primitives
    case bool(Bool)
    case string(String)
    case double(Double)
    case float(Float)
    case int(Int)
    case date(Date)
    case intervalDS(IntervalDS)
    case vectorInt8(OracleVectorInt8)
    case vectorFloat32(OracleVectorFloat32)
    case vectorFloat64(OracleVectorFloat64)
    case vectorBinary(OracleVectorBinary)
}

extension OracleJSONStorage {
    var debugDataTypeDescription: String {
        switch self {
        case .container:
            "a dictionary"
        case .array:
            "an array"
        case .none:
            "null"
        case .bool:
            "bool"
        case .string:
            "a string"
        case .double:
            "a double"
        case .float:
            "a float"
        case .int:
            "an int"
        case .date:
            "a date"
        case .intervalDS:
            "a day second interval"
        case .vectorInt8:
            "an int8 vector"
        case .vectorFloat32:
            "a float32 vector"
        case .vectorFloat64:
            "a float64 vector"
        case .vectorBinary:
            "a binary vector"
        }
    }
}
