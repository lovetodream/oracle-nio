import NIOSSL
import struct Foundation.URL
import class Foundation.ProcessInfo

extension OracleConnection {
    public struct Configuration {

        // MARK: - TLS

        /// The possible modes of operation for TLS encapsulation of a connection.
        public struct TLS {

            /// Do not try to create a TLS connection to the server.
            public static var disable: Self { .init(base: .disable) }

            /// Try to create a TLS connection to the server.
            ///
            /// If the server supports TLS, create a TLS connection. If the server does not support TLS,
            /// fail the connection creation.
            public static func require(_ sslContext: NIOSSLContext) -> Self {
                self.init(base: .require(sslContext))
            }

            public var sslContext: NIOSSLContext? {
                switch self.base {
                case .disable: return nil
                case .require(let context): return context
                }
            }

            enum Base {
                case disable
                case require(NIOSSLContext)
            }
            let base: Base
            private init(base: Base) { self.base = base }
        }

        // MARK: - Underlying connection options

        /// Describes options affecting how the underlying connection is made.
        public struct Options {
            /// A timeout for connection attempts. Defaults to ten seconds.
            public var connectTimeout: TimeAmount

            /// The server name to use for certificate validation and SNI (Server Name Indication) when
            /// TLS is enabled.
            ///
            /// Defaults to none (but see below).
            ///
            /// > When set to `nil`:
            /// If the connection is made to a server over TCP using
            /// ``OracleConnection/Configuration/init(host:port:serviceName:username:password:tls:)``, 
            /// the given `host` is used, unless it was an IP address string. If it _was_ an IP, or the
            /// connection is made by any other method, SNI is disabled.
            public var tlsServerName: String?

            /// Create an options structure with default values.
            ///
            /// Most users should not need to adjust the defaults.
            public init() {
                self.connectTimeout = .seconds(10)
            }
        }

        // MARK: Oracle connection options

        enum OracleProtocol: CustomStringConvertible {
            /// Unencrypted network traffic.
            case tcp
            /// Encrypted network traffic via TLS.
            case tcps

            var description: String {
                switch self {
                case .tcp:
                    return "tcp"
                case .tcps:
                    return "tcps"
                }
            }
        }

        var options: Options = .init()

        /// The name or IP address of the machine hosting the database or the database listener.
        var host: String
        /// The port number on which the database listener is listening.
        var port: Int

        var tls: TLS
        var serverNameForTLS: String? {
            // If a name was explicitly configured always use it.
            if let tlsServerName = options.tlsServerName {
                return tlsServerName
            }

            // Otherwise, if the hostname wasn't an IP use that.
            if !host.isIPAddress() { return host }

            // Otherwise disable SNI
            return nil
        }
        /// The protocol used to send network traffic.
        internal var _protocol: OracleProtocol {
            switch self.tls.base {
            case .disable: return .tcp
            case .require: return .tcps
            }
        }

        /// The name of the user to connect to.
        var username: String
        
        /// The password for the user.
        var password: String

        /// The service name of the database.
        var serviceName: String
        /// The system identifier (SID) of the database.
        ///
        /// - Note: Using a ``serviceName`` instead is recommended by Oracle.
        var sid: String?

        /// Authorization mode to use.
        var mode: AuthenticationMode = .default

        /// Boolean indicating whether out-of-band breaks should be disabled.
        ///
        /// - Note: Windows does not support this functionality at all.
        var disableOOB: Bool = false

        /// Prefix for the connection id sent to the database server.
        ///
        /// - Note: This has nothing to do with ``OracleConnection.connectionID``. This
        ///         prefix can be used to identify the connection on the oracle server. It will be
        ///         sanitized.
        var connectionIDPrefix: String {
            get { _connectionIDPrefix }
            set { _connectionIDPrefix = sanitize(value: newValue) }
        }
        private var _connectionIDPrefix: String = ""

        /// Connection ID on the oracle server.
        private(set) var connectionID: String

        /// The name of the process, sent to the oracle server upon connection.
        ///
        /// Defaults to the name of the current process.
        ///
        /// - Note: The value set here will be sanitized.
        public var programName: String {
            get { _programName }
            set { _programName = sanitize(value: newValue) }
        }
        private var _programName: String = sanitize(
            value: ProcessInfo.processInfo.processName
        )
        /// The name of the machine, sent to the oracle server upon connection.
        ///
        /// Defaults to the hostname of your system.
        ///
        /// - Note: The value set here will be sanitized.
        public var machineName: String {
            get { _machineName }
            set { _machineName = sanitize(value: newValue) }
        }
        private var _machineName: String = sanitize(
            value: ProcessInfo.processInfo.hostName
        )
        /// The process ID, sent to the oracle server upon connection.
        ///
        /// Defaults to the current process ID.
        var pid = ProcessInfo.processInfo.processIdentifier
        /// The name of the user running the process, sent to the oracle server upon connection.
        ///
        /// Defaults to the user running the current process.
        ///
        /// - Note: The value set here will be sanitized.
        var processUsername: String {
            get { _processUsername }
            set { _processUsername = sanitize(value: newValue) }
        }
        private var _processUsername = sanitize(
            value: defaultUsername()
        )
        private static func defaultUsername() -> String {
            #if os(iOS) || os(tvOS) || os(watchOS)
            return "unknown"
            #else
            return ProcessInfo.processInfo.userName
            #endif
        }
        internal let _terminalName = "unknown"


        public init(
            host: String,
            port: Int = 1521,
            serviceName: String,
            username: String,
            password: String,
            tls: TLS = .disable
        ) {
            self.host = host
            self.port = port
            self.serviceName = serviceName
            self.username = username
            self.password = password
            self.tls = tls

            self.connectionID = sanitize(
                value: self._connectionIDPrefix +
                    [UInt8].random(count: 16).toBase64()
            )
        }


        // MARK: - Implementation details

        enum EndpointInfo {
            case connectTCP(host: String, port: Int)
        }

        internal func getDescription() -> Description {
            let address = Address(
                protocol: self._protocol, host: self.host, port: self.port
            )
            let addressList = AddressList(addresses: [address])
            let desc = Description(
                connectionID: self.connectionID,
                addressLists: [addressList],
                sourceRoute: false,
                loadBalance: false,
                tcpConnectTimeout: self.options.connectTimeout,
                serviceName: self.serviceName,
                sid: self.sid,
                sslServerDnMatch: self.serverNameForTLS != nil,
                sslServerCertDn: self.serverNameForTLS,
                walletLocation: nil
            )
            return desc
        }

        internal func getConnectString() -> String {
            let description = self.getDescription()
            let cid = """
            (PROGRAM=\(self.programName)) \
            (HOST=\(self.machineName)) \
            (USER=\(self.username))
            """
            return description.buildConnectString(cid)
        }
    }
}

// originally taken from NIOSSL
private extension String {
    func isIPAddress() -> Bool {
        // We need some scratch space to let inet_pton write into.
        var ipv4Addr = in_addr(), ipv6Addr = in6_addr() 
        // inet_pton() assumes the provided address buffer is non-NULL

        /// N.B.: ``String/withCString(_:)`` is much more efficient than directly passing 
        /// `self`, especially twice.
        return self.withCString { ptr in
            inet_pton(AF_INET, ptr, &ipv4Addr) == 1 || 
            inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
        }
    }
}

private func sanitize(value: String) -> String {
    return value
        .replacingOccurrences(of: "(", with: "?")
        .replacingOccurrences(of: ")", with: "?")
        .replacingOccurrences(of: "=", with: "?")
}
