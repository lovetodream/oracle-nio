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

import NIOCore

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// A type that can encode itself to a Oracle wire binary representation.
///
/// Dynamic types are types that don't have a well-known Oracle type OID at compile time.
/// For example, custom types created at runtime, such as enums, or extension types whose OID is not
/// stable between databases.
public protocol OracleThrowingDynamicTypeEncodable: ~Copyable, Sendable {
    /// Identifies the default data type that we will encode into `ByteBuffer` in `encode`.
    ///
    /// It is used to encode `NULL` values to the correct format.
    static var defaultOracleType: OracleDataType { get }

    /// Identifies the data type that we will encode into `ByteBuffer` in `encode`.
    ///
    /// A default implementation is provided.
    var oracleType: OracleDataType { get }

    /// Identifies the byte size indicator which will be sent to Oracle.
    ///
    /// This doesn't need to be the actual size. Mostly it is the corresponding
    /// ``OracleDataType/defaultSize-property``. A default
    /// implementation based on that is provided.
    var size: UInt32 { get }

    /// Indicates if the data type is an array.
    ///
    /// A default implementation is provided.
    static var isArray: Bool { get }

    /// Indicates the number of elements in the array if the value is an array.
    ///
    /// Typically `Array.count`. A default implementation is provided.
    var arrayCount: Int? { get }

    /// Indicates the array size sent to Oracle.
    ///
    /// Only required if ``isArray`` is `true`. A default implementation is provided.
    var arraySize: Int? { get }

    /// Encode the entity into the `ByteBuffer` in Oracle binary format, without setting the byte count.
    func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) throws

    /// Encode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten if length needs to be specially
    /// handled. You shouldn't have to touch this.
    ///
    /// This method is called from the ``OracleBindings``.
    func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) throws
}

/// A type that can encode itself to a Oracle wire binary representation.
///
/// Dynamic types are types that don't have a well-known Oracle type OID at compile time.
/// For example, custom types created at runtime, such as enums, or extension types whose OID is not
/// stable between databases.
///
/// This is the non-throwing alternative to ``OracleThrowingDynamicTypeEncodable``. It allows
/// users to create ``OracleStatement``s via `ExpressibleByStringInterpolation` without
/// having to spell `try`.
public protocol OracleDynamicTypeEncodable: ~Copyable, OracleThrowingDynamicTypeEncodable {
    /// Encode the entity into `buffer`, using the provided `context` as needed, without setting
    /// the byte count.
    func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    )

    /// Encode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten if length needs to be specially
    /// handled. You shouldn't have to touch this.
    ///
    /// This method is called by ``OracleBindings``.
    func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    )
}

/// A type that can encode itself to a Oracle wire binary representation.
public protocol OracleThrowingEncodable: ~Copyable, OracleThrowingDynamicTypeEncodable {}

extension OracleThrowingDynamicTypeEncodable {
    public var oracleType: OracleDataType { Self.defaultOracleType }

    public var size: UInt32 { UInt32(self.oracleType.defaultSize) }

    public static var isArray: Bool { false }
    public var arrayCount: Int? { nil }
    public var arraySize: Int? { Self.isArray ? 1 : nil }
}

// swift-format-ignore: DontRepeatTypeInStaticProperties
extension Array where Element: OracleThrowingDynamicTypeEncodable {
    public var oracleType: OracleDataType { Element.defaultOracleType }

    public static var isArray: Bool { true }
    public var arrayCount: Int? { self.count }
    public var arraySize: Int? { self.capacity }
}

/// A type that can encode itself to a oracle wire binary representation.
///
/// It enforces that the ``OracleThrowingDynamicTypeEncodable-Implementations``
/// does not throw. This allows users to create ``OracleStatement``'s using the
/// `ExpressibleByStringInterpolation` without having to spell `try`.
public protocol OracleEncodable: ~Copyable,
    OracleThrowingEncodable, OracleDynamicTypeEncodable
{}

/// A type that can decode itself from a oracle wire binary representation.
///
/// If you want to conform a type to OracleDecodable you must implement the decode method.
public protocol OracleNonCopyableDecodable: ~Copyable, Sendable {
    /// Create an entity from the `ByteBuffer` in Oracle wire format.
    /// - Parameters:
    ///   - buffer: A `ByteBuffer` to decode. The `ByteBuffer` is sliced in such a way that it is expected that the complete buffer is consumed for decoding.
    ///   - type: The oracle data type. Depending on this type the `ByteBuffer`'s bytes need to be interpreted in different ways.
    ///   - context: A `OracleDecodingContext` providing context for decoding.
    init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws

