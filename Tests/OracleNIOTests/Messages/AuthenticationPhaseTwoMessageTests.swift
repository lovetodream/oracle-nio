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
import NIOTestUtils
import Testing

@testable import OracleNIO

@Suite(.timeLimit(.minutes(5))) struct AuthenticationPhaseTwoMessageTests {
    let testPrivateKey = """
        -----BEGIN PRIVATE KEY-----
        MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDspXJrIBJ9KMDY
        6st8D5r7uVw1c2f4K0eU2NOjsbLG7OV1oSowmnz7VuaRH340ngOLGJ0kxA3ukykT
        3fzgbXuHh+fbP4yO8bfKs6RuCNDgsIufd55jhGrDV7KaGfaN34zcCUzysU7L1iFM
        MdLwiDLsLGz5FWSgUdIphJJXoMijrhQaxbgd/NZpLfITlHFI1rdaLX7XO8v9fTnK
        giefSKyNXf/17PTE86KdeIbG9boVYD+8jtXj/ud9ZNgIbbThH+/o+Zr6f2UF+DwX
        4GMm68QWoyZ5Z26A5nCUFl3G1Sl/0ZANEI0ZMEOLtL8CsByj9qDvupKmpmxh79Pb
        7MsMt5m9AgMBAAECggEAISTvCJf+Xu9FS1xfUanx4A3PH2Fhj32oUe2ofsXVr0zg
        un/vI82PcbhzJKJPj9kNz/6Li+m1tdOArlqqH1jWM15Sl/+nlSG/xzEv94VelAnG
        FHixg2i5d1CiIDlAshA8b1kSIO+6hIwiL8TOsYex8igqvxxC8r1i/ROnV4SadWoY
        TkDjKkn0oeGeyCneI8oShBid/XlULaDkaasrorBbpDkJMri7tk9Aao998UTXbaPv
        EAKQJzt4mcpiT6SMlSttuShjXy4IVVqjxqF4zaB7Ss0rIkhQcpnFuZmRkwjAY0Op
        lW4lrl2ZL6GrpGkxTJ6haceBBmLJM32I5YGSTN3mdQKBgQD25Cx6RAoja85bSv3A
        4P6g2pdHGB99lNCo6+Dnv5Q8DX7E6EstZscADdrxgHhnDxfSsRH2F6Dvwv3N4ryu
        2chNAwfFUuYdv/GVWFz1w3JSD5oR3CeyXoiwz9dpaa8E5P9t+6+fyoXZsxWveNt2
        Y2CqpCkROFxWUQviyp3wKYWCWwKBgQD1YILyLnp/Ho4eVXEOrrviAVOAyYhOGnD+
        A7T8qdmUUlZHv/X+ZKVSU9KPQgFc4lKrdrTYKYeAC8Hfq585PfpgQNWRR/QZ27YE
        uqAyide+L73dGeAxMJyaftkYqNUq0uC5QXCufDrPqkzq8d0xF7qxJSN8aep93SmL
        L2p4pcbfxwKBgCAhZ8xtqGgdsphc9RMx9NFYQVHGSOreAB3LvNRMMW1zUCkuFgKN
        mp5eLz04u/KlmzMXSkAdqRsq5D70IBwdSZ0EJPHALSR4A2etPUPasLkPQLzMSvpC
        pUVldyJH17gqWTemBqAkCjFfxhW1A9Kvcjgi7xlHnXS6TXKxbcaAkNh7AoGADEfY
        Reatms8crcf48JMuNBF87GUpvT71iMEGvd6CVToJt22UEjdXTteDIkhbaRqqqIo4
        YtkxPudXvKoKPgMsFMUp6yt+vAyS/4mXmu/rLEmXZwl0fwG/1LukgedxQ8NqG9t6
        mED/cIVFdDzGpT5ayaLiM8fZRJNdEOo+mesyGOECgYB/NFqRpRIh23iFR5PCJaVX
        VadDAzAmBeVYXMpoBC4hvylnJyrjSXS5SSHB5XhCkWDMpbRxqMzurpLrJzwL8OP3
        UVULK3Kl1BtiGpXohoFX1VrrR1bsTjhY7FBUaUcLMn+b+SNi0gxcag8cRn9Mmhnx
        Bwg0UU3K3rR9uLe6G8kimQ==
        -----END PRIVATE KEY-----
        """

    @Test func encodeWithTokenAndPrivateKeyDoesNotFailWithValidKey() throws {
        let context = AuthContext(
            method: .init(token: .tokenAndPrivateKey(token: "my_token", key: testPrivateKey)),
            service: .serviceName("test"),
            terminalName: "terminal",
            programName: "program",
            machineName: "machine",
            pid: 1,
            processUsername: "user",
            mode: .sysDBA,
            description: .init(
                connectionID: "1",
                addressLists: [],
                service: .serviceName("test"),
                sslServerDnMatch: false,
                purity: .new
            )
        )
        var encoder = OracleFrontendMessageEncoder(buffer: .init(), capabilities: .init())
        _ = try encoder.authenticationPhaseTwo(authContext: context, parameters: .init([:]))
    }
}
