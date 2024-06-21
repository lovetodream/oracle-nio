//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2024 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOSSL

extension TLSConfiguration {
    /// Creates a mutual TLS configuration for Oracle database connections.
    ///
    /// This is especially useful for establishing connections to Oracle Autonomous Dabases.
    ///
    /// For customising fields, modify the returned TLSConfiguration object.
    ///
    /// - Parameters:
    ///   - wallet: The path to your wallet folder.
    ///   - walletPassword: The password of your wallet.
    /// - Returns: A `TLSConfiguration`, configured for mutual TLS.
    public static func makeOracleWalletConfiguration(wallet: String, walletPassword: String) throws
    -> TLSConfiguration
    {
        let file =
        if wallet.last == "/" {
            wallet + "ewallet.pem"
        } else {
            wallet + "/ewallet.pem"
        }

        return try makeOracleWalletConfiguration(pemFile: file, pemPassword: walletPassword)
    }

    /// - Parameters:
    ///   - pemFile: The path to your pem file.
    ///   - pemPassword: The password of your pem file.
    /// - Returns: A `TLSConfiguration`, configured for mutual TLS.
    public static func makeOracleWalletConfiguration(pemFile: String, pemPassword: String) throws
    -> TLSConfiguration
    {
        let key = try NIOSSLPrivateKey(file: pemFile, format: .pem) { completion in
            completion(pemPassword.utf8)
        }
        let certificate = try NIOSSLCertificate(file: pemFile, format: .pem)

        var tls = TLSConfiguration.makeClientConfiguration()
        tls.privateKey = NIOSSLPrivateKeySource.privateKey(key)
        tls.certificateChain = [.certificate(certificate)]

        return tls
    }
}
