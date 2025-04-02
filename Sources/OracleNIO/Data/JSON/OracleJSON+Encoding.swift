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

extension OracleJSON: Encodable where Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension OracleJSON: OracleThrowingDynamicTypeEncodable where Value: Encodable {
    public static var defaultOracleType: OracleDataType { .json }

    public func _encodeRaw(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) throws {
        var temp = ByteBuffer()
        try self.encode(into: &temp, context: context)
        buffer.writeQLocator(dataLength: UInt64(temp.readableBytes))
        temp._encodeRaw(into: &buffer, context: context)
    }

    public func encode(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext
    ) throws {
        let storage = try _OracleJSONEncoder().encode(value)
        var writer = OracleJSONWriter()
        try writer.encode(
            storage, into: &buffer,
            maxFieldNameSize: OracleEncodingContext.jsonMaximumFieldNameSize
        )
    }

    public init(_ value: Value) {
        self.value = value
    }
}

final class _OracleJSONEncoder: Encoder {
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]

    fileprivate var object: JSONObject?
    fileprivate var array: JSONArray?
    fileprivate var singleValue: OracleJSONStorage?

    var value: OracleJSONStorage? {
        if let object {
            return .container(object.values)
        }
        if let array {
            return .array(array.values)
        }
        return self.singleValue
    }

    init() {
        self.codingPath = []
    }

    fileprivate init(
        codingPath: [any CodingKey] = [],
        userInfo: [CodingUserInfoKey: Any],
        value: OracleJSONStorage? = nil,
        object: JSONObject? = nil,
        array: JSONArray? = nil
    ) {
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.singleValue = value
        self.object = object
        self.array = array
    }

    func encode(_ value: some Encodable) throws -> OracleJSONStorage {
        // workaround to prevent Date being transformed to Double
        if let value = value as? Date {
            return .date(value)
        }
        try value.encode(to: self)
        return self.value ?? .none
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        if let object {
            let container = OracleKeyedEncodingContainer<Key>(
                codingPath: codingPath, encoder: self, object: object)
            return KeyedEncodingContainer(container)
        }

        precondition(singleValue == nil && array == nil)

        object = .init()
        let container = OracleKeyedEncodingContainer<Key>(
            codingPath: codingPath, encoder: self, object: object!)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        if let array {
            return OracleUnkeyedEncodingContainer(
                codingPath: codingPath, encoder: self, array: array)
        }

        precondition(singleValue == nil && object == nil)

        array = .init()
        return OracleUnkeyedEncodingContainer(codingPath: codingPath, encoder: self, array: array!)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        precondition(array == nil && object == nil)
        return OracleSingleValueEncodingContainer(codingPath: codingPath, encoder: self)
    }
}

struct OracleKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let codingPath: [any CodingKey]
    let encoder: _OracleJSONEncoder
    fileprivate let object: JSONObject

    func encodeNil(forKey key: Key) throws {}

    func encode(_ value: Bool, forKey key: Key) throws {
        object.set(.bool(value), for: key.stringValue)
    }

    func encode(_ value: String, forKey key: Key) throws {
        object.set(.string(value), for: key.stringValue)
    }

    func encode(_ value: Double, forKey key: Key) throws {
        object.set(.double(value), for: key.stringValue)
    }

    func encode(_ value: Float, forKey key: Key) throws {
        object.set(.float(value), for: key.stringValue)
    }

    func encode(_ value: Int, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: Int8, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: Int16, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: Int32, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: Int64, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: UInt, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: UInt8, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: UInt16, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: UInt32, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode(_ value: UInt64, forKey key: Key) throws {
        try encodeFixedWidthInteger(value, for: key)
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        switch value {
        case let value as Date:
            self.object.set(.date(value), for: key.stringValue)
        case let value as IntervalDS:
            self.object.set(.intervalDS(value), for: key.stringValue)
        case let value as OracleVectorInt8:
            self.object.set(.vectorInt8(value), for: key.stringValue)
        case let value as OracleVectorFloat32:
            self.object.set(.vectorFloat32(value), for: key.stringValue)
        case let value as OracleVectorFloat64:
            self.object.set(.vectorFloat64(value), for: key.stringValue)
        case let value as OracleVectorBinary:
            self.object.set(.vectorBinary(value), for: key.stringValue)
        default:
            let newPath = self.codingPath + [key]
            let newEncoder = _OracleJSONEncoder(codingPath: newPath, userInfo: encoder.userInfo)
            try value.encode(to: newEncoder)

            guard let value = newEncoder.value else {
                preconditionFailure()
            }

            self.object.set(value, for: key.stringValue)
        }
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key)
        -> KeyedEncodingContainer<NestedKey>
    {
        let newPath = codingPath + [key]
        let object = object.setObject(for: key.stringValue)
        let nestedContainer = OracleKeyedEncodingContainer<NestedKey>(
            codingPath: newPath,
            encoder: encoder,
            object: object
        )
        return KeyedEncodingContainer(nestedContainer)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let newPath = codingPath + [key]
        let array = object.setArray(for: key.stringValue)
        let nestedContainer = OracleUnkeyedEncodingContainer(
            codingPath: newPath,
            encoder: encoder,
            array: array
        )
        return nestedContainer
    }

    func superEncoder() -> any Encoder {
        encoder
    }

    func superEncoder(forKey key: Key) -> any Encoder {
        encoder
    }
}

