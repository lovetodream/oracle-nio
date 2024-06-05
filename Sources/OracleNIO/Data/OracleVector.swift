import NIOCore

// MARK: Int8

public struct OracleVectorInt8: OracleVectorProtocol {
    public typealias MaskStorage = Self
    public typealias Scalar = Int8

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_INT8

    private var underlying: [Int8]
    var count: Int { underlying.count }

    public init() {
        self.underlying = []
    }

    public init(arrayLiteral elements: Int8...) {
        self.underlying = elements
    }

    init(underlying: [Int8]) {
        self.underlying = underlying
    }

    public subscript(index: Int) -> Int8 {
        get {
            self.underlying[index]
        }
        set(newValue) {
            self.underlying[index] = newValue
        }
    }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        for element in self.underlying {
            buffer.writeInteger(element)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> OracleVectorInt8 {
        var values = [Int8]()
        values.reserveCapacity(elements)

        for _ in 0..<elements {
            try values.append(buffer.throwingReadInteger(as: Int8.self))
        }

        return .init(underlying: values)
    }
}

// MARK: Float32

public struct OracleVectorFloat32: OracleVectorProtocol {
    public typealias Scalar = Float32

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_FLOAT32

    private var underlying: [Float32]
    var count: Int { underlying.count }

    public init() {
        self.underlying = []
    }

    public init(arrayLiteral elements: Float32...) {
        self.underlying = elements
    }

    init(underlying: [Float32]) {
        self.underlying = underlying
    }

    public subscript(index: Int) -> Float32 {
        get {
            self.underlying[index]
        }
        set(newValue) {
            self.underlying[index] = newValue
        }
    }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        for element in self.underlying {
            element.encode(into: &buffer, context: context)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> OracleVectorFloat32 {
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

public struct OracleVectorFloat64: OracleVectorProtocol {
    public typealias Scalar = Float64

    static let vectorFormat: UInt8 = Constants.VECTOR_FORMAT_FLOAT64

    private var underlying: [Float64]
    public var count: Int { underlying.count }

    public init() {
        self.underlying = []
    }

    public init(arrayLiteral elements: Float64...) {
        self.underlying = elements
    }

    init(underlying: [Float64]) {
        self.underlying = underlying
    }

    public subscript(index: Int) -> Float64 {
        get {
            self.underlying[index]
        }
        set(newValue) {
            self.underlying[index] = newValue
        }
    }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        for element in self.underlying {
            element.encode(into: &buffer, context: context)
        }
    }

    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> OracleVectorFloat64 {
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


// MARK: - Internal helper protocols

private protocol OracleVectorProtocol: OracleCodable, Equatable, SIMD where ArrayLiteralElement == Scalar {
    var count: Int { get }
    static var vectorFormat: UInt8 { get }
    static func _decodeActual(from buffer: inout ByteBuffer, elements: Int) throws -> Self
}

extension OracleVectorProtocol {
    public var scalarCount: Int { self.count }
    public var oracleType: OracleDataType { .vector }

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
        buffer.writeInteger(UInt16(Constants.TNS_VECTOR_FLAG_NORM | Constants.TNS_VECTOR_FLAG_NORM_RESERVED))
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

}

