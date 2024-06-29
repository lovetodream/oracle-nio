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

import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

/// A type that can encode itself to a Oracle wire binary representation.
///
/// Dynamic types are types that don't have a well-known Oracle type OID at compile time.
/// For example, custom types created at runtime, such as enums, or extension types whose OID is not
/// stable between databases.
public protocol OracleThrowingDynamicTypeEncodable: Sendable {
    /// Identifies the data type that we will encode into `ByteBuffer` in `encode`.
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
    func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) throws

    /// Encode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten if length needs to be specially
    /// handled. You shouldn't have to touch this.
    ///
    /// This method is called from the ``OracleBindings``.
    func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
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
public protocol OracleDynamicTypeEncodable: OracleThrowingDynamicTypeEncodable {
    /// Encode the entity into `buffer`, using the provided `context` as needed, without setting
    /// the byte count.
    func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    )

    /// Encode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten if length needs to be specially
    /// handled. You shouldn't have to touch this.
    ///
    /// This method is called by ``OracleBindings``.
    func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    )
}

/// A type that can encode itself to a Oracle wire binary representation.
public protocol OracleThrowingEncodable: OracleThrowingDynamicTypeEncodable {}

extension OracleThrowingDynamicTypeEncodable {
    public var size: UInt32 { UInt32(self.oracleType.defaultSize) }

    public static var isArray: Bool { false }
    public var arrayCount: Int? { nil }
    public var arraySize: Int? { Self.isArray ? 1 : nil }
}

// swift-format-ignore: DontRepeatTypeInStaticProperties
extension Array where Element: OracleThrowingDynamicTypeEncodable {
    public static var isArray: Bool { true }
    public var arrayCount: Int? { self.count }
    public var arraySize: Int? { self.capacity }
}

/// A type that can encode itself to a oracle wire binary representation.
///
/// It enforces that the ``OracleThrowingDynamicTypeEncodable-Implementations``
/// does not throw. This allows users to create ``OracleStatement``'s using the
/// `ExpressibleByStringInterpolation` without having to spell `try`.
public protocol OracleEncodable:
    OracleThrowingEncodable, OracleDynamicTypeEncodable
{}

/// A type that can decode itself from a oracle wire binary representation.
///
/// If you want to conform a type to OracleDecodable you must implement the decode method.
public protocol OracleDecodable: Sendable {
    /// A type definition of the type that actually implements the OracleDecodable protocol.
    ///
    /// This is an escape hatch to prevent a cycle in the conformance of the Optional type to
    /// ``OracleDecodable``.
    /// `String?` should be OracleDecodable, `String??` should not be ORacleDecodable.
    associatedtype _DecodableType: OracleDecodable = Self

    /// Create an entity from the `ByteBuffer` in Oracle wire format.
    /// - Parameters:
    ///   - byteBuffer: A `ByteBuffer` to decode. The `ByteBuffer` is sliced in such a way that it is expected that the complete buffer is consumed for decoding.
    ///   - type: The oracle data type. Depending on this type the `ByteBuffer`'s bytes need to be interpreted in different ways.
    ///   - format: The oracle wire format.
    ///   - context: A `OracleDecodingContext` providing context for decoding. This includes a `JSONDecoder` to use when decoding json and metadata to create better errors.
    init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws

    /// Decode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten for `Optional`'s.
    static func _decodeRaw<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws -> Self
}

extension OracleDecodable {
    @inlinable
    public static func _decodeRaw<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
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
    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
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
    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
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
public struct OracleEncodingContext<JSONEncoder: OracleJSONEncoder>: Sendable {
    /// A ``OracleJSONEncoder`` used to encode the object to JSON.
    public var jsonEncoder: JSONEncoder


    /// Creates a ``OracleEncodingContext`` with the given ``OracleJSONEncoder``.
    ///
    /// In case you want to use a ``OracleEncodingContext`` with an unconfigured Foundation
    /// `JSONEncoder` you can use the ``default`` context instead.
    ///
    /// - Parameter jsonEncoder: A ``OracleJSONEncoder`` to use when encoding objects to
    /// json.
    public init(jsonEncoder: JSONEncoder) {
        self.jsonEncoder = jsonEncoder
    }
}

extension OracleEncodingContext where JSONEncoder == Foundation.JSONEncoder {
    /// A default ``OracleEncodingContext`` that uses a Foundation `JSONEncoder`.
    public static let `default` =
        OracleEncodingContext(jsonEncoder: JSONEncoder())
}

extension OracleDecodingContext where JSONDecoder == Foundation.JSONDecoder {
    /// A default ``OracleDecodingContext`` that uses a Foundation `JSONDecoder`.
    public static let `default` =
        OracleDecodingContext(jsonDecoder: Foundation.JSONDecoder())
}

/// A context that is passed to Swift objects that are decoded from the Oracle wire format.
///
/// Used to pass further information to the decoding method.
public struct OracleDecodingContext<JSONDecoder: OracleJSONDecoder>: Sendable {
    /// A ``OracleJSONDecoder`` used to decode the object from JSON.
    public var jsonDecoder: JSONDecoder

    /// Creates a ``OracleDecodingContext`` with the given ``OracleJSONDecoder``.
    ///
    /// In cases you want to use a ``OracleDecodingContext`` with an unconfigured Foundation
    /// `JSONDecoder` you can use the ``default`` context instead.
    ///
    /// - Parameter jsonDecoder: A ``OracleJSONDecoder`` to use when decoding objects
    /// from json.
    public init(jsonDecoder: JSONDecoder) {
        self.jsonDecoder = jsonDecoder
    }
}

extension Optional: OracleDecodable
where Wrapped: OracleDecodable, Wrapped._DecodableType == Wrapped {
    public typealias _DecodableType = Wrapped

    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        preconditionFailure("This should not be called")
    }

    @inlinable
    public static func _decodeRaw<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
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
