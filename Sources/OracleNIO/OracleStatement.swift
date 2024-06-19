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

import NIOConcurrencyHelpers
import NIOCore

/// A Oracle SQL statement, that can be executed on a Oracle server.
/// Contains the raw sql string and bindings.
public struct OracleStatement: Sendable, Hashable {
    /// The statement's string.
    public var sql: String
    /// The statement's binds.
    public var binds: OracleBindings

    public init(
        unsafeSQL sql: String,
        binds: OracleBindings = OracleBindings()
    ) {
        self.sql = sql
        self.binds = binds
    }
}

extension OracleStatement: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self.sql = stringInterpolation.sql
        self.binds = stringInterpolation.binds
    }

    public init(stringLiteral value: StringLiteralType) {
        self.sql = value
        self.binds = OracleBindings()
    }
}

extension OracleStatement {
    public struct StringInterpolation: StringInterpolationProtocol {
        public typealias StringLiteralType = String

        @usableFromInline
        var sql: String
        @usableFromInline
        var binds: OracleBindings

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.sql = ""
            self.binds = OracleBindings(capacity: interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            self.sql.append(contentsOf: literal)
        }

        @inlinable
        public mutating func appendInterpolation<
            Value: OracleThrowingDynamicTypeEncodable
        >(_ value: Value) throws {
            let bindName = "\(self.binds.count)"
            try self.binds.append(value, context: .default, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation<
            Value: OracleThrowingDynamicTypeEncodable
        >(_ value: Value?) throws {
            let bindName = "\(self.binds.count)"
            switch value {
            case .none:
                self.binds.appendNull(value?.oracleType, bindName: bindName)
            case .some(let value):
                try self.binds
                    .append(value, context: .default, bindName: bindName)
            }

            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation<Value: OracleDynamicTypeEncodable>(
            _ value: Value
        ) {
            let bindName = "\(self.binds.count)"
            self.binds.append(value, context: .default, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation<Value: OracleDynamicTypeEncodable>(
            _ value: Value?
        ) {
            let bindName = "\(self.binds.count)"
            switch value {
            case .none:
                self.binds.appendNull(value?.oracleType, bindName: bindName)
            case .some(let value):
                self.binds.append(value, context: .default, bindName: bindName)
            }

            self.sql.append(contentsOf: ":\(bindName)")
        }

        public mutating func appendInterpolation<Value: OracleRef>(
            _ value: Value
        ) {
            if let bindName = self.binds.contains(ref: value) {
                self.sql.append(contentsOf: ":\(bindName)")
            } else {
                let bindName = "\(self.binds.count)"
                self.binds.append(value, bindName: bindName)
                self.sql.append(contentsOf: ":\(bindName)")
            }
        }

        @inlinable
        public mutating func appendInterpolation<
            Value: OracleThrowingDynamicTypeEncodable,
            JSONEncoder: OracleJSONEncoder
        >(_ value: Value, context: OracleEncodingContext<JSONEncoder>) throws {
            let bindName = "\(self.binds.count)"
            try self.binds.append(value, context: context, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation(unescaped interpolation: String) {
            self.sql.append(contentsOf: interpolation)
        }
    }
}

extension OracleStatement: CustomStringConvertible {
    public var description: String {
        "\(self.sql) \(self.binds)"
    }
}

extension OracleStatement: CustomDebugStringConvertible {
    public var debugDescription: String {
        "OracleStatement(sql: \(String(describing: self.sql)), binds: \(String(reflecting: self.binds))"
    }
}

public struct OracleBindings: Sendable, Hashable {
    @usableFromInline
    struct Metadata: Sendable, Hashable {
        @usableFromInline
        var dataType: OracleDataType
        @usableFromInline
        var protected: Bool
        @usableFromInline
        var isReturnBind: Bool
        @usableFromInline
        var size: UInt32
        @usableFromInline
        var bufferSize: UInt32

        @usableFromInline
        var isArray: Bool
        @usableFromInline
        var arrayCount: Int
        @usableFromInline
        var maxArraySize: Int

        @usableFromInline
        var bindName: String?
        @usableFromInline
        var outContainer: OracleRef?  // reference type for return binds

        @inlinable
        init(
            dataType: OracleDataType,
            protected: Bool,
            isReturnBind: Bool,
            size: UInt32 = 0,
            isArray: Bool,
            arrayCount: Int?,
            maxArraySize: Int?,
            bindName: String?
        ) {
            self.dataType = dataType
            self.protected = protected
            self.isReturnBind = isReturnBind
            let size =
                if size == 0 {
                    UInt32(self.dataType.defaultSize)
                } else {
                    size
                }
            self.size = size
            if dataType.defaultSize > 0 {
                self.bufferSize = size * UInt32(dataType.bufferSizeFactor)
            } else {
                self.bufferSize = UInt32(dataType.bufferSizeFactor)
            }
            self.isArray = isArray
            self.arrayCount = arrayCount ?? 0
            self.maxArraySize = maxArraySize ?? 0
            self.bindName = bindName
        }

        @inlinable
        init<Value: OracleThrowingDynamicTypeEncodable>(
            value: Value,
            protected: Bool,
            isReturnBind: Bool,
            bindName: String?
        ) {
            self.init(
                dataType: value.oracleType,
                protected: protected,
                isReturnBind: isReturnBind,
                size: value.size,
                isArray: Value.isArray,
                arrayCount: value.arrayCount,
                maxArraySize: value.arraySize,
                bindName: bindName
            )
        }
    }

    @usableFromInline
    var metadata: [Metadata]
    @usableFromInline
    var bytes: ByteBuffer
    /// LONG binds need to be sent at last, so they require their own buffer.
    /// In the end ``bytes`` + ``longBytes`` will be written to the wire.
    @usableFromInline
    var longBytes: ByteBuffer

    public var count: Int {
        self.metadata.count
    }

    public init() {
        self.metadata = []
        self.bytes = ByteBuffer()
        self.longBytes = ByteBuffer()
    }

    public init(capacity: Int) {
        self.metadata = []
        self.metadata.reserveCapacity(capacity)
        self.bytes = ByteBuffer()
        self.bytes.reserveCapacity(128 * capacity)
        self.longBytes = ByteBuffer()  // no capacity as it is rare
    }

    public mutating func appendNull(
        _ dataType: OracleDataType?, bindName: String
    ) {
        let dataType = dataType ?? .varchar
        if dataType == .boolean {
            self.bytes.writeInteger(Constants.TNS_ESCAPE_CHAR)
            self.bytes.writeInteger(UInt8(1))
        } else if dataType._oracleType == .intNamed {
            self.bytes.writeUB4(0)  // TOID
            self.bytes.writeUB4(0)  // OID
            self.bytes.writeUB4(0)  // snapshot
            self.bytes.writeUB4(0)  // version
            self.bytes.writeUB4(0)  // packed data length
            self.bytes.writeUB4(Constants.TNS_OBJ_TOP_LEVEL)  // flags
        } else {
            self.bytes.writeInteger(UInt8(0))
        }
        self.metadata.append(
            .init(
                dataType: dataType,
                protected: false,
                isReturnBind: false,
                size: 1,
                isArray: false,
                arrayCount: nil,
                maxArraySize: nil,
                bindName: bindName
            ))
    }

    @inlinable
    public mutating func append<
        Value: OracleThrowingDynamicTypeEncodable,
        JSONEncoder: OracleJSONEncoder
    >(
        _ value: Value, context: OracleEncodingContext<JSONEncoder>, bindName: String
    ) throws {
        let metadata = Metadata(
            value: value,
            protected: true,
            isReturnBind: false,
            bindName: bindName
        )
        if metadata.bufferSize >= Constants.TNS_MIN_LONG_LENGTH {
            try value._encodeRaw(into: &self.longBytes, context: context)
        } else {
            try value._encodeRaw(into: &self.bytes, context: context)
        }
        self.metadata.append(metadata)
    }

    @inlinable
    public mutating func append<
        Value: OracleDynamicTypeEncodable, JSONEncoder: OracleJSONEncoder
    >(
        _ value: Value,
        context: OracleEncodingContext<JSONEncoder>,
        bindName: String
    ) {
        let metadata = Metadata(
            value: value,
            protected: true,
            isReturnBind: false,
            bindName: bindName
        )
        if metadata.bufferSize >= Constants.TNS_MIN_LONG_LENGTH {
            value._encodeRaw(into: &self.longBytes, context: context)
        } else {
            value._encodeRaw(into: &self.bytes, context: context)
        }
        self.metadata.append(metadata)
    }

    @inlinable
    public mutating func append<Value: OracleRef>(
        _ value: Value, bindName: String
    ) {
        value.metadata.withLockedValue { valueMetadata in
            valueMetadata.bindName = bindName
            var metadata = valueMetadata
            metadata.bindName = bindName
            metadata.outContainer = value
            value.storage.withLockedValue { valueStorage in
                if var bytes = valueStorage {
                    if metadata.bufferSize >= Constants.TNS_MIN_LONG_LENGTH {
                        self.longBytes.writeBuffer(&bytes)
                    } else {
                        self.bytes.writeBuffer(&bytes)
                    }
                } else if !metadata.isReturnBind {  // return binds do not send null
                    self.bytes.writeInteger(UInt8(0))  // null
                }
            }
            self.metadata.append(metadata)
        }
    }

    @inlinable
    mutating func appendUnprotected<
        Value: OracleThrowingDynamicTypeEncodable,
        JSONEncoder: OracleJSONEncoder
    >(
        _ value: Value,
        context: OracleEncodingContext<JSONEncoder>,
        bindName: String
    ) throws {
        let metadata = Metadata(
            value: value,
            protected: false,
            isReturnBind: false,
            bindName: bindName
        )
        if metadata.bufferSize >= Constants.TNS_MIN_LONG_LENGTH {
            try value._encodeRaw(into: &self.longBytes, context: context)
        } else {
            try value._encodeRaw(into: &self.bytes, context: context)
        }
        self.metadata.append(metadata)
    }

    @inlinable
    mutating func appendUnprotected<
        Value: OracleDynamicTypeEncodable, JSONEncoder: OracleJSONEncoder
    >(
        _ value: Value,
        context: OracleEncodingContext<JSONEncoder>,
        bindName: String
    ) {
        let metadata = Metadata(
            value: value,
            protected: false,
            isReturnBind: false,
            bindName: bindName
        )
        if metadata.bufferSize >= Constants.TNS_LONG_LENGTH_INDICATOR {
            value._encodeRaw(into: &self.longBytes, context: context)
        } else {
            value._encodeRaw(into: &self.bytes, context: context)
        }
        self.metadata.append(metadata)
    }

    /// Checks if a INOUT bind is already present and returns its bind name to be reused.
    ///
    /// This ensures that we don't shadow those binds on the db side and potentially returning incorrect
    /// results in the out bind.
    ///
    /// You might wonder why we don't use the metadata on `OracleRef` itself.
    /// This is because we cannot know if the metadata is from a previous statement or not.
    func contains(ref: OracleRef) -> String? {
        self.metadata.first(where: { $0.outContainer === ref })?.bindName
    }
}

extension OracleBindings:
    CustomStringConvertible, CustomDebugStringConvertible
{
    public var description: String {
        """
        [
        \(zip(self.metadata, BindingsReader(buffer: self.bytes))
            .lazy
            .map({
                Self.makeBindingPrintable(
                    protected: $0.protected,
                    type: $0.dataType,
                    buffer: $1
                )
            })
            .joined(separator: ", "))
        ]
        """
    }

    public var debugDescription: String {
        """
        [
        \(zip(self.metadata, BindingsReader(buffer: self.bytes))
                .lazy
                .map({
                    Self.makeDebugDescription(
                        protected: $0.protected,
                        type: $0.dataType,
                        buffer: $1
                    )
                })
                .joined(separator: ", "))
        ]
        """
    }

    private static func makeDebugDescription(
        protected: Bool, type: OracleDataType, buffer: ByteBuffer?
    ) -> String {
        "(\(Self.makeBindingPrintable(protected: protected, type: type, buffer: buffer)); \(type))"
    }

    private static func makeBindingPrintable(
        protected: Bool, type: OracleDataType, buffer: ByteBuffer?
    ) -> String {
        if protected {
            return "****"
        }

        guard var buffer else {
            return "null"
        }

        do {
            switch type {
            case .binaryInteger, .number:
                let number = try Int64(
                    from: &buffer, type: type, context: .default
                )
                return String(describing: number)
            case .boolean:
                let bool = try Bool(
                    from: &buffer, type: type, context: .default
                )
                return String(describing: bool)
            case .varchar, .char, .long, .rowID:
                let value = try String(
                    from: &buffer, type: type, context: .default
                )
                return String(reflecting: value)  // adds quotes
            default:
                return "\(buffer.readableBytes) bytes"
            }
        } catch {
            return "\(buffer.readableBytes) bytes"
        }
    }
}

/// A small helper to inspect encoded bindings
private struct BindingsReader: Sequence {
    typealias Element = ByteBuffer?

    var buffer: ByteBuffer

    struct Iterator: IteratorProtocol {
        typealias Element = ByteBuffer?
        private var buffer: ByteBuffer

        init(buffer: ByteBuffer) {
            self.buffer = buffer
        }

        mutating func next() -> ByteBuffer?? {
            return try? self.buffer.readOracleSpecificLengthPrefixedSlice()
        }
    }

    func makeIterator() -> Iterator {
        Iterator(buffer: self.buffer)
    }
}
