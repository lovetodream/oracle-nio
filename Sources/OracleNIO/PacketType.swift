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

/// TNS Packet Types
enum PacketType: UInt8 {
    case connect = 1
    case accept = 2
    case refuse = 4
    case data = 6
    case resend = 11
    case marker = 12
    case control = 14
    case redirect = 5
}
