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

import NIOConcurrencyHelpers
import NIOCore

/// A Oracle SQL statement, that can be executed on a Oracle server.
/// Contains the raw sql string and bindings.
public struct OracleStatement: Sendable, Hashable {
    /// The statement's string.
    public var sql: String
    /// The statement's binds.
    public var binds: OracleBindings

    var keyword: String
    var isReturning: Bool
    var summary: String

    /// Creates an OracleStatement from a static SQL string and it's corresponding binds.
    /// - Parameters:
    ///   - sql: A static SQL string.
    ///   - binds: A collection of binds.
    ///
    /// The amount of binds must match the number of variables in the SQL string.
    ///
    /// ```swift
    /// let sql = "INSERT INTO my_table (content, initial_content, user_id) VALUES (:0, :0, :1)"
    /// var binds = OracleBindings(capacity: 2) // 2 due to :0 and :1 being the variables in the statement.
    /// binds.append("hello there")
    /// binds.append(1)
    /// let statement = OracleStatement(unsafeSQL: sql, binds: binds)
    /// ```
    public init(
        unsafeSQL sql: String,
        binds: OracleBindings = OracleBindings()
    ) {
        self.sql = sql
        self.binds = binds
        var parser = Parser(currentSQL: sql)
        try? parser.continueParsing(with: sql)
        self.keyword = parser.keyword
        self.isReturning = parser.isReturning
        self.summary = parser.summary.joined(separator: " ")
    }
}

extension OracleStatement: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self.sql = stringInterpolation.sql
        self.binds = stringInterpolation.binds
        self.keyword = stringInterpolation.parser.keyword
        self.isReturning = stringInterpolation.parser.isReturning
        self.summary = stringInterpolation.parser.summary.joined(separator: " ")
    }

    /// Creates a SQL statement from a _raw string_ without binds.
    /// - Parameter value: An unescaped String without binds.
    ///
    /// This initializer should only be used with static SQL statements that do not include variables.
    ///
    /// Here is an example of using the initializer, that might lead to SQL injection.
    ///
    /// ```swift
    /// let input = "user_input"
    /// let unsafeStatement = "INSERT INTO my_table (content) VALUES ('\(input)')"
    /// print(OracleStatement(stringLiteral: unsafeStatement))
    /// // -> INSERT INTO my_table (content) VALUES ('user_input') [ ]
    /// // Potential SQL injection on unsanitized input!
    /// ```
    ///
    /// - Warning: Use this initializer with extreme caution. String interpolations won't be recognized as such, and therefor binds are not created for them.
    ///            Prefer using ``StringInterpolation`` or ``init(unsafeSQL:binds:)`` whenever possible.
    ///
    /// There are multiple ways to prevent SQL injection.
    ///
    /// ## StringInterpolation
    ///
    /// To create a ``OracleStatement`` with ``StringInterpolation``, all you need to do is add a type annotation to the statement.
    /// This is the "magic" of string interpolation.
    ///
    /// ```swift
    /// let input = "user_input"
    /// let safeStatement: OracleStatement = "INSERT INTO my_table (content) VALUES (\(input))"
    /// print(safeStatement)
    /// // -> INSERT INTO my_table (content) VALUES (:0) [ **** ]
    /// // The variable did now get correctly recognized as a bind.
    /// ```
    ///
    /// ## Bind declaration
    ///
    /// Creating the binds manually is also possible, albeit more inconvinient.
    ///
    /// ```swift
    /// let rawStatement = "INSERT INTO my_table (content) VALUES (:0)"
    /// var binds = OracleBindings(capacity: 1)
    /// binds.append(input)
    /// print(OracleStatement(unsafeSQL: rawStatement, binds: binds))
    /// // -> INSERT INTO my_table (content) VALUES (:0) [ **** ]
    /// ```
    public init(stringLiteral value: String) {
        self.sql = value
        self.binds = OracleBindings()
        var parser = Parser(currentSQL: sql)
        try? parser.continueParsing(with: sql)
        self.keyword = parser.keyword
        self.isReturning = parser.isReturning
        self.summary = parser.summary.joined(separator: " ")
    }
}

extension OracleStatement {
    public struct StringInterpolation: StringInterpolationProtocol {
        public typealias StringLiteralType = String

        @usableFromInline
        var sql: String {
            mutating didSet {
                try? self.parser.continueParsing(with: self.sql)
            }
        }
        @usableFromInline
        var binds: OracleBindings

        var parser: Parser

