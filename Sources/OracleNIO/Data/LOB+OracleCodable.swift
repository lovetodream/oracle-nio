import NIOCore

final class LOB {
    var size: UInt64
    var chunkSize: UInt32
    internal var locator: ByteBuffer
    private(set) var hasMetadata: Bool
    public let dbType: DBType

    private(set) weak var cleanupContext: CleanupContext?

    init(
        size: UInt64,
        chunkSize: UInt32,
        locator: ByteBuffer,
        hasMetadata: Bool,
        dbType: DBType
    ) {
        self.size = size
        self.chunkSize = chunkSize
        self.locator = locator
        self.hasMetadata = hasMetadata
        self.dbType = dbType
    }
    deinit { self.free() }

    static func create(dbType: DBType, locator: ByteBuffer?) -> Self {
        if let locator {
            return self.init(
                size: 0,
                chunkSize: 0,
                locator: locator,
                hasMetadata: false,
                dbType: dbType
            )
        } else {
            let locator = ByteBuffer(repeating: 0, count: 40)
            let lob = self.init(
                size: 0,
                chunkSize: 0,
                locator: locator,
                hasMetadata: false,
                dbType: dbType
            )
            // TODO: create temp lob on db
            return lob
        }
    }

    func encoding() -> String {
        locator.moveReaderIndex(to: 0)
        if dbType.csfrm == Constants.TNS_CS_NCHAR ||
            (locator.readableBytes >= Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3 &&
             ((locator.getInteger(
                at: Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_3, as: UInt8.self
             )! & Constants.TNS_LOB_LOCATOR_VAR_LENGTH_CHARSET) != 0))
        {
            return Constants.TNS_ENCODING_UTF16
        }
        return Constants.TNS_ENCODING_UTF8
    }

    func write(
        _ buffer: ByteBuffer, offset: UInt64, on connection: OracleConnection
    ) {
        fatalError("TODO: write lob")
    }

    func free() {
        let flags1 = self.locator.getInteger(
            at: Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_1, as: UInt8.self
        )!
        let flags4 = self.locator.getInteger(
            at: Constants.TNS_LOB_LOCATOR_OFFSET_FLAG_4, as: UInt8.self
        )!
        if flags1 & Constants.TNS_LOB_LOCATOR_FLAGS_ABSTRACT != 0 ||
            flags4 & Constants.TNS_LOB_LOCATOR_FLAGS_TEMP != 0 {
            if self.cleanupContext?.tempLOBsToClose == nil {
                self.cleanupContext?.tempLOBsToClose = []
            }
            self.cleanupContext?.tempLOBsToClose?.append(self.locator)
            self.cleanupContext?.tempLOBsTotalSize += self.locator.readableBytes
        }
    }

}

extension LOB: OracleEncodable {
    public var oracleType: DBType { .blob }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        preconditionFailure("This should not be called")
    }

    public func _encodeRaw<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        let length = self.locator.readableBytes
        buffer.writeUB4(UInt32(length))
        self.locator._encodeRaw(into: &buffer, context: context)
    }
}

extension LOB: OracleDecodable {
    public convenience init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .clob, .blob:
            let size = try buffer.throwingReadUB8()
            let chunkSize = try buffer.throwingReadUB4()
            let locator = try buffer.readOracleSpecificLengthPrefixedSlice()
            self.init(
                size: size,
                chunkSize: chunkSize,
                locator: locator,
                hasMetadata: true,
                dbType: type
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
