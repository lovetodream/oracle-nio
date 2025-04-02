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

enum VectorFormat: UInt8 {
    case float32 = 2
    case float64 = 3
    case int8 = 4
    case binary = 5
}


// MARK: Binary

/// A dynamically sized vector of type UInt8, used to send
/// and receive `vector(n * 8, binary)` data to and from Oracle databases.
///
/// The binary format represents each dimension value as a binary value (0 or 1).
/// Binary vectors require less memory storage. For example, a 16 dimensional vector with binary
/// format requires only 2 bytes of storage while a 16 dimensional vector with Int8 format
/// requires 16 bytes of storage.
///
/// Binary vectors are represented as 8-bit unsigned integers.
public struct OracleVectorBinary: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = UInt8

    static let vectorFormat: VectorFormat = .binary

    @usableFromInline
    var base: TinySequence<Element>

    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.base = .init(elements)
    }

    @inlinable
    public init(_ collection: some Collection<Element>) {
        self.base = .init(collection)
    }

    init(underlying: TinySequence<Element>) {
        self.base = underlying
    }

    @inlinable
    public subscript(position: Index) -> Element {
        get {
            self.base[position]
        }
        set(newValue) {
            self.base[position] = newValue
        }
    }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        for element in self.base {
            buffer.writeInteger(element)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorBinary
    {
        var values: TinySequence<Element> = []
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(buffer.throwingReadInteger(as: Element.self))
        }

        return .init(underlying: values)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if encoder is _OracleJSONEncoder {
            try container.encode(self)
        } else {
            try container.encode(Array(self.base))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.base = .init(try container.decode([Element].self))
    }
}


// MARK: Int8

/// A dynamically sized vector of type Int8, used to send
/// and receive `vector(n, int8)` data to and from Oracle databases.
public struct OracleVectorInt8: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = Int8

    static let vectorFormat: VectorFormat = .int8

    @usableFromInline
    var base: TinySequence<Element>

    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.base = .init(elements)
    }

    @inlinable
    public init(_ collection: some Collection<Element>) {
        self.base = .init(collection)
    }

    init(underlying: TinySequence<Element>) {
        self.base = underlying
    }

    @inlinable
    public subscript(position: Index) -> Element {
        get {
            self.base[position]
        }
        set(newValue) {
            self.base[position] = newValue
        }
    }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        for element in self.base {
            buffer.writeInteger(element)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorInt8
    {
        var values: TinySequence<Int8> = []
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(buffer.throwingReadInteger(as: Int8.self))
        }

        return .init(underlying: values)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if encoder is _OracleJSONEncoder {
            try container.encode(self)
        } else {
            try container.encode(Array(self.base))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.base = .init(try container.decode([Element].self))
    }
}

// MARK: Float32

/// A dynamically sized vector of type Float32, used to send
/// and receive `vector(n, float32)` data to and from Oracle databases.
public struct OracleVectorFloat32: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = Float32

    static let vectorFormat: VectorFormat = .float32

    @usableFromInline
    var base: TinySequence<Element>

    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.base = .init(elements)
    }

    @inlinable
    public init(_ collection: some Collection<Element>) {
        self.base = .init(collection)
    }

    init(underlying: TinySequence<Element>) {
        self.base = underlying
    }

    @inlinable
    public subscript(position: Index) -> Element {
        get {
            self.base[position]
        }
        set(newValue) {
            self.base[position] = newValue
        }
    }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        for element in self.base {
            element.encode(into: &buffer, context: context)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorFloat32
    {
        var values: TinySequence<Float32> = []
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(OracleNumeric.parseBinaryFloat(from: &buffer))
        }

        return .init(underlying: values)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if encoder is _OracleJSONEncoder {
            try container.encode(self)
        } else {
            try container.encode(Array(self.base))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.base = .init(try container.decode([Element].self))
    }
}


// MARK: Float64

/// A dynamically sized vector of type Float64, used to send
/// and receive `vector(n, float64)` data to and from Oracle databases.
public struct OracleVectorFloat64: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = Float64

    static let vectorFormat: VectorFormat = .float64

    @usableFromInline
    var base: TinySequence<Element>

    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.base = .init(elements)
    }

    @inlinable
    public init(_ collection: some Collection<Element>) {
        self.base = .init(collection)
    }

    init(underlying: TinySequence<Element>) {
        self.base = underlying
    }

    @inlinable
    public subscript(position: Index) -> Element {
        get {
            self.base[position]
        }
        set(newValue) {
            self.base[position] = newValue
        }
    }

    @inlinable
    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        for element in self.base {
            element.encode(into: &buffer, context: context)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorFloat64
    {
        var values: TinySequence<Float64> = []
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(OracleNumeric.parseBinaryDouble(from: &buffer))
        }

        return .init(underlying: values)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if encoder is _OracleJSONEncoder {
            try container.encode(self)
        } else {
            try container.encode(Array(self.base))
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.base = .init(try container.decode([Element].self))
    }
}


