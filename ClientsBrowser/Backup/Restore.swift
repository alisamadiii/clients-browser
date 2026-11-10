import Foundation
import WebKit

/// Backup payload → profiles, cookies (set now), storage (injected on next load).
enum Restore {
  struct Summary {
    var added = 0
    var merged = 0
    var cookies = 0
  }

  static func apply(_ payload: BackupPayload, store: Store) async -> Summary {
    var summary = Summary()
    for bp in payload.profiles {
      if store.profile(bp.id) != nil {
        summary.merged += 1
        store.updateProfile(bp.id) { p in
          // Keep what's here, add tabs we don't have, re-inject storage.
          let have = Set(p.tabs.map(\.id))
          p.tabs.append(contentsOf: bp.tabs.filter { !have.contains($0.id) })
          if p.selectedTabId == nil { p.selectedTabId = bp.selectedTabId }
          p.localStorage.merge(bp.localStorage) { _, new in new }
          if p.info == nil { p.info = bp.info }
          var pending = p.pendingLocalStorage ?? [:]
          pending.merge(bp.localStorage) { _, new in new }
          p.pendingLocalStorage = pending.isEmpty ? nil : pending
        }
      } else {
        summary.added += 1
        var p = Profile(id: bp.id, name: bp.name, color: bp.color)
        p.createdAt = bp.createdAt
        p.tabs = bp.tabs
        p.selectedTabId = bp.selectedTabId ?? bp.tabs.first?.id
        p.localStorage = bp.localStorage
        p.info = bp.info
        p.pendingLocalStorage = bp.localStorage.isEmpty ? nil : bp.localStorage
        store.mutate { $0.profiles.append(p) }
      }

      let cookieStore = DataStores.store(for: bp.id).httpCookieStore
      for record in bp.cookies {
        guard let cookie = record.httpCookie else { continue }
        await cookieStore.setCookie(cookie)
        summary.cookies += 1
      }
    }
    if store.db.selectedProfileId == nil, let first = payload.selectedProfileId ?? payload.profiles.first?.id {
      store.mutate { $0.selectedProfileId = first }
    }
    store.saveNow()
    return summary
  }
}
