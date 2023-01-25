import CryptoSwift

func decryptCBC(_ key: [UInt8], _ encryptedText: [UInt8]) throws -> [UInt8] {
    let iv = [UInt8](repeating: 0, count: 16)
    let aes = try AES(key: key, blockMode: CBC(iv: iv))
    var decryptor = try aes.makeDecryptor()
    return try decryptor.update(withBytes: encryptedText, isLast: true)
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
    let kdf = try PKCS5.PBKDF2(password: key, salt: salt, iterations: iterations, keyLength: length, variant: .sha2(.sha224))
    return try kdf.calculate()
}