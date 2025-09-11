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

import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct RowIDTests {
    @Test func description() {
        let id = RowID(
            rba: 76402,
            partitionID: 15,
            blockNumber: 733,
            slotNumber: 0
        )
        #expect(id?.description == "AAASpyAAPAAAALdAAA")
    }
}
