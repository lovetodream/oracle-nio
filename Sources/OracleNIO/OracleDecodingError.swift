public struct OracleDecodingError: Error {
    public struct Code: Hashable, Error, CustomStringConvertible {
        enum Base {
            case missingData
            case typeMismatch
        }

        var base: Base

        init(_ base: Base) {
            self.base = base
        }

        public static let missingData = Self(.missingData)
        public static let typeMismatch = Self(.typeMismatch)

        public var description: String {
            switch self.base {
            case .missingData:
                return "missingData"
            case .typeMismatch:
                return "typeMismatch"
            }
        }
    }
}
