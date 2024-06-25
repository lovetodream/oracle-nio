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

import protocol Foundation.DataProtocol

let charA = UInt8(UnicodeScalar("a").value)
let char0 = UInt8(UnicodeScalar("0").value)

private func itoh(_ value: UInt8) -> UInt8 {
    return (value > 9) ? (charA + value - 10) : (char0 + value)
}

extension DataProtocol {
    var hexString: String {
        let hexLen = self.count * 2
        var hexChars = [UInt8](repeating: 0, count: hexLen)
        var offset = 0

        for _ in self.regions {
            for i in self {
                hexChars[Int(offset * 2)] = itoh((i >> 4) & 0xF)
                hexChars[Int(offset * 2 + 1)] = itoh(i & 0xF)
                offset += 1
            }
        }

        return String(bytes: hexChars, encoding: .utf8)!
    }
}