    /// Decode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten for `Optional`'s.
    static func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> Self
}

/// A type that can decode itself from a oracle wire binary representation.
///
/// If you want to conform a type to OracleDecodable you must implement the decode method.
public protocol OracleDecodable: Sendable {
    /// A type definition of the type that actually implements the OracleDecodable protocol.
    ///
    /// This is an escape hatch to prevent a cycle in the conformance of the Optional type to
    /// ``OracleDecodable``.
    /// `String?` should be OracleDecodable, `String??` should not be OracleDecodable.
    associatedtype _DecodableType: OracleDecodable = Self

    /// Create an entity from the `ByteBuffer` in Oracle wire format.
    /// - Parameters:
    ///   - buffer: A `ByteBuffer` to decode. The `ByteBuffer` is sliced in such a way that it is expected that the complete buffer is consumed for decoding.
    ///   - type: The oracle data type. Depending on this type the `ByteBuffer`'s bytes need to be interpreted in different ways.
    ///   - context: A `OracleDecodingContext` providing context for decoding.
    init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws

    /// Decode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten for `Optional`'s.
    static func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> Self
}

extension OracleDecodable {
    @inlinable
    public static func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> Self {
        guard var buffer else {
            throw OracleDecodingError.Code.missingData
        }
        return try self.init(from: &buffer, type: type, context: context)
    }
}

/// A type that can be encoded into and decoded from a oracle binary format.
public typealias OracleCodable = OracleEncodable & OracleDecodable

extension OracleThrowingDynamicTypeEncodable {
    @inlinable
    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) throws {
        // The length of the parameter value, in bytes
        // (this count does not include itself). Can be zero.
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(0, as: UInt8.self)
        let startIndex = buffer.writerIndex
        // The value of the parameter, in the format indicated by the associated
        // format code.
        try self.encode(into: &buffer, context: context)

        // overwrite the empty length with the real value
        buffer.setInteger(
            numericCast(buffer.writerIndex - startIndex),
            at: lengthIndex, as: UInt8.self
        )
    }
}

extension OracleDynamicTypeEncodable {
    @inlinable
    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        // The length of the parameter value, in bytes (this count does not
        // include itself). Can be zero.
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(0, as: UInt8.self)
        let startIndex = buffer.writerIndex
        // The value of the parameter, in the format indicated by the associated
        // format code.
        self.encode(into: &buffer, context: context)

        // overwrite the empty length, with the real value.
        buffer.setInteger(
            numericCast(buffer.writerIndex - startIndex),
            at: lengthIndex, as: UInt8.self
        )
    }
}

/// A context hat is passed to Swift objects that are encoded into the oracle wire format.
///
/// Used to pass further information to the encoding method.
public struct OracleEncodingContext: Sendable {
    @usableFromInline
    @TaskLocal static var jsonMaximumFieldNameSize: Int = 255

    @usableFromInline
    init() {}
}

extension OracleEncodingContext {
    /// A default ``OracleEncodingContext``.
    @inlinable
    public static var `default`: OracleEncodingContext {
        OracleEncodingContext()
    }
}

/// A context that is passed to Swift objects that are decoded from the Oracle wire format.
///
/// Used to pass further information to the decoding method.
public struct OracleDecodingContext: Sendable {
    @usableFromInline
    init() {}
}

extension OracleDecodingContext {
    /// A default ``OracleDecodingContext``.
    @inlinable
    public static var `default`: OracleDecodingContext {
        OracleDecodingContext()
    }
}

extension Optional: OracleDecodable
where Wrapped: OracleDecodable, Wrapped._DecodableType == Wrapped {
    public typealias _DecodableType = Wrapped

    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        preconditionFailure("This should not be called")
    }

    @inlinable
    public static func _decodeRaw(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws -> Self {
        switch buffer {
        case .some(var buffer):
            return try Wrapped(
                from: &buffer,
                type: type,
                context: context
            )
        case .none:
            return .none
        }
    }
}
