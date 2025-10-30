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

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// An error that is thrown from the OracleClient.
///
/// - Warning: These errors should not be forwareded to the end user, as they may leak sensitive information.
public struct OracleSQLError: Sendable, Error {

    public struct Code: Sendable, Hashable, CustomStringConvertible {
        @usableFromInline
        enum Base: Sendable, Hashable {
            case clientClosesConnection
            case clientClosedConnection
            case failedToAddSSLHandler
            case failedToVerifyTLSCertificates
            case connectionError
            case messageDecodingFailure
            case nationalCharsetNotSupported
            case uncleanShutdown
            case unexpectedBackendMessage
            case server
            case statementCancelled
            case serverVersionNotSupported
            case sidNotSupported
            case missingParameter
            case unsupportedDataType
            case missingStatement
            case malformedStatement
        }

        @usableFromInline
        internal var base: Base

        @inlinable
        init(_ base: Base) {
            self.base = base
        }

        @inlinable
        public static var clientClosesConnection: Self {
            Self(.clientClosesConnection)
        }

        @inlinable
        public static var clientClosedConnection: Self {
            Self(.clientClosedConnection)
        }

        @inlinable
        public static var failedToAddSSLHandler: Self {
            Self(.failedToAddSSLHandler)
        }

        @inlinable
        public static var failedToVerifyTLSCertificates: Self {
            Self(.failedToVerifyTLSCertificates)
        }

        @inlinable
        public static var connectionError: Self {
            Self(.connectionError)
        }

        @inlinable
        public static var messageDecodingFailure: Self {
            Self(.messageDecodingFailure)
        }

        @inlinable
        public static var nationalCharsetNotSupported: Self {
            Self(.nationalCharsetNotSupported)
        }

        @inlinable
        public static var uncleanShutdown: Self {
            Self(.uncleanShutdown)
        }

        @inlinable
        public static var unexpectedBackendMessage: Self {
            Self(.unexpectedBackendMessage)
        }

        @inlinable
        public static var server: Self {
            Self(.server)
        }

        @inlinable
        public static var statementCancelled: Self {
            Self(.statementCancelled)
        }

        @inlinable
        public static var serverVersionNotSupported: Self {
            Self(.serverVersionNotSupported)
        }

        @inlinable
        public static var sidNotSupported: Self {
            Self(.sidNotSupported)
        }

        @inlinable
        public static var missingParameter: Self {
            Self(.missingParameter)
        }

        @inlinable
        public static var unsupportedDataType: Self {
            Self(.unsupportedDataType)
        }

        @inlinable
        public static var missingStatement: Self {
            Self(.missingStatement)
        }

        @inlinable
        public static var malformedStatement: Self {
            Self(.malformedStatement)
        }

        @inlinable
        public var description: String {
            switch self.base {
            case .clientClosesConnection:
                return "clientClosesConnection"
            case .clientClosedConnection:
                return "clientClosedConnection"
            case .failedToAddSSLHandler:
                return "failedToAddSSLHandler"
            case .failedToVerifyTLSCertificates:
                return "failedToVerifyTLSCertificates"
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
            case .statementCancelled:
                return "statementCancelled"
            case .serverVersionNotSupported:
                return "serverVersionNotSupported"
            case .sidNotSupported:
                return "sidNotSupported"
            case .missingParameter:
                return "missingParameter"
            case .unsupportedDataType:
                return "unsupportedDataType"
            case .missingStatement:
                return "missingStatement"
            case .malformedStatement:
                return "malformedStatement"
            }
        }
    }

    @usableFromInline
    /* private */ var backing: Backing

    @usableFromInline
    mutating func copyBackingStorageIfNecessary() {
        if !isKnownUniquelyReferenced(&self.backing) {
            self.backing = self.backing.copy()
        }
    }

