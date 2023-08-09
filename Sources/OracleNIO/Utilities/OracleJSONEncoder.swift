import class Foundation.JSONEncoder
import struct Foundation.Data
import NIOFoundationCompat
import NIOCore

/// A protocol that mimics the Foundation `JSONEncoder.encode(_:)` function.
///
/// Conform a non-Foundation JSON encoder to this protocol if you want OracleNIO to be able to use it
/// when encoding JSON values (see ``_defaultJSONEncoder``).
public protocol OracleJSONEncoder {
    func encode<T>(_ value: T) throws -> Data where T: Encodable

    func encode<T: Encodable>(_ value: T, into buffer: inout ByteBuffer) throws
}

extension OracleJSONEncoder {
    public func encode<T: Encodable>(
        _ value: T,
        into buffer: inout ByteBuffer
    ) throws {
        let data = try self.encode(value)
        buffer.writeData(data)
    }
}

extension JSONEncoder: OracleJSONEncoder { }

/// The default JSON encoder used by OracleNIO when encoding JSON values.
///
/// As `_defaultJSONEncoder` will be reused for encoding all JSON values from potentially multiple
/// threads at once, you must ensure your custom JSON encoder is thread safe internally like
/// `Foundation.JSONEncoder`.
public var _defaultJSONEncoder: OracleJSONEncoder = JSONEncoder()
