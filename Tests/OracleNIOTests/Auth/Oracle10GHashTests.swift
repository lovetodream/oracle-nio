//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2026 Timo Zacherl and the OracleNIO project authors
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

@Suite("Oracle 10G password hash") struct Oracle10GHashTests {
    @Test("Canonical passlib test vector: username/password -> 872805F3F4C83365")
    func canonicalVector() {
        let hash = Oracle10GHash.compute(username: "username", password: "password")
        #expect(hash.hexString.uppercased() == "872805F3F4C83365")
    }

    @Test("Demo SCOTT/TIGER vector matches public reference")
    func scottTiger() {
        let hash = Oracle10GHash.compute(username: "SCOTT", password: "TIGER")
        #expect(hash.hexString.uppercased() == "F894844C34402B67")
    }

    @Test("Lowercase input produces same hash as uppercase (case-insensitive 10G)")
    func caseInsensitive() {
        let upper = Oracle10GHash.compute(username: "SCOTT", password: "TIGER")
        let lower = Oracle10GHash.compute(username: "scott", password: "tiger")
        let mixed = Oracle10GHash.compute(username: "Scott", password: "TiGeR")
        #expect(upper == lower)
        #expect(upper == mixed)
    }

    @Test("Empty password produces a deterministic hash, no crash")
    func emptyPassword() {
        let hash = Oracle10GHash.compute(username: "USER", password: "")
        #expect(hash.count == 8)
    }

    @Test("Output is always exactly 8 bytes")
    func outputLength() {
        let inputs: [(String, String)] = [
            ("a", "b"),
            ("longusername123", "longpassword456"),
            ("X", "Y"),
            ("SYSTEM", "MANAGER"),
        ]
        for (user, pass) in inputs {
            #expect(Oracle10GHash.compute(username: user, password: pass).count == 8)
        }
    }
}
