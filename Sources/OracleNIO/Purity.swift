// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

/// Purity types.
enum Purity: UInt32 {
    case `default` = 0
    case new = 1
    case `self` = 2
}
