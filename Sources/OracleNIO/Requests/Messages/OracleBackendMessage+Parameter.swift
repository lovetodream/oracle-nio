import NIOCore

extension OracleBackendMessage {
    struct Parameter: PayloadDecodable, ExpressibleByDictionaryLiteral {
        
        typealias Key = String
        typealias Value = (value: String, flags: UInt32?)

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

        static func decode(from buffer: inout NIOCore.ByteBuffer, capabilities: Capabilities) throws -> OracleBackendMessage.Parameter {
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
                elements[key] = (value, flags)
            }
            return .init(elements)
        }
    }
}
