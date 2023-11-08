import NIOCore

/// A reference type used to capture `OUT` and `IN/OUT` binds in `DML` returning statements or 
/// `PL/SQL`.
///
/// - Note: `OracleRef`s used as `IN/OUT` binds without a value will be declared
///         as `NULL` in `PL/SQL`.
///
/// Here is an example showing how to use `OUT` binds in a `RETURNING` clause:
///
/// ```swift
/// let ref = OracleRef(dataType: .number, isReturnBind: true)
/// try await connection.query(
///     "INSERT INTO table(id) VALUES (1) RETURNING id INTO \(ref)",
///     logger: logger
/// )
/// let id = try ref.decode(as: Int.self) // 1
/// ```
///
/// Here is an example showing how to use `OUT` binds in `PL\SQL`:
///
/// ```swift
/// let ref = OracleRef(dataType: .number)
/// try await conn.query("""
///     begin
///         \(ref) := \(OracleNumber(8)) + \(OracleNumber(7));
///     end;
///     """, logger: logger)
/// let result = try ref.decode(as: Int.self) // 15
/// ```
///
public final class OracleRef: @unchecked Sendable, Hashable {
    public static func == (lhs: OracleRef, rhs: OracleRef) -> Bool {
        lhs.storage == rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.storage)
    }

    @usableFromInline
    internal var storage: ByteBuffer?
    @usableFromInline
    internal var metadata: OracleBindings.Metadata

    /// Use this initializer to create a OUT bind.
    /// 
    /// Please be aware that you still have to decode the database response into the Swift type you want
    /// after completing the query (using ``OracleRef.decode()``).
    /// 
    /// - Parameter dataType: The desired datatype within the Oracle database.
    /// - Parameter isReturnBind: Set this to `true` if the bind is used as part of a DML
    ///                           statement in the `RETURNING ... INTO binds` where
    ///                           binds are x `OracleRef`'s.
    public init(dataType: DBType, isReturnBind: Bool = false) {
        self.storage = nil
        self.metadata = .init(
            dataType: dataType,
            protected: false,
            isReturnBind: isReturnBind,
            isArray: false,
            arrayCount: nil,
            maxArraySize: nil,
            bindName: nil
        )
    }

    /// Use this initializer to create a IN/OUT bind.
    public init<V: OracleThrowingDynamicTypeEncodable>(_ value: V) throws {
        self.storage = ByteBuffer()
        self.metadata = .init(
            value: value, protected: true, isReturnBind: false, bindName: nil
        )
        try value._encodeRaw(into: &self.storage!, context: .default)
    }

    /// Use this initializer to create a IN/OUT bind.
    public init<V: OracleEncodable>(_ value: V) {
        self.storage = ByteBuffer()
        self.metadata = .init(
            value: value, protected: true, isReturnBind: false, bindName: nil
        )
        value._encodeRaw(into: &self.storage!, context: .default)
    }

    public func decode<V: OracleDecodable>(of: V.Type = V.self) throws -> V {
        let length = Int(self.storage?.getInteger(at: 0, as: UInt8.self) ?? 0)

        var buffer: ByteBuffer?

        if length == Constants.TNS_LONG_LENGTH_INDICATOR {
            buffer = ByteBuffer()
            var position = MemoryLayout<UInt8>.size
            while true {
                let chunkLength =
                Int(self.storage!.getInteger(at: position, as: UInt32.self)!)
                position += MemoryLayout<UInt32>.size
                if chunkLength == 0 { break }
                var temp = self.storage!.getSlice(
                    at: position, length: chunkLength
                )!
                position += chunkLength
                buffer?.writeBuffer(&temp)
            }
        } else if length != 0 && length != Constants.TNS_NULL_LENGTH_INDICATOR {
            buffer = self.storage!.getSlice(
                at: MemoryLayout<UInt8>.size, length: length
            )!
        }
        return try V._decodeRaw(
            from: &buffer, type: self.metadata.dataType, context: .default
        )
    }
}
