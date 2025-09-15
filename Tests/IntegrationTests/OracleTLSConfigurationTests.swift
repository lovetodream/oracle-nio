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

import Foundation
import NIOSSL
import OracleNIO
import Testing

@Suite(.timeLimit(.minutes(5))) final class OracleTLSConfigurationTests {
    @Test func tlsUtilities() throws {
        let filePath = try #require(
            Bundle.module.path(
                forResource: "ewallet", ofType: "pem"
            ))
        let pemConfig = try TLSConfiguration.makeOracleWalletConfiguration(
            pemFile: filePath, pemPassword: "password"
        )
        let pemHasPrivateKey =
            switch pemConfig.privateKey {
            case .privateKey: true
            default: false
            }
        #expect(pemHasPrivateKey)
        #expect(!pemConfig.certificateChain.isEmpty)

        let folderPath = filePath.dropLast("ewallet.pem".count)
        for path in [folderPath, folderPath.dropLast()] {
            let walletConfig = try TLSConfiguration.makeOracleWalletConfiguration(
                wallet: .init(path), walletPassword: "password"
            )
            let walletHasPrivateKey =
                switch walletConfig.privateKey {
                case .privateKey: true
                default: false
                }
            #expect(walletHasPrivateKey)
            #expect(!walletConfig.certificateChain.isEmpty)
        }
    }
}
