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

/// Oracle authentication modes.
public enum AuthenticationMode: UInt32, Sendable, CustomStringConvertible {
    case `default` = 0
    case prelim = 0x0000_0008
    case sysASM = 0x0000_8000
    case sysBKP = 0x0002_0000
    case sysDBA = 0x0000_0002
    case sysDGD = 0x0004_0000
    case sysKMT = 0x0008_0000
    case sysOPER = 0x0000_0004
    case sysRAC = 0x0010_0000

    public var description: String {
        switch self {
        case .default:
            return "DEFAULT"
        case .prelim:
            return "PRELIM"
        case .sysASM:
            return "SYSASM"
        case .sysBKP:
            return "SYSBKP"
        case .sysDBA:
            return "SYSDBA"
        case .sysDGD:
            return "SYSDGD"
        case .sysKMT:
            return "SYSKMT"
        case .sysOPER:
            return "SYSOPER"
        case .sysRAC:
            return "SYSRAC"
        }
    }

    /// Bitwise comparison.
    func compare(with other: Self) -> Bool {
        other.rawValue & self.rawValue != 0
    }
}
