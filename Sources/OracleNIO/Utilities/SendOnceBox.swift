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

import NIOConcurrencyHelpers

struct SendOnceBox<Value>: ~Copyable, @unchecked Sendable {
    let mutex: NIOLockedValueBox<Value?>

    init() {
        mutex = NIOLockedValueBox(nil)
    }

    func set(_ value: sending Value) {
        mutex.withLockedValue { $0 = value }
    }

    /// Causes a runtime error if no value has been set previously.
    consuming func take() -> sending Value {
        mutex.withLockedValue { value -> sending Value in
            return value.unsafelyUnwrapped
        }
    }
}