        public init(literalCapacity: Int, interpolationCount: Int) {
            self.sql = ""
            self.binds = OracleBindings(capacity: interpolationCount)
            self.parser = Parser(currentSQL: "")
        }

        public mutating func appendLiteral(_ literal: String) {
            self.sql.append(contentsOf: literal)
        }

        @inlinable
        public mutating func appendInterpolation(
            _ value: some OracleThrowingDynamicTypeEncodable,
            context: OracleEncodingContext = .default
        ) throws {
            let bindName = "\(self.binds.count)"
            try self.binds.append(value, context: context, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation<T: OracleThrowingDynamicTypeEncodable>(
            _ value: T?,
            context: OracleEncodingContext = .default
        ) throws {
            let bindName = "\(self.binds.count)"
            switch value {
            case .none:
                self.binds.appendNull(T.defaultOracleType, bindName: bindName)
            case .some(let value):
                try self.binds
                    .append(value, context: context, bindName: bindName)
            }

            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation(
            _ value: some OracleDynamicTypeEncodable,
            context: OracleEncodingContext = .default
        ) {
            let bindName = "\(self.binds.count)"
            self.binds.append(value, context: context, bindName: bindName)
            self.sql.append(contentsOf: ":\(bindName)")
        }

        @inlinable
        public mutating func appendInterpolation(
            _ value: (some OracleDynamicTypeEncodable)?,
            context: OracleEncodingContext = .default
        ) {
            let bindName = "\(self.binds.count)"
            switch value {
            case .none:
                self.binds.appendNull(value?.oracleType, bindName: bindName)
            case .some(let value):
                self.binds.append(value, context: context, bindName: bindName)
            }

            self.sql.append(contentsOf: ":\(bindName)")
        }

        public mutating func appendInterpolation(_ value: some OracleRef) {
            if let bindName = self.binds.contains(ref: value) {
                self.sql.append(contentsOf: ":\(bindName)")
            } else {
                let bindName = "\(self.binds.count)"
                self.binds.append(value, bindName: bindName, isReturning: parser.isReturning)
                self.sql.append(contentsOf: ":\(bindName)")
            }
        }

        /// Adds a list of values as individual binds.
        ///
        /// ```swift
        /// let values = [15, 24, 33]
        /// let statement: OracleStatement = "SELECT id FROM my_table WHERE id IN (\(list: values))"
        /// print(statement.sql)
        /// // SELECT id FROM my_table WHERE id IN (:1, :2, :3)
        /// ```
        @inlinable
        public mutating func appendInterpolation(
            list: [some OracleDynamicTypeEncodable],
            context: OracleEncodingContext = .default
        ) {
            guard !list.isEmpty else { return }
            for value in list {
                self.appendInterpolation(value, context: context)
                self.sql.append(", ")
            }
            self.sql.removeLast(2)
        }

        /// Adds an unescaped string to the statement.
        /// - Parameter interpolation: The string that should be added to the statement.
        ///
        /// Useful when dynamically building a statement.
        ///
        /// ```swift
        /// let ascending: Bool = true
        /// let orderClause = if ascending {
        ///     "ASC"
        /// } else {
        ///     "DESC"
        /// }
        /// let statement: OracleStatement = "SELECT name FROM table ORDER BY id \(unescaped: orderClause)"
        /// print(statement)
        /// // -> SELECT name FROM table ORDER BY id ASC [ ]
        /// ```
        @inlinable
        public mutating func appendInterpolation(unescaped interpolation: String) {
            self.sql.append(contentsOf: interpolation)
        }
    }
}

extension OracleStatement: CustomStringConvertible {
    public var description: String {
        "\(self.sql) \(self.binds)"
    }
}

extension OracleStatement: CustomDebugStringConvertible {
    public var debugDescription: String {
        "OracleStatement(sql: \(String(describing: self.sql)), binds: \(String(reflecting: self.binds))"
    }
}

extension OracleStatement {
    struct Parser {
        private var sql: String

        var isReturning = false
        var keyword = ""
        var summary: [Substring] = []

        private var isDDL = false
        private var isDML = false

        private var position: String.Index
        private var lookaheadPosition: String.Index

        private var lastWasLetter = false
        private var letterStartPosition: String.Index
        private var currentKeyword: Substring = ""
        private var letterStartChar: Character = "_"
        private var lastChar: Character = "_"
        private var initialKeywordFound = false
        private var returningKeywordFound = false
        private var lastWasString = false

        private var tableNameFollowing = false
        private var lastWasTableName = false

        init(currentSQL: String) {
            self.sql = currentSQL
            self.position = sql.startIndex
            self.lookaheadPosition = sql.startIndex
            self.letterStartPosition = sql.startIndex
        }

        mutating func continueParsing(with newSQL: String) throws(OracleSQLError) {
            if newSQL.starts(with: self.sql) {
                self.sql = newSQL

                if self.isDDL { return }
            } else {
                self = .init(currentSQL: newSQL)
            }

            while self.position < self.sql.endIndex {
                self.lookaheadPosition = self.position
                let char = self.sql[self.lookaheadPosition]

                // look for certain keywords (initial keyword and the ones for
                // detecting DML returning statements
                let isLetter =
                    char.isLetter || (self.tableNameFollowing && (char == "_" || char == "." || char.isNumber))
                if isLetter && !self.lastWasLetter {
                    self.letterStartPosition = self.position
                    self.letterStartChar = char
                } else if !isLetter && lastWasLetter {
                    self.currentKeyword = self.sql[letterStartPosition..<self.position]
                    if !self.initialKeywordFound {
                        self.keyword = currentKeyword.uppercased()
                        self.initialKeywordFound = true
                        switch self.keyword {
                        case "INSERT", "UPDATE", "DELETE", "MERGE":
                            self.isDDL = false
                            self.isDML = true
                        case "CREATE", "ALTER", "DROP", "GRANT", "REVOKE", "ANALYZE", "AUDIT", "COMMENT", "TRUNCATE":
                            self.isDDL = true
                            self.isDML = false
                            return
                        default:
                            self.isDDL = false
                            self.isDML = false
                        }
                        self.summary.append(self.keyword[...])
                    } else if self.isDML && !self.returningKeywordFound && self.currentKeyword.count == 9
                        && (self.letterStartChar == "R" || self.letterStartChar == "r")
                    {
                        if self.currentKeyword.uppercased() == "RETURNING" {
                            self.returningKeywordFound = true
                        }
                    } else if self.returningKeywordFound && self.currentKeyword.count == 4
                        && (self.letterStartChar == "I" || self.letterStartChar == "i")
                    {
                        if self.currentKeyword.uppercased() == "INTO" {
                            self.isReturning = true
                        }
                    } else if self.tableNameFollowing {
                        self.tableNameFollowing = false
                        self.lastWasTableName = true
                        self.summary.append(self.currentKeyword)
                    } else {
                        switch currentKeyword.uppercased() {
                        case "FROM", "INTO", "UPDATE", "TABLE", "JOIN":
                            self.tableNameFollowing = true
                        default:
                            self.tableNameFollowing = false
                        }
                    }
                }

                if char == "," && self.lastWasTableName {
                    self.tableNameFollowing = true
                    self.lastWasTableName = false
                }

                // need to keep track of whether the last token parsed was a string
                // (exluding whitespace) as if the last token parsed was a string
                // a following colon is not a bind variable but a part of the JSON
                // constant syntax
                if char == "'" {
                    self.lastWasString = true
                    if self.lastChar == "q" || self.lastChar == "Q" {
                        try self.parseQString()
                    } else {
                        self.lookaheadPosition = self.sql.index(after: self.position)
                        let qualifier = try self.parseQuotedString(quoteType: char)
                        if self.tableNameFollowing {
                            self.tableNameFollowing = false
                            self.lastWasTableName = true
                            self.summary.append(qualifier)
                        }
                        self.sql.formIndex(before: &self.position)
                    }
                } else if !char.isWhitespace {
                    switch char {
                    case "-":
                        self.parseSingleLineComment()
                    case "/":
                        self.parseMultipleLineComment()
                    case "\"":
                        self.lookaheadPosition = self.sql.index(after: self.position)
                        let qualifier = try self.parseQuotedString(quoteType: char)
                        if self.tableNameFollowing {
                            self.tableNameFollowing = false
                            self.lastWasTableName = true
                            self.summary.append(qualifier)
                        }
                        self.sql.formIndex(before: &self.position)
                    case ":" where !self.lastWasString:
                        _ = self.parseBindName()
                    default:
                        break
                    }
                    self.lastWasString = false
                }

                // advance to next character and track previous character
                _ = self.sql.formIndex(&self.position, offsetBy: 1, limitedBy: self.sql.endIndex)
                self.lastWasLetter = isLetter
                self.lastChar = char
            }  // end while

            if self.tableNameFollowing && (self.lastChar.isLetter || self.lastChar.isNumber) {
                self.summary.append(self.sql[self.letterStartPosition..<self.sql.endIndex])
            }
        }

        mutating func parseQString() throws(OracleSQLError) {
            var sep: Character = "_"
            var inQString = false
            var exitingQString = false

            self.sql.formIndex(after: &self.lookaheadPosition)
            while self.lookaheadPosition < self.sql.endIndex {
                let char = self.sql[self.lookaheadPosition]
                if !inQString {
                    switch char {
                    case "[":
                        sep = "]"
                    case "{":
                        sep = "}"
                    case "<":
                        sep = ">"
                    case "(":
                        sep = ")"
                    default:
                        sep = char
                    }
                    inQString = true
                } else if !exitingQString && char == sep {
                    exitingQString = true
                } else if exitingQString {
                    if char == "'" {
                        self.position = self.lookaheadPosition
                        return
                    } else if char != sep {
                        exitingQString = false
                    }
                }
                self.sql.formIndex(after: &self.lookaheadPosition)
            }

            throw OracleSQLError.malformedStatement(reason: .missingEndingSingleQuote)
        }

        mutating func parseQuotedString(quoteType: Character) throws(OracleSQLError) -> Substring {
            var char: Character

            while self.lookaheadPosition < self.sql.endIndex {
                char = self.sql[self.lookaheadPosition]
                self.sql.formIndex(after: &self.lookaheadPosition)
                if char == quoteType {
                    defer { self.position = self.lookaheadPosition }
                    return self.sql[self.position..<self.lookaheadPosition]
                }
            }

            if quoteType == "'" {
                throw OracleSQLError.malformedStatement(reason: .missingEndingSingleQuote)
            } else {
                throw OracleSQLError.malformedStatement(reason: .missingEndingDoubleQuote)
            }
        }

        mutating func parseSingleLineComment() {
            var char: Character
            var inComment = false

            self.sql.formIndex(after: &self.lookaheadPosition)
            while self.lookaheadPosition < self.sql.endIndex {
                char = self.sql[self.lookaheadPosition]
                if !inComment {
                    if char != "-" {
                        return
                    }
                    inComment = true
                } else if char.isNewline {
                    break
                }
                self.sql.formIndex(after: &self.lookaheadPosition)
            }
            self.position = self.lookaheadPosition
        }

        mutating func parseMultipleLineComment() {
            var inComment = false
            var exitingComment = false

            self.lookaheadPosition = self.sql.index(after: self.position)
            while self.lookaheadPosition < self.sql.endIndex {
                let char = self.sql[self.lookaheadPosition]
                if !inComment {
                    if char != "*" {
                        break
                    }
                    inComment = true
                } else if char == "*" {
                    exitingComment = true
                } else if exitingComment {
                    if char == "/" {
                        self.position = self.lookaheadPosition
                        return
                    }
                    exitingComment = false
                }
                self.sql.formIndex(after: &self.lookaheadPosition)
            }
        }

        mutating func parseBindName() -> String? {
            var inBind = false
            var quotedName = false
            var digitsOnly = false
            var startPosition: String.Index = self.lookaheadPosition

            self.lookaheadPosition = self.sql.index(after: self.position)
            while self.lookaheadPosition < self.sql.endIndex {
                let char = self.sql[self.lookaheadPosition]
                if !inBind {
                    if char.isWhitespace {
                        self.sql.formIndex(after: &self.lookaheadPosition)
                        continue
                    } else if char == "\"" {
                        quotedName = true
                    } else if char.isNumber {
                        digitsOnly = true
                    } else if !char.isLetter {
                        break
                    }
                    inBind = true
                    startPosition = self.lookaheadPosition
                } else if digitsOnly && !char.isNumber {
                    self.position = self.sql.index(before: self.lookaheadPosition)
                    break
                } else if quotedName && char == "\"" {
                    self.position = self.lookaheadPosition
                    break
                } else if !digitsOnly && !quotedName && !char.isLetter && !char.isNumber && char != "_" && char != "$"
                    && char != "#"
                {
                    self.position = self.sql.index(before: self.lookaheadPosition)
                    break
                }
                self.sql.formIndex(after: &self.lookaheadPosition)
            }

            let bindName: String?
            if inBind {
                if quotedName {
                    self.sql.formIndex(after: &startPosition)
                    bindName = String(self.sql[startPosition..<self.lookaheadPosition])
                } else if digitsOnly {
                    bindName = String(self.sql[startPosition..<self.lookaheadPosition])
                } else {
                    bindName = self.sql[startPosition..<self.lookaheadPosition].uppercased()
                }
            } else {
                bindName = nil
            }
            return bindName
        }
    }
}
