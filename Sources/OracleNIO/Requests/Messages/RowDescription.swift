import NIOCore

/// A backend row description message.
@usableFromInline
struct RowDescription: OracleBackendMessage.PayloadDecodable, Sendable, Equatable {
    @usableFromInline
    var columns: [Column]

    @usableFromInline
    struct Column: OracleBackendMessage.PayloadDecodable, Equatable, Sendable {
        /// The field name.
        @usableFromInline
        var name: String

        /// The object ID of the field's data type.
        @usableFromInline
        var dataType: OracleDataType

        /// The data type size.
        @usableFromInline
        var dataTypeSize: UInt32

        /// The number of significant digits. Oracle guarantees the portability of numbers with precision ranging from 1 to 38.
        ///
        /// - NOTE: This is only relevant for the datatype `NUMBER`.
        ///         For reference: https://docs.oracle.com/cd/B28359_01/server.111/b28318/datatype.htm#CNCPT1832
        @usableFromInline
        var precision: Int16

        /// The number of digits to the right (positive) or left (negative) of the decimal point. The scale can range from -84 to 127.
        ///
        /// - NOTE: This is only relevant for the datatype `NUMBER`.
        ///         For reference: https://docs.oracle.com/cd/B28359_01/server.111/b28318/datatype.htm#CNCPT1832
        @usableFromInline
        var scale: Int16

        /// - WARNING: I am unsure what this is for atm! - @lovetodream
        @usableFromInline
        var bufferSize: UInt32

        /// Indicates if values for the column are `Optional`.
        @usableFromInline
        var nullsAllowed: Bool

        static func decode(from buffer: inout ByteBuffer, capabilities: Capabilities) throws -> RowDescription.Column {
            let dataType = try buffer.throwingReadUB1()
            buffer.skipUB1() // flags
            let precision = try buffer.throwingReadSB1()

            let scale: Int16
            if
                let dataType = OracleDataType(rawValue: UInt16(dataType)),
                [.number, .intervalDS, .timestamp, .timestampLTZ, .timestampTZ].contains(dataType)
            {
                scale = try buffer.throwingReadSB2()
            } else {
                scale = try Int16(buffer.throwingReadSB1())
            }

            let bufferSize = try buffer.throwingReadUB4()

            buffer.skipUB4() // max number of array elements
            buffer.skipUB4() // cont flags

            let oidByteCount = try buffer.throwingReadUB1() // OID
            if oidByteCount > 0 {
                _ = buffer.readBytes() // oid, only relevant for intNamed
            }

            buffer.skipUB2() // version
            buffer.skipUB2() // character set id

            let csfrm = try buffer.throwingReadUB1() // character set form
            let dbType = try DBType.fromORATypeAndCSFRM(typeNumber: dataType, csfrm: csfrm)
            guard let oracleDataType = dbType.oracleType else {
                throw OraclePartialDecodingError.fieldNotDecodable(type: OracleDataType.self)
            }

            var size = try buffer.throwingReadUB4()
            if dataType == DataType.Value.raw.rawValue {
                size = bufferSize
            }

            if capabilities.ttcFieldVersion >= Constants.TNS_CCAP_FIELD_VERSION_12_2 {
                buffer.skipUB4() // oaccolid
            }

            let nullsAllowed = try buffer.throwingReadUB1() != 0

            buffer.skipUB1() // v7 length of name

            guard try buffer.throwingReadUB4() > 0, let name = buffer.readString(with: Constants.TNS_CS_IMPLICIT) else {
                throw OraclePartialDecodingError.fieldNotDecodable(type: String.self)
            }

            if try buffer.throwingReadUB4() > 0 {
                _ = buffer.readString(with: Constants.TNS_CS_IMPLICIT) ?? "" // current schema name, for intNamed
            }
            if try buffer.throwingReadUB4() > 0 {
                _ = buffer.readString(with: Constants.TNS_CS_IMPLICIT) ?? "" // name of intNamed
            }

            buffer.skipUB2() // column position
            buffer.skipUB4() // uds flag

            if dataType == OracleDataType.intNamed.rawValue {
                throw OraclePartialDecodingError.unsupportedDataType(type: .intNamed)
            }

            return Column(
                name: name, dataType: oracleDataType, dataTypeSize: size,
                precision: Int16(precision), scale: scale, bufferSize: bufferSize, nullsAllowed: nullsAllowed
            )
        }
    }

    static func decode(from buffer: inout ByteBuffer, capabilities: Capabilities) throws -> RowDescription {
        buffer.skipUB4() // max row size
        let columnCount = try buffer.throwingReadUB4()

        if columnCount > 0 {
            buffer.skipUB1()
        }

        var result = [Column]()
        result.reserveCapacity(Int(columnCount))

        for _ in 0..<columnCount {
            let field = try Column.decode(from: &buffer, capabilities: capabilities)
            result.append(field)
        }

        if try buffer.throwingReadUB4() > 0 {
            buffer.skipRawBytesChunked() // current date
        }
        buffer.skipUB4() // dcbflag
        buffer.skipUB4() // dcbmdbz
        buffer.skipUB4() // dcbmnpr
        buffer.skipUB4() // dcbmxpr
        if try buffer.throwingReadUB4() > 0 {
            buffer.skipRawBytesChunked() // dcbqcky
        }

        return RowDescription(columns: result)
    }
}