public protocol OracleVectorProtocol {}


// MARK: - Internal helper protocols

protocol _OracleVectorJSONEncodable: OracleEncodable {
    var count: Int { get }
    static var vectorFormat: VectorFormat { get }
    func encodeForJSON(into buffer: inout ByteBuffer)
}

extension _OracleVectorJSONEncodable {
    func encodeForJSON(into buffer: inout ByteBuffer) {
        buffer.writeInteger(0, as: UInt32.self)
        let writerIndex = buffer.writerIndex
        _encodeOracleVectorHeader(
            elements: UInt32(self.count),
            format: Self.vectorFormat,
            into: &buffer
        )
        self.encode(into: &buffer, context: .default)
        let length = UInt32(buffer.writerIndex - writerIndex)
        buffer.setInteger(length, at: writerIndex - MemoryLayout<UInt32>.size)
    }
}

private protocol _OracleVectorProtocol: _OracleVectorJSONEncodable, OracleCodable, Equatable,
    Collection,
    ExpressibleByArrayLiteral,
    Decodable,
    Encodable
where Index == Int {
    var base: TinySequence<Element> { get set }
    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> Self
}

extension _OracleVectorProtocol {
    public static var defaultOracleType: OracleDataType { .vector }
    public var oracleType: OracleDataType { .vector }
    @inlinable public var count: Int { base.count }
    @inlinable public var startIndex: Index { 0 }
    @inlinable public var endIndex: Index { self.base.count }

    @inlinable
    public func index(after i: Index) -> Index {
        i + 1
    }

    @inlinable
    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) {
        var temp = ByteBuffer()
        _encodeOracleVectorHeader(
            elements: UInt32(self.count),
            format: Self.vectorFormat,
            into: &temp
        )
        self.encode(into: &temp, context: context)
        buffer.writeQLocator(dataLength: UInt64(temp.readableBytes))
        temp._encodeRaw(into: &buffer, context: context)
    }

    @inlinable
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        guard type == .vector else {
            throw OracleDecodingError.Code.typeMismatch
        }
        let elements = try Self._decodeOracleVectorHeader(from: &buffer)
        self = try Self._decodeActual(from: &buffer, elements: elements)
    }

    private static func _decodeOracleVectorHeader(from buffer: inout ByteBuffer) throws -> Int {
        let (format, elements) = try _decodeOracleVectorMetadata(from: &buffer)
        guard format == self.vectorFormat else {
            throw OracleDecodingError.Code.typeMismatch
        }
        return elements
    }
}

func _decodeOracleVectorMetadata(from buffer: inout ByteBuffer) throws -> (
    VectorFormat, elements: Int
) {
    let magicByte = try buffer.throwingReadInteger(as: UInt8.self)
    if magicByte != Constants.TNS_VECTOR_MAGIC_BYTE {
        throw OracleDecodingError.Code.typeMismatch
    }

    let version = try buffer.throwingReadInteger(as: UInt8.self)
    if version > Constants.TNS_VECTOR_VERSION_WITH_BINARY {
        throw OracleDecodingError.Code.failure
    }

    let flags = try buffer.throwingReadInteger(as: UInt16.self)
    let vectorFormat = try buffer.throwingReadInteger(as: UInt8.self)
    guard let vectorFormat = VectorFormat(rawValue: vectorFormat) else {
        throw OracleDecodingError.Code.typeMismatch
    }

    let elementsCount =
        if vectorFormat == .binary {
            Int(try buffer.throwingReadInteger(as: UInt32.self) / 8)
        } else {
            Int(try buffer.throwingReadInteger(as: UInt32.self))
        }

    if (flags & Constants.TNS_VECTOR_FLAG_NORM_RESERVED) != 0
        || (flags & Constants.TNS_VECTOR_FLAG_NORM) != 0
    {
        buffer.moveReaderIndex(forwardBy: 8)
    }

    return (vectorFormat, elementsCount)
}

func _encodeOracleVectorHeader(
    elements: UInt32,
    format: VectorFormat,
    into buffer: inout ByteBuffer
) {
    var flags = Constants.TNS_VECTOR_FLAG_NORM_RESERVED
    let version: UInt8
    let count: UInt32
    if format == .binary {
        version = Constants.TNS_VECTOR_VERSION_WITH_BINARY
        count = elements * 8
    } else {
        version = Constants.TNS_VECTOR_VERSION_BASE
        count = elements
        flags |= Constants.TNS_VECTOR_FLAG_NORM
    }
    buffer.writeInteger(Constants.TNS_VECTOR_MAGIC_BYTE)
    buffer.writeInteger(version)
    buffer.writeInteger(flags)
    buffer.writeInteger(format.rawValue)
    buffer.writeInteger(count)
    buffer.writeRepeatingByte(0, count: 8)
}
