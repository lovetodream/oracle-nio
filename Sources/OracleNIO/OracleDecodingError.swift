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

public struct OracleDecodingError: Error, Equatable {
    public struct Code: Hashable, Error, CustomStringConvertible {
        enum Base {
            case missingData
            case typeMismatch
            case decimalPointFound
            case signedIntegerFound
            case failure
        }

        var base: Base

        init(_ base: Base) {
            self.base = base
        }

        public static let missingData = Self(.missingData)
        public static let typeMismatch = Self(.typeMismatch)
        /// Occurs if you're trying to decode a `FixedWidthInteger`, but the database sent a
        /// `BinaryFloatingPoint` with a decimal point.
        ///
        /// - Note: `oracle-nio` does not make assumptions on how to round
        ///         `BinaryFloatingPoint` to  `FixedWithInteger`. So we rather fail,
        ///         instead of causing undefined behavior.
        ///
        /// - Tip: To fix this error you should either decode as `Float`, `Double` or `Decimal`,
        ///      depending on your needs.
        public static let decimalPointFound = Self(.typeMismatch)
        /// Occurs if you're trying to decode a negative signed `FixedWithInteger` to an
        /// `UnsignedInteger`.
        ///
        /// - Note: `oracle-nio` does not make assumption on how to handle negative values.
        ///         Instead of causing Integer overflow or crashing to program, we throw an error.
        ///
        /// - Tip: To fix this error, either change to an appropriate `SignedInteger` or handle such
        ///      cases within the database call.
        public static let signedIntegerFound = Self(.signedIntegerFound)
        public static let failure = Self(.failure)

        public var description: String {
            switch self.base {
            case .missingData:
                return "missingData"
            case .typeMismatch:
                return "typeMismatch"
            case .decimalPointFound:
                return "decimalPointFound"
            case .signedIntegerFound:
                return "signedIntegerFound"
            case .failure:
                return "failure"
            }
        }
    }

    /// The decoding error code.
    public let code: Code

    /// The cell's column name for which the decoding failed.
    public let columnName: String
    /// The cell's column index for which the decoding failed.
    public let columnIndex: Int
    /// The swift type the cell should have been decoded into.
    public let targetType: Any.Type
    /// The cell's oracle data type for which the decoding failed.
    public let oracleType: OracleDataType
    /// A copy of the cell data which was attempted to be decoded.
    public let oracleData: ByteBuffer?

    /// The file the decoding was attempted in.
    public let file: String
    /// The line the decoding was attempted in.
    public let line: Int

    @usableFromInline
    init(
        code: Code,
        columnName: String,
        columnIndex: Int,
        targetType: Any.Type,
        oracleType: OracleDataType,
        oracleData: ByteBuffer?,
        file: String,
        line: Int
    ) {
        self.code = code
        self.columnName = columnName
        self.columnIndex = columnIndex
        self.targetType = targetType
        self.oracleType = oracleType
        self.oracleData = oracleData
        self.file = file
        self.line = line
    }

    public static func == (lhs: OracleDecodingError, rhs: OracleDecodingError) -> Bool {
        return lhs.code == rhs.code
            && lhs.columnName == rhs.columnName
            && lhs.columnIndex == rhs.columnIndex
            && lhs.targetType == rhs.targetType
            && lhs.oracleType == rhs.oracleType
            && lhs.oracleData == rhs.oracleData
            && lhs.file == rhs.file
            && lhs.line == rhs.line
    }

}

extension OracleDecodingError: CustomStringConvertible {
    public var description: String {
        var result = #"OracleDecodingError(code: \#(self.code)"#

        result.append(#", columnName: \#(String(repeating: "*", count: self.columnName.count))"#)
        result.append(#", columnIndex: \#(self.columnIndex)"#)
        result.append(#", targetType: \#(String(reflecting: self.targetType))"#)
        result.append(#", oracleType: \#(self.oracleType)"#)
        if let oracleData {
            result.append(#", oracleData: \#(String(reflecting: oracleData))"#)
        }
        result.append(") ")

        result.append(
            """
            - Some information has been reducted to prevent accidental leakage of \
            sensitive data. For additional debugging details, use \
            `String(reflecting: error)`.
            """)

        return result
    }
}

extension OracleDecodingError: CustomDebugStringConvertible {
    public var debugDescription: String {
        var result = #"OracleDecodingError(code: \#(self.code)"#

        result.append(#", columnName: \#(String(reflecting: self.columnName))"#)
        result.append(#", columnIndex: \#(self.columnIndex)"#)
        result.append(#", targetType: \#(String(reflecting: self.targetType))"#)
        result.append(#", oracleType: \#(self.oracleType)"#)
        if let oracleData {
            result.append(#", oracleData: \#(String(reflecting: oracleData))"#)
        }
        result.append(#", file: \#(self.file)"#)
        result.append(#", line: \#(self.line)"#)
        result.append(")")

        return result
    }
}
