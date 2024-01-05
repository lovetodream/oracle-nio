import NIOCore

public struct Cursor {
    public let id: UInt16
    let isQuery: Bool
    let requiresFullExecute: Bool
    let moreRowsToFetch: Bool

    // fetchArraySize = QueryOptions.arraySize + QueryOptions.prefetchRows
}

extension Cursor: OracleEncodable {
    public var oracleType: OracleDataType { .cursor }

    public func encode<JSONEncoder: OracleJSONEncoder>(
        into buffer: inout ByteBuffer,
        context: OracleEncodingContext<JSONEncoder>
    ) {
        if self.id == 0 {
            buffer.writeInteger(UInt8(0))
        } else {
            buffer.writeUB4(UInt32(self.id))
        }
    }
}

extension Cursor: OracleDecodable {
    public init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .cursor:
            let id = try buffer.throwingReadUB2()
            self = Cursor(
                id: id,
                isQuery: true,
                requiresFullExecute: true,
                moreRowsToFetch: true
            )
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
