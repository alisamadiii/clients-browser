import SwiftUI
import WebKit

struct BrowserView: View {
  @Environment(BrowserController.self) private var controller

  var body: some View {
    @Bindable var controller = controller
    VStack(spacing: 0) {
      if let session = controller.session {
        TabStrip(session: session)
        Toolbar(session: session)
        if controller.showFind, let tab = session.selectedTab {
          FindBar(tab: tab)
        }
        Divider()
        if session.homeSelected, let profile = controller.profile {
          NewTabPage(profile: profile) { url in session.newTab().navigate(url) }
        } else if let tab = session.selectedTab {
          if tab.isBlank, let profile = controller.profile {
            NewTabPage(profile: profile) { tab.navigate($0) }
          } else {
            WebViewContainer(tab: tab)
          }
        } else {
          Color(nsColor: .textBackgroundColor)
        }
      } else {
        ContentUnavailableView("No client selected", systemImage: "person.crop.circle.badge.questionmark")
      }
    }
    .navigationTitle(controller.profile?.name ?? "Clients Browser")
    .sheet(isPresented: $controller.showNewProfile) {
      ProfileEditor(profile: nil)
    }
    .sheet(item: $controller.editingProfile) { p in
      ProfileEditor(profile: p)
    }
    .sheet(isPresented: $controller.showProfileSwitcher) {
      ProfileSwitcher()
    }
    .sheet(isPresented: $controller.showRestore) {
      RestoreSheet()
    }
    .sheet(isPresented: $controller.needsPassphrase) {
      PassphraseSetup()
    }
  }
}

// MARK: - Tab strip

private struct TabStrip: View {
  @Environment(BrowserController.self) private var controller
  let session: ProfileSession

  var body: some View {
    let color = Color(hex: controller.profile?.color ?? "#2F6BFF")
    HStack(spacing: 4) {
      ProfileButton()
      HomeChip(profile: controller.profile, selected: session.homeSelected, tint: color) {
        session.selectHome()
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(session.tabs) { tab in
            TabChip(tab: tab, selected: tab.id == session.selectedTabId, tint: color) {
              session.select(tab.id)
            } close: {
              session.closeTab(tab.id)
            }
          }
          NewTabButton(tint: color) { controller.newTab() }
        }
        .padding(.horizontal, 2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(color.opacity(0.14))
  }
}

/// Pinned square at the start of the strip: the client's info page.
private struct HomeChip: View {
  let profile: Profile?
  let selected: Bool
  let tint: Color
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    // Same look as TabChip, just square with a globe.
    Image(systemName: "globe")
      .font(.system(size: 12))
      .foregroundStyle(selected ? .primary : .secondary)
      .frame(width: 28, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 7)
          .fill(selected ? Color(nsColor: .textBackgroundColor) : (hovering ? tint.opacity(0.12) : .clear))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7).stroke(selected ? tint.opacity(0.35) : .clear, lineWidth: 1)
      )
      .contentShape(Rectangle())
      .onTapGesture(perform: action)
      .onHover { hovering = $0 }
      .help("Client info")
  }
}

/// Chrome-style “+” right after the last tab.
private struct NewTabButton: View {
  let tint: Color
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? tint.opacity(0.18) : .clear))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help("New Tab (⌘T)")
  }
}

private struct TabChip: View {
  let tab: Tab
  let selected: Bool
  let tint: Color
  let select: () -> Void
  let close: () -> Void
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 6) {
      if tab.isLoading, tab.favicon == nil {
        ProgressView().controlSize(.mini).frame(width: 16, height: 16)
      } else if let icon = tab.favicon {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: 16, height: 16)
          .clipShape(RoundedRectangle(cornerRadius: 3))
      } else {
        Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
      }
      Text(tab.displayTitle)
        .font(.system(size: 12))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: close) {
        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
          .frame(width: 16, height: 16)
      }
      .buttonStyle(.borderless)
      .opacity(hovering || selected ? 1 : 0)
    }
    .padding(.leading, 10)
    .padding(.trailing, 6)
    .frame(width: 180, height: 28)
    .background(
      RoundedRectangle(cornerRadius: 7)
        .fill(selected ? Color(nsColor: .textBackgroundColor) : (hovering ? tint.opacity(0.12) : .clear))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 7).stroke(selected ? tint.opacity(0.35) : .clear, lineWidth: 1)
    )
    .contentShape(Rectangle())
    .onTapGesture(perform: select)
    .onHover { hovering = $0 }
    .help(tab.url?.absoluteString ?? "")
  }
}

