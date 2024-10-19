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

#if compiler(>=6.0)
    import Testing

    @testable import OracleNIO

    @Suite
    struct OracleSQLErrorTests {
        @Test
        func serverInfoDescription() {
            let errorWithMessage = OracleSQLError.ServerInfo(
                .init(
                    number: 1017,
                    isWarning: false,
                    message: "ORA-01017: invalid credential or not authorized; logon denied\n",
                    batchErrors: []
                ))
            #expect(
                String(describing: errorWithMessage) == "ORA-01017: invalid credential or not authorized; logon denied")
            let errorWithoutMessage = OracleSQLError.ServerInfo(
                .init(
                    number: 1017,
                    isWarning: false,
                    batchErrors: []
                ))
            #expect(String(describing: errorWithoutMessage) == "ORA-1017")
        }
    }
#endif
