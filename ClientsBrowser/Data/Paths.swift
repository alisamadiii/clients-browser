import Foundation

nonisolated enum Paths {
  /// ~/Library/Application Support/Clients Browser — db.json (profiles + tabs).
  static let dataDir: URL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "Clients Browser", directoryHint: .isDirectory)

  static let dbFile = dataDir.appending(path: "db.json")

  private static let home = FileManager.default.homeDirectoryForCurrentUser

  /// iCloud Drive root (plain path — the app isn't sandboxed).
  static let iCloudDocs = home
    .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)

  /// Where the encrypted backup lands: iCloud Drive if it's on, else ~/Documents.
  static var backupDir: URL {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    let base: URL
    if fm.fileExists(atPath: iCloudDocs.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue {
      base = iCloudDocs
    } else {
      base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    return base.appending(path: "Clients Browser", directoryHint: .isDirectory)
  }

  static var backupFile: URL { backupDir.appending(path: "backup-latest.txt") }
  static var backupHistoryDir: URL { backupDir.appending(path: "history", directoryHint: .isDirectory) }

  static let downloadsDir: URL = FileManager.default
    .urls(for: .downloadsDirectory, in: .userDomainMask)[0]

  static func ensureDirs() {
    let fm = FileManager.default
    try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
  }

  /// ~/Downloads/<name>, with " 2", " 3"… appended if taken.
  static func uniqueDownload(_ suggested: String) -> URL {
    let fm = FileManager.default
    let base = (suggested as NSString).deletingPathExtension
    let ext = (suggested as NSString).pathExtension
    var candidate = downloadsDir.appending(path: suggested)
    var n = 2
    while fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
      let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
      candidate = downloadsDir.appending(path: name)
      n += 1
    }
    return candidate
  }
}