// MARK: - Toolbar

private struct Toolbar: View {
  @Environment(BrowserController.self) private var controller
  let session: ProfileSession
  @State private var text = ""
  @State private var editing = false
  @FocusState private var focused: Bool

  private var tab: Tab? { session.selectedTab }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        navButton("chevron.left", enabled: tab?.canGoBack ?? false) { tab?.goBack() }
        navButton("chevron.right", enabled: tab?.canGoForward ?? false) { tab?.goForward() }
        navButton(tab?.isLoading == true ? "xmark" : "arrow.clockwise", enabled: tab != nil) {
          if tab?.isLoading == true { tab?.stop() } else { tab?.reload() }
        }

        HStack(spacing: 6) {
          Image(systemName: tab?.url?.scheme == "https" ? "lock.fill" : "globe")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
          TextField("Search or enter address", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($focused)
            .onSubmit {
              // On the home chip there's no tab yet — open one.
              (tab ?? session.newTab()).navigate(text)
              focused = false
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: focused ? 2 : 1))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)

      if let tab, tab.isLoading {
        ProgressView(value: tab.progress).progressViewStyle(.linear).frame(height: 2).padding(.horizontal, -2)
      } else {
        Color.clear.frame(height: 2)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: tab?.id, initial: true) { _, _ in syncText(); if tab?.isBlank == true { focused = true } }
    .onChange(of: tab?.url) { _, _ in if !focused { syncText() } }
    .onChange(of: controller.addressFocusToken) { _, _ in focused = true }
    .onChange(of: focused) { _, now in
      if now {
        DispatchQueue.main.async { NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSTextView }?.selectAll(nil) }
      } else {
        syncText()
      }
    }
  }

  private func syncText() {
    text = tab?.url?.absoluteString ?? ""
  }

  private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
    }
    .buttonStyle(.borderless)
    .disabled(!enabled)
  }
}

// MARK: - Find bar

private struct FindBar: View {
  @Environment(BrowserController.self) private var controller
  let tab: Tab
  @State private var query = ""
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      TextField("Find in page", text: $query)
        .textFieldStyle(.plain)
        .focused($focused)
        .onSubmit { tab.find(query) }
        .onChange(of: query) { _, q in tab.find(q) }
      Button("Previous") { tab.find(query, backwards: true) }.keyboardShortcut("g", modifiers: [.command, .shift])
      Button("Next") { tab.find(query) }.keyboardShortcut("g", modifiers: .command)
      Button("Done") { controller.showFind = false }.keyboardShortcut(.escape, modifiers: [])
    }
    .controlSize(.small)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { focused = true }
    .onChange(of: controller.findFocusToken) { _, _ in focused = true }
  }
}

// MARK: - Web view host

/// Hosts the selected tab's WKWebView; swaps the subview when the tab changes.
struct WebViewContainer: NSViewRepresentable {
  let tab: Tab

  func makeNSView(context: Context) -> NSView {
    let host = NSView()
    host.autoresizesSubviews = true
    return host
  }

  func updateNSView(_ host: NSView, context: Context) {
    let wv = tab.ensureWebView()
    if wv.superview !== host {
      host.subviews.forEach { $0.removeFromSuperview() }
      wv.frame = host.bounds
      wv.autoresizingMask = [.width, .height]
      host.addSubview(wv)
      DispatchQueue.main.async { wv.window?.makeFirstResponder(wv) }
    }
  }
}

// MARK: - Color

extension Color {
  init(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    let r = Double((v >> 16) & 0xFF) / 255
    let g = Double((v >> 8) & 0xFF) / 255
    let b = Double(v & 0xFF) / 255
    self.init(red: r, green: g, blue: b)
  }
}
