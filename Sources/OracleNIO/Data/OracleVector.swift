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

// MARK: Int8

/// A dynamically sized vector of type Int8, used to send
/// and receive `vector(n, int8)` data to and from Oracle databases.
public struct OracleVectorInt8: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = Int8

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_INT8

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
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
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
}

// MARK: Float32

/// A dynamically sized vector of type Float32, used to send
/// and receive `vector(n, float32)` data to and from Oracle databases.
public struct OracleVectorFloat32: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = Float32

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_FLOAT32

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
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
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
}


// MARK: Float64

/// A dynamically sized vector of type Float64, used to send
/// and receive `vector(n, float64)` data to and from Oracle databases.
public struct OracleVectorFloat64: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Element = Float64

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_FLOAT64

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
    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
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
}


public protocol OracleVectorProtocol {}


// MARK: - Internal helper protocols

private protocol _OracleVectorProtocol: OracleCodable, Equatable, Collection,
    ExpressibleByArrayLiteral
where Index == Int {
    var count: Int { get }
    var base: TinySequence<Element> { get set }
    static var vectorFormat: UInt8 { get }
    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> Self
}

extension _OracleVectorProtocol {
    public var oracleType: OracleDataType { .vector }
    @inlinable public var count: Int { base.count }
    @inlinable public var startIndex: Index { 0 }
    @inlinable public var endIndex: Index { self.base.count }

    @inlinable
    public func index(after i: Index) -> Index {
        i + 1
    }

    @inlinable
    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        var temp = ByteBuffer()
        Self._encodeOracleVectorHeader(
            elements: UInt32(self.count),
            format: Self.vectorFormat,
            into: &temp
        )
        self.encode(into: &temp, context: context)
        buffer.writeQLocator(dataLength: UInt64(temp.readableBytes))
        if temp.readableBytes <= Constants.TNS_OBJ_MAX_SHORT_LENGTH {
            buffer.writeInteger(UInt8(temp.readableBytes))
        } else {
            buffer.writeInteger(Constants.TNS_LONG_LENGTH_INDICATOR)
            buffer.writeInteger(UInt32(temp.readableBytes))
        }
        buffer.writeBuffer(&temp)
    }

    @inlinable
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        guard type == .vector else {
            throw OracleDecodingError.Code.typeMismatch
        }
        let elements = try Self._decodeOracleVectorHeader(from: &buffer)
        self = try Self._decodeActual(from: &buffer, elements: elements)
    }

    private static func _encodeOracleVectorHeader(
        elements: UInt32,
        format: UInt8,
        into buffer: inout ByteBuffer
    ) {
        buffer.writeInteger(UInt8(Constants.TNS_VECTOR_MAGIC_BYTE))
        buffer.writeInteger(UInt8(Constants.TNS_VECTOR_VERSION))
        buffer.writeInteger(
            UInt16(Constants.TNS_VECTOR_FLAG_NORM | Constants.TNS_VECTOR_FLAG_NORM_RESERVED))
        buffer.writeInteger(format)
        buffer.writeInteger(elements)
        buffer.writeRepeatingByte(0, count: 8)
    }

    private static func _decodeOracleVectorHeader(from buffer: inout ByteBuffer) throws -> Int {
        let magicByte = try buffer.throwingReadInteger(as: UInt8.self)
        if magicByte != Constants.TNS_VECTOR_MAGIC_BYTE {
            throw OracleDecodingError.Code.typeMismatch
        }

        let version = try buffer.throwingReadInteger(as: UInt8.self)
        if version != Constants.TNS_VECTOR_VERSION {
            throw OracleDecodingError.Code.failure
        }

        let flags = try buffer.throwingReadInteger(as: UInt16.self)
        let vectorFormat = try buffer.throwingReadInteger(as: UInt8.self)
        if vectorFormat != self.vectorFormat {
            throw OracleDecodingError.Code.typeMismatch
        }

        let elementsCount = Int(try buffer.throwingReadInteger(as: UInt32.self))

        if (flags & Constants.TNS_VECTOR_FLAG_NORM) != 0 {
            buffer.moveReaderIndex(forwardBy: 8)
        }

        return elementsCount
    }
}
