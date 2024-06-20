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
import Foundation

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
        let file: String
        var directory: ObjCBool = false
        // The wallet points to a PEM file
        if FileManager.default.fileExists(atPath: wallet, isDirectory: &directory), !directory.boolValue {
            file = wallet
        // Folder
        } else {
            if wallet.last == "/" {
                file = wallet + "ewallet.pem"
            } else {
                file = wallet + "/ewallet.pem"
            }
        }

        let key = try NIOSSLPrivateKey(file: file, format: .pem) { completion in
            completion(walletPassword.utf8)
        }
        let certificate = try NIOSSLCertificate(file: file, format: .pem)

        var tls = TLSConfiguration.makeClientConfiguration()
        tls.privateKey = NIOSSLPrivateKeySource.privateKey(key)
        tls.certificateChain = [.certificate(certificate)]

        return tls
    }
}
