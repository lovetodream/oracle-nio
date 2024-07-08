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

/// OracleJSON is an intermediate type to decode `JSON` columns from the Oracle Wire Format.
///
/// Use ``decode(as:)`` to decode an actual Swift type you can work with.
public struct OracleJSON: OracleDecodable {

    enum Storage: Sendable {
        /// Containers
        case container([String: Storage])
        case array([Storage])
        case none

        /// Primitives
        case bool(Bool)
        case string(String)
        case double(Double)
        case float(Float)
        case int(Int)
        case int8(Int8)
        case int16(Int16)
        case int32(Int32)
        case int64(Int64)
        case uint(UInt)
        case uint8(UInt8)
        case uint16(UInt16)
        case uint32(UInt32)
        case uint64(UInt64)
        case date(Date)
        case intervalDS(IntervalDS)
        case vectorInt8(OracleVectorInt8)
        case vectorFloat32(OracleVectorFloat32)
        case vectorFloat64(OracleVectorFloat64)
    }

    let base: Storage

    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        self.base = try OracleJSONParser.parse(from: &buffer)
    }

    public func decode<T: Decodable>(as: T.Type = T.self) throws -> T {
        try OraJSONDecoder().decode(T.self, from: self.base)
    }
}


// MARK: Decoder

struct OraJSONDecoder {
    var userInfo: [CodingUserInfoKey: Any] = [:]

    init() {}

    func decode<T: Decodable>(_: T.Type, from value: OracleJSON.Storage) throws -> T {
        let decoder = _OraJSONDecoder(codingPath: [], userInfo: self.userInfo, value: value)
        return try decoder.decode(T.self)
    }
}

