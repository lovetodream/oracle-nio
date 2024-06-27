//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOPosix
import NIOSSL

import struct Foundation.Data
import class Foundation.ProcessInfo
import struct Foundation.TimeZone
import struct Foundation.URL

extension OracleConnection {
    /// A configuration object for a connection.
    public struct Configuration: Sendable {

        // MARK: - TLS

        /// The possible modes of operation for TLS encapsulation of a connection.
        public struct TLS: Sendable {

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
        public struct Options: Sendable {
            /// A timeout for connection attempts. Defaults to ten seconds.
            public var connectTimeout: TimeAmount

            /// The server name to use for certificate validation and SNI (Server Name Indication) when
            /// TLS is enabled.
            ///
            /// Defaults to none (but see below).
            ///
            /// > When set to `nil`:
            /// If the connection is made to a server over TCP using
            /// ``OracleConnection/Configuration/init(host:port:service:username:password:tls:)``,
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

        public var options: Options = .init()

        /// The name or IP address of the machine hosting the database or the database listener.
        public var host: String
        /// The port number on which the database listener is listening.
        public var port: Int

        public var tls: TLS
        public var serverNameForTLS: String? {
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

        /// The name of the proxy user to connect to.
        public var proxyUser: String?

        /// The authentication variant used to connect to the database.
        ///
        /// It is defined as a closure to ensure we'll have an up-to-date token for establishing future
        /// connections if token based authentication is used.
        public var authenticationMethod: @Sendable () -> OracleAuthenticationMethod

        public var service: OracleServiceMethod

        /// Authorization mode to use.
        public var mode: AuthenticationMode = .default

        /// Boolean indicating whether out-of-band breaks should be disabled.
        ///
        /// - Note: Windows does not support this functionality at all.
        public var disableOOB: Bool = false

        /// A string with the format `host=<host>;port=<port>` that specifies the host and port of
        /// the PL/SQL debugger.
        public var debugJDWP: String?

        /// By default the timezone for the established session will be set to the client's (our) current
        /// timezone, provide a custom timezone if you want to set the timezone to something other than
        /// the one of the system.
        public var customTimezone: TimeZone?

        /// Prefix for the connection id sent to the database server.
        ///
        /// - Note: This has nothing to do with ``OracleConnection/id-property``. This
        ///         prefix can be used to identify the connection on the oracle server. It will be
        ///         sanitized.
        public var connectionIDPrefix: String {
            get { _connectionIDPrefix }
            set { _connectionIDPrefix = sanitize(value: newValue) }
        }
        private var _connectionIDPrefix: String = "" {
            didSet {
                self.connectionID = sanitize(
                    value: self._connectionIDPrefix
                        + Data([UInt8].random(count: 16)).base64EncodedString()
                )
            }
        }

        /// The number of tries that a connection attempt
        /// should be retried before the attempt is terminated.
        ///
        /// Defaults to `0`.
        public var retryCount: Int = 0

        /// The number of seconds to wait before making a new connection attempt.
        ///
        /// Defaults to `0`.
        public var retryDelay: Int = 0

        /// Connection ID on the oracle server.
        public private(set) var connectionID: String = ""

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
        public var processUsername: String {
            get { _processUsername }
            set { _processUsername = sanitize(value: newValue) }
        }
        private var _processUsername = sanitize(
            value: defaultUsername()
        )
        private static func defaultUsername() -> String {
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                return "unknown"
            #else
                return ProcessInfo.processInfo.userName
            #endif
        }
        internal let _terminalName = "unknown"


        // MARK: - Connection Pooling
        internal var purity: Purity = .default
        internal var serverType: String?
        internal var drcpEnabled = false
        internal var cclass: String?

        public init(
            host: String,
            port: Int = 1521,
            service: OracleServiceMethod,
            username: String,
            password: String,
            tls: TLS = .disable
        ) {
            self.host = host
            self.port = port
            self.service = service
            self.authenticationMethod = {
                .init(username: username, password: password)
            }
            self.tls = tls
        }

        public init(
            host: String,
            port: Int = 1521,
            service: OracleServiceMethod,
            authenticationMethod:
                @Sendable @autoclosure @escaping () -> OracleAuthenticationMethod,
            tls: TLS = .disable
        ) {
            self.host = host
            self.port = port
            self.service = service
            self.authenticationMethod = authenticationMethod
            self.tls = tls
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
                retryCount: self.retryCount,
                retryDelay: self.retryDelay,
                tcpConnectTimeout: self.options.connectTimeout,
                service: self.service,
                sslServerDnMatch: self.serverNameForTLS != nil,
                sslServerCertDn: nil,
                walletLocation: nil,
                purity: self.purity,
                serverType: self.serverType,
                cclass: self.cclass
            )
            return desc
        }

        internal func getConnectString() -> String {
            let description = self.getDescription()
            let cid = """
                (PROGRAM=\(self.programName))\
                (HOST=\(self.machineName))\
                (USER=\(self.processUsername))
                """
            return description.buildConnectString(cid)
        }
    }
}

// originally taken from NIOSSL
extension String {
    fileprivate func isIPAddress() -> Bool {
        // We need some scratch space to let inet_pton write into.
        var ipv4Addr = in_addr()
        var ipv6Addr = in6_addr()
        // inet_pton() assumes the provided address buffer is non-NULL

        /// N.B.: ``String/withCString(_:)`` is much more efficient than directly passing
        /// `self`, especially twice.
        return self.withCString { ptr in
            inet_pton(AF_INET, ptr, &ipv4Addr) == 1 || inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
        }
    }
}

private func sanitize(value: String) -> String {
    return
        value
        .replacingOccurrences(of: "(", with: "?")
        .replacingOccurrences(of: ")", with: "?")
        .replacingOccurrences(of: "=", with: "?")
}

public enum OracleAccessToken: Equatable {
    /// Specifies an Azure AD OAuth2 token used for Open Authorization (OAuth 2.0) token
    /// based authentication.
    case oAuth2(String)
    /// Specifies the token and private key strings used for Oracle Cloud Infrastructure (OCI)
    /// Identity and Access Management (IAM) token based authentication.
    case tokenAndPrivateKey(token: String, key: String)
}

public struct OracleAuthenticationMethod:
    Equatable, CustomDebugStringConvertible
{
    var base: Base

    enum Base: Equatable {
        case usernamePassword(String, String, String?)
        case token(OracleAccessToken)
    }

    /// Authenticate with username and password.
    /// - Parameters:
    ///   - username: The name of the user to connect to.
    ///   - password: The password for the user.
    ///   - newPassword: If set, the new password will take effect immediately upon a
    ///                  successful connection to the database.
    public init(
        username: String, password: String, newPassword: String? = nil
    ) {
        self.base = .usernamePassword(username, password, newPassword)
    }

    /// Authenticate with access token.
    /// - Parameter token: The access token can be one of ``OracleAccessToken``.
    public init(token: OracleAccessToken) {
        self.base = .token(token)
    }

    public var debugDescription: String {
        switch self.base {
        case .usernamePassword(let username, _, let newPassword):
            return """
                OracleAuthenticationVariant(username: \(String(reflecting: username)), \
                password: ********, \
                newPassword: \(newPassword != nil ? "********" : "nil"))
                """
        case .token:
            return "OracleAuthenticationVariant(token: ********)"
        }
    }

}

public enum OracleServiceMethod: Sendable, Equatable {
    /// The service name of the database.
    case serviceName(String)
    /// The system identifier (SID) of the database.
    ///
    /// - Note: Using a ``serviceName(_:)`` instead is recommended by Oracle.
    case sid(String)
}
