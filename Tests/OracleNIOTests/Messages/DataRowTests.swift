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
    import NIOCore
    import Testing

    @testable import OracleNIO

    @Suite struct DataRowTests {
        @Test func columnWithNullIndicator() {
            let buffer = ByteBuffer(bytes: [Constants.TNS_NULL_LENGTH_INDICATOR])
            let row = DataRow(columnCount: 1, bytes: buffer)
            for column in row {
                #expect(column == .none)
            }
        }
    }
#endif
