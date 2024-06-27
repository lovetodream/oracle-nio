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

import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationCompat

import struct Foundation.Data
import class Foundation.JSONEncoder

/// A protocol that mimics the Foundation `JSONEncoder.encode(_:)` function.
///
/// Conform a non-Foundation JSON encoder to this protocol if you want OracleNIO to be able to use it
/// when encoding JSON values.
public protocol OracleJSONEncoder: Sendable {
    func encode<T>(_ value: T) throws -> Data where T: Encodable

    func encode<T: Encodable>(_ value: T, into buffer: inout ByteBuffer) throws
}

extension OracleJSONEncoder {
    public func encode<T: Encodable>(
        _ value: T,
        into buffer: inout ByteBuffer
    ) throws {
        let data = try self.encode(value)
        buffer.writeData(data)
    }
}

extension JSONEncoder: OracleJSONEncoder {}

private let jsonEncoderLocked: NIOLockedValueBox<OracleJSONEncoder> = NIOLockedValueBox(
    JSONEncoder())

/// The default JSON encoder used by OracleNIO when encoding JSON values.
///
/// As `_defaultJSONEncoder` will be reused for encoding all JSON values from potentially multiple
/// threads at once, you must ensure your custom JSON encoder is thread safe internally like
/// `Foundation.JSONEncoder`.
public var _defaultJSONEncoder: OracleJSONEncoder {
    get { jsonEncoderLocked.withLockedValue { $0 } }
    set { jsonEncoderLocked.withLockedValue { $0 = newValue } }
}
