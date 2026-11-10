import Foundation
import Observation
import WebKit

/// One WKWebsiteDataStore object per profile id for the whole process — the
/// browser session and the backup builder must share the same instance.
enum DataStores {
  private static var cache: [UUID: WKWebsiteDataStore] = [:]

  static func store(for id: UUID) -> WKWebsiteDataStore {
    if let s = cache[id] { return s }
    let s = WKWebsiteDataStore(forIdentifier: id)
    cache[id] = s
    return s
  }

  static func remove(_ id: UUID) async {
    cache[id] = nil
    try? await WKWebsiteDataStore.remove(forIdentifier: id)
  }
}

/// The live tabs of the active profile. Only one exists at a time.
@Observable
final class ProfileSession: NSObject, WKScriptMessageHandler, WKHTTPCookieStoreObserver {
  let profileId: UUID
  let dataStore: WKWebsiteDataStore
  @ObservationIgnored unowned let store: Store
  private(set) var tabs: [Tab] = []
  private(set) var selectedTabId: UUID?
  /// The pinned square chip: client info page instead of a web tab.
  private(set) var homeSelected = false
  /// Fired on cookie changes (login/logout) so a backup gets scheduled.
  @ObservationIgnored var onCookiesChanged: (() -> Void)?

  static let captureScript: String = {
    guard let url = Bundle.main.url(forResource: "StorageCapture", withExtension: "js"),
          let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    return s
  }()

  init(profile: Profile, store: Store) {
    profileId = profile.id
    self.store = store
    dataStore = DataStores.store(for: profile.id)
    super.init()
    dataStore.httpCookieStore.add(self)
    tabs = profile.tabs.map { Tab(state: $0, session: self) }
    selectedTabId = profile.selectedTabId ?? tabs.first?.id
    if tabs.isEmpty { newTab() }
  }

  var profile: Profile? { store.profile(profileId) }
  var selectedTab: Tab? { homeSelected ? nil : tabs.first { $0.id == selectedTabId } }

  func selectHome() {
    guard !homeSelected else { return }
    selectedTab?.persist()
    homeSelected = true
  }

  func tab(_ id: UUID) -> Tab? { tabs.first { $0.id == id } }
  func tab(for webView: WKWebView) -> Tab? { tabs.first { $0.webView === webView } }

  // MARK: - Configuration

