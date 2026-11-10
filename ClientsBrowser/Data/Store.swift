import Foundation
import Observation

/// In-memory db.json with debounced, serialized atomic writes.
@Observable
final class Store {
  private(set) var db: DbSchema
  /// Fired after every mutation (the backup writer hangs off it).
  @ObservationIgnored var onChange: (() -> Void)?
  @ObservationIgnored private var saveTask: Task<Void, Never>?
  @ObservationIgnored private var lastWrite: Task<Void, Never>?

  init() {
    Paths.ensureDirs()
    if let data = try? Data(contentsOf: Paths.dbFile),
       let decoded = try? JSONDecoder().decode(DbSchema.self, from: data) {
      db = decoded
    } else {
      db = .defaults
    }
    if db.profiles.isEmpty {
      let first = Profile(name: "Personal", color: Profile.palette[0])
      db.profiles = [first]
      db.selectedProfileId = first.id
    }
    if db.selectedProfileId == nil || !db.profiles.contains(where: { $0.id == db.selectedProfileId }) {
      db.selectedProfileId = db.profiles.first?.id
    }
  }

  // MARK: - Writes

  /// `notify: false` saves without waking the backup writer (used by the writer itself).
  func mutate(notify: Bool = true, _ body: (inout DbSchema) -> Void) {
    body(&db)
    scheduleSave()
    if notify { onChange?() }
  }

  func updateProfile(_ id: UUID, _ body: (inout Profile) -> Void) {
    guard let i = db.profiles.firstIndex(where: { $0.id == id }) else { return }
    mutate { body(&$0.profiles[i]) }
  }

