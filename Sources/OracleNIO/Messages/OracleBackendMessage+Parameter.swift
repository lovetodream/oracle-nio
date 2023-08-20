import NIOCore
import class Foundation.NSDictionary

extension OracleBackendMessage {
    struct Parameter: PayloadDecodable, ExpressibleByDictionaryLiteral, Hashable {

        typealias Key = String
        struct Value: Hashable {
            let value: String
            let flags: UInt32?
        }


        var elements: [Key: Value]

        internal init(_ elements: [Key: Value]) {
            self.elements = elements
        }

        internal init(
            dictionaryLiteral elements:
                (Key, Value)...
        ) {
            self.elements = .init(uniqueKeysWithValues: elements)
        }

        subscript(key: Key) -> Value? {
            get { return elements[key] }
        }

        static func decode(
            from buffer: inout NIOCore.ByteBuffer, capabilities: Capabilities
        ) throws -> OracleBackendMessage.Parameter {
            let numberOfParameters = buffer.readUB2() ?? 0
            var elements = [Key: Value]()
            for _ in 0..<numberOfParameters {
                buffer.skipUB4()
                guard
                    let key = buffer.readString(with: Constants.TNS_CS_IMPLICIT)
                else {
                    preconditionFailure("add an error here")
                }
                let length = buffer.readUB4() ?? 0
                let value: String
                if length > 0 {
                    value =
                        buffer.readString(with: Constants.TNS_CS_IMPLICIT) ?? ""
                } else {
                    value = ""
                }
                let flags = buffer.readUB4()
                elements[key] = .init(value: value, flags: flags)
            }
            return .init(elements)
        }
    }

    struct QueryParameter: Hashable {
        var schema: String?
        var edition: String?
        var rowCounts: [UInt64]?

        static func decode(
            from buffer: inout ByteBuffer,
            capabilities: Capabilities,
            options: QueryOptions
        ) throws -> OracleBackendMessage.QueryParameter {
            let parametersCount = buffer.readUB2() ?? 0 // al8o4l (ignored)
            for _ in 0..<parametersCount {
                buffer.skipUB4()
            }
            if
                let bytesCount = buffer.readUB2()  // al8txl (ignored)
                    .flatMap(Int.init), bytesCount > 0
            {
                buffer.moveReaderIndex(forwardBy: bytesCount)
            }
            let pairsCount = buffer.readUB2() ?? 0 // number of key/value pairs
            var schema: String? = nil
            var edition: String? = nil
            var rowCounts: [UInt64]? = nil
            for _ in 0..<pairsCount {
                var keyValue: [UInt8]? = nil
                if let bytesCount = buffer.readUB2(), bytesCount > 0 { // key
                    keyValue = buffer.readBytes()
                }
                if let bytesCount = buffer.readUB2(), bytesCount > 0 { // value
                    buffer.skipRawBytesChunked()
                }
                let keywordNumber = buffer.readUB2() ?? 0 // keyword number
                if 
                    keywordNumber == Constants.TNS_KEYWORD_NUM_CURRENT_SCHEMA,
                    let keyValue 
                {
                    schema = String(cString: keyValue)
                } else if
                    keywordNumber == Constants.TNS_KEYWORD_NUM_EDITION,
                    let keyValue
                {
                    edition = String(cString: keyValue)
                }
            }
            if
                let bytesCount = buffer.readUB2().flatMap(Int.init),
                bytesCount > 0
            {
                buffer.moveReaderIndex(forwardBy: bytesCount)
            }
            if options.arrayDMLRowCounts {
                let numberOfRows = buffer.readUB4() ?? 0
                rowCounts = []
                for _ in 0..<numberOfRows {
                    let rowCount = buffer.readUB8() ?? 0
                    rowCounts?.append(rowCount)
                }
            }
            return .init(schema: schema, edition: edition, rowCounts: rowCounts)
        }
    }
}
