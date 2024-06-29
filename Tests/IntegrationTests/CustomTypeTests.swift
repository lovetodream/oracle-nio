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
import XCTest

@testable import OracleNIO

final class CustomTypeTests: XCTIntegrationTest {
    func testCustomType() async throws {
        // create types and scheme
        _ = try? await self.connection.execute(
            """
            create type udt_SubObject as object (
            SubNumberValue                      number,
            SubStringValue                      varchar2(60)
            )
            """)
        _ = try? await self.connection.execute(
            """
            create type udt_ObjectArray as
            varray(10) of udt_SubObject
            """)
        _ = try? await self.connection.execute(
            """
            create type udt_Object as object (
            NumberValue                         number,
            StringValue                         varchar2(60),
            FixedCharValue                      char(10),
            NStringValue                        nvarchar2(60),
            NFixedCharValue                     nchar(10),
            RawValue                            raw(16),
            IntValue                            integer,
            SmallIntValue                       smallint,
            RealValue                           real,
            DoublePrecisionValue                double precision,
            FloatValue                          float,
            BinaryFloatValue                    binary_float,
            BinaryDoubleValue                   binary_double,
            DateValue                           date,
            TimestampValue                      timestamp,
            TimestampTZValue                    timestamp with time zone,
            TimestampLTZValue                   timestamp with local time zone,
            CLOBValue                           clob,
            NCLOBValue                          nclob,
            BLOBValue                           blob,
            SubObjectValue                      udt_SubObject,
            SubObjectArray                      udt_ObjectArray
            )
            """)
        _ = try? await self.connection.execute("create type udt_Array as varray(10) of number")
        _ = try? await self.connection.execute("drop table TestObjects")
        try await self.connection.execute(
            """
            create table TestObjects (
            IntCol                              number(9) not null,
            ObjectCol                           udt_Object,
            ArrayCol                            udt_Array
            )
            """)

        // insert samples
        try await self.connection.execute(
            """
            insert into TestObjects values (1,
            udt_Object(1, 'First row', 'First', 'N First Row', 'N First',
            '52617720446174612031', 2, 5, 12.125, 0.5, 12.5, 25.25, 50.125,
            to_date(20070306, 'YYYYMMDD'),
            to_timestamp('20080912 16:40:00', 'YYYYMMDD HH24:MI:SS'),
            to_timestamp_tz('20091013 17:50:00 00:00',
                    'YYYYMMDD HH24:MI:SS TZH:TZM'),
            to_timestamp_tz('20101114 18:55:00 00:00',
                    'YYYYMMDD HH24:MI:SS TZH:TZM'),
            'Short CLOB value', 'Short NCLOB Value',
            utl_raw.cast_to_raw('Short BLOB value'),
            udt_SubObject(11, 'Sub object 1'),
            udt_ObjectArray(
                    udt_SubObject(5, 'first element'),
                    udt_SubObject(6, 'second element'))),
            udt_Array(5, 10, null, 20))
            """)
        try await self.connection.execute(
            """
            insert into TestObjects values (2, null,
            udt_Array(3, null, 9, 12, 15))
            """)
        try await self.connection.execute(
            """
            insert into TestObjects values (3,
            udt_Object(3, 'Third row', 'Third', 'N Third Row', 'N Third',
            '52617720446174612033', 4, 10, 6.5, 0.75, 43.25, 86.5, 192.125,
            to_date(20070621, 'YYYYMMDD'),
            to_timestamp('20071213 07:30:45', 'YYYYMMDD HH24:MI:SS'),
            to_timestamp_tz('20170621 23:18:45 00:00',
                    'YYYYMMDD HH24:MI:SS TZH:TZM'),
            to_timestamp_tz('20170721 08:27:13 00:00',
                    'YYYYMMDD HH24:MI:SS TZH:TZM'),
            'Another short CLOB value', 'Another short NCLOB Value',
            utl_raw.cast_to_raw('Yet another short BLOB value'),
            udt_SubObject(13, 'Sub object 3'),
            udt_ObjectArray(
                    udt_SubObject(10, 'element #1'),
                    udt_SubObject(20, 'element #2'),
                    udt_SubObject(30, 'element #3'),
                    udt_SubObject(40, 'element #4'))), null)
            """)

        // actual test
        let stream = try await self.connection.execute(
            """
            select IntCol, ObjectCol, ArrayCol
                from TestObjects
                order by IntCol
            """)
        var iterator =
            stream
            .decode((Int, CustomOracleObject, CustomOracleObject).self)
            .makeAsyncIterator()
        var id = 0
        while let row = try await iterator.next() {
            id += 1
            XCTAssertEqual(row.0, id)
        }
        XCTAssertEqual(id, 3)
    }
}

struct CustomOracleObject: OracleDecodable {
    let typeOID: ByteBuffer
    let oid: ByteBuffer
    let snapshot: ByteBuffer
    let data: ByteBuffer

    init(
        typeOID: ByteBuffer,
        oid: ByteBuffer,
        snapshot: ByteBuffer,
        data: ByteBuffer
    ) {
        self.typeOID = typeOID
        self.oid = oid
        self.snapshot = snapshot
        self.data = data
    }

    static func _decodeRaw<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer?,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws -> CustomOracleObject {
        guard var buffer else {
            throw OracleDecodingError.Code.missingData
        }
        return try self.init(from: &buffer, type: type, context: context)
    }

    init<JSONDecoder: OracleJSONDecoder>(
        from buffer: inout ByteBuffer,
        type: OracleDataType,
        context: OracleDecodingContext<JSONDecoder>
    ) throws {
        switch type {
        case .object:
            let typeOID =
                if try buffer.throwingReadUB4() > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            let oid =
                if try buffer.throwingReadUB4() > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            let snapshot =
                if try buffer.throwingReadUB4() > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            buffer.skipUB2()  // version
            let dataLength = try buffer.throwingReadUB4()
            buffer.skipUB2()  // flags
            let data =
                if dataLength > 0 {
                    try buffer.throwingReadOracleSpecificLengthPrefixedSlice()
                } else { ByteBuffer() }
            self.init(typeOID: typeOID, oid: oid, snapshot: snapshot, data: data)
        default:
            throw OracleDecodingError.Code.typeMismatch
        }
    }
}
