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

/// A fast path to request more data from the wire while decoding.
///
/// Throw ``MissingDataDecodingError/Trigger`` if you require more data,
/// do not throw an instance of ``MissingDataDecodingError`` directly.
struct MissingDataDecodingError: Error {
    let decodedMessages: TinySequence<OracleBackendMessage>
    let resetToReaderIndex: Int

    struct Trigger: Error {}
}
