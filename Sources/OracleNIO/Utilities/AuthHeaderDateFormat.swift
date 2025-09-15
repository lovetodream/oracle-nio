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

func authHeaderDate(for date: Date) -> String {
    var calendar = Calendar.current
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = .gmt
    let components = calendar.dateComponents([.weekday, .day, .month, .year, .hour, .minute, .second], from: date)


    let weekday = switch components.weekday {
    case 1:
        "Sun"
    case 2:
        "Mon"
    case 3:
        "Tue"
    case 4:
        "Wed"
    case 5:
        "Thu"
    case 6:
        "Fri"
    case 7:
        "Sat"
    default:
        fatalError("Invalid weekday \(String(reflecting: components.weekday))")
    }
    let day = String(components.day.unsafelyUnwrapped, padding: 2)
    let month = switch components.month {
    case 1:
        "Jan"
    case 2:
        "Feb"
    case 3:
        "Mar"
    case 4:
        "Apr"
    case 5:
        "May"
    case 6:
        "Jun"
    case 7:
        "Jul"
    case 8:
        "Aug"
    case 9:
        "Sep"
    case 10:
        "Oct"
    case 11:
        "Nov"
    case 12:
        "Dec"
    default:
        fatalError("Invalid month \(String(reflecting: components.month))")
    }
    let year = String(components.year.unsafelyUnwrapped, padding: 4)
    let hour = String(components.hour.unsafelyUnwrapped, padding: 2)
    let minute = String(components.minute.unsafelyUnwrapped, padding: 2)
    let second = String(components.second.unsafelyUnwrapped, padding: 2)
    return "\(weekday), \(day) \(month) \(year) \(hour):\(minute):\(second) GMT"
}

extension String {
    @inlinable
    internal init(_ value: some BinaryInteger, padding: Int) {
        let formatted = String(value)
        let padding = Swift.max(padding - formatted.count, 0)
        self = String(repeating: "0", count: padding) + formatted
    }
}
