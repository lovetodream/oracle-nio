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

#if compiler(>=6.0)
    import Testing

    import struct Foundation.Date
    import struct Foundation.TimeZone

    @testable import OracleNIO

    @Suite struct OracleFrontendMessageEncoderTests {
        @Test func alterTimezone() {
            let berlin = TimeZone(identifier: "Europe/Berlin")
            let encoder = OracleFrontendMessageEncoder(buffer: .init(), capabilities: .init())
            let summer2024 = Date(timeIntervalSince1970: 1_717_236_000)  // 2024-12-01 12:00:00 +01:00
            let winter2024 = Date(timeIntervalSince1970: 1_733_050_800)  // 2024-06-01 11:00:00 +01:00
            let summerStatement = encoder._getAlterTimezoneStatement(
                customTimezone: berlin, atDate: summer2024)
            let winterStatement = encoder._getAlterTimezoneStatement(
                customTimezone: berlin, atDate: winter2024)
            #expect(summerStatement == "ALTER SESSION SET TIME_ZONE='+02:00'\0")
            #expect(winterStatement == "ALTER SESSION SET TIME_ZONE='+01:00'\0")
        }
    }
#endif