    /// The ``OracleSQLError/Code`` code.
    @inlinable
    public internal(set) var code: Code {
        get { self.backing.code }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.code = newValue
        }
    }

    /// The info that was received from the server.
    @inlinable
    public internal(set) var serverInfo: ServerInfo? {
        get { self.backing.serverInfo }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.serverInfo = newValue
        }
    }

    /// The underlying error.
    @inlinable
    public internal(set) var underlying: Error? {
        get { self.backing.underlying }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.underlying = newValue
        }
    }

    /// The file in which the Oracle operation was triggered that failed.
    @inlinable
    public internal(set) var file: String? {
        get { self.backing.file }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.file = newValue
        }
    }

    /// The line in which the Oracle operation was triggered that failed.
    @inlinable
    public internal(set) var line: Int? {
        get { self.backing.line }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.line = newValue
        }
    }

    /// The statement that failed.
    @inlinable
    public internal(set) var statement: OracleStatement? {
        get { self.backing.statement }
        set {
            self.copyBackingStorageIfNecessary()
            self.backing.statement = newValue
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

    @usableFromInline
    init(
        code: Code, statement: OracleStatement,
        file: String? = nil, line: Int? = nil
    ) {
        self.backing = .init(code: code)
        self.statement = statement
        self.file = file
        self.line = line
    }

    @usableFromInline
    init(code: Code) {
        self.backing = .init(code: code)
    }

    @usableFromInline
    /* private */ final class Backing: @unchecked Sendable {
        @usableFromInline
        /* fileprivate */ var code: Code
        @usableFromInline
        /* fileprivate */ var serverInfo: ServerInfo?
        @usableFromInline
        /* fileprivate */ var underlying: Error?
        @usableFromInline
        /* fileprivate */ var file: String?
        @usableFromInline
        /* fileprivate */ var line: Int?
        @usableFromInline
        /* fileprivate */ var statement: OracleStatement?
        fileprivate var backendMessage: OracleBackendMessage?

        @inlinable
        init(code: Code) {
            self.code = code
        }

        func copy() -> Self {
            let new = Self.init(code: self.code)
            new.serverInfo = self.serverInfo
            new.underlying = self.underlying
            new.file = self.file
            new.line = self.line
            new.statement = self.statement
            new.backendMessage = self.backendMessage
            return new
        }
    }

    public struct ServerInfo: Sendable, CustomStringConvertible {
        @usableFromInline
        let underlying: BackendError

        /// The error number/identifier.
        @inlinable
        public var number: UInt32 {
            self.underlying.number
        }

        /// The error message, typically prefixed with `ORA-` & ``number``.
        @inlinable
        public var message: String? {
            self.underlying.message
        }

        /// The amount of rows affected by the operation.
        ///
        /// In most cases, this is `0`, although it is posslbe that a statement
        /// (e.g. ``OracleConnection/execute(_:binds:encodingContext:options:logger:file:line:)``
        /// executes some if its statements successfully, while others might have failed. In this case, `affectedRows` shows
        /// how many operations have been successful.
        ///
        ///
        /// Defaults to `0`.
        @inlinable
        public var affectedRows: Int {
            self.underlying.rowCount
        }

        @inlinable
        init(_ underlying: BackendError) {
            self.underlying = underlying
        }

        @inlinable
        public var description: String {
            self.message ?? "ORA-\(String(self.number, padding: 5))"
        }
    }

    public struct BatchError: Sendable {
        @usableFromInline
        let base: OracleError

        /// The index of the statement in which the error occurred.
        @inlinable
        public var statementIndex: Int {
            self.base.offset
        }

        /// The error number/identifier.
        @inlinable
        public var number: Int {
            self.base.code
        }

        /// The error message, typically prefixed with `ORA-` & ``number``.
        @inlinable
        public var message: String {
            self.base.message
        }

        @usableFromInline
        init(_ error: OracleError) {
            self.base = error
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

    @inlinable
    static func clientClosesConnection(underlying: Error?) -> OracleSQLError {
        var error = OracleSQLError(code: .clientClosesConnection)
        error.underlying = underlying
        return error
    }

    @inlinable
    static func clientClosedConnection(underlying: Error?) -> OracleSQLError {
        var error = OracleSQLError(code: .clientClosedConnection)
        error.underlying = underlying
        return error
    }

    @inlinable
    static var uncleanShutdown: OracleSQLError {
        OracleSQLError(code: .uncleanShutdown)
    }

    @inlinable
    static func failedToAddSSLHandler(underlying: Error) -> OracleSQLError {
        var error = OracleSQLError(code: .failedToAddSSLHandler)
        error.underlying = underlying
        return error
    }

    @inlinable
    static var failedToVerifyTLSCertificates: OracleSQLError {
        OracleSQLError(code: .failedToVerifyTLSCertificates)
    }

    @inlinable
    static func connectionError(underlying: Error) -> OracleSQLError {
        var error = OracleSQLError(code: .connectionError)
        error.underlying = underlying
        return error
    }

    @inlinable
    static func messageDecodingFailure(
        _ error: OracleMessageDecodingError
    ) -> OracleSQLError {
        var new = OracleSQLError(code: .messageDecodingFailure)
        new.underlying = error
        return new
    }

    @inlinable
    static func server(
        _ error: BackendError
    ) -> OracleSQLError {
        var new = OracleSQLError(code: .server)
        new.serverInfo = .init(error)
        return new
    }

    @inlinable
    static var nationalCharsetNotSupported: OracleSQLError {
        OracleSQLError(code: .nationalCharsetNotSupported)
    }

    @inlinable
    static var statementCancelled: OracleSQLError {
        OracleSQLError(code: .statementCancelled)
    }

    @inlinable
    static var serverVersionNotSupported: OracleSQLError {
        OracleSQLError(code: .serverVersionNotSupported)
    }

    @inlinable
    static var sidNotSupported: OracleSQLError {
        OracleSQLError(code: .sidNotSupported)
    }

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

    @inlinable
    static var unsupportedDataType: OracleSQLError {
        OracleSQLError(code: .unsupportedDataType)
    }

    @inlinable
    static var missingStatement: OracleSQLError {
        OracleSQLError(code: .missingStatement)
    }

    @inlinable
    static func malformedStatement(reason: MalformedStatementError) -> OracleSQLError {
        var error = OracleSQLError(code: .missingStatement)
        error.underlying = reason
        return error
    }
}

extension OracleSQLError: CustomStringConvertible {
    public var description: String {
        var result = #"OracleSQLError(code: \#(self.code)"#

        if let serverInfo = self.serverInfo?.underlying {
            result.append(", serverInfo: ")
            result.append("BackendError(")
            result.append("number: \(String(reflecting: serverInfo.number))")
            result.append(", message: \(String(reflecting: serverInfo.message))")
            result.append(", position: \(String(reflecting: serverInfo.position))")
            result.append(", cursorID: \(String(reflecting: serverInfo.cursorID))")
            result.append(", rowCount: \(String(reflecting: serverInfo.rowCount))")
            result.append(", rowID: \(String(reflecting: serverInfo.rowID))")
            result.append(")")
        }

        if let backendMessage = self.backendMessage {
            result.append(", backendMessage: \(String(reflecting: backendMessage))")
        }

        if let underlying = self.underlying {
            result.append(", underlying: \(String(reflecting: underlying))")
        }

        if self.file != nil {
            result.append(", triggeredFromRequestInFile: ********")
            if self.line != nil {
                result.append(", line: ********")
            }
        }

        if self.statement != nil {
            result.append(", statement: ********")
        }

        result.append(") ")

        result.append(
            """
            - Some information has been reducted to prevent accidental leakage of \
            sensitive data. For additional debugging details, use `String(reflecting: error)`.
            """)

        return result
    }
}

extension OracleSQLError: CustomDebugStringConvertible {
    public var debugDescription: String {
        var result = #"OracleSQLError(code: \#(self.code)"#

        if let serverInfo = self.serverInfo?.underlying {
            result.append(", serverInfo: ")
            result.append("BackendError(")
            result.append("number: \(String(reflecting: serverInfo.number))")
            result.append(", message: \(String(reflecting: serverInfo.message))")
            result.append(", position: \(String(reflecting: serverInfo.position))")
            result.append(", cursorID: \(String(reflecting: serverInfo.cursorID))")
            result.append(", rowCount: \(String(reflecting: serverInfo.rowCount))")
            result.append(", rowID: \(String(reflecting: serverInfo.rowID))")
            result.append(")")
        }

        if let backendMessage {
            result.append(", backendMessage: \(String(reflecting: backendMessage))")
        }

        if let underlying {
            result.append(", underlying: \(String(reflecting: underlying))")
        }

        if let file {
            result.append(", triggeredFromRequestInFile: \(file)")
            if let line = self.line {
                result.append(", line: \(line)")
            }
        }

        if let statement {
            result.append(", statement: \(String(reflecting: statement))")
        }

        result.append(")")

        return result
    }
}


// MARK: - Error Implementations -

extension OracleSQLError {

    struct MissingParameterError: Error {
        var expectedKey: String
        var actualParameters: OracleBackendMessage.Parameter
    }

    @usableFromInline
    enum MalformedStatementError: Error {
        case missingEndingSingleQuote
        case missingEndingDoubleQuote
    }

    enum ConnectionError: Error {
        case invalidServerResponse
    }

}
