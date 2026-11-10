import AppKit
import WebKit

/// Favicons by host: memory + ~/Library/Caches/<bundle>/favicons. WebKit has no
/// favicon API, so the page's <link rel="icon"> is read with JS after load.
final class FaviconCache {
  static let shared = FaviconCache()

  private var memory: [String: NSImage] = [:]
  private var inflight: Set<String> = []
  private let dir: URL = {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let d = base.appending(path: "com.alisamadi.clientsbrowser/favicons", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()

  /// Memory, then disk. Nil = never fetched for this host.
  func cached(host: String) -> NSImage? {
    if let img = memory[host] { return img }
    let file = dir.appending(path: Self.fileName(host))
    guard let data = try? Data(contentsOf: file), let img = NSImage(data: data) else { return nil }
    memory[host] = img
    return img
  }

  /// Ask the page for its icon URL, download it, cache it, hand it back.
  func fetch(for webView: WKWebView) async -> NSImage? {
    guard let pageURL = webView.url, let host = pageURL.host(), !inflight.contains(host) else { return nil }
    inflight.insert(host)
    defer { inflight.remove(host) }

    let js = """
    (function () {
      var links = document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]');
      var best = null, bestSize = 0;
      links.forEach(function (l) {
        var size = parseInt((l.getAttribute('sizes') || '0').split('x')[0], 10) || (l.rel.indexOf('apple') >= 0 ? 180 : 16);
        if (size > 192) return;
        if (!best || size > bestSize) { best = l.href; bestSize = size; }
      });
      return best || (location.origin + '/favicon.ico');
    })()
    """
    let href = (try? await webView.evaluateJavaScript(js)) as? String
    guard let href, let iconURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else { return nil }

    var request = URLRequest(url: iconURL, timeoutInterval: 8)
    request.setValue("Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 Version/26.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
    // Site cookies are in WebKit's jar, not URLSession's; most icons are public anyway.
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
          data.count > 0, data.count < 512 * 1024,
          let image = NSImage(data: data), image.isValid
    else { return nil }

    memory[host] = image
    let file = dir.appending(path: Self.fileName(host))
    try? data.write(to: file, options: .atomic)
    return image
  }

  private static func fileName(_ host: String) -> String {
    host.replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "_", options: .regularExpression) + ".img"
  }
}
