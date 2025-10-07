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
import OracleNIO
import Testing

@Suite(.disabled(if: env("SMOKE_TEST_ONLY") == "1"), .timeLimit(.minutes(5))) final class XMLTests: IntegrationTest {
    let connection: OracleConnection

    init() async throws {
        #expect(isLoggingConfigured)
        self.connection = try await OracleConnection.test()
    }

    deinit {
        #expect(throws: Never.self, performing: { try self.connection.syncClose() })
    }

    @Test func xmlType() async throws {
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
        for try await (id, xml, lob) in stream.decode((Int, OracleXML, String).self) {
            currentID += 1
            #expect(id == currentID)
            #expect(lob.hasPrefix("<?xml version=\"1.0\"?>\n<records>"))
            #expect(lob.hasSuffix("</records>\n"))
            #expect(xml.description.hasPrefix("<?xml version=\"1.0\"?>\n<records>"))
            #expect(xml.description.hasSuffix("</records>\n"))
        }
        #expect(currentID == 100)
    }
}
