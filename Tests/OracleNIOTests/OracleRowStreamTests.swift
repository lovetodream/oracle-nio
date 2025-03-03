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
import NIOPosix
import Testing

@testable import OracleNIO

@Suite struct OracleRowStreamTests {
    @Test func emptyStream() {
        let stream = OracleRowStream(source: .noRows(.success(())))

        #expect(throws: Never.self, performing: {
            let result = try stream.all().wait()
            #expect(result == [])
        })
    }

    @Test func asyncEmptyStream() async throws {
        let stream = OracleRowStream(source: .noRows(.success(())))

        let rows = try await stream.asyncSequence().collect()
        #expect(rows == [])
    }

}
#endif