struct _OraJSONDecoder: Decoder {
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey : Any]

    let value: OracleJSON.Storage

    func decode<T: Decodable>(_: T.Type) throws -> T {
        try T(from: self)
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        guard case .container(let dictionary) = self.value else {
            throw DecodingError.typeMismatch(
                [String: OracleJSON.Storage].self,
                .init(
                    codingPath: self.codingPath,
                    debugDescription: "Expected to decode \([String: OracleJSON.Storage].self) but found \(self.value.debugDataTypeDescription) instead."
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
                [OracleJSON.Storage].self,
                .init(
                    codingPath: self.codingPath,
                    debugDescription: "Expected to decode \([OracleJSON.Storage].self) but found \(self.value.debugDataTypeDescription) instead."
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
    typealias Value = OracleJSON.Storage

    let codingPath: [any CodingKey]
    let dictionary: [String: Value]
    let decoder: _OraJSONDecoder
    let allKeys: [Key]

    init(codingPath: [any CodingKey], dictionary: [String: Value], decoder: _OraJSONDecoder) {
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

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        let value = try self.getValue(forKey: key)
        guard case .double(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        let value = try self.getValue(forKey: key)
        guard case .float(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        let value = try self.getValue(forKey: key)
        guard case .int(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        let value = try self.getValue(forKey: key)
        guard case .int8(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        let value = try self.getValue(forKey: key)
        guard case .int16(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        let value = try self.getValue(forKey: key)
        guard case .int32(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        let value = try self.getValue(forKey: key)
        guard case .int64(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        let value = try self.getValue(forKey: key)
        guard case .uint(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        let value = try self.getValue(forKey: key)
        guard case .uint8(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        let value = try self.getValue(forKey: key)
        guard case .uint16(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        let value = try self.getValue(forKey: key)
        guard case .uint32(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        let value = try self.getValue(forKey: key)
        guard case .uint64(let value) = value else {
            throw self.createTypeMismatchError(type: type, forKey: key, value: value)
        }
        return value
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
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
        default:
            break
        }
        
        let decoder = try decoderForKey(key)
        return try T(from: decoder)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
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
    private func decoderForKey(_ key: Key) throws -> _OraJSONDecoder {
        let value = try getValue(forKey: key)
        var newPath = self.codingPath
        newPath.append(key)

        return _OraJSONDecoder(
            codingPath: newPath,
            userInfo: self.decoder.userInfo,
            value: value
        )
    }

    @inline(__always)
    private func getValue(forKey key: Key) throws -> Value {
        guard let value = dictionary[key.stringValue] else {
            throw DecodingError.keyNotFound(key, .init(
                codingPath: self.codingPath,
                debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."
            ))
        }

        return value
    }

    @inline(__always)
    private func createTypeMismatchError(type: Any.Type, forKey key: Key, value: Value) -> DecodingError {
        let codingPath = self.codingPath + [key]
        return DecodingError.typeMismatch(type, .init(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }
}


// MARK: SingleValueDecodingContainer

struct OracleSingleValueDecodingContainer: SingleValueDecodingContainer {
    typealias Value = OracleJSON.Storage

    let decoder: _OraJSONDecoder
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

    func decode(_ type: Double.Type) throws -> Double {
        guard case .double(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard case .float(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: Int.Type) throws -> Int {
        guard case .int(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        guard case .int8(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        guard case .int16(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        guard case .int32(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard case .int64(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        guard case .uint(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard case .uint8(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard case .uint16(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard case .uint32(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard case .uint64(let value) = self.value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }
        return value
    }

    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
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
        default:
            break
        }

        return try T(from: self.decoder)
    }
}

extension OracleSingleValueDecodingContainer {
    @inline(__always)
    private func createTypeMismatchError(type: Any.Type, value: Value) -> DecodingError {
        return DecodingError.typeMismatch(type, .init(
            codingPath: self.codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }
}


// MARK: UnkeyedDecodingContainer

struct OracleUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    typealias Value = OracleJSON.Storage

    let codingPath: [any CodingKey]
    let decoder: _OraJSONDecoder
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

    mutating func decode(_ type: Double.Type) throws -> Double {
        let value = try self.getNextValue(ofType: type)
        guard case .double(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
        let value = try self.getNextValue(ofType: Float.self)
        guard case .float(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
        let value = try self.getNextValue(ofType: String.self)
        guard case .int(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .int8(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .int16(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .int32(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .int64(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
        let value = try self.getNextValue(ofType: String.self)
        guard case .uint(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .uint8(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .uint16(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .uint32(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
        let value = try self.getNextValue(ofType: String.self)
        guard case .uint64(let value) = value else {
            throw self.createTypeMismatchError(type: type, value: value)
        }

        self.currentIndex += 1
        return value
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

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        let decoder = try self.decoderForNextElement(ofType: KeyedDecodingContainer<NestedKey>.self, isNested: true)
        let container = try decoder.container(keyedBy: type)

        self.currentIndex += 1
        return container
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let decoder = try self.decoderForNextElement(ofType: UnkeyedDecodingContainer.self, isNested: true)
        let container = try decoder.unkeyedContainer()

        self.currentIndex += 1
        return container
    }
    
    mutating func superDecoder() throws -> any Decoder {
        self.decoder
    }
}

extension OracleUnkeyedDecodingContainer {
    private mutating func decoderForNextElement<T>(ofType: T.Type, isNested: Bool = false) throws -> _OraJSONDecoder {
        let value = try self.getNextValue(ofType: T.self, isNested: isNested)
        let newPath = self.codingPath + [ArrayKey(index: self.currentIndex)]

        return _OraJSONDecoder(
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
                        debugDescription: "Cannot get nested keyed container -- unkeyed container is at end.",
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
        return DecodingError.typeMismatch(type, .init(
            codingPath: codingPath,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }
}


// MARK: Utility

extension OracleJSON.Storage {
    var debugDataTypeDescription: String {
        switch self {
        case .container:
            "a dictionary"
        case .array:
            "an array"
        case .none:
            "null"
        case .bool:
            "bool"
        case .string:
            "a string"
        case .double:
            "a double"
        case .float:
            "a float"
        case .int:
            "an int"
        case .int8:
            "an int8"
        case .int16:
            "an in16"
        case .int32:
            "an int32"
        case .int64:
            "an int64"
        case .uint:
            "an uint"
        case .uint8:
            "an uint8"
        case .uint16:
            "an uint16"
        case .uint32:
            "an uint32"
        case .uint64:
            "an uint64"
        case .date:
            "a date"
        case .intervalDS:
            "a day second interval"
        case .vectorInt8:
            "an int8 vector"
        case .vectorFloat32:
            "a float32 vector"
        case .vectorFloat64:
            "a float64 vector"
        }
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
