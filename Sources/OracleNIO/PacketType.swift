// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

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
