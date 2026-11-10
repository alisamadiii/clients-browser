import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  let controller = BrowserController()

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let c = controller
    Task { @MainActor in
      await c.prepareQuit()
      NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

@main
struct ClientsBrowserApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

  var body: some Scene {
    Window("Clients Browser", id: "main") {
      BrowserView()
        .environment(app.controller)
        .frame(minWidth: 720, minHeight: 480)
    }
    .defaultSize(width: 1280, height: 860)
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Tab") { app.controller.newTab() }
          .keyboardShortcut("t", modifiers: .command)
        Button("New Client…") { app.controller.showNewProfile = true }
          .keyboardShortcut("n", modifiers: [.command, .shift])
        Button("Reopen Closed Tab") { app.controller.reopenClosedTab() }
          .keyboardShortcut("t", modifiers: [.command, .shift])
      }
      CommandGroup(replacing: .saveItem) {
        Button("Close Tab") { app.controller.closeTab() }
          .keyboardShortcut("w", modifiers: .command)
        Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
          .keyboardShortcut("w", modifiers: [.command, .shift])
      }
      CommandGroup(replacing: .printItem) {
        Button("Print…") { app.controller.session?.selectedTab?.print() }
          .keyboardShortcut("p", modifiers: .command)
      }
      CommandGroup(replacing: .textEditing) {
        Button("Find…") { app.controller.toggleFind() }
          .keyboardShortcut("f", modifiers: .command)
      }
      CommandMenu("View") {
        Button("Open Location") { app.controller.focusAddressBar() }
          .keyboardShortcut("l", modifiers: .command)
        Button("Reload Page") { app.controller.session?.selectedTab?.reload() }
          .keyboardShortcut("r", modifiers: .command)
        Button("Hard Reload (Ignore Cache)") { app.controller.session?.selectedTab?.hardReload() }
          .keyboardShortcut("r", modifiers: [.command, .shift])
        Button("Stop") { app.controller.session?.selectedTab?.stop() }
          .keyboardShortcut(".", modifiers: .command)
        Divider()
        Button("Zoom In") { app.controller.session?.selectedTab?.zoom(0.1) }
          .keyboardShortcut("+", modifiers: .command)
        Button("Zoom Out") { app.controller.session?.selectedTab?.zoom(-0.1) }
          .keyboardShortcut("-", modifiers: .command)
        Button("Actual Size") { app.controller.session?.selectedTab?.resetZoom() }
          .keyboardShortcut("0", modifiers: .command)
        Divider()
        Button("Back") { app.controller.session?.selectedTab?.goBack() }
          .keyboardShortcut("[", modifiers: .command)
        Button("Forward") { app.controller.session?.selectedTab?.goForward() }
          .keyboardShortcut("]", modifiers: .command)
        Button("Back (Chrome)") { app.controller.session?.selectedTab?.goBack() }
          .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        Button("Forward (Chrome)") { app.controller.session?.selectedTab?.goForward() }
          .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        Divider()
        Button("Next Tab") { app.controller.selectRelativeTab(1) }
          .keyboardShortcut("]", modifiers: [.command, .shift])
        Button("Previous Tab") { app.controller.selectRelativeTab(-1) }
          .keyboardShortcut("[", modifiers: [.command, .shift])
        Button("Next Tab (Ctrl+Tab)") { app.controller.selectRelativeTab(1) }
          .keyboardShortcut(.tab, modifiers: .control)
        Button("Previous Tab (Ctrl+Shift+Tab)") { app.controller.selectRelativeTab(-1) }
          .keyboardShortcut(.tab, modifiers: [.control, .shift])
        ForEach(0..<9, id: \.self) { i in
          Button(i == 8 ? "Last Tab" : "Tab \(i + 1)") { app.controller.selectTab(i) }
            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
        }
      }
      CommandMenu("Clients") {
        Button("Switch Client…") { app.controller.showProfileSwitcher = true }
          .keyboardShortcut("p", modifiers: [.command, .shift])
        Button("Next Client") { app.controller.nextProfile(1) }
          .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        Button("Previous Client") { app.controller.nextProfile(-1) }
          .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        Divider()
        Button("Edit Client…") { app.controller.editingProfile = app.controller.profile }
        Divider()
        Button("Back Up Now") { Task { app.controller.backup.schedule(); await app.controller.backup.writeNow() } }
        Button("Restore from Backup…") { app.controller.showRestore = true }
      }
    }

    Settings {
      BackupView()
        .environment(app.controller)
    }
  }
}
