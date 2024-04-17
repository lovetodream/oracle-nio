// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OracleNIO

final class OracleFrontendMessageEncoderTests: XCTestCase {
    func testAlterTimezone() {
        let berlin = TimeZone(identifier: "Europe/Berlin")
        let encoder = OracleFrontendMessageEncoder(buffer: .init(), capabilities: .init())
        let summer2024 = Date(timeIntervalSince1970: 1717236000) // 2024-12-01 12:00:00 +01:00
        let winter2024 = Date(timeIntervalSince1970: 1733050800) // 2024-06-01 11:00:00 +01:00
        let summerStatement = encoder._getAlterTimezoneStatement(customTimezone: berlin, atDate: summer2024)
        let winterStatement = encoder._getAlterTimezoneStatement(customTimezone: berlin, atDate: winter2024)
        XCTAssertEqual(summerStatement, "ALTER SESSION SET TIME_ZONE='+02:00'\0")
        XCTAssertEqual(winterStatement, "ALTER SESSION SET TIME_ZONE='+01:00'\0")
    }
}
