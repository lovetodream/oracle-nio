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

/// A reference type used to capture `OUT` and `IN/OUT` binds in `DML` returning statements or
/// `PL/SQL`.
///
/// - Note: `OracleRef`s used as `IN/OUT` binds without a value will be declared
///         as `NULL` in `PL/SQL`.
///
/// Here is an example showing how to use `OUT` binds in a `RETURNING` clause:
///
/// ```swift
/// let ref = OracleRef(dataType: .number, isReturnBind: true)
/// try await connection.execute(
///     "INSERT INTO table(id) VALUES (1) RETURNING id INTO \(ref)",
///     logger: logger
/// )
/// let id = try ref.decode(as: Int.self) // 1
/// ```
///
/// Here is an example showing how to use `OUT` binds in `PL/SQL`:
///
/// ```swift
/// let ref = OracleRef(dataType: .number)
/// try await conn.execute("""
///     begin
///         \(ref) := \(OracleNumber(8)) + \(OracleNumber(7));
///     end;
///     """, logger: logger)
/// let result = try ref.decode(as: Int.self) // 15
/// ```
///
/// Here is an example showing how to use `IN/OUT` binds in `PL/SQL`
///
/// ```swift
/// let ref = OracleRef(OracleNumber(25))
/// try await conn.execute("""
///     begin
///     \(ref) := \(ref) + \(OracleNumber(8)) + \(OracleNumber(7));
///     end;
///     """, logger: .oracleTest)
/// let result = try ref.decode(as: Int.self) // 40
/// ```
///
public final class OracleRef: Sendable, Hashable {
    public static func == (lhs: OracleRef, rhs: OracleRef) -> Bool {
        lhs.storage.withLockedValue { lhs in
            rhs.storage.withLockedValue { rhs in
                lhs == rhs
            }
        }
    }

    public func hash(into hasher: inout Hasher) {
        self.storage.withLockedValue { hasher.combine($0) }
    }

    @usableFromInline
    internal let storage: NIOLockedValueBox<ByteBuffer?>
    @usableFromInline
    internal let metadata: NIOLockedValueBox<OracleBindings.Metadata>

    /// Use this initializer to create an OUT bind.
    ///
    /// Please be aware that you still have to decode the database response into the Swift type you want
    /// after completing the statement (using ``decode(of:)``).
    ///
    /// - Parameter dataType: The desired datatype within the Oracle database.
    /// - Parameter isReturnBind: Set this to `true` if the bind is used as part of a DML
    ///                           statement in the `RETURNING ... INTO binds` where
    ///                           binds are x `OracleRef`'s.
    public init(dataType: OracleDataType, isReturnBind: Bool = false) {
        self.storage = NIOLockedValueBox(nil)
        self.metadata = NIOLockedValueBox(
            .init(
                dataType: dataType,
                protected: false,
                isReturnBind: isReturnBind,
                isArray: false,
                arrayCount: nil,
                maxArraySize: nil,
                bindName: nil
            ))
    }

    /// Use this initializer to create an IN/OUT bind.
    /// - Parameter value: The initial value of the bind.
    public init<V: OracleThrowingDynamicTypeEncodable>(_ value: V) throws {
        var storage = ByteBuffer()
        try value._encodeRaw(into: &storage, context: .default)
        self.storage = NIOLockedValueBox(storage)
        self.metadata = NIOLockedValueBox(
            .init(
                value: value, protected: true, isReturnBind: false, bindName: nil
            ))
    }

    /// Use this initializer to create a IN/OUT bind.
    /// - Parameter value: The initial value of the bind.
    public init<V: OracleEncodable>(_ value: V) {
        var storage = ByteBuffer()
        value._encodeRaw(into: &storage, context: .default)
        self.storage = NIOLockedValueBox(storage)
        self.metadata = NIOLockedValueBox(
            .init(
                value: value, protected: true, isReturnBind: false, bindName: nil
            ))
    }

    /// Decodes a value of the given type from the bind.
    ///
    /// This method uses the ``OracleDecodable/init(from:type:context:)`` to decode
    /// the value internally.
    ///
    /// - Parameter of: The type of the returned value.
    /// - Returns: A value of the specified type.
    public func decode<V: OracleDecodable>(of: V.Type = V.self) throws -> V {
        var buffer: ByteBuffer?
        self.storage.withLockedValue { storage in
            let length = Int(storage?.getInteger(at: 0, as: UInt8.self) ?? 0)

            if length == Constants.TNS_LONG_LENGTH_INDICATOR {
                buffer = ByteBuffer()
                var position = MemoryLayout<UInt8>.size
                while true {
                    let chunkLength =
                        Int(storage!.getInteger(at: position, as: UInt32.self)!)
                    position += MemoryLayout<UInt32>.size
                    if chunkLength == 0 { break }
                    var temp = storage!.getSlice(
                        at: position, length: chunkLength
                    )!
                    position += chunkLength
                    buffer?.writeBuffer(&temp)
                }
            } else if length != 0 && length != Constants.TNS_NULL_LENGTH_INDICATOR {
                buffer = storage!.getSlice(
                    at: MemoryLayout<UInt8>.size, length: length
                )!
            }
        }
        return try self.metadata.withLockedValue { metadata in
            try V._decodeRaw(
                from: &buffer, type: metadata.dataType, context: .default
            )
        }
    }
}
