//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

// MARK: Int8

public struct OracleVectorInt8: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias MaskStorage = Self
    public typealias Scalar = Int8

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_INT8
    static let zero: Scalar = .zero

    fileprivate var underlying: [Int8]

    public init() {
        self.underlying = []
    }

    public init(arrayLiteral elements: Int8...) {
        self.underlying = elements
    }

    init(underlying: [Int8]) {
        self.underlying = underlying
    }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        for element in self.underlying {
            buffer.writeInteger(element)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorInt8
    {
        var values = [Int8]()
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(buffer.throwingReadInteger(as: Int8.self))
        }

        return .init(underlying: values)
    }
}

// MARK: Float32

public struct OracleVectorFloat32: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Scalar = Float32

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_FLOAT32
    static let zero: Scalar = .zero

    fileprivate var underlying: [Float32]

    public init() {
        self.underlying = []
    }

    public init(arrayLiteral elements: Float32...) {
        self.underlying = elements
    }

    init(underlying: [Float32]) {
        self.underlying = underlying
    }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        for element in self.underlying {
            element.encode(into: &buffer, context: context)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorFloat32
    {
        var values = [Float32]()
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(OracleNumeric.parseBinaryFloat(from: &buffer))
        }

        return .init(underlying: values)
    }
}

extension OracleVectorFloat32 {
    public struct MaskStorage: SIMD {
        public typealias MaskStorage = Self
        public typealias ArrayLiteralElement = Scalar
        public typealias Scalar = Int32

        private var underlying: [Int32]
        public var scalarCount: Int { self.underlying.count }

        public init() {
            self.underlying = []
        }

        public init(arrayLiteral elements: Int32...) {
            self.underlying = elements
        }

        public subscript(index: Int) -> Int32 {
            get {
                self.underlying[index]
            }
            set(newValue) {
                self.underlying[index] = newValue
            }
        }
    }
}


// MARK: Float64

public struct OracleVectorFloat64: _OracleVectorProtocol, OracleVectorProtocol {
    public typealias Scalar = Float64

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_FLOAT64
    static let zero: Scalar = .zero

    fileprivate var underlying: [Float64]

    public init() {
        self.underlying = []
    }

    public init(arrayLiteral elements: Float64...) {
        self.underlying = elements
    }

    init(underlying: [Float64]) {
        self.underlying = underlying
    }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        for element in self.underlying {
            element.encode(into: &buffer, context: context)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws
        -> OracleVectorFloat64
    {
        var values = [Float64]()
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(OracleNumeric.parseBinaryDouble(from: &buffer))
        }

        return .init(underlying: values)
    }
}

extension OracleVectorFloat64 {
    public struct MaskStorage: SIMD {
        public typealias MaskStorage = Self
        public typealias ArrayLiteralElement = Scalar
        public typealias Scalar = Int64

        private var underlying: [Int64]
        public var scalarCount: Int { self.underlying.count }

        public init() {
            self.underlying = []
        }

        public init(arrayLiteral elements: Int64...) {
            self.underlying = elements
        }

        public subscript(index: Int) -> Int64 {
            get {
                self.underlying[index]
            }
            set(newValue) {
                self.underlying[index] = newValue
            }
        }
    }
}


public protocol OracleVectorProtocol {
    /// Increases the number of lanes to the given amount.
    ///
    /// New lanes will be initialised with zero values. Existing lanes remain untouched.
    /// If lanes is less or equal to the current amount of lanes, nothing happens.
    mutating func reserveLanes(_ lanes: Int)
}


// MARK: - Internal helper protocols

private protocol _OracleVectorProtocol: OracleCodable, Equatable, SIMD
where ArrayLiteralElement == Scalar {
    var count: Int { get }
    var underlying: [Scalar] { get set }
    static var vectorFormat: UInt8 { get }
    static var zero: Scalar { get }
    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> Self
}

extension _OracleVectorProtocol {
    public var scalarCount: Int { self.count }
    public var oracleType: OracleDataType { .vector }

    var count: Int { underlying.count }

    public subscript(index: Int) -> Scalar {
        get {
            self.underlying[index]
        }
        set(newValue) {
            self.underlying[index] = newValue
        }
    }

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
            throw OracleDecodingError.Code.failure
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

    public mutating func reserveLanes(_ lanes: Int) {
        if self.underlying.count < lanes {
            self.underlying.reserveCapacity(lanes)
            self.underlying.append(
                contentsOf: [Scalar](
                    repeating: Self.zero,
                    count: lanes - self.underlying.count)
            )
        }
    }

}
