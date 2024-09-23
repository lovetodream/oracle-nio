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

import struct Foundation.Date

extension OracleJSON: Decodable where Value: Decodable {
    public init(from decoder: any Decoder) throws {
        self.value = try .init(from: decoder)
    }
}

extension OracleJSON: OracleDecodable where Value: Decodable {
    public init(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext
    ) throws {
        let base = try OracleJSONParser.parse(from: &buffer)
        self.value = try OracleJSONDecoder().decode(Value.self, from: base)
    }
}

struct OracleJSONDecoder {
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init() {}

    func decode<T: Decodable>(_: T.Type, from value: OracleJSONStorage) throws -> T {
        let decoder = _OracleJSONDecoder(codingPath: [], userInfo: self.userInfo, value: value)
        return try decoder.decode(T.self)
    }
}

struct _OracleJSONDecoder: Decoder {
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    let value: OracleJSONStorage

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        switch type {
        case is Date.Type:
            guard case .date(let value) = self.value else { break }
            return value as! T
        case is IntervalDS.Type:
            guard case .intervalDS(let value) = self.value else { break }
            return value as! T
        case is OracleVectorInt8.Type:
            guard case .vectorInt8(let value) = value else { break }
            return value as! T
        case is OracleVectorFloat32.Type:
            guard case .vectorFloat32(let value) = value else { break }
            return value as! T
        case is OracleVectorFloat64.Type:
            guard case .vectorFloat64(let value) = value else { break }
            return value as! T
        case is OracleVectorBinary.Type:
            guard case .vectorBinary(let value) = value else { break }
            return value as! T
        default:
            break
        }

        return try T(from: self)
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key>
    where Key: CodingKey {
        guard case .container(let dictionary) = self.value else {
            throw DecodingError.typeMismatch(
                [String: OracleJSONStorage].self,
                .init(
                    codingPath: self.codingPath,
                    debugDescription:
                        "Expected to decode \([String: OracleJSONStorage].self) but found \(self.value.debugDataTypeDescription) instead."
                )
            )
        }

        let container = OracleKeyedDecodingContainer<Key>(
            codingPath: codingPath,
            dictionary: dictionary,
            decoder: self
        )
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let array) = self.value else {
            throw DecodingError.typeMismatch(
                [OracleJSONStorage].self,
                .init(
                    codingPath: self.codingPath,
                    debugDescription:
                        "Expected to decode \([OracleJSONStorage].self) but found \(self.value.debugDataTypeDescription) instead."
                )
            )
        }

        return OracleUnkeyedDecodingContainer(
            codingPath: codingPath,
            decoder: self,
            array: array
        )
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        OracleSingleValueDecodingContainer(
            decoder: self,
            value: self.value,
            codingPath: self.codingPath
        )
    }
}


// MARK: KeyedDecodingContainer

