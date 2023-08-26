import NIOCore

/// A Oracle SQL query, that can be executed on a Oracle server. Contains the raw sql string and bindings.
public struct OracleQuery: Sendable, Hashable {
    /// The query string.
    public var sql: String
    /// The query binds.
    public var binds: OracleBindings

    public init(
        unsafeSQL sql: String,
        binds: OracleBindings = OracleBindings()
    ) {
        self.sql = sql
        self.binds = binds
    }
}

extension OracleQuery: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self.sql = stringInterpolation.sql
        self.binds = stringInterpolation.binds
    }

    public init(stringLiteral value: StringLiteralType) {
        self.sql = value
        self.binds = OracleBindings()
    }
}

extension OracleQuery {
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
        public mutating func appendInterpolation<Value: OracleThrowingEncodable>(_ value: Value) throws {
            try self.binds.append(value, context: .default)
            self.sql.append(contentsOf: ":\(self.binds.count)")
        }

        @inlinable
        public mutating func appendInterpolation<Value: OracleThrowingEncodable>(_ value: Optional<Value>) throws {
            switch value {
            case .none:
                self.binds.appendNull(Value.self)
            case .some(let value):
                try self.binds.append(value, context: .default)
            }

            self.sql.append(contentsOf: ":\(self.binds.count)")
        }

        @inlinable
        public mutating func appendInterpolation<Value: OracleEncodable>(_ value: Value) {
            self.binds.append(value, context: .default)
            self.sql.append(contentsOf: ":\(self.binds.count)")
        }

        @inlinable
        public mutating func appendInterpolation<Value: OracleEncodable>(_ value: Optional<Value>) {
            switch value {
            case .none:
                self.binds.appendNull(Value.self)
            case .some(let value):
                self.binds.append(value, context: .default)
            }

            self.sql.append(contentsOf: ":\(self.binds.count)")
        }

        @inlinable
        public mutating func appendInterpolation<Value: OracleThrowingEncodable, JSONEncoder: OracleJSONEncoder>(_ value: Value, context: OracleEncodingContext<JSONEncoder>) throws {
            try self.binds.append(value, context: context)
            self.sql.append(contentsOf: ":\(self.binds.count)")
        }

        @inlinable
        public mutating func appendInterpolation(unescaped interpolation: String) {
            self.sql.append(contentsOf: interpolation)
        }
    }
}

extension OracleQuery: CustomStringConvertible {
    public var description: String {
        "\(self.sql) \(self.binds)"
    }
}

extension OracleQuery: CustomDebugStringConvertible {
    public var debugDescription: String {
        "OracleQuery(sql: \(String(describing: self.sql)), binds: \(String(reflecting: self.binds))"
    }
}

public struct OracleBindings: Sendable, Hashable {
    @usableFromInline
    struct Metadata: Sendable, Hashable {
        @usableFromInline
        var dataType: DBType
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

        @inlinable
        init(
            dataType: DBType,
            protected: Bool,
            isReturnBind: Bool,
            size: UInt32 = 0,
            isArray: Bool,
            arrayCount: Int?,
            maxArraySize: Int?
        ) {
            self.dataType = dataType
            self.protected = protected
            self.isReturnBind = isReturnBind
            if size == 0 {
                self.size = UInt32(self.dataType.defaultSize)
            } else {
                self.size = size
            }
            if dataType.defaultSize > 0 {
                self.bufferSize = size * UInt32(dataType.bufferSizeFactor)
            } else {
                self.bufferSize = UInt32(dataType.bufferSizeFactor)
            }
            self.isArray = isArray
            self.arrayCount = arrayCount ?? 0
            self.maxArraySize = maxArraySize ?? 0
        }

        @inlinable
        init<Value: OracleEncodable>(
            value: Value,
            protected: Bool,
            isReturnBind: Bool
        ) {
            self.init(
                dataType: Value.oracleType,
                protected: protected,
                isReturnBind: isReturnBind,
                size: value.size,
                isArray: Value.isArray,
                arrayCount: value.arrayCount,
                maxArraySize: value.arraySize
            )
        }
    }

