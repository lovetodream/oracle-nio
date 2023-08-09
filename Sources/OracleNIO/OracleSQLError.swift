import NIOCore

/// An error that is thrown from the OracleClient.
public struct OracleSQLError: Error {

    public struct Code: Sendable, Hashable, CustomStringConvertible {
        enum Base: Sendable, Hashable {
            case connectionError
            case messageDecodingFailure
            case uncleanShutdown
        }

        internal var base: Base

        private init(_ base: Base) {
            self.base = base
        }

        public static let connectionError = Self(.connectionError)
        public static let messageDecodingFailure = Self(.messageDecodingFailure)
        public static let uncleanShutdown = Self(.uncleanShutdown)

        public var description: String {
            switch self.base {
            case .connectionError:
                return "connectionError"
            case .messageDecodingFailure:
                return "messageDecodingFailure"
            case .uncleanShutdown:
                return "uncleanShutdown"
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
        // TODO: this might be the new OracleError
    }

    // MARK: - Internal convenience factory methods -

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

 }
