import Crypto
import CryptoSwift
import RegexBuilder

func decryptCBC(_ key: [UInt8], _ encryptedText: [UInt8]) throws -> [UInt8] {
    let iv = [UInt8](repeating: 0, count: 16)
    let aes = try AES(key: key, blockMode: CBC(iv: iv), padding: .noPadding)
    return try aes.decrypt(encryptedText)
}

func encryptCBC(_ key: [UInt8], _ plainText: [UInt8], zeros: Bool = false) throws -> [UInt8] {
    var plainText = plainText
    let blockSize = 16
    let iv = [UInt8](repeating: 0, count: blockSize)
    let n = blockSize - plainText.count % blockSize
    if n != 0, !zeros {
        plainText += Array<UInt8>(repeating: UInt8(n), count: n)
    }
    let aes = try AES(key: key, blockMode: CBC(iv: iv), padding: zeros ? .zeroPadding : .noPadding)
    var encryptor = try aes.makeEncryptor()
    return try encryptor.update(withBytes: plainText, isLast: true) + encryptor.finish()
}

func getDerivedKey(key: [UInt8], salt: [UInt8], length: Int, iterations: Int) throws -> [UInt8] {
    let kdf = try PKCS5.PBKDF2(password: key, salt: salt, iterations: iterations, keyLength: length, variant: .sha2(.sha512))
    return try kdf.calculate()
}

/// Returns a signed version of the given payload (used for Oracle IAM token authentication) in base64
/// encoding.
func getSignature(key: String, payload: String) throws -> String {
    var key = key
    if !key.contains({
        Regex {
            Anchor.startOfSubject
            One("-----BEGIN PRIVATE KEY-----")
            One(.newlineSequence)
            ZeroOrMore(.any)
            One(.newlineSequence)
            One("-----END PRIVATE KEY-----")
            Anchor.endOfSubject
        }
    }) {
        key = "-----BEGIN PRIVATE KEY-----" + "\n" +
            key + "\n" + "-----END PRIVATE KEY-----"
    }
    let rsa = try RSA(
        rawRepresentation: key.data(using: .utf8) ?? .init()
    )
    let signature = try rsa
        .sign(payload.bytes, variant: .message_pkcs1v15_SHA256)
    return signature.toBase64()
}