    @usableFromInline
    var metadata: [Metadata]
    @usableFromInline
    var bytes: ByteBuffer

    public var count: Int {
        self.metadata.count
    }

    public init() {
        self.metadata = []
        self.bytes = ByteBuffer()
    }

    public init(capacity: Int) {
        self.metadata = []
        self.metadata.reserveCapacity(capacity)
        self.bytes = ByteBuffer()
        self.bytes.reserveCapacity(128 * capacity)
    }

    public mutating func appendNull<T: OracleThrowingEncodable>(
        _ type: T.Type
    ) {
        if T.oracleType == .boolean {
            self.bytes.writeInteger(Constants.TNS_ESCAPE_CHAR)
            self.bytes.writeInteger(UInt8(1))
        } else if T.oracleType._oracleType == .intNamed {
            self.bytes.writeUB4(0) // TOID
            self.bytes.writeUB4(0) // OID
            self.bytes.writeUB4(0) // snapshot
            self.bytes.writeUB4(0) // version
            self.bytes.writeUB4(0) // packed data length
            self.bytes.writeUB4(Constants.TNS_OBJ_TOP_LEVEL) // flags
        } else {
            self.bytes.writeInteger(UInt8(0))
        }
        self.metadata.append(.init(
            dataType: type.oracleType,
            protected: false,
            isReturnBind: false,
            size: 1,
            isArray: type.isArray,
            arrayCount: type.isArray ? 0 : nil,
            maxArraySize: type.isArray ? 0 : nil
        ))
    }

    @inlinable
    public mutating func append<Value: OracleThrowingEncodable, JSONEncoder: OracleJSONEncoder>(_ value: Value, context: OracleEncodingContext<JSONEncoder>) throws {
        fatalError()
    }

    @inlinable
    public mutating func append<Value: OracleEncodable, JSONEncoder: OracleJSONEncoder>(
        _ value: Value,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        value.encode(into: &self.bytes, context: context)
        self.metadata.append(.init(
            value: value,
            protected: true,
            isReturnBind: false
        ))
    }

    @inlinable
    mutating func appendUnprotected<Value: OracleThrowingEncodable, JSONEncoder: OracleJSONEncoder>(
        _ value: Value,
        context: OracleEncodingContext<JSONEncoder>
    ) throws {
        fatalError()
    }

    @inlinable
    mutating func appendUnprotected<Value: OracleEncodable, JSONEncoder: OracleJSONEncoder>(
        _ value: Value,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        fatalError()
    }
}

extension OracleBindings:
    CustomStringConvertible, CustomDebugStringConvertible {
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
        protected: Bool, type: DBType, buffer: ByteBuffer?
    ) -> String {
        "(\(Self.makeBindingPrintable(protected: protected, type: type, buffer: buffer)); \(type))"
    }

    private static func makeBindingPrintable(
        protected: Bool, type: DBType, buffer: ByteBuffer?
    ) -> String {
        if protected {
            return "****"
        }

        guard var buffer = buffer else {
            return "null"
        }

        // TODO: better printout for numeric, string, bool
        return "\(buffer.readableBytes) bytes"
    }
}

/// A small helper to inspect encoded bindings
private struct BindingsReader: Sequence {
    typealias Element = Optional<ByteBuffer>

    var buffer: ByteBuffer

    struct Iterator: IteratorProtocol {
        typealias Element = Optional<ByteBuffer>
        private var buffer: ByteBuffer

        init(buffer: ByteBuffer) {
            self.buffer = buffer
        }

        mutating func next() -> Optional<Optional<ByteBuffer>> {
            guard let length = self.buffer.readInteger(as: Int32.self) else {
                return .none
            }

            if length < 0 {
                return .some(.none)
            }

            return .some(self.buffer.readSlice(length: Int(length))!)
        }
    }

    func makeIterator() -> Iterator {
        Iterator(buffer: self.buffer)
    }
}
