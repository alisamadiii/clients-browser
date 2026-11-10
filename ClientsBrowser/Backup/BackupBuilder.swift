import Foundation
import WebKit

/// Collects every profile's cookies + mirrored storage + tabs into one payload.
enum BackupBuilder {
  static func payload(store: Store, liveSession: ProfileSession?) async -> BackupPayload {
    liveSession?.persistAll()
    var profiles: [BackupProfile] = []
    for p in store.profiles {
      let dataStore = DataStores.store(for: p.id)
      let cookies = await dataStore.httpCookieStore.allCookies()
      profiles.append(BackupProfile(
        id: p.id, name: p.name, color: p.color,
        tabs: p.tabs, selectedTabId: p.selectedTabId, createdAt: p.createdAt,
        cookies: cookies.map(CookieRecord.init),
        localStorage: p.localStorage,
        info: p.info
      ))
    }
    return BackupPayload(
      version: 1, createdAt: DateKey.iso(),
      selectedProfileId: store.db.selectedProfileId, profiles: profiles
    )
  }

  /// Encrypt off the main actor — PBKDF2 at 210k rounds takes a moment.
  static func encodedString(_ payload: BackupPayload, passphrase: String) async throws -> String {
    let json = try JSONEncoder().encode(payload)
    return try await Task.detached(priority: .utility) {
      try BackupCrypto.encrypt(json, passphrase: passphrase)
    }.value
  }

  static func decode(_ string: String, passphrase: String) async throws -> BackupPayload {
    let data = try await Task.detached(priority: .utility) {
      try BackupCrypto.decrypt(string, passphrase: passphrase)
    }.value
    return try JSONDecoder().decode(BackupPayload.self, from: data)
  }
}
