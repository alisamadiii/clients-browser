import AppKit
import SwiftUI

/// Settings window: backup status, copy string, restore, passphrase.
struct BackupView: View {
  @Environment(BrowserController.self) private var controller
  @State private var status: String?
  @State private var showPassphrase = false
  @State private var showRestore = false

  var body: some View {
    Form {
      Section("Automatic backup") {
        LabeledContent("Location") {
          HStack {
            Text(Paths.backupFile.path(percentEncoded: false)).textSelection(.enabled).font(.caption)
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([Paths.backupFile]) }
          }
        }
        LabeledContent("Last backup") {
          if let at = controller.store.db.lastBackupAt {
            Text("\(Self.pretty(at)) · \(Self.size(controller.store.db.lastBackupBytes ?? 0))")
          } else {
            Text("Never").foregroundStyle(.secondary)
          }
        }
        if let err = controller.backup.lastError {
          Text(err).foregroundStyle(.red).font(.caption)
        }
        HStack {
          Button("Back Up Now") {
            Task {
              controller.backup.schedule()
              await controller.backup.writeNow()
              status = controller.backup.lastError == nil ? "Backup written." : nil
            }
          }
          Button("Copy Backup String") {
            Task {
              do {
                let s = try await controller.backup.currentString()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
                status = "Copied \(Self.size(s.utf8.count)) to the clipboard."
              } catch {
                status = error.localizedDescription
              }
            }
          }
          if controller.backup.isWriting { ProgressView().controlSize(.small) }
        }
        if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
      }

      Section("Restore") {
        Text("Paste a backup string (or pick the backup file) to bring clients, logins and tabs back. Existing clients are merged, not duplicated.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Restore from Backup…") { showRestore = true }
      }

      Section("Passphrase") {
        Text("Encrypts every backup. Changing it only affects new backups — old strings still need the old passphrase.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Change Passphrase…") { showPassphrase = true }
      }

      Section("What's in a backup") {
        Text("Cookies, localStorage and open tabs for every client. IndexedDB can't be exported from WebKit, so a site that keeps its login only there needs a fresh sign-in after a restore.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 560)
    .sheet(isPresented: $showRestore) { RestoreSheet() }
    .sheet(isPresented: $showPassphrase) { PassphraseSetup(changing: true) }
  }

  static func pretty(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
    return d.formatted(date: .abbreviated, time: .shortened)
  }

  static func size(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }
}

/// First launch (or Change Passphrase): set the backup passphrase.
struct PassphraseSetup: View {
  @Environment(BrowserController.self) private var controller
  @Environment(\.dismiss) private var dismiss
  var changing = false
  @State private var one = ""
  @State private var two = ""
  @State private var saved = false

  private var valid: Bool { one.count >= 8 && one == two && saved }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(changing ? "Change Backup Passphrase" : "Set a Backup Passphrase").font(.title3.bold())
      Text("Every client login is written to an encrypted backup string in iCloud Drive. This passphrase is the only way to open it — it is never stored outside this Mac's Keychain.")
        .font(.callout).foregroundStyle(.secondary)
      SecureField("Passphrase (8+ characters)", text: $one).textFieldStyle(.roundedBorder)
      SecureField("Repeat passphrase", text: $two).textFieldStyle(.roundedBorder)
      if !two.isEmpty, one != two {
        Text("Passphrases don't match.").font(.caption).foregroundStyle(.red)
      }
      Toggle("I saved this passphrase somewhere safe (password manager, notes)", isOn: $saved)
      HStack {
        Spacer()
        if changing { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        Button(changing ? "Change" : "Start Browsing") {
          controller.setPassphrase(one)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!valid)
      }
    }
    .padding(22)
    .frame(width: 440)
    .interactiveDismissDisabled(!changing)
  }
}

/// Paste a string or pick the file; decrypt with the Keychain passphrase (or another).
struct RestoreSheet: View {
  @Environment(BrowserController.self) private var controller
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var passphrase = ""
  @State private var useOther = false
  @State private var busy = false
  @State private var message: String?
  @State private var done = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Restore from Backup").font(.title3.bold())
      TextEditor(text: $text)
        .font(.system(size: 11, design: .monospaced))
        .frame(height: 140)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
      HStack {
        Button("Choose File…") { pickFile() }
        Button("Use Latest Backup File") {
          text = (try? String(contentsOf: Paths.backupFile, encoding: .utf8)) ?? ""
          if text.isEmpty { message = "No backup file found at \(Paths.backupFile.path(percentEncoded: false))" }
        }
        Spacer()
      }
      Toggle("Backup was made with a different passphrase", isOn: $useOther)
      if useOther {
        SecureField("That passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
      }
      if let message {
        Text(message).font(.caption).foregroundStyle(done ? .green : .red)
      }
      HStack {
        Spacer()
        if busy { ProgressView().controlSize(.small) }
        Button(done ? "Close" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Restore") { restore() }
          .keyboardShortcut(.defaultAction)
          .disabled(busy || done || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 520)
  }

  private func pickFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.plainText]
    panel.directoryURL = Paths.backupDir
    guard panel.runModal() == .OK, let url = panel.url else { return }
    text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }

  private func restore() {
    let pass = useOther ? passphrase : (Secrets.passphrase ?? "")
    guard !pass.isEmpty else { message = "No passphrase."; return }
    busy = true
    message = nil
    Task {
      do {
        let s = try await controller.restore(from: text, passphrase: pass)
        message = "Restored: \(s.added) new client(s), \(s.merged) merged, \(s.cookies) cookies."
        done = true
      } catch {
        message = error.localizedDescription
      }
      busy = false
    }
  }
}
