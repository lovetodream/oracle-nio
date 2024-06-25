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

import OracleNIO
import XCTest

class XCTIntegrationTest: XCTestCase, IntegrationTest {
    var connection: OracleConnection!

    override func setUp() async throws {
        try await super.setUp()
        if env("SMOKE_TEST_ONLY") == "1" {
            throw XCTSkip("Skipping... running only smoke test suite")
        }
        XCTAssertTrue(isLoggingConfigured)
        self.connection = try await OracleConnection.test()
    }

    override func tearDown() async throws {
        try await self.connection?.close()
        try await super.tearDown()
    }
}
