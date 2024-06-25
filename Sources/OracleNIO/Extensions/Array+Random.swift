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

extension FixedWidthInteger {
    static func random() -> Self {
        return Self.random(in: .min ... .max)
    }

    static func random<T>(using generator: inout T) -> Self
    where T: RandomNumberGenerator {
        return Self.random(in: .min ... .max, using: &generator)
    }
}

extension Array where Element: FixedWidthInteger {
    static func random(count: Int) -> Self {
        var array: Self = .init(repeating: 0, count: count)
        for i in 0..<count { array[i] = Element.random() }
        return array
    }

    static func random<T>(count: Int, using generator: inout T) -> Self
    where T: RandomNumberGenerator {
        var array: Self = .init(repeating: 0, count: count)
        for i in 0..<count { array[i] = Element.random(using: &generator) }
        return array
    }
}
