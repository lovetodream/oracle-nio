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

import Crypto
import RegexBuilder
import _CryptoExtras
import _PBKDF2

import struct Foundation.Data

func decryptCBC(_ key: [UInt8], _ encryptedText: [UInt8]) throws -> [UInt8] {
    let iv = [UInt8](repeating: 0, count: 16)
    return try Array(
        Crypto.AES._CBC.decrypt(
            encryptedText,
            using: SymmetricKey(data: key),
            iv: AES._CBC.IV(ivBytes: iv),
            noPadding: true
        ))
}

func encryptCBC(_ key: [UInt8], _ plainText: [UInt8], zeros: Bool = false) throws -> [UInt8] {
    var plainText = plainText
    let blockSize = 16
    let iv = [UInt8](repeating: 0, count: blockSize)
    let n = blockSize - plainText.count % blockSize
    if n != 0, !zeros {
        plainText += [UInt8](repeating: UInt8(n), count: n)
    }
    return try Array(
        AES._CBC.encrypt(
            plainText,
            using: .init(data: key),
            iv: AES._CBC.IV(ivBytes: iv),
            noPadding: true
        ))
}

func getDerivedKey(key: Data, salt: [UInt8], length: Int, iterations: Int) throws -> [UInt8] {
    Array(
        try PBKDF2<SHA512>.calculate(length: length, password: key, salt: salt, rounds: iterations))
}

/// Returns a signed version of the given payload (used for Oracle IAM token authentication) in base64
/// encoding.
func getSignature(key: String, payload: String) throws -> String {
    let payload = Array(payload.utf8)
    return try _RSA.Signing.PrivateKey(unsafePEMRepresentation: key)
        .signature(for: payload, padding: .insecurePKCS1v1_5)
        .rawRepresentation
        .base64EncodedString()
}
