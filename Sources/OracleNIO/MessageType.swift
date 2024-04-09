// Copyright 2024 Timo Zacherl
// SPDX-License-Identifier: Apache-2.0

/// TNS Message Types
@available(*, unavailable)
enum MessageType: UInt8 {
    case implicitResultset = 27
    case renegotiate = 28
}
