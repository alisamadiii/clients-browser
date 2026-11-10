import Foundation
import Observation

/// Debounced auto-backup to iCloud Drive. Any store change, cookie change or
/// storage message calls `schedule()`; 5s of quiet later the file is rewritten.
@Observable
final class BackupWriter {
  @ObservationIgnored unowned let store: Store
  @ObservationIgnored var liveSession: () -> ProfileSession? = { nil }
  private(set) var isWriting = false
  private(set) var lastError: String?
  @ObservationIgnored private var pending: Task<Void, Never>?
  @ObservationIgnored private var writing: Task<Void, Never>?
  @ObservationIgnored private var dirty = false

  nonisolated static let historyLimit = 10

  init(store: Store) {
    self.store = store
  }

  var hasPassphrase: Bool { Secrets.passphrase != nil }

  func schedule() {
    dirty = true
    pending?.cancel()
    pending = Task {
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      await writeNow()
    }
  }

  /// Build + encrypt + write. Serialized; a second call waits for the first.
  func writeNow() async {
    pending?.cancel()
    if let writing { await writing.value }
    guard dirty, let passphrase = Secrets.passphrase else { return }
    dirty = false
    let task = Task { await self.write(passphrase: passphrase) }
    writing = task
    await task.value
    writing = nil
  }

  private func write(passphrase: String) async {
    isWriting = true
    defer { isWriting = false }
    do {
      let payload = await BackupBuilder.payload(store: store, liveSession: liveSession())
      let string = try await BackupBuilder.encodedString(payload, passphrase: passphrase)
      let bytes = string.utf8.count
      try await Task.detached(priority: .utility) {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.backupHistoryDir, withIntermediateDirectories: true)
        let data = Data(string.utf8)
        try data.write(to: Paths.backupFile, options: .atomic)
        try data.write(to: Paths.backupHistoryDir.appending(path: "backup-\(DateKey.stamp()).txt"), options: .atomic)
        Self.pruneHistory()
      }.value
      // Don't bounce through mutate(): that would schedule another backup.
      store.mutate(notify: false) { $0.lastBackupAt = DateKey.iso(); $0.lastBackupBytes = bytes }
      dirty = false
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// Fresh string for the clipboard (doesn't touch the file).
  func currentString() async throws -> String {
    guard let passphrase = Secrets.passphrase else { throw BackupCrypto.CryptoError.keyDerivation }
    let payload = await BackupBuilder.payload(store: store, liveSession: liveSession())
    return try await BackupBuilder.encodedString(payload, passphrase: passphrase)
  }

  nonisolated private static func pruneHistory() {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: Paths.backupHistoryDir, includingPropertiesForKeys: nil) else { return }
    let sorted = files.filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    for old in sorted.dropFirst(historyLimit) { try? fm.removeItem(at: old) }
  }
}