extension OracleKeyedEncodingContainer {
    @inline(__always)
    private func encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T, for key: Key) throws {
        guard let value = Int(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: self.codingPath,
                    debugDescription: "Number \(value) does not fit in \(Int.self)."
                )
            )
        }
        self.object.set(.int(value), for: key.stringValue)
    }
}


struct OracleUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var count: Int { encoder.array!.array.count }
    let codingPath: [any CodingKey]
    let encoder: _OracleJSONEncoder
    fileprivate let array: JSONArray

    func encodeNil() throws {}

    func encode(_ value: Bool) throws {
        self.array.append(.bool(value))
    }

    func encode(_ value: String) throws {
        self.array.append(.string(value))
    }

    func encode(_ value: Double) throws {
        self.array.append(.double(value))
    }

    func encode(_ value: Float) throws {
        self.array.append(.float(value))
    }

    func encode(_ value: Int) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int8) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int16) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int32) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int64) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt8) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt16) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt32) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt64) throws {
        try self.encodeFixedWidthInteger(value)
    }

    func encode(_ value: some Encodable) throws {
        switch value {
        case let value as Date:
            self.array.append(.date(value))
        case let value as IntervalDS:
            self.array.append(.intervalDS(value))
        case let value as OracleVectorInt8:
            self.array.append(.vectorInt8(value))
        case let value as OracleVectorFloat32:
            self.array.append(.vectorFloat32(value))
        case let value as OracleVectorFloat64:
            self.array.append(.vectorFloat64(value))
        case let value as OracleVectorBinary:
            self.array.append(.vectorBinary(value))
        default:
            let newPath = self.codingPath + [ArrayKey(index: self.count)]
            let newEncoder = _OracleJSONEncoder(codingPath: newPath, userInfo: encoder.userInfo)
            try value.encode(to: newEncoder)

            guard let value = newEncoder.value else {
                preconditionFailure()
            }

            self.array.append(value)
        }
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type)
        -> KeyedEncodingContainer<NestedKey>
    {
        let object = self.array.appendObject()
        let newPath = self.encoder.codingPath + [ArrayKey(index: self.count)]
        let nestedContainer = OracleKeyedEncodingContainer<NestedKey>(
            codingPath: newPath, encoder: encoder, object: object
        )
        return KeyedEncodingContainer(nestedContainer)
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let array = self.encoder.array!.appendArray()
        let newPath = self.codingPath + [ArrayKey(index: self.count)]
        let nestedContainer = OracleUnkeyedEncodingContainer(
            codingPath: newPath, encoder: encoder, array: array
        )
        return nestedContainer
    }

    func superEncoder() -> any Encoder {
        preconditionFailure()
    }
}

