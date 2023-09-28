import NIOCore

/// A backend row description message.
@usableFromInline
struct DescribeInfo: OracleBackendMessage.PayloadDecodable, Sendable, Hashable {
    @usableFromInline
    var columns: [Column]

    @usableFromInline
    struct Column: OracleBackendMessage.PayloadDecodable, Hashable, Sendable {
        /// The field name.
        @usableFromInline
        var name: String

        /// The object ID of the field's data type.
        @usableFromInline
        var dataType: OracleDataType

        /// The data type size.
        @usableFromInline
        var dataTypeSize: UInt32

        /// The number of significant digits. Oracle guarantees the portability of numbers with precision 
        /// ranging from 1 to 38.
        ///
        /// - NOTE: This is only relevant for the datatype `NUMBER`.
        ///         For reference: https://docs.oracle.com/cd/B28359_01/server.111/b28318/datatype.htm#CNCPT1832
        @usableFromInline
        var precision: Int16

        /// The number of digits to the right (positive) or left (negative) of the decimal point. The scale can 
        /// range from -84 to 127.
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

        static func decode(
            from buffer: inout ByteBuffer, 
            capabilities: Capabilities,
            context: OracleBackendMessageDecoder.Context
        ) throws -> DescribeInfo.Column {
            let dataType = try buffer.throwingReadInteger(as: UInt8.self)
            buffer.moveReaderIndex(forwardBy: 1) // flags
            let precision = try buffer.throwingReadInteger(as: Int8.self)

            let scale: Int16
            if
                let dataType = DataType.Value(rawValue: UInt16(dataType)),
                [.number, .intervalDS, .timestamp, .timestampLTZ, .timestampTZ]
                    .contains(dataType)
            {
                scale = try buffer.throwingReadSB2()
            } else {
                scale = try Int16(buffer.throwingReadInteger(as: Int8.self))
            }

            let bufferSize = try buffer.throwingReadUB4()

            buffer.skipUB4() // max number of array elements
            buffer.skipUB4() // cont flags

            let oidByteCount = try buffer.throwingReadInteger(as: UInt8.self)
                // OID
            if oidByteCount > 0 {
                // oid, only relevant for intNamed
                _ = try buffer.readOracleSpecificLengthPrefixedSlice()
            }

            buffer.skipUB2() // version
            buffer.skipUB2() // character set id

            let csfrm = try buffer.throwingReadInteger(as: UInt8.self)
                // character set form
            let dbType = try DBType.fromORATypeAndCSFRM(
                typeNumber: dataType, csfrm: csfrm
            )
            guard dbType._oracleType != nil else {
                throw OraclePartialDecodingError
                    .fieldNotDecodable(type: OracleDataType.self)
            }

            var size = try buffer.throwingReadUB4()
            if dataType == DataType.Value.raw.rawValue {
                size = bufferSize
            }

            if capabilities.ttcFieldVersion >= 
                Constants.TNS_CCAP_FIELD_VERSION_12_2
            {
                buffer.skipUB4() // oaccolid
            }

            let nullsAllowed =
                try buffer.throwingReadInteger(as: UInt8.self) != 0

            buffer.moveReaderIndex(forwardBy: 1) // v7 length of name

            guard 
                try buffer.throwingReadUB4() > 0,
                let name = try buffer
                    .readString(with: Constants.TNS_CS_IMPLICIT)
            else {
                throw OraclePartialDecodingError
                    .fieldNotDecodable(type: String.self)
            }

            if try buffer.throwingReadUB4() > 0 {
                _ = try buffer.readString(with: Constants.TNS_CS_IMPLICIT) ?? ""
                    // current schema name, for intNamed
            }
            if try buffer.throwingReadUB4() > 0 {
                _ = try buffer.readString(with: Constants.TNS_CS_IMPLICIT) ?? "" 
                    // name of intNamed
            }

            buffer.skipUB2() // column position
            buffer.skipUB4() // uds flag

            if dataType == DataType.Value.intNamed.rawValue {
                throw OraclePartialDecodingError
                    .unsupportedDataType(type: .intNamed)
            }

            return Column(
                name: name, dataType: dbType, dataTypeSize: size,
                precision: Int16(precision), scale: scale,
                bufferSize: bufferSize, nullsAllowed: nullsAllowed
            )
        }
    }

    static func decode(
        from buffer: inout ByteBuffer,
        capabilities: Capabilities,
        context: OracleBackendMessageDecoder.Context
    ) throws -> DescribeInfo {
        buffer.skipRawBytesChunked()
        buffer.skipUB4() // max row size
        let columnCount = try buffer.throwingReadUB4()
        context.columnsCount = Int(columnCount)

        if columnCount > 0 {
            buffer.moveReaderIndex(forwardBy: 1)
        }

        var result = [Column]()
        result.reserveCapacity(Int(columnCount))

        for _ in 0..<columnCount {
            let field = try Column.decode(
                from: &buffer, 
                capabilities: capabilities,
                context: context
            )
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

        return DescribeInfo(columns: result)
    }
}
