import NIOCore
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder

/// A type that can encode itself to a Oracle wire binary representation.
public protocol OracleThrowingEncodable {
    /// Identifies the data type that we will encode into `ByteBuffer` in `encode`.
    static var oracleType: OracleDataType { get }

    /// Identifies the oracle format that is used to encode the value into `ByteBuffer` in `encode`.
    static var oracleFormat: OracleFormat { get }

    /// Encode the entity into the `ByteBuffer` in Oracle binary format, without setting the byte count.
    ///
    /// This method is called from the ``OracleBindings``.
    func encode<JSONEncoder: OracleJSONEncoder>(into byteBuffer: inout ByteBuffer, context: OracleEncodingContext<JSONEncoder>) throws
}

/// A type that can encode itself to a oracle wire binary representation.
///
/// It enforces that the ``OracleEncodable.encode(into:context:)`` does not throw.
/// This allows users to create ``OracleQuery``'s using the
/// `ExpressibleByStringInterpolation` without having to spell `try`.
public protocol OracleEncodable: OracleThrowingEncodable {
    func encode<JSONEncoder: OracleJSONEncoder>(into byteBuffer: inout ByteBuffer, context: OracleEncodingContext<JSONEncoder>)
}

/// A type that can decode itself from a oracle wire binary representation.
///
/// If you want to conform a type to OracleDecodable you must implement the decode method.
public protocol OracleDecodable {
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
        from byteBuffer: inout ByteBuffer,
        type: OracleDataType,
        format: OracleFormat,
        context: OracleDecodingContext<JSONDecoder>
    ) throws

    /// Decode an entity from the `ByteBuffer` in oracle wire format.
    ///
    /// This method has a default implementation and is only overwritten for `Optional`'s.
    static func _decodeRaw<JSONDecoder: OracleJSONEncoder>(
        from byteBuffer: inout ByteBuffer?,
        type: OracleDataType,
        format: OracleFormat,
        context: OracleDecodingContext<JSONDecoder>
    ) throws -> Self
}

extension OracleDecodable {
    @inlinable
    public static func _decodeRaw<JSONDecoder: OracleJSONDecoder>(
        from byteBuffer: inout ByteBuffer?,
        type: OracleDataType,
        format: OracleFormat,
        context: OracleDecodingContext<JSONDecoder>
    ) throws -> Self {
        guard var buffer = byteBuffer else {
            throw OracleDecodingError.Code.missingData
        }
        return try self.init(from: &buffer, type: type, format: format, context: context)
    }
}

/// A type that can be encoded into and decoded from a oracle binary format.
public typealias OracleCodable = OracleEncodable & OracleDecodable

extension OracleThrowingEncodable {
    @inlinable
    func encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) throws {
        // The length of the parameter value, in bytes
        // (this count does not include itself). Can be zero.
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(0, as: Int32.self)
        let startIndex = buffer.writerIndex
        // The value of the parameter, in the format indicated by the associated
        // format code.
        try self.encode(into: &buffer, context: context)

        // overwrite the empty length with the real value
        buffer.setInteger(
            numericCast(buffer.writerIndex - startIndex),
            at: lengthIndex, as: Int32.self
        )
    }
}

extension OracleEncodable {
    @inlinable
    func encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) throws {
        // The length of the parameter value, in bytes (this count does not
        // include itself). Can be zero.
        let lengthIndex = buffer.writerIndex
        buffer.writeInteger(0, as: Int32.self)
        let startIndex = buffer.writerIndex
        // The value of the parameter, in the format indicated by the associated
        // format code.
        self.encode(into: &buffer, context: context)

        // overwrite the empty length, with the real value.
        buffer.setInteger(
            numericCast(buffer.writerIndex - startIndex),
            at: lengthIndex, as: Int32.self
        )
    }
}

/// A context hat is passed to Swift objects that are encoded into the oracle wire format.
///
/// Used to pass further information to the encoding method.
public struct OracleEncodingContext<JSONEncoder: OracleJSONEncoder> {
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

/// A context that is passed to Swift objects that are decoded from the Oracle wire format.
///
/// Used to pass further information to the decoding method.
public struct OracleDecodingContext<JSONDecoder: OracleJSONDecoder> {
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

extension Optional: OracleDecodable where Wrapped: OracleDecodable, Wrapped._DecodableType == Wrapped {
    public typealias _DecodableType = Wrapped

    public init<JSONDecoder: OracleJSONDecoder>(
        from byteBuffer: inout ByteBuffer,
        type: OracleDataType,
        format: OracleFormat,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        preconditionFailure("This should not be called")
    }

    @inlinable
    public static func _decodeRaw<JSONDecoder: OracleJSONDecoder>(
        from byteBuffer: inout ByteBuffer?,
        type: OracleDataType,
        format: OracleFormat,
        context: OracleDecodingContext<JSONDecoder>
    ) throws -> Optional<Wrapped> {
        switch byteBuffer {
        case .some(var buffer):
            return try Wrapped(
                from: &buffer,
                type: type,
                format: format,
                context: context
            )
        case .none:
            return .none
        }
    }
}
