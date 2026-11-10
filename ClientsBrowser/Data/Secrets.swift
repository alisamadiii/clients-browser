import Foundation
import Security

/// The backup passphrase lives in the login Keychain.
nonisolated enum Secrets {
  enum Key: String {
    case backupPassphrase = "BACKUP_PASSPHRASE"
  }

  private static let service = "com.alisamadi.clientsbrowser"

  static func get(_ key: Key) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
          let data = out as? Data,
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty
    else { return nil }
    return value
  }

  static func set(_ key: Key, _ value: String) {
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
    ]
    SecItemDelete(base as CFDictionary)
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var add = base
    add[kSecValueData as String] = Data(trimmed.utf8)
    SecItemAdd(add as CFDictionary, nil)
  }

  static var passphrase: String? { return Self.get(.backupPassphrase) }
}
