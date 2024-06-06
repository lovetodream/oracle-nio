import NIOCore
import NIOEmbedded

@testable import OracleNIO

extension QueryResult {
    init(value: Value) {
        self.init(value: value, logger: OracleConnection.noopLogger)
    }
}
