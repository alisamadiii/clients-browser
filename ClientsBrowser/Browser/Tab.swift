import AppKit
import Observation
import WebKit

/// A tab: its WKWebView (created on first show) plus what the toolbar needs.
@Observable
final class Tab: NSObject, Identifiable {
  let id: UUID
  @ObservationIgnored unowned let session: ProfileSession
  private(set) var webView: WKWebView?
  private(set) var title: String
  private(set) var url: URL?
  private(set) var isLoading = false
  private(set) var progress: Double = 0
  private(set) var canGoBack = false
  private(set) var canGoForward = false
  private(set) var favicon: NSImage?

  @ObservationIgnored private var initialURL: String
  @ObservationIgnored private var restoreState: Data?
  @ObservationIgnored private var presetConfiguration: WKWebViewConfiguration?
  @ObservationIgnored private var restoreScriptsInstalled = true

  init(state: TabState, session: ProfileSession, presetConfiguration: WKWebViewConfiguration? = nil) {
    id = state.id
    self.session = session
    title = state.title
    url = URL(string: state.url)
    initialURL = state.url
    restoreState = state.interactionState
    self.presetConfiguration = presetConfiguration
    favicon = URL(string: state.url)?.host().flatMap { FaviconCache.shared.cached(host: $0) }
    super.init()
  }

  var displayTitle: String {
    if !title.isEmpty { return title }
    if let host = url?.host() { return host }
    return "New Tab"
  }

  var isBlank: Bool { url == nil && initialURL.isEmpty }

  // MARK: - Web view

  @discardableResult
  func ensureWebView() -> WKWebView {
    if let webView { return webView }
    let config: WKWebViewConfiguration
    if let preset = presetConfiguration {
      // Popup: WebKit requires the configuration it handed us, untouched.
      config = preset
      presetConfiguration = nil
    } else {
      config = session.makeConfiguration(for: self)
    }
    let wv = WKWebView(frame: .zero, configuration: config)
    wv.navigationDelegate = self
    wv.uiDelegate = self
    wv.allowsBackForwardNavigationGestures = true
    wv.allowsMagnification = true
    wv.isInspectable = true
    webView = wv
    for key in Self.observedKeys { wv.addObserver(self, forKeyPath: key, options: [.new], context: nil) }

    if let restoreState, wv.interactionState == nil {
      wv.interactionState = restoreState
    } else if !initialURL.isEmpty, let u = URL(string: initialURL) {
      wv.load(URLRequest(url: u))
    }
    restoreState = nil
    return wv
  }

  private static let observedKeys = ["title", "URL", "loading", "estimatedProgress", "canGoBack", "canGoForward"]

  // Classic KVO: the typed observe() closure is @Sendable, which a MainActor
  // object can't be captured in under Swift 6. WebKit posts these on main.
  nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated {
      guard let wv = webView else { return }
      switch keyPath {
      case "title": title = wv.title ?? ""
      case "URL":
        let newHost = wv.url?.host()
        if newHost != url?.host() {
          favicon = newHost.flatMap { FaviconCache.shared.cached(host: $0) }
        }
        url = wv.url
      case "loading": isLoading = wv.isLoading
      case "estimatedProgress": progress = wv.estimatedProgress
      case "canGoBack": canGoBack = wv.canGoBack
      case "canGoForward": canGoForward = wv.canGoForward
      default: break
      }
    }
  }

  func teardown() {
    if let webView {
      for key in Self.observedKeys { webView.removeObserver(self, forKeyPath: key) }
    }
    webView?.navigationDelegate = nil
    webView?.uiDelegate = nil
    webView?.stopLoading()
    webView?.removeFromSuperview()
    webView = nil
  }

  // MARK: - Actions

  /// Address bar input: URL if it looks like one, else a Google search.
  func navigate(_ input: String) {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let wv = ensureWebView()
    if let u = Self.url(from: text) {
      wv.load(URLRequest(url: u))
    } else {
      let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
      wv.load(URLRequest(url: URL(string: "https://www.google.com/search?q=\(q)")!))
    }
  }

  static func url(from text: String) -> URL? {
    if text.contains(" ") { return nil }
    if let u = URL(string: text), let scheme = u.scheme, ["http", "https", "file", "about"].contains(scheme) {
      return u
    }
    if text == "localhost" || text.hasPrefix("localhost:") || text.hasPrefix("127.0.0.1") {
      return URL(string: "http://\(text)")
    }
    // "netlify.com", "app.netlify.com/sites" — needs a dot in the host part.
    let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
    guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
    return URL(string: "https://\(text)")
  }

  func goBack() { webView?.goBack() }
  func goForward() { webView?.goForward() }
  func reload() {
    if let webView, webView.url != nil { webView.reload() } else if !initialURL.isEmpty { navigate(initialURL) }
  }
  func stop() { webView?.stopLoading() }
  /// ⌘⇧R: bypass caches.
  func hardReload() { webView?.reloadFromOrigin() }

  func zoom(_ delta: Double) {
    guard let webView else { return }
    webView.pageZoom = min(3, max(0.5, (webView.pageZoom + delta).rounded(toPlaces: 2)))
  }
  func resetZoom() { webView?.pageZoom = 1 }

  func print() {
    guard let webView, let window = webView.window else { return }
    let info = NSPrintInfo.shared
    info.horizontalPagination = .fit
    info.isHorizontallyCentered = true
    let op = webView.printOperation(with: info)
    op.view?.frame = webView.bounds
    op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
  }

  func find(_ text: String, backwards: Bool = false) {
    guard let webView, !text.isEmpty else { return }
    let config = WKFindConfiguration()
    config.backwards = backwards
    config.caseSensitive = false
    config.wraps = true
    Task { _ = try? await webView.find(text, configuration: config) }
  }

  /// Write url/title/back-forward history to the store.
  func persist() {
    guard let webView else { return }
    let urlString = webView.url?.absoluteString ?? initialURL
    let state = webView.interactionState as? Data
    let t = title
    session.store.updateTab(profile: session.profileId, tab: id) { tab in
      tab.url = urlString
      tab.title = t
      if let state { tab.interactionState = state }
    }
  }
}

