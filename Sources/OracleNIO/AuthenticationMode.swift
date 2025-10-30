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
public struct AuthenticationMode: Sendable, Equatable, CustomStringConvertible {
    @usableFromInline
    let base: Base

    @usableFromInline
    enum Base: UInt32, Sendable {
        case `default` = 0
        case prelim = 0x0000_0008
        case sysASM = 0x0000_8000
        case sysBKP = 0x0002_0000
        case sysDBA = 0x0000_0002
        case sysDGD = 0x0004_0000
        case sysKMT = 0x0008_0000
        case sysOPER = 0x0000_0004
        case sysRAC = 0x0010_0000

        @inlinable
        var description: String {
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
    }

    @inlinable
    public var description: String {
        self.base.description
    }

    @inlinable
    init(_ base: Base) {
        self.base = base
    }

    @inlinable
    public static var `default`: AuthenticationMode {
        AuthenticationMode(.default)
    }

    @inlinable
    public static var prelim: AuthenticationMode {
        AuthenticationMode(.prelim)
    }

    @inlinable
    public static var sysASM: AuthenticationMode {
        AuthenticationMode(.sysASM)
    }

    @inlinable
    public static var sysBKP: AuthenticationMode {
        AuthenticationMode(.sysBKP)
    }

    @inlinable
    public static var sysDBA: AuthenticationMode {
        AuthenticationMode(.sysDBA)
    }

    @inlinable
    public static var sysDGD: AuthenticationMode {
        AuthenticationMode(.sysDGD)
    }

    @inlinable
    public static var sysKMT: AuthenticationMode {
        AuthenticationMode(.sysKMT)
    }

    @inlinable
    public static var sysOPER: AuthenticationMode {
        AuthenticationMode(.sysOPER)
    }

    @inlinable
    public static var sysRAC: AuthenticationMode {
        AuthenticationMode(.sysRAC)
    }

    /// Bitwise comparison.
    func compare(with other: Self) -> Bool {
        other.base.rawValue & self.base.rawValue != 0
    }
}
