//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
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

@Suite struct ConfigurationTests {
    @Test func sanitization() {
        var config = OracleConnection.Configuration(
            host: "127.0.0.1",
            service: .serviceName("sn"),
            username: "us",
            password: "pw"
        )
        config.connectionIDPrefix = "a()bce="
        config.programName = "x=0y"
        config.machineName = "192.168.1.1(mypc)"
        config.processUsername = "sha=(full)"
        #expect(config.connectionIDPrefix == "a??bce?")
        #expect(config.programName == "x?0y")
        #expect(config.machineName == "192.168.1.1?mypc?")
        #expect(config.processUsername == "sha??full?")
    }
}