struct OracleKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    typealias Value = OracleJSONStorage

    let codingPath: [any CodingKey]
    let dictionary: [String: Value]
    let decoder: _OracleJSONDecoder
    let allKeys: [Key]

    init(codingPath: [any CodingKey], dictionary: [String: Value], decoder: _OracleJSONDecoder) {
        self.codingPath = codingPath
        self.dictionary = dictionary
        self.decoder = decoder
        self.allKeys = dictionary.keys.compactMap(Key.init(stringValue:))
    }

    func contains(_ key: Key) -> Bool {
        self.allKeys.contains { $0.stringValue == key.stringValue }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        let value = try self.getValue(forKey: key)
        switch value {
        case .none:
            return true
        default:
            return false
        }
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        let value = try self.getValue(forKey: key)
        guard case .bool(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        let value = try self.getValue(forKey: key)
        guard case .string(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_: Double.Type, forKey key: Key) throws -> Double {
        try self.decodeFloatingPointNumber(forKey: key)
    }

    func decode(_: Float.Type, forKey key: Key) throws -> Float {
        try self.decodeFloatingPointNumber(forKey: key)
    }

    func decode(_: Int.Type, forKey key: Key) throws -> Int {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: Int8.Type, forKey key: Key) throws -> Int8 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: Int16.Type, forKey key: Key) throws -> Int16 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: Int32.Type, forKey key: Key) throws -> Int32 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: Int64.Type, forKey key: Key) throws -> Int64 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: UInt.Type, forKey key: Key) throws -> UInt {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode(_: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try self.decodeBinaryInteger(forKey: key)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        switch type {
        case is Date.Type:
            let value = try self.getValue(forKey: key)
            guard case .date(let value) = value else { break }
            return value as! T
        case is IntervalDS.Type:
            let value = try self.getValue(forKey: key)
            guard case .intervalDS(let value) = value else { break }
            return value as! T
        case is OracleVectorInt8.Type:
            let value = try self.getValue(forKey: key)
            guard case .vectorInt8(let value) = value else { break }
            return value as! T
        case is OracleVectorFloat32.Type:
            let value = try self.getValue(forKey: key)
            guard case .vectorFloat32(let value) = value else { break }
            return value as! T
        case is OracleVectorFloat64.Type:
            let value = try self.getValue(forKey: key)
            guard case .vectorFloat64(let value) = value else { break }
            return value as! T
        case is OracleVectorBinary.Type:
            let value = try self.getValue(forKey: key)
            guard case .vectorBinary(let value) = value else { break }
            return value as! T
        default:
            break
        }

        let decoder = try decoderForKey(key)
        return try T(from: decoder)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
    {
        try decoderForKey(key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try decoderForKey(key).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        self.decoder
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        self.decoder
    }

}

extension OracleKeyedDecodingContainer {
    private func decoderForKey(_ key: Key) throws -> _OracleJSONDecoder {
        let value = try getValue(forKey: key)
        var newPath = self.codingPath
        newPath.append(key)

        return _OracleJSONDecoder(
            codingPath: newPath,
            userInfo: self.decoder.userInfo,
            value: value
        )
    }

    @inline(__always)
    private func getValue(forKey key: Key) throws -> Value {
        guard let value = dictionary[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                .init(
                    codingPath: self.codingPath,
                    debugDescription:
                        "No value associated with key \(key) (\"\(key.stringValue)\")."
                ))
        }

        return value
    }

    @inline(__always)
    private func createTypeMismatchError(type: Any.Type, forKey key: Key, value: Value)
        -> DecodingError
    {
        let codingPath = self.codingPath + [key]
        return DecodingError.typeMismatch(
            type,
            .init(
                codingPath: codingPath,
                debugDescription:
                    "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
            ))
    }

    @inline(__always)
    private func decodeBinaryInteger<T: BinaryInteger>(forKey key: Key) throws -> T {
        let value = try self.getValue(forKey: key)
        switch value {
        case .int(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }
            return value
        case .float(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }
            return value
        case .double(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }
            return value
        default:
            throw self.createTypeMismatchError(type: T.self, forKey: key, value: value)
        }
    }

    @inline(__always)
    private func decodeFloatingPointNumber<T: BinaryFloatingPoint>(forKey key: Key) throws -> T {
        let value = try self.getValue(forKey: key)
        let (float, original): (T?, any Numeric) =
            switch value {
            case .int(let value):
                (T(exactly: value), value)
            case .double(let value):
                (T(value), value)
            case .float(let value):
                (T(value), value)
            default:
                throw self.createTypeMismatchError(type: T.self, forKey: key, value: value)
            }

        guard let float else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Number \(original) does not fit in \(T.self)."
            )
        }
        return float
    }
}


// MARK: SingleValueDecodingContainer

struct OracleSingleValueDecodingContainer: SingleValueDecodingContainer {
    typealias Value = OracleJSONStorage

    let decoder: _OracleJSONDecoder
    let value: Value
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        switch self.value {
        case .none:
            return true
        default:
            return false
        }
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: String.Type) throws -> String {
        guard case .string(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_: Double.Type) throws -> Double {
        try self.decodeFloatingPointNumber()
    }

    func decode(_: Float.Type) throws -> Float {
        try self.decodeFloatingPointNumber()
    }

    func decode(_: Int.Type) throws -> Int {
        try self.decodeBinaryInteger()
    }

    func decode(_: Int8.Type) throws -> Int8 {
        try self.decodeBinaryInteger()
    }

    func decode(_: Int16.Type) throws -> Int16 {
        try self.decodeBinaryInteger()
    }

    func decode(_: Int32.Type) throws -> Int32 {
        try self.decodeBinaryInteger()
    }

    func decode(_: Int64.Type) throws -> Int64 {
        try self.decodeBinaryInteger()
    }

    func decode(_: UInt.Type) throws -> UInt {
        try self.decodeBinaryInteger()
    }

    func decode(_: UInt8.Type) throws -> UInt8 {
        try self.decodeBinaryInteger()
    }

    func decode(_: UInt16.Type) throws -> UInt16 {
        try self.decodeBinaryInteger()
    }

    func decode(_: UInt32.Type) throws -> UInt32 {
        try self.decodeBinaryInteger()
    }

    func decode(_: UInt64.Type) throws -> UInt64 {
        try self.decodeBinaryInteger()
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        switch type {
        case is Date.Type:
            guard case .date(let value) = self.value else { break }
            return value as! T
        case is IntervalDS.Type:
            guard case .intervalDS(let value) = self.value else { break }
            return value as! T
        case is OracleVectorInt8.Type:
            guard case .vectorInt8(let value) = value else { break }
            return value as! T
        case is OracleVectorFloat32.Type:
            guard case .vectorFloat32(let value) = value else { break }
            return value as! T
        case is OracleVectorFloat64.Type:
            guard case .vectorFloat64(let value) = value else { break }
            return value as! T
        case is OracleVectorBinary.Type:
            guard case .vectorBinary(let value) = value else { break }
            return value as! T
        default:
            break
        }

        return try T(from: self.decoder)
    }
}