// MARK: - Navigation

extension Tab: WKNavigationDelegate {
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
    if navigationAction.shouldPerformDownload { return (.download, preferences) }
    // ⌘-click / middle-click a link → background tab, like Chrome.
    if navigationAction.navigationType == .linkActivated,
       navigationAction.modifierFlags.contains(.command) || navigationAction.buttonNumber == 2,
       let u = navigationAction.request.url {
      session.newTab(url: u.absoluteString, select: navigationAction.modifierFlags.contains(.shift), after: id)
      return (.cancel, preferences)
    }
    if let u = navigationAction.request.url, let scheme = u.scheme?.lowercased(),
       !["http", "https", "about", "blob", "data", "file", "javascript"].contains(scheme) {
      // mailto:, tel:, app links → hand to macOS.
      NSWorkspace.shared.open(u)
      return (.cancel, preferences)
    }
    return (.allow, preferences)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
    navigationResponse.canShowMIMEType ? .allow : .download
  }

  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if restoreScriptsInstalled {
      // One-shot restore scripts have done their job; keep only capture.
      restoreScriptsInstalled = false
      session.installScripts(into: webView.configuration.userContentController, for: self, includeRestore: false)
    }
    persist()
    Task { [weak self] in
      guard let self, let wv = self.webView else { return }
      if let img = await FaviconCache.shared.fetch(for: wv) { self.favicon = img }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    showError(error)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    showError(error)
  }

  private func showError(_ error: Error) {
    let ns = error as NSError
    // Cancelled loads (user navigated away, download took over) aren't errors.
    guard ns.code != NSURLErrorCancelled, ns.code != 102 else { return }
    let html = """
    <html><body style="font-family:-apple-system;color:#555;padding:48px;max-width:560px">
    <h2 style="color:#222">Can't open this page</h2><p>\(ns.localizedDescription)</p></body></html>
    """
    webView?.loadHTMLString(html, baseURL: nil)
  }

  func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    let method = challenge.protectionSpace.authenticationMethod
    guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest else {
      return (.performDefaultHandling, nil)
    }
    if challenge.previousFailureCount > 2 { return (.cancelAuthenticationChallenge, nil) }
    guard let cred = Dialogs.credentials(host: challenge.protectionSpace.host) else {
      return (.cancelAuthenticationChallenge, nil)
    }
    return (.useCredential, cred)
  }
}

// MARK: - UI (popups, dialogs, file picker)

extension Tab: WKUIDelegate {
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    // OAuth popups and target=_blank open as a new tab sharing this profile's cookies.
    let tab = session.newTab(url: navigationAction.request.url?.absoluteString ?? "", after: id, configuration: configuration)
    return tab.ensureWebView()
  }

  func webViewDidClose(_ webView: WKWebView) {
    session.closeTab(id)
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
    Dialogs.alert(message, host: frame.request.url?.host())
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
    Dialogs.confirm(message, host: frame.request.url?.host())
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
    Dialogs.prompt(prompt, defaultText: defaultText ?? "", host: frame.request.url?.host())
  }

  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    return panel.runModal() == .OK ? panel.urls : nil
  }

  func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
    .prompt
  }
}

// MARK: - Downloads

extension Tab: WKDownloadDelegate {
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
    Paths.uniqueDownload(suggestedFilename)
  }

  func downloadDidFinish(_ download: WKDownload) {
    NSSound(named: "Glass")?.play()
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    Dialogs.alert("Download failed: \(error.localizedDescription)", host: nil)
  }
}

private extension Double {
  func rounded(toPlaces n: Int) -> Double {
    let f = pow(10.0, Double(n))
    return (self * f).rounded() / f
  }
}

// MARK: - Native dialogs

enum Dialogs {
  static func alert(_ message: String, host: String?) {
    let a = NSAlert()
    a.messageText = host.map { "\($0) says" } ?? "Page says"
    a.informativeText = message
    a.runModal()
  }

  static func confirm(_ message: String, host: String?) -> Bool {
    let a = NSAlert()
    a.messageText = host.map { "\($0) says" } ?? "Page says"
    a.informativeText = message
    a.addButton(withTitle: "OK")
    a.addButton(withTitle: "Cancel")
    return a.runModal() == .alertFirstButtonReturn
  }

  static func prompt(_ message: String, defaultText: String, host: String?) -> String? {
    let a = NSAlert()
    a.messageText = host.map { "\($0) asks" } ?? "Page asks"
    a.informativeText = message
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = defaultText
    a.accessoryView = field
    a.addButton(withTitle: "OK")
    a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = field
    return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
  }

  static func credentials(host: String) -> URLCredential? {
    let a = NSAlert()
    a.messageText = "Sign in to \(host)"
    a.informativeText = "This site asks for a username and password."
    let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
    stack.orientation = .vertical
    stack.spacing = 8
    let user = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    user.placeholderString = "Username"
    let pass = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    pass.placeholderString = "Password"
    stack.addArrangedSubview(user)
    stack.addArrangedSubview(pass)
    a.accessoryView = stack
    a.addButton(withTitle: "Sign In")
    a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = user
    guard a.runModal() == .alertFirstButtonReturn else { return nil }
    return URLCredential(user: user.stringValue, password: pass.stringValue, persistence: .forSession)
  }
}
