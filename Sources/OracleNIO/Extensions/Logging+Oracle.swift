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

import Logging

@usableFromInline
enum OracleSQLConnection {}

extension OracleSQLConnection {
    @usableFromInline
    enum LoggerMetadataKey: String {
        case connectionID = "oraclesql_connection_id"
        case sessionID = "oraclesql_session_id"
        case connectionAction = "oraclesql_connection_action"
        case error = "oraclesql_error"
        case warning = "oraclesql_warning"
        case message = "oraclesql_message"
        case userEvent = "oraclesql_user_event"
    }
}

@usableFromInline
struct OracleSQLLoggingMetadata: ExpressibleByDictionaryLiteral {
    @usableFromInline
    typealias Key = OracleSQLConnection.LoggerMetadataKey
    @usableFromInline
    typealias Value = Logger.MetadataValue

    @usableFromInline
    var _baseRepresentation: Logger.Metadata

    @usableFromInline
    init(
        dictionaryLiteral elements:
            (OracleSQLConnection.LoggerMetadataKey, Logger.MetadataValue)...
    ) {
        let values = elements.lazy.map { (key, value) -> (String, Self.Value) in
            (key.rawValue, value)
        }

        self._baseRepresentation = Logger.Metadata(uniqueKeysWithValues: values)
    }

    @usableFromInline
    subscript(
        oracleLoggingKey loggingKey: OracleSQLConnection.LoggerMetadataKey
    ) -> Logger.Metadata.Value? {
        get {
            return self._baseRepresentation[loggingKey.rawValue]
        }
        set {
            self._baseRepresentation[loggingKey.rawValue] = newValue
        }
    }

    @inlinable
    var representation: Logger.Metadata {
        self._baseRepresentation
    }
}

extension Logger {

    @usableFromInline
    subscript(
        oracleMetadataKey metadataKey: OracleSQLConnection.LoggerMetadataKey
    ) -> Logger.Metadata.Value? {
        get {
            return self[metadataKey: metadataKey.rawValue]
        }
        set {
            self[metadataKey: metadataKey.rawValue] = newValue
        }
    }

}

extension Logger {

    /// See `Logger.trace(_:metadata:source:file:function:line:)`
    @usableFromInline
    func trace(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .trace,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }

    /// See `Logger.debug(_:metadata:source:file:function:line:)`
    @usableFromInline
    func debug(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .debug,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }

    /// See `Logger.info(_:metadata:source:file:function:line:)`
    @usableFromInline
    func info(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .info,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }

    /// See `Logger.notice(_:metadata:source:file:function:line:)`
    @usableFromInline
    func notice(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .notice,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }

    /// See `Logger.warning(_:metadata:source:file:function:line:)`
    @usableFromInline
    func warning(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .warning,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }

    /// See `Logger.error(_:metadata:source:file:function:line:)`
    @usableFromInline
    func error(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .error,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }

    /// See `Logger.critical(_:metadata:source:file:function:line:)`
    @usableFromInline
    func critical(
        _ message: @autoclosure () -> Logger.Message,
        metadata: @autoclosure () -> OracleSQLLoggingMetadata,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        self.log(
            level: .critical,
            message(), metadata: metadata().representation,
            source: source(), file: file, function: function, line: line
        )
    }
}
