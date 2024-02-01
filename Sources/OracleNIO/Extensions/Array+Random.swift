// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

extension FixedWidthInteger {
    public static func random() -> Self {
        return Self.random(in: .min ... .max)
    }

    public static func random<T>(using generator: inout T) -> Self
        where T : RandomNumberGenerator
    {
        return Self.random(in: .min ... .max, using: &generator)
    }
}

extension Array where Element: FixedWidthInteger {
    public static func random(count: Int) -> Self {
        var array: Self = .init(repeating: 0, count: count)
        (0..<count).forEach { array[$0] = Element.random() }
        return array
    }

    public static func random<T>(count: Int, using generator: inout T) -> Self
        where T: RandomNumberGenerator
    {
        var array: Self = .init(repeating: 0, count: count)
        (0..<count).forEach { array[$0] = Element.random(using: &generator) }
        return array
    }
}
