import Foundation
import Observation
import WebKit

/// App-wide state: the store, the backup writer, and the one live profile session.
@Observable
final class BrowserController {
  let store: Store
  let backup: BackupWriter
  private(set) var session: ProfileSession?

  // UI signals driven from menu commands.
  var addressFocusToken = 0
  var showFind = false
  var findFocusToken = 0
  var showProfileSwitcher = false
  var showNewProfile = false
  var editingProfile: Profile?
  var showRestore = false
  /// Drives the first-launch sheet; mirrors whether the Keychain has a passphrase.
  var needsPassphrase = Secrets.passphrase == nil

  func setPassphrase(_ value: String) {
    Secrets.set(.backupPassphrase, value)
    needsPassphrase = Secrets.passphrase == nil
    backup.schedule()
  }

  init() {
    let store = Store()
    self.store = store
    backup = BackupWriter(store: store)
    backup.liveSession = { [weak self] in self?.session }
    store.onChange = { [weak self] in self?.backup.schedule() }
    if let id = store.db.selectedProfileId { activate(id) }
  }

  var profile: Profile? { store.selectedProfile }

  // MARK: - Profiles

  func switchProfile(_ id: UUID) {
    guard id != session?.profileId, store.profile(id) != nil else { return }
    store.selectProfile(id)
    activate(id)
  }

  private func activate(_ id: UUID) {
    session?.teardown()
    guard let p = store.profile(id) else { session = nil; return }
    let s = ProfileSession(profile: p, store: store)
    s.onCookiesChanged = { [weak self] in self?.backup.schedule() }
    session = s
  }

  func createProfile(name: String, color: String) {
    let p = store.addProfile(name: name, color: color)
    switchProfile(p.id)
  }

  /// Removes the row and WebKit's on-disk store (cookies, storage, cache).
  func deleteProfile(_ id: UUID) async {
    if session?.profileId == id {
      session?.teardown()
      session = nil
    }
    store.deleteProfile(id)
    await DataStores.remove(id)
    if store.profiles.isEmpty {
      let p = store.addProfile(name: "Personal")
      store.selectProfile(p.id)
    }
    if let next = store.db.selectedProfileId { activate(next) }
  }

  func nextProfile(_ delta: Int) {
    let ps = store.profiles
    guard let cur = ps.firstIndex(where: { $0.id == session?.profileId }), ps.count > 1 else { return }
    switchProfile(ps[(cur + delta + ps.count) % ps.count].id)
  }

  // MARK: - Tabs (menu targets)

  func newTab() {
    session?.newTab()
    addressFocusToken += 1
  }

  func closeTab() {
    guard let session, let id = session.selectedTabId else { return }
    session.closeTab(id)
  }

  func reopenClosedTab() { session?.reopenClosedTab() }
  func selectTab(_ i: Int) { session?.selectIndex(i) }
  func selectRelativeTab(_ d: Int) { session?.selectRelative(d) }

  func focusAddressBar() { addressFocusToken += 1 }

  func toggleFind() {
    showFind = true
    findFocusToken += 1
  }

  // MARK: - Quit

  /// Save tabs, flush db.json, write a final backup (bounded to ~6s).
  func prepareQuit() async {
    session?.persistAll()
    store.flush()
    backup.schedule()
    let write = Task { await backup.writeNow() }
    let deadline = Task { try? await Task.sleep(for: .seconds(6)) }
    // Whichever lands first; a stuck cookie fetch can't hold up quitting.
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      var resumed = false
      Task { await write.value; if !resumed { resumed = true; cont.resume() } }
      Task { await deadline.value; if !resumed { resumed = true; cont.resume() } }
    }
    // The writer records lastBackupAt through a debounced save; land it before exit.
    store.flush()
  }

  /// Decrypt a backup string and merge it in; the selected profile reloads.
  func restore(from string: String, passphrase: String) async throws -> Restore.Summary {
    let payload = try await BackupBuilder.decode(string, passphrase: passphrase)
    session?.teardown()
    session = nil
    let summary = await Restore.apply(payload, store: store)
    if let id = store.db.selectedProfileId { activate(id) }
    backup.schedule()
    return summary
  }
}