extension OracleSingleValueDecodingContainer {
    @inline(__always)
    private func createTypeMismatchError(type: Any.Type, value: Value) -> DecodingError {
        return DecodingError.typeMismatch(
            type,
            .init(
                codingPath: self.codingPath,
                debugDescription:
                    "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
            ))
    }

    @inline(__always)
    private func decodeBinaryInteger<T: BinaryInteger>() throws -> T {
        switch self.value {
        case .int(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }
            return value
        case .float(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }
            return value
        case .double(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }
            return value
        default:
            throw self.createTypeMismatchError(type: T.self, value: self.value)
        }
    }

    @inline(__always)
    private func decodeFloatingPointNumber<T: BinaryFloatingPoint>() throws -> T {
        let (float, original): (T?, any Numeric) =
            switch self.value {
            case .int(let value):
                (T(exactly: value), value)
            case .double(let value):
                (T(value), value)
            case .float(let value):
                (T(value), value)
            default:
                throw self.createTypeMismatchError(type: T.self, value: value)
            }

        guard let float else {
            throw DecodingError.dataCorruptedError(
                in: self,
                debugDescription: "Number \(original) does not fit in \(T.self)."
            )
        }
        return float
    }
}


// MARK: UnkeyedDecodingContainer

struct OracleUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    typealias Value = OracleJSONStorage

    let codingPath: [any CodingKey]
    let decoder: _OracleJSONDecoder
    let array: [Value]

    var count: Int? { self.array.count }
    var isAtEnd: Bool { self.currentIndex >= (self.array.count) }
    var currentIndex = 0

    mutating func decodeNil() throws -> Bool {
        if case .none = try self.getNextValue(ofType: Never.self) {
            self.currentIndex += 1
            return true
        }

        // The protocol states:
        //   If the value is not null, does not increment currentIndex.
        return false
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
        let value = try self.getNextValue(ofType: type)
        guard case .bool(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: String.Type) throws -> String {
        let value = try self.getNextValue(ofType: type)
        guard case .string(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_: Double.Type) throws -> Double {
        try self.decodeFloatingPointNumber()
    }

    mutating func decode(_: Float.Type) throws -> Float {
        try self.decodeFloatingPointNumber()
    }

    mutating func decode(_: Int.Type) throws -> Int {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: Int8.Type) throws -> Int8 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: Int16.Type) throws -> Int16 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: Int32.Type) throws -> Int32 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: Int64.Type) throws -> Int64 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: UInt.Type) throws -> UInt {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: UInt8.Type) throws -> UInt8 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: UInt16.Type) throws -> UInt16 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: UInt32.Type) throws -> UInt32 {
        try self.decodeBinaryInteger()
    }

    mutating func decode(_: UInt64.Type) throws -> UInt64 {
        try self.decodeBinaryInteger()
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        switch type {
        case is Date.Type:
            let value = try self.getNextValue(ofType: Date.self)
            guard case .date(let value) = value else { break }
            self.currentIndex += 1
            return value as! T
        case is IntervalDS.Type:
            let value = try self.getNextValue(ofType: IntervalDS.self)
            guard case .intervalDS(let value) = value else { break }
            self.currentIndex += 1
            return value as! T
        case is OracleVectorInt8.Type:
            let value = try self.getNextValue(ofType: OracleVectorInt8.self)
            guard case .vectorInt8(let value) = value else { break }
            self.currentIndex += 1
            return value as! T
        case is OracleVectorFloat32.Type:
            let value = try self.getNextValue(ofType: OracleVectorFloat32.self)
            guard case .vectorFloat32(let value) = value else { break }
            self.currentIndex += 1
            return value as! T
        case is OracleVectorFloat64.Type:
            let value = try self.getNextValue(ofType: OracleVectorFloat64.self)
            guard case .vectorFloat64(let value) = value else { break }
            self.currentIndex += 1
            return value as! T
        case is OracleVectorBinary.Type:
            let value = try self.getNextValue(ofType: OracleVectorBinary.self)
            guard case .vectorBinary(let value) = value else { break }
            self.currentIndex += 1
            return value as! T
        default: break
        }

        let decoder = try self.decoderForNextElement(ofType: type)
        let result = try T(from: decoder)

        // Because of the requirement that the index not be incremented unless
        // decoding the desired result type succeeds, it can not be a tail call.
        // Hopefully the compiler still optimizes well enough that the result
        // doesn't get copied around.
        self.currentIndex += 1
        return result
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
    {
        let decoder = try self.decoderForNextElement(
            ofType: KeyedDecodingContainer<NestedKey>.self, isNested: true)
        let container = try decoder.container(keyedBy: type)

        self.currentIndex += 1
        return container
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let decoder = try self.decoderForNextElement(
            ofType: UnkeyedDecodingContainer.self, isNested: true)
        let container = try decoder.unkeyedContainer()

        self.currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> any Decoder {
        self.decoder
    }
}

extension OracleUnkeyedDecodingContainer {
    private mutating func decoderForNextElement<T>(ofType: T.Type, isNested: Bool = false) throws
        -> _OracleJSONDecoder
    {
        let value = try self.getNextValue(ofType: T.self, isNested: isNested)
        let newPath = self.codingPath + [ArrayKey(index: self.currentIndex)]

        return _OracleJSONDecoder(
            codingPath: newPath,
            userInfo: self.decoder.userInfo,
            value: value
        )
    }

    /// - Note: Instead of having the `isNested` parameter, it would have been quite nice to just check whether
    ///   `T` conforms to either `KeyedDecodingContainer` or `UnkeyedDecodingContainer`. Unfortunately, since
    ///   `KeyedDecodingContainer` takes a generic parameter (the `Key` type), we can't just ask if `T` is one, and
    ///   type-erasure workarounds are not appropriate to this use case due to, among other things, the inability to
    ///   conform most of the types that would matter. We also can't use `KeyedDecodingContainerProtocol` for the
    ///   purpose, as it isn't even an existential and conformance to it can't be checked at runtime at all.
    ///
    ///   However, it's worth noting that the value of `isNested` is always a compile-time constant and the compiler
    ///   can quite neatly remove whichever branch of the `if` is not taken during optimization, making doing it this
    ///   way _much_ more performant (for what little it matters given that it's only checked in case of an error).
    @inline(__always)
    private func getNextValue<T>(ofType: T.Type, isNested: Bool = false) throws -> Value {
        guard !self.isAtEnd else {
            if isNested {
                throw DecodingError.valueNotFound(
                    T.self,
                    .init(
                        codingPath: self.codingPath,
                        debugDescription:
                            "Cannot get nested keyed container -- unkeyed container is at end.",
                        underlyingError: nil
                    )
                )
            } else {
                throw DecodingError.valueNotFound(
                    T.self,
                    .init(
                        codingPath: [ArrayKey(index: self.currentIndex)],
                        debugDescription: "Unkeyed container is at end.",
                        underlyingError: nil
                    )
                )
            }
        }
        return self.array[self.currentIndex]
    }

    @inline(__always)
    private func createTypeMismatchError(type: Any.Type, value: Value) -> DecodingError {
        let codingPath = self.codingPath + [ArrayKey(index: self.currentIndex)]
        return DecodingError.typeMismatch(
            type,
            .init(
                codingPath: codingPath,
                debugDescription:
                    "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
            ))
    }

    @inline(__always)
    private mutating func decodeBinaryInteger<T: BinaryInteger>() throws -> T {
        let value = try self.getNextValue(ofType: Int.self)
        switch value {
        case .int(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }

            self.currentIndex += 1
            return value

        case .float(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }

            self.currentIndex += 1
            return value

        case .double(let value):
            guard let value = T(exactly: value) else {
                throw DecodingError.dataCorruptedError(
                    in: self,
                    debugDescription: "Number \(value) does not fit in \(T.self)."
                )
            }

            self.currentIndex += 1
            return value

        default:
            throw self.createTypeMismatchError(type: T.self, value: value)
        }
    }

    @inline(__always)
    private mutating func decodeFloatingPointNumber<T: BinaryFloatingPoint>() throws -> T {
        let value = try self.getNextValue(ofType: T.self)
        let (float, original): (T?, any Numeric) =
            switch value {
            case .int(let value):
                (T(exactly: value), value)
            case .double(let value):
                (T(value), value)
            case .float(let value):
                (T(value), value)
            default:
                throw self.createTypeMismatchError(type: T.self, value: value)
            }

        guard let float else {
            throw DecodingError.dataCorruptedError(
                in: self,
                debugDescription: "Number \(original) does not fit in \(T.self)."
            )
        }

        self.currentIndex += 1
        return float
    }
}

struct ArrayKey: CodingKey, Equatable {
    init(index: Int) {
        self.intValue = index
    }

    init?(stringValue _: String) {
        preconditionFailure("Did not expect to be initialized with a string")
    }

    init?(intValue: Int) {
        self.intValue = intValue
    }

    var intValue: Int?

    var stringValue: String {
        "Index \(self.intValue!)"
    }

    static func == (lhs: ArrayKey, rhs: ArrayKey) -> Bool {
        return lhs.intValue == rhs.intValue
    }
}
