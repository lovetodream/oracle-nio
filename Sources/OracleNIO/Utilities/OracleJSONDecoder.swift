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
import class Foundation.JSONDecoder

/// A protocol that mimics the Foundation `JSONDecoder.decode(_:from:)` function.
///
/// Conform a non-Foundation JSON decoder to this protocol if you want OracleNIO to be able to use it
/// when decoding JSON values (see ``_defaultJSONDecoder``).
public protocol OracleJSONDecoder: Sendable {
    func decode<T>(
        _ type: T.Type, from data: Data
    ) throws -> T where T: Decodable

    func decode<T: Decodable>(
        _ type: T.Type,
        from buffer: ByteBuffer
    ) throws -> T
}

extension OracleJSONDecoder {
    public func decode<T: Decodable>(
        _ type: T.Type,
        from buffer: ByteBuffer
    ) throws -> T {
        var copy = buffer
        let data = copy.readData(length: buffer.readableBytes)!
        return try self.decode(type, from: data)
    }
}

extension JSONDecoder: OracleJSONDecoder {}

private let jsonDecoderLocked: NIOLockedValueBox<OracleJSONDecoder> = NIOLockedValueBox(
    JSONDecoder())

/// The default JSON decoder used by OracleNIO when decoding JSON values.
///
/// As `_defaultJSONDecoder` will be reused for decoding all JSON values from potentially multiple
/// threads at once, you must ensure your custom JSON decoder is thread safe internally like
/// `Foundation.JSONDecoder`.
public var _defaultJSONDecoder: OracleJSONDecoder {
    get { jsonDecoderLocked.withLockedValue { $0 } }
    set { jsonDecoderLocked.withLockedValue { $0 = newValue } }
}
