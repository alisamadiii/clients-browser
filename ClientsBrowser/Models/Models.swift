import Foundation

/// key → value, as the page's storage API reports it.
typealias StorageMap = [String: String]

nonisolated struct TabState: Codable, Identifiable, Hashable, Sendable {
  var id: UUID
  var url: String
  var title: String
  /// WKWebView.interactionState: back/forward list, scroll position.
  var interactionState: Data?
  /// origin → sessionStorage, captured from the page; reinjected once on relaunch.
  var sessionStorage: [String: StorageMap]?

  init(id: UUID = UUID(), url: String, title: String = "") {
    self.id = id
    self.url = url
    self.title = title
  }
}

nonisolated struct QuickLink: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var title: String
  var url: String
}

/// What the new-tab page shows for a client. No credentials here — those live in cookies.
nonisolated struct ClientInfo: Codable, Hashable, Sendable {
  var business = ""
  var website = ""
  var contactName = ""
  var email = ""
  var phone = ""
  var address = ""
  var notes = ""
  var links: [QuickLink] = []
}

nonisolated struct Profile: Codable, Identifiable, Hashable, Sendable {
  var id: UUID
  var name: String
  /// Hex "#RRGGBB" — tints the tab strip so it's obvious which client is active.
  var color: String
  var tabs: [TabState]
  var selectedTabId: UUID?
  var createdAt: String
  /// origin → localStorage, mirrored from the page for the backup string.
  var localStorage: [String: StorageMap]
  /// Set by a restore: injected into each origin's localStorage on its first load.
  var pendingLocalStorage: [String: StorageMap]?
  var info: ClientInfo?

  init(id: UUID = UUID(), name: String, color: String) {
    self.id = id
    self.name = name
    self.color = color
    self.tabs = []
    self.selectedTabId = nil
    self.createdAt = DateKey.iso()
    self.localStorage = [:]
    self.pendingLocalStorage = nil
  }

  static let palette = [
    "#2F6BFF", "#E5484D", "#F5A524", "#30A46C", "#8E4EC6",
    "#D6409F", "#12A594", "#F76B15", "#5B5BD6", "#3E63DD",
  ]
}

nonisolated struct ClosedTab: Codable, Hashable, Sendable {
  var profileId: UUID
  var tab: TabState
}

nonisolated struct DbSchema: Codable, Sendable {
  var version: Int
  var profiles: [Profile]
  var selectedProfileId: UUID?
  var closedTabs: [ClosedTab]
  var lastBackupAt: String?
  var lastBackupBytes: Int?

  static let defaults = DbSchema(
    version: 1, profiles: [], selectedProfileId: nil, closedTabs: [], lastBackupAt: nil, lastBackupBytes: nil
  )
}

// MARK: - Backup payload (what the encrypted string contains)

nonisolated struct CookieRecord: Codable, Hashable, Sendable {
  var name: String
  var value: String
  var domain: String
  var path: String
  var expires: Double?
  var secure: Bool
  var httpOnly: Bool
  var sameSite: String?

  init(_ c: HTTPCookie) {
    name = c.name
    value = c.value
    domain = c.domain
    path = c.path
    expires = c.expiresDate?.timeIntervalSince1970
    secure = c.isSecure
    httpOnly = c.isHTTPOnly
    sameSite = c.sameSitePolicy?.rawValue
  }

  var httpCookie: HTTPCookie? {
    var props: [HTTPCookiePropertyKey: Any] = [
      .name: name, .value: value, .domain: domain, .path: path,
    ]
    if let expires { props[.expires] = Date(timeIntervalSince1970: expires) }
    if secure { props[.secure] = "TRUE" }
    if httpOnly { props[.init("HttpOnly")] = "TRUE" }
    if let sameSite { props[.sameSitePolicy] = sameSite }
    return HTTPCookie(properties: props)
  }
}

nonisolated struct BackupProfile: Codable, Sendable {
  var id: UUID
  var name: String
  var color: String
  var tabs: [TabState]
  var selectedTabId: UUID?
  var createdAt: String
  var cookies: [CookieRecord]
  var localStorage: [String: StorageMap]
  var info: ClientInfo?
}

nonisolated struct BackupPayload: Codable, Sendable {
  var version: Int
  var createdAt: String
  var selectedProfileId: UUID?
  var profiles: [BackupProfile]
}

nonisolated enum DateKey {
  static func iso(_ date: Date = Date()) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  /// yyyy-MM-dd-HHmmss for history filenames.
  static func stamp(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f.string(from: date)
  }
}
