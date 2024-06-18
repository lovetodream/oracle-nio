//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Describes the metadata of a table's column on an Oracle server.
public struct OracleColumn: Hashable, Sendable {
    /// The field name.
    public let name: String

    /// The object ID of the field's data type.
    @usableFromInline
    var dataType: OracleDataType

    /// The data type size.
    @usableFromInline
    var dataTypeSize: UInt32

    /// The number of significant digits. Oracle guarantees the portability of numbers with precision
    /// ranging from 1 to 38.
    ///
    /// - NOTE: This is only relevant for the datatype `NUMBER`.
    ///         For reference: https://docs.oracle.com/cd/B28359_01/server.111/b28318/datatype.htm#CNCPT1832
    @usableFromInline
    let precision: Int16

    /// The number of digits to the right (positive) or left (negative) of the decimal point. The scale can
    /// range from -84 to 127.
    ///
    /// - NOTE: This is only relevant for the datatype `NUMBER`.
    ///         For reference: https://docs.oracle.com/cd/B28359_01/server.111/b28318/datatype.htm#CNCPT1832
    @usableFromInline
    let scale: Int16

    /// The maximum number of bytes a value is allowed to take on the server side.
    @usableFromInline
    var bufferSize: UInt32

    /// Indicates if values for the column are `Optional`.
    @usableFromInline
    let nullsAllowed: Bool

    /// The current scheme of a custom datatype.
    let typeScheme: String?
    /// The name of a custom datatype.
    let typeName: String?

    /// The schema of the [SQL domain](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/create-domain.html#GUID-17D3A9C6-D993-4E94-BF6B-CACA56581F41) associated with the fetched column.
    ///
    /// `nil`, if there is no SQL domain.
    /// SQL domains require at least Oracle Database 23ai.
    let domainSchema: String?
    /// The name of the [SQL domain](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/create-domain.html#GUID-17D3A9C6-D993-4E94-BF6B-CACA56581F41)
    /// associated with the fetched column.
    ///
    /// `nil`, if there is no SQL domain.
    /// SQL domains require at least Oracle Database 23ai.
    let domainName: String?
    /// The [annotations](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/annotations_clause.html#GUID-1AC16117-BBB6-4435-8794-2B99F8F68052) associated with the fetched column.
    ///
    /// Annotations require at least Oracle Database 23ai.
    let annotations: [String: String]

    let vectorDimensions: UInt32?
    let vectorFormat: UInt8?
}