extension OracleUnkeyedEncodingContainer {
    @inline(__always)
    private func encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T) throws {
        guard let value = Int(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: self.codingPath,
                    debugDescription: "Number \(value) does not fit in \(Int.self)."
                )
            )
        }
        self.array.append(.int(value))
    }
}


struct OracleSingleValueEncodingContainer: SingleValueEncodingContainer {
    let codingPath: [any CodingKey]
    let encoder: _OracleJSONEncoder

    mutating func encodeNil() throws {}

    func encode(_ value: Bool) throws {
        self.encoder.singleValue = .bool(value)
    }

    func encode(_ value: String) throws {
        self.encoder.singleValue = .string(value)
    }

    func encode(_ value: Float) throws {
        self.encoder.singleValue = .float(value)
    }

    func encode(_ value: Double) throws {
        self.encoder.singleValue = .double(value)
    }

    func encode(_ value: Int) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int8) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int16) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int32) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int64) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt8) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt16) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt32) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt64) throws {
        try encodeFixedWidthInteger(value)
    }

    func encode(_ value: some Encodable) throws {
        switch value {
        case let value as Date:
            self.encoder.singleValue = .date(value)
        case let value as IntervalDS:
            self.encoder.singleValue = .intervalDS(value)
        case let value as OracleVectorInt8:
            self.encoder.singleValue = .vectorInt8(value)
        case let value as OracleVectorFloat32:
            self.encoder.singleValue = .vectorFloat32(value)
        case let value as OracleVectorFloat64:
            self.encoder.singleValue = .vectorFloat64(value)
        case let value as OracleVectorBinary:
            self.encoder.singleValue = .vectorBinary(value)
        default:
            try value.encode(to: encoder)
        }
    }
}

extension OracleSingleValueEncodingContainer {
    @inline(__always)
    private func encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T) throws {
        guard let value = Int(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: self.codingPath,
                    debugDescription: "Number \(value) does not fit in \(Int.self)."
                )
            )
        }
        self.encoder.singleValue = .int(value)
    }
}


// MARK: Implementation details

private enum JSONFuture {
    case value(OracleJSONStorage)
    case array(JSONArray)
    case object(JSONObject)
}

private final class JSONArray {
    private(set) var array: [JSONFuture] = []

    init() {
        self.array.reserveCapacity(10)
    }

    @inline(__always)
    func append(_ element: OracleJSONStorage) {
        self.array.append(.value(element))
    }

    @inline(__always)
    func appendArray() -> JSONArray {
        let array = JSONArray()
        self.array.append(.array(array))
        return array
    }

    @inline(__always)
    func appendObject() -> JSONObject {
        let object = JSONObject()
        self.array.append(.object(object))
        return object
    }

    var values: [OracleJSONStorage] {
        self.array.map {
            switch $0 {
            case .value(let value):
                value
            case .array(let array):
                .array(array.values)
            case .object(let object):
                .container(object.values)
            }
        }
    }
}

private final class JSONObject {
    private(set) var object: [String: JSONFuture] = [:]

    init() {
        self.object.reserveCapacity(20)
    }

    @inline(__always)
    func set(_ value: OracleJSONStorage, for key: String) {
        self.object[key] = .value(value)
    }

    @inline(__always)
    func setArray(for key: String) -> JSONArray {
        if case .array(let array) = self.object[key] {
            return array
        }

        if case .object = self.object[key] {
            preconditionFailure(#"A keyed container has already been created for "\#(key)"."#)
        }

        let array = JSONArray()
        object[key] = .array(array)
        return array
    }

    @inline(__always)
    func setObject(for key: String) -> JSONObject {
        if case .object(let object) = self.object[key] {
            return object
        }

        if case .array = self.object[key] {
            preconditionFailure(#"A unkeyed container has already been created for "\#(key)"."#)
        }

        let object = JSONObject()
        self.object[key] = .object(object)
        return object
    }

    var values: [String: OracleJSONStorage] {
        self.object.mapValues {
            switch $0 {
            case .value(let value):
                value
            case .array(let array):
                .array(array.values)
            case .object(let object):
                .container(object.values)
            }
        }
    }
}
