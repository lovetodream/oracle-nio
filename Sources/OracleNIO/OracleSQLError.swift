import NIOCore

/// An error that is thrown from the OracleClient.
public struct OracleSQLError: Error {

    public struct Code: Sendable, Hashable, CustomStringConvertible {
        enum Base: Sendable, Hashable {
            case clientClosesConnection
            case clientClosedConnection
            case connectionError
            case messageDecodingFailure
            case nationalCharsetNotSupported
            case uncleanShutdown
            case unexpectedBackendMessage
            case server
            case queryCancelled
            case serverVersionNotSupported
            case sidNotSupported
            case missingParameter
            case malformedQuery
        }

        internal var base: Base

        private init(_ base: Base) {
            self.base = base
        }

        public static let clientClosesConnection = Self(.clientClosesConnection)
        public static let clientClosedConnection = Self(.clientClosedConnection)
        public static let connectionError = Self(.connectionError)
        public static let messageDecodingFailure = Self(.messageDecodingFailure)
        public static let nationalCharsetNotSupported =
        Self(.nationalCharsetNotSupported)
        public static let uncleanShutdown = Self(.uncleanShutdown)
        public static let unexpectedBackendMessage =
        Self(.unexpectedBackendMessage)
        public static let server = Self(.server)
        public static let queryCancelled = Self(.queryCancelled)
        public static let serverVersionNotSupported =
        Self(.serverVersionNotSupported)
        public static let sidNotSupported = Self(.sidNotSupported)
        public static let missingParameter = Self(.missingParameter)
        public static let malformedQuery = Self(.malformedQuery)

        public var description: String {
            switch self.base {
            case .clientClosesConnection:
                return "clientClosesConnection"
            case .clientClosedConnection:
                return "clientClosedConnection"
            case .connectionError:
                return "connectionError"
            case .messageDecodingFailure:
                return "messageDecodingFailure"
            case .nationalCharsetNotSupported:
                return "nationalCharsetNotSupported"
            case .uncleanShutdown:
                return "uncleanShutdown"
            case .unexpectedBackendMessage:
                return "unexpectedBackendMessage"
            case .server:
                return "server"
            case .queryCancelled:
                return "queryCancelled"
            case .serverVersionNotSupported:
                return "serverVersionNotSupported"
            case .sidNotSupported:
                return "sidNotSupported"
            case .missingParameter:
                return "missingParameter"
            case .malformedQuery:
                return "malformedQuery"
            }
        }
    }

    private var backing: Backing

    private mutating func copyBackingStorageIfNecessary() {
        if !isKnownUniquelyReferenced(&self.backing) {
            self.backing = self.backing.copy()
        }
    }

    /// The ``struct Code`` code.
    public internal(set) var code: Code {
        get { self.backing.code }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.code = newValue
        }
    }

    /// The info that was received from the server.
    public internal(set) var serverInfo: ServerInfo? {
        get { self.backing.serverInfo }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.serverInfo = newValue
        }
    }

    /// The underlying error.
    public internal(set) var underlying: Error? {
        get { self.backing.underlying }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.underlying = newValue
        }
    }

    /// The file in which the Oracle operation was triggered that failed.
    public internal(set) var file: String? {
        get { self.backing.file }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.file = newValue
        }
    }

    /// The line in which the Oracle operation was triggered that failed.
    public internal(set) var line: Int? {
        get { self.backing.line }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.line = newValue
        }
    }

    /// The query that failed.
    public internal(set) var query: OracleQuery? {
        get { self.backing.query }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.query = newValue
        }
    }

    /// The backend message... we should keep this internal but we can use it to print more advanced
    /// debug reasons.
    var backendMessage: OracleBackendMessage? {
        get { self.backing.backendMessage }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.backendMessage = newValue
        }
    }

    init(
        code: Code, query: OracleQuery,
        file: String? = nil, line: Int? = nil
    ) {
        self.backing = .init(code: code)
        self.query = query
        self.file = file
        self.line = line
    }

    init(code: Code) {
        self.backing = .init(code: code)
    }

    private final class Backing {
        fileprivate var code: Code
        fileprivate var serverInfo: ServerInfo?
        fileprivate var underlying: Error?
        fileprivate var file: String?
        fileprivate var line: Int?
        fileprivate var query: OracleQuery?
        fileprivate var backendMessage: OracleBackendMessage?

        init(code: Code) {
            self.code = code
        }

        func copy() -> Self {
            let new = Self.init(code: self.code)
            new.serverInfo = self.serverInfo
            new.underlying = self.underlying
            new.file = self.file
            new.line = self.line
            new.query = self.query
            new.backendMessage = self.backendMessage
            return new
        }
    }

    public struct ServerInfo {
        let underlying: OracleBackendMessage.BackendError

        /// The error number/identifier.
        public var number: UInt32 {
            self.underlying.number
        }

        /// The error message, typically prefixed with `ORA-` & ``ServerInfo.number``.
        public var message: String? {
            self.underlying.message
        }

        init(_ underlying: OracleBackendMessage.BackendError) {
            self.underlying = underlying
        }
    }

    // MARK: - Internal convenience factory methods -

    static func unexpectedBackendMessage(
        _ message: OracleBackendMessage
    ) -> Self {
        var new = OracleSQLError(code: .unexpectedBackendMessage)
        new.backendMessage = message
        return new
    }

    static func clientClosesConnection(underlying: Error?) -> OracleSQLError {
        var error = OracleSQLError(code: .clientClosesConnection)
        error.underlying = underlying
        return error
    }

    static func clientClosedConnection(underlying: Error?) -> OracleSQLError {
        var error = OracleSQLError(code: .clientClosedConnection)
        error.underlying = underlying
        return error
    }

    static var uncleanShutdown: OracleSQLError {
        OracleSQLError(code: .uncleanShutdown)
    }

    static func connectionError(underlying: Error) -> OracleSQLError {
        var error = OracleSQLError(code: .connectionError)
        error.underlying = underlying
        return error
    }

    static func messageDecodingFailure(
        _ error: OracleMessageDecodingError
    ) -> OracleSQLError {
        var new = OracleSQLError(code: .messageDecodingFailure)
        new.underlying = error
        return new
    }

    static func server(
        _ error: OracleBackendMessage.BackendError
    ) -> OracleSQLError {
        var new = OracleSQLError(code: .server)
        new.serverInfo = .init(error)
        return new
    }

    static let nationalCharsetNotSupported =
    OracleSQLError(code: .nationalCharsetNotSupported)

    static let queryCancelled = OracleSQLError(code: .queryCancelled)

    static let serverVersionNotSupported =
    OracleSQLError(code: .serverVersionNotSupported)

    static let sidNotSupported = OracleSQLError(code: .sidNotSupported)

    static func missingParameter(
        expected key: String,
        in parameters: OracleBackendMessage.Parameter
    ) -> OracleSQLError {
        var error = OracleSQLError(code: .missingParameter)
        error.underlying = MissingParameterError(
            expectedKey: key, actualParameters: parameters
        )
        return error
    }

    static func malformedQuery(minified sql: String) -> OracleSQLError {
        var error = OracleSQLError(code: .malformedQuery)
        error.underlying = MalformedQueryError(sql: sql)
        return error
    }

}


// MARK: - Error Implementations -

extension OracleSQLError {

    struct MissingParameterError: Error {
        var expectedKey: String
        var actualParameters: OracleBackendMessage.Parameter
    }

    struct MalformedQueryError: Error {
        /// Minified sql statement which was malformed.
        var sql: String
    }

 }