  func updateTab(profile: UUID, tab: UUID, _ body: (inout TabState) -> Void) {
    updateProfile(profile) { p in
      guard let i = p.tabs.firstIndex(where: { $0.id == tab }) else { return }
      body(&p.tabs[i])
    }
  }

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      saveNow()
    }
  }

  /// Encode on the main actor (consistent snapshot), write off it, in order.
  func saveNow() {
    saveTask?.cancel()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
    guard let data = try? encoder.encode(db) else { return }
    let previous = lastWrite
    lastWrite = Task.detached(priority: .utility) {
      await previous?.value
      try? data.write(to: Paths.dbFile, options: .atomic)
    }
  }

  /// Block until pending writes land — used on quit.
  func flush() {
    saveNow()
    let done = DispatchSemaphore(value: 0)
    let pending = lastWrite
    Task.detached {
      await pending?.value
      done.signal()
    }
    _ = done.wait(timeout: .now() + 3)
  }

  // MARK: - Reads

  var profiles: [Profile] { db.profiles }

  var selectedProfile: Profile? {
    db.profiles.first { $0.id == db.selectedProfileId }
  }

  func profile(_ id: UUID) -> Profile? { db.profiles.first { $0.id == id } }

  // MARK: - Profiles

  @discardableResult
  func addProfile(name: String, color: String? = nil) -> Profile {
    let used = Set(db.profiles.map(\.color))
    let pick = color ?? Profile.palette.first { !used.contains($0) } ?? Profile.palette[db.profiles.count % Profile.palette.count]
    let p = Profile(name: name, color: pick)
    mutate { $0.profiles.append(p) }
    return p
  }

  func renameProfile(_ id: UUID, name: String, color: String) {
    updateProfile(id) {
      $0.name = name
      $0.color = color
    }
  }

  /// Removes the row; WebKit's on-disk store is removed by the caller.
  func deleteProfile(_ id: UUID) {
    mutate { data in
      data.profiles.removeAll { $0.id == id }
      data.closedTabs.removeAll { $0.profileId == id }
      if data.selectedProfileId == id { data.selectedProfileId = data.profiles.first?.id }
    }
  }

  func selectProfile(_ id: UUID) {
    guard db.selectedProfileId != id, db.profiles.contains(where: { $0.id == id }) else { return }
    mutate { $0.selectedProfileId = id }
  }

  // MARK: - Tabs

  func addTab(profile id: UUID, url: String, select: Bool = true, after: UUID? = nil) -> TabState {
    let tab = TabState(url: url)
    updateProfile(id) { p in
      if let after, let i = p.tabs.firstIndex(where: { $0.id == after }) {
        p.tabs.insert(tab, at: i + 1)
      } else {
        p.tabs.append(tab)
      }
      if select || p.selectedTabId == nil { p.selectedTabId = tab.id }
    }
    return tab
  }

  func closeTab(profile id: UUID, tab tabId: UUID) {
    mutate { data in
      guard let pi = data.profiles.firstIndex(where: { $0.id == id }),
            let i = data.profiles[pi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
      let closed = data.profiles[pi].tabs.remove(at: i)
      if !closed.url.isEmpty {
        data.closedTabs.append(ClosedTab(profileId: id, tab: closed))
        if data.closedTabs.count > 25 { data.closedTabs.removeFirst() }
      }
      let tabs = data.profiles[pi].tabs
      if data.profiles[pi].selectedTabId == tabId {
        data.profiles[pi].selectedTabId = tabs.indices.contains(i) ? tabs[i].id : tabs.last?.id
      }
    }
  }

  /// Puts the most recently closed tab of this profile back; returns it.
  @discardableResult
  func reopenClosedTab(profile id: UUID) -> TabState? {
    guard let i = db.closedTabs.lastIndex(where: { $0.profileId == id }) else { return nil }
    let closed = db.closedTabs[i].tab
    mutate { data in
      data.closedTabs.remove(at: i)
      guard let pi = data.profiles.firstIndex(where: { $0.id == id }) else { return }
      data.profiles[pi].tabs.append(closed)
      data.profiles[pi].selectedTabId = closed.id
    }
    return closed
  }

  func selectTab(profile id: UUID, tab tabId: UUID) {
    updateProfile(id) { $0.selectedTabId = tabId }
  }

  func moveTab(profile id: UUID, from: IndexSet, to: Int) {
    updateProfile(id) { $0.tabs.move(fromOffsets: from, toOffset: to) }
  }

  // MARK: - Client info (new-tab page)

  func info(_ id: UUID) -> ClientInfo { profile(id)?.info ?? ClientInfo() }

  func setInfo(_ id: UUID, _ info: ClientInfo) {
    guard profile(id)?.info != info else { return }
    updateProfile(id) { $0.info = info }
  }

  // MARK: - Storage mirror

  static let maxOriginBytes = 2 * 1024 * 1024

  func recordLocalStorage(profile id: UUID, origin: String, map: StorageMap) {
    guard Self.size(of: map) <= Self.maxOriginBytes else { return }
    guard profile(id)?.localStorage[origin] != map else { return }
    updateProfile(id) { $0.localStorage[origin] = map.isEmpty ? nil : map }
  }

  func recordSessionStorage(profile id: UUID, tab: UUID, origin: String, map: StorageMap) {
    guard Self.size(of: map) <= Self.maxOriginBytes else { return }
    let current = profile(id)?.tabs.first { $0.id == tab }?.sessionStorage?[origin]
    guard current != map else { return }
    updateTab(profile: id, tab: tab) { t in
      var all = t.sessionStorage ?? [:]
      all[origin] = map.isEmpty ? nil : map
      t.sessionStorage = all.isEmpty ? nil : all
    }
  }

  func clearPendingLocalStorage(profile id: UUID, origin: String) {
    guard profile(id)?.pendingLocalStorage?[origin] != nil else { return }
    updateProfile(id) { p in
      p.pendingLocalStorage?[origin] = nil
      if p.pendingLocalStorage?.isEmpty == true { p.pendingLocalStorage = nil }
    }
  }

  private static func size(of map: StorageMap) -> Int {
    map.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
  }
}
