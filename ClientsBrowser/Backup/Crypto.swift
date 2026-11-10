import CommonCrypto
import CryptoKit
import Foundation

/// Backup string: "CB1:" + base64( salt[16] ‖ AES-GCM nonce[12] ‖ ciphertext ‖ tag[16] )
/// Key = PBKDF2-HMAC-SHA256(passphrase, salt, 210k rounds). Plaintext is zlib'd JSON.
nonisolated enum BackupCrypto {
  static let prefix = "CB1:"
  static let saltLength = 16
  static let iterations: UInt32 = 210_000

  enum CryptoError: LocalizedError {
    case badFormat
    case wrongPassphrase
    case keyDerivation
    case compression

    var errorDescription: String? {
      switch self {
      case .badFormat: "That doesn't look like a Clients Browser backup string."
      case .wrongPassphrase: "Wrong passphrase, or the string is damaged."
      case .keyDerivation: "Couldn't derive the encryption key."
      case .compression: "Couldn't compress the backup."
      }
    }
  }

  static func encrypt(_ plain: Data, passphrase: String) throws -> String {
    var salt = Data(count: saltLength)
    let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
    guard status == errSecSuccess else { throw CryptoError.keyDerivation }
    let key = try deriveKey(passphrase: passphrase, salt: salt)
    let compressed = try compress(plain)
    let box = try AES.GCM.seal(compressed, using: key)
    guard let combined = box.combined else { throw CryptoError.keyDerivation }
    return prefix + (salt + combined).base64EncodedString()
  }

  static func decrypt(_ string: String, passphrase: String) throws -> Data {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix(prefix),
          let blob = Data(base64Encoded: String(trimmed.dropFirst(prefix.count))),
          blob.count > saltLength + 28
    else { throw CryptoError.badFormat }
    let salt = blob.prefix(saltLength)
    let combined = blob.dropFirst(saltLength)
    let key = try deriveKey(passphrase: passphrase, salt: Data(salt))
    do {
      let box = try AES.GCM.SealedBox(combined: combined)
      let compressed = try AES.GCM.open(box, using: key)
      return try decompress(compressed)
    } catch let e as CryptoError {
      throw e
    } catch {
      throw CryptoError.wrongPassphrase
    }
  }

  private static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
    var derived = [UInt8](repeating: 0, count: 32)
    let pass = Array(passphrase.utf8)
    let saltBytes = [UInt8](salt)
    let result = CCKeyDerivationPBKDF(
      CCPBKDFAlgorithm(kCCPBKDF2),
      pass.map { CChar(bitPattern: $0) }, pass.count,
      saltBytes, saltBytes.count,
      CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
      iterations,
      &derived, derived.count
    )
    guard result == kCCSuccess else { throw CryptoError.keyDerivation }
    return SymmetricKey(data: derived)
  }

  private static func compress(_ data: Data) throws -> Data {
    do { return try (data as NSData).compressed(using: .zlib) as Data } catch { throw CryptoError.compression }
  }

  private static func decompress(_ data: Data) throws -> Data {
    do { return try (data as NSData).decompressed(using: .zlib) as Data } catch { throw CryptoError.wrongPassphrase }
  }
}
