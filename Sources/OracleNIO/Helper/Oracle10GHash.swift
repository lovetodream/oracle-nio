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

#if canImport(CommonCrypto)
import CommonCrypto
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Oracle 10G "O5LOGON" password hash used for accounts whose
/// `password_versions` includes a 10G verifier.
///
/// Two-pass DES-CBC over UTF-16BE(uppercase(username + password)) padded to an
/// 8-byte boundary. First pass uses Oracle's published fixed key; the last
/// 8 bytes of its ciphertext become the second-pass key. The 8-byte hash is
/// the last 8 bytes of the second-pass ciphertext.
///
/// Reference test vector: `username` / `password` -> `872805F3F4C83365`.
public enum Oracle10GHash {
    static let initialKey: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef]

    public static func compute(username: String, password: String) -> [UInt8] {
        let posix = Locale(identifier: "en_US_POSIX")
        let combined = (username + password).uppercased(with: posix)
        let utf16 = combined.data(using: .utf16BigEndian) ?? Data()
        var padded = [UInt8](utf16)
        let remainder = padded.count % 8
        if remainder != 0 {
            padded.append(contentsOf: [UInt8](repeating: 0, count: 8 - remainder))
        }
        let pass1 = desCBCEncrypt(key: initialKey, plaintext: padded)
        let key2 = Array(pass1.suffix(8))
        let pass2 = desCBCEncrypt(key: key2, plaintext: padded)
        return Array(pass2.suffix(8))
    }
}

#if canImport(CommonCrypto)
@usableFromInline
func desCBCEncrypt(key: [UInt8], plaintext: [UInt8]) -> [UInt8] {
    precondition(key.count == 8, "DES key must be 8 bytes")
    precondition(plaintext.count % 8 == 0, "DES-CBC plaintext must be multiple of 8 bytes")
    let iv = [UInt8](repeating: 0, count: 8)
    var output = [UInt8](repeating: 0, count: plaintext.count + 8)
    var produced: size_t = 0
    let status = CCCrypt(
        CCOperation(kCCEncrypt),
        CCAlgorithm(kCCAlgorithmDES),
        CCOptions(0),
        key, key.count,
        iv,
        plaintext, plaintext.count,
        &output, output.count,
        &produced
    )
    precondition(status == kCCSuccess, "CCCrypt(DES-CBC) failed with status \(status)")
    return Array(output.prefix(produced))
}
#else
@usableFromInline
func desCBCEncrypt(key: [UInt8], plaintext: [UInt8]) -> [UInt8] {
    fatalError("DES-CBC unavailable on this platform; oracle-nio 10G auth requires CommonCrypto (Apple platforms)")
}
#endif
