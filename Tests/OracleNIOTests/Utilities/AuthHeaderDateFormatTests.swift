//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing

@testable import OracleNIO

@Test func authHeaderDateFormatTests() throws {
    let authHeaderDateFormatter: DateFormatter = {
        let format = "E, dd MMM yyyy HH:mm:ss 'GMT'"
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter
    }()

    let iso8601TestStrings: [String] = [
        "2024-01-01T00:00:00Z",
        "2024-01-01T12:00:00Z",
        "2024-01-01T23:59:59Z",
        "2024-02-14T14:30:00Z",
        "2024-02-29T09:15:30Z",
        "2024-03-15T08:45:22Z",
        "2024-04-01T16:20:10Z",
        "2024-05-20T11:35:45Z",
        "2024-06-21T06:00:00Z",
        "2024-07-04T18:30:00Z",
        "2024-08-15T22:45:33Z",
        "2024-09-01T05:15:20Z",
        "2024-10-31T13:25:40Z",
        "2024-11-15T19:55:15Z",
        "2024-12-31T23:59:59Z",
        "2023-12-25T10:30:00Z",
        "2025-06-15T14:22:18Z",
        "2024-03-10T02:30:00Z",
        "2024-07-28T20:15:45Z",
        "2024-11-03T17:40:25Z",
        "2024-05-05T05:05:05Z",
        "2024-08-08T08:08:08Z",
        "2024-12-12T12:12:12Z",
        "2024-04-30T23:00:00Z",
        "2024-06-01T01:01:01Z",
        "2025-09-14T00:00:00Z",
    ]

    for string in iso8601TestStrings {
        let date = try Date(string, strategy: .iso8601)
        #expect(authHeaderDateFormatter.string(from: date) == authHeaderDate(for: date))
    }
}
