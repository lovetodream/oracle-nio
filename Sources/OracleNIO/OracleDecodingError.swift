public struct OracleDecodingError: Error {
    public struct Code: Hashable, Error, CustomStringConvertible {
        enum Base {
            case typeMismatch
        }

        var base: Base

        init(_ base: Base) {
            self.base = base
        }

        public static let typeMismatch = Self.init(.typeMismatch)

        public var description: String {
            switch self.base {
            case .typeMismatch:
                return "t"
            }
        }
    }
}
