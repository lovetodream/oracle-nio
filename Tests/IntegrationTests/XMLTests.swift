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

final class XMLTests: XCTIntegrationTest {
    func testXMLType() async throws {
        _ = try? await connection.execute("DROP TABLE testxml")
        try await connection.execute(
            """
            create table TestXML (
            IntCol                              number(9) not null,
            XMLCol                              xmltype not null
            )
            """)
        try await connection.execute(
            """
            begin
            for i in 1..100 loop
            insert into TestXML
            values (i, '<?xml version="1.0"?><records>' ||
                    dbms_random.string('x', 1024) || '</records>');
            end loop;
            end;
            """)
        let stream = try await connection.execute(
            "SELECT intcol, xmlcol, extract(xmlcol, '/').getclobval() FROM testxml ORDER BY intcol"
        )
        var currentID = 0
        for try await (id, value, lob) in stream.decode((Int, CustomOracleObject, String).self) {
            currentID += 1
            XCTAssertEqual(id, currentID)
            var buffer = value.data
            let xml = try OracleXML(from: &buffer)
            XCTAssert(lob.hasPrefix("<?xml version=\"1.0\"?>\n<records>"))
            XCTAssert(lob.hasSuffix("</records>\n"))
            switch xml.value {
            case .string(let value):
                XCTAssert(value.hasPrefix("<?xml version=\"1.0\"?>\n<records>"))
                XCTAssert(value.hasSuffix("</records>\n"))
            }
        }
        XCTAssertEqual(currentID, 100)
    }
}

struct OracleXML {
    enum Value {
        case string(String)
    }
    let value: Value

    init(from buffer: inout ByteBuffer) throws {
        var decoder = Decoder(buffer: buffer)
        self = try decoder.decode()
    }

    init(_ value: String) {
        self.value = .string(value)
    }

    enum Error: Swift.Error {
        case unexpectedXMLType(flag: UInt32)
    }

    struct Decoder {
        var buffer: ByteBuffer

        mutating func decode() throws -> OracleXML {
            _ = try readHeader()
            buffer.moveReaderIndex(forwardBy: 1)  // xml version
            let xmlFlag = try buffer.throwingReadInteger(as: UInt32.self)
            if (xmlFlag & Constants.TNS_XML_TYPE_FLAG_SKIP_NEXT_4) != 0 {
                buffer.moveReaderIndex(forwardBy: 4)
            }
            var slice = buffer.slice()
            if (xmlFlag & Constants.TNS_XML_TYPE_STRING) != 0 {
                return .init(slice.readString(length: slice.readableBytes)!)
            } else if (xmlFlag & Constants.TNS_XML_TYPE_LOB) != 0 {
                assertionFailure("LOB not yet supported")
            }
            throw Error.unexpectedXMLType(flag: xmlFlag)
        }

        mutating func readHeader() throws -> (flags: UInt8, version: UInt8) {
            let flags = try buffer.throwingReadInteger(as: UInt8.self)
            let version = try buffer.throwingReadInteger(as: UInt8.self)
            try skipLength()
            if (flags & Constants.TNS_OBJ_NO_PREFIX_SEG) != 0 {
                return (flags, version)
            }
            let prefixSegmentLength = try self.readLength()
            buffer.moveReaderIndex(forwardBy: Int(prefixSegmentLength))
            return (flags, version)
        }

        mutating func readLength() throws -> UInt32 {
            let shortLength = try buffer.throwingReadInteger(as: UInt8.self)
            if shortLength == Constants.TNS_LONG_LENGTH_INDICATOR {
                return try buffer.throwingReadInteger()
            }
            return UInt32(shortLength)
        }

        mutating func skipLength() throws {
            if try buffer.throwingReadInteger(as: UInt8.self) == Constants.TNS_LONG_LENGTH_INDICATOR
            {
                buffer.moveReaderIndex(forwardBy: 4)
            }
        }
    }
}