  /// Base config: shared data store, Safari UA, capture script. Each tab adds
  /// its own one-shot restore script on top.
  func makeConfiguration(for tab: Tab) -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = dataStore
    config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
    config.preferences.isElementFullscreenEnabled = true
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    installScripts(into: config.userContentController, for: tab, includeRestore: true)
    return config
  }

  func installScripts(into controller: WKUserContentController, for tab: Tab, includeRestore: Bool) {
    controller.removeAllUserScripts()
    controller.removeScriptMessageHandler(forName: "cb")
    controller.add(self, name: "cb")
    if includeRestore, let restore = restoreScript(for: tab) {
      controller.addUserScript(WKUserScript(source: restore, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }
    controller.addUserScript(WKUserScript(source: Self.captureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
  }

  /// Puts restored localStorage (profile-wide) and this tab's saved
  /// sessionStorage back before any page script runs.
  private func restoreScript(for tab: Tab) -> String? {
    let pendingLocal = profile?.pendingLocalStorage ?? [:]
    let session = profile?.tabs.first { $0.id == tab.id }?.sessionStorage ?? [:]
    guard !pendingLocal.isEmpty || !session.isEmpty else { return nil }
    guard let localJSON = try? JSONEncoder().encode(pendingLocal),
          let sessionJSON = try? JSONEncoder().encode(session),
          let l = String(data: localJSON, encoding: .utf8),
          let s = String(data: sessionJSON, encoding: .utf8) else { return nil }
    return """
    (function () {
      var o = location.origin;
      var local = \(l)[o];
      var session = \(s)[o];
      var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cb;
      try {
        if (local) {
          for (var k in local) localStorage.setItem(k, local[k]);
          if (handler) handler.postMessage({ kind: "restoredLocal", origin: o });
        }
        if (session && sessionStorage.length === 0) {
          for (var k2 in session) sessionStorage.setItem(k2, session[k2]);
        }
      } catch (e) {}
    })();
    """
  }

  // MARK: - Tabs

  @discardableResult
  func newTab(url: String = "", select: Bool = true, after: UUID? = nil, configuration: WKWebViewConfiguration? = nil) -> Tab {
    let state = store.addTab(profile: profileId, url: url, select: select, after: after)
    let tab = Tab(state: state, session: self, presetConfiguration: configuration)
    if let after, let i = tabs.firstIndex(where: { $0.id == after }) {
      tabs.insert(tab, at: i + 1)
    } else {
      tabs.append(tab)
    }
    if select || selectedTabId == nil {
      selectedTabId = tab.id
      if select { homeSelected = false }
    }
    return tab
  }

  func closeTab(_ id: UUID) {
    guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
    tabs[i].persist()
    tabs[i].teardown()
    tabs.remove(at: i)
    store.closeTab(profile: profileId, tab: id)
    if selectedTabId == id {
      selectedTabId = tabs.indices.contains(i) ? tabs[i].id : tabs.last?.id
      if let selectedTabId { store.selectTab(profile: profileId, tab: selectedTabId) }
    }
    if tabs.isEmpty { newTab() }
  }

  func reopenClosedTab() {
    guard let state = store.reopenClosedTab(profile: profileId) else { return }
    let tab = Tab(state: state, session: self)
    tabs.append(tab)
    selectedTabId = tab.id
    homeSelected = false
  }

  func select(_ id: UUID) {
    guard tabs.contains(where: { $0.id == id }) else { return }
    if homeSelected {
      homeSelected = false
      if selectedTabId == id { return }
    } else if selectedTabId == id {
      return
    }
    selectedTab?.persist()
    selectedTabId = id
    store.selectTab(profile: profileId, tab: id)
  }

  func selectRelative(_ delta: Int) {
    guard let cur = tabs.firstIndex(where: { $0.id == selectedTabId }), !tabs.isEmpty else { return }
    let next = (cur + delta + tabs.count) % tabs.count
    select(tabs[next].id)
  }

  func selectIndex(_ i: Int) {
    // ⌘9 = last tab, like Chrome.
    let idx = i == 8 ? tabs.count - 1 : i
    guard tabs.indices.contains(idx) else { return }
    select(tabs[idx].id)
  }

  func move(from: IndexSet, to: Int) {
    tabs.move(fromOffsets: from, toOffset: to)
    store.moveTab(profile: profileId, from: from, to: to)
  }

  /// Save every tab's state (quit / profile switch).
  func persistAll() {
    for t in tabs { t.persist() }
  }

  func teardown() {
    persistAll()
    for t in tabs { t.teardown() }
    tabs = []
    dataStore.httpCookieStore.remove(self)
  }

  // MARK: - WKScriptMessageHandler

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any],
          let kind = body["kind"] as? String,
          let origin = body["origin"] as? String, origin != "null" else { return }
    switch kind {
    case "storage":
      let local = (body["local"] as? [String: String]) ?? [:]
      let session = (body["session"] as? [String: String]) ?? [:]
      store.recordLocalStorage(profile: profileId, origin: origin, map: local)
      if let wv = message.webView, let tab = tab(for: wv) {
        store.recordSessionStorage(profile: profileId, tab: tab.id, origin: origin, map: session)
      }
    case "restoredLocal":
      store.clearPendingLocalStorage(profile: profileId, origin: origin)
    default:
      break
    }
  }

  // MARK: - WKHTTPCookieStoreObserver

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    onCookiesChanged?()
  }
}
