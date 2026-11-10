import AppKit
import SwiftUI

/// Client workspace: shown on the home chip and on blank tabs. Follows the
/// system appearance; accent is the client's color. Edits save on every change.
struct NewTabPage: View {
  @Environment(BrowserController.self) private var controller
  @Environment(\.colorScheme) private var scheme
  let profile: Profile
  /// Where links go: the blank tab itself, or a fresh tab from the home chip.
  let open: (String) -> Void

  private var info: Binding<ClientInfo> {
    Binding(
      get: { controller.store.info(profile.id) },
      set: { controller.store.setInfo(profile.id, $0) }
    )
  }

  var body: some View {
    let theme = WorkspaceTheme(accent: Color(hex: profile.color), scheme: scheme)
    // Read through the store so edits re-render this view.
    let current = controller.store.info(profile.id)

    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        HeaderSection(profile: profile, info: info, current: current, open: open)

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 24) {
            mainColumn.frame(minWidth: 520)
            sideColumn.frame(width: 340)
          }
          VStack(spacing: 24) {
            mainColumn
            sideColumn
          }
        }
      }
      .padding(.horizontal, 32)
      .padding(.top, 40)
      .padding(.bottom, 64)
      .frame(maxWidth: 1180)
      .frame(maxWidth: .infinity)
    }
    .background(WorkspaceBackground())
    .foregroundStyle(theme.text)
    .tint(theme.accent)
    .environment(\.workspaceTheme, theme)
  }

  private var mainColumn: some View {
    VStack(spacing: 24) {
      DetailsCard(info: info, open: open)
      NotesCard(notes: info.notes)
    }
  }

  private var sideColumn: some View {
    VStack(spacing: 24) {
      AccountsCard(open: open)
      QuickLinksCard(links: info.links, open: open)
    }
  }
}

// MARK: - Accounts (fixed dashboards, open inside this client's cookie jar)

nonisolated struct ClientAccount: Identifiable, Equatable, Sendable {
  var id: String { url }
  var mono: String
  var name: String
  var role: String
  var url: String

  static let defaults: [ClientAccount] = [
    .init(mono: "NF", name: "Netlify", role: "Hosting", url: "https://app.netlify.com"),
    .init(mono: "GD", name: "GoDaddy", role: "Domain registrar", url: "https://dcc.godaddy.com/control/portfolio"),
    .init(mono: "CF", name: "Cloudflare", role: "DNS", url: "https://dash.cloudflare.com"),
    .init(mono: "SC", name: "Search Console", role: "Search performance", url: "https://search.google.com/search-console"),
    .init(mono: "BP", name: "Business Profile", role: "Google listing", url: "https://business.google.com"),
    .init(mono: "GA", name: "Analytics", role: "Site traffic", url: "https://analytics.google.com"),
    .init(mono: "GM", name: "Gmail", role: "Client inbox", url: "https://mail.google.com"),
    .init(mono: "GH", name: "GitHub", role: "Source code", url: "https://github.com"),
  ]
}

// MARK: - Theme (light + dark)

nonisolated struct WorkspaceTheme: Sendable {
  var accent: Color
  var scheme: ColorScheme

  private var dark: Bool { scheme == .dark }

  // Text
  var text: Color { dark ? Color(hex: 0xEDEAE5) : Color(hex: 0x1C1A17) }
  var muted: Color { dark ? Color(hex: 0x9C978F) : Color(hex: 0x5F5A53) }
  var faint: Color { dark ? Color(hex: 0x8A857D) : Color(hex: 0x6F6961) }
  var placeholder: Color { dark ? Color(hex: 0x6F6A63) : Color(hex: 0x9A948B) }
  var monoChipText: Color { dark ? Color(hex: 0xC9C4BC) : Color(hex: 0x4A453F) }

  // Accent
  /// Accent for text/labels — darkened in light mode so it stays readable on white.
  var accentInk: Color { dark ? accent : accent.mixed(with: .black, by: 0.42) }
  var onAccent: Color { Color(hex: 0x1A1208) }
  var haloOpacity: Double { dark ? 0.18 : 0.22 }

  // Surfaces
  var baseTop: Color { dark ? Color(hex: 0x171513) : Color(hex: 0xFAF8F5) }
  var baseBottom: Color { dark ? Color(hex: 0x121110) : Color(hex: 0xF1EEE9) }
  var cardFill: Color { dark ? Color(hex: 0x1B1917).opacity(0.72) : Color.white.opacity(0.70) }
  var noteFill: Color { dark ? Color(hex: 0x100F0E).opacity(0.60) : Color.white.opacity(0.75) }
  var chipFill: Color { dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04) }
  var chipHover: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
  var rowHover: Color { dark ? Color.white.opacity(0.035) : Color.black.opacity(0.03) }
  var fieldHoverFill: Color { dark ? Color.white.opacity(0.03) : Color.black.opacity(0.03) }
  var fieldFocusFill: Color { dark ? Color.white.opacity(0.05) : Color.white }

  // Lines & depth
  var hairline: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
  var hairlineStrong: Color { dark ? Color.white.opacity(0.14) : Color.black.opacity(0.14) }
  var divider: Color { dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06) }
  var cardShadow: Color { dark ? Color.black.opacity(0.35) : Color.black.opacity(0.06) }

  // Background glow
  var glowStrong: Double { dark ? 0.24 : 0.22 }
  var glowSoft: Double { dark ? 0.09 : 0.10 }
  var coolGlow: Color { Color(hex: 0x786EFF).opacity(dark ? 0.06 : 0.07) }
}

private nonisolated struct WorkspaceThemeKey: EnvironmentKey {
  static let defaultValue = WorkspaceTheme(accent: Color(hex: 0xE2A54E), scheme: .dark)
}

extension EnvironmentValues {
  var workspaceTheme: WorkspaceTheme {
    get { self[WorkspaceThemeKey.self] }
    set { self[WorkspaceThemeKey.self] = newValue }
  }
}

nonisolated extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }

  func mixed(with other: NSColor, by fraction: CGFloat) -> Color {
    let base = NSColor(self).usingColorSpace(.sRGB) ?? .black
    return Color(nsColor: base.blended(withFraction: fraction, of: other) ?? base)
  }
}

// MARK: - Background

private struct WorkspaceBackground: View {
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    ZStack {
      LinearGradient(colors: [theme.baseTop, theme.baseBottom], startPoint: .top, endPoint: .bottom)
      RadialGradient(
        colors: [theme.accent.opacity(theme.glowStrong), .clear],
        center: UnitPoint(x: 0.12, y: -0.12), startRadius: 0, endRadius: 720
      )
      RadialGradient(
        colors: [theme.accent.opacity(theme.glowSoft), .clear],
        center: UnitPoint(x: 1.0, y: 0.08), startRadius: 0, endRadius: 560
      )
      RadialGradient(
        colors: [theme.coolGlow, .clear],
        center: UnitPoint(x: 0.6, y: 1.15), startRadius: 0, endRadius: 700
      )
    }
    .ignoresSafeArea()
  }
}

// MARK: - Header

private struct HeaderSection: View {
  let profile: Profile
  @Binding var info: ClientInfo
  let current: ClientInfo
  let open: (String) -> Void
  @Environment(\.workspaceTheme) private var theme

  private var displayName: String { current.business.isEmpty ? profile.name : current.business }

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      HStack(spacing: 16) {
        Text(String(displayName.prefix(1)).uppercased())
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(theme.accentInk)
          .frame(width: 52, height: 52)
          .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent.opacity(0.14)))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.accent.opacity(0.30), lineWidth: 1))
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 4) {
          TextField("Name", text: $info.business, prompt: Text(profile.name).foregroundStyle(theme.text))
            .textFieldStyle(.plain)
            .labelsHidden()
            .focusEffectDisabled()
            .font(.system(size: 26, weight: .semibold))
            .tracking(-0.5)
            .foregroundStyle(theme.text)
          HStack(spacing: 8) {
            Text("Client workspace")
            Circle().fill(theme.faint.opacity(0.6)).frame(width: 3, height: 3)
            Text(current.website.isEmpty ? "No website added" : current.website)
              .font(.system(size: 12, design: .monospaced))
              .lineLimit(1)
          }
          .font(.system(size: 13))
          .foregroundStyle(theme.muted)
        }
      }

      Spacer(minLength: 0)

      Button {
        open(current.website)
      } label: {
        HStack(spacing: 8) {
          Text("Visit website")
          Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
        }
      }
      .buttonStyle(PrimaryButtonStyle())
      .disabled(current.website.isEmpty)
    }
  }
}

// MARK: - Client details

private struct DetailsCard: View {
  @Binding var info: ClientInfo
  let open: (String) -> Void
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text("Client details").font(.system(size: 14, weight: .semibold))
        Spacer()
        Text("Click a field to edit").font(.system(size: 12)).foregroundStyle(theme.faint)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 18)

      divider
      FieldRow("Website", placeholder: "example.com", text: $info.website, monospaced: true) {
        IconButton(symbol: "arrow.up.right", help: "Open website") { open(info.website) }
          .disabled(info.website.isEmpty)
      }
      divider
      FieldRow("Contact", placeholder: "Owner or main contact", text: $info.contactName)
      divider
      FieldRow("Email", placeholder: "name@example.com", text: $info.email) {
        CopyIconButton(value: info.email, help: "Copy email")
        IconButton(symbol: "paperplane", help: "Write email") { Links.mail(info.email) }
          .disabled(info.email.isEmpty)
      }
      divider
      FieldRow("Phone", placeholder: "+1 (555) 000-0000", text: $info.phone, monospaced: true) {
        CopyIconButton(value: info.phone, help: "Copy phone number")
      }
      divider
      FieldRow("Address", placeholder: "Street, City, State", text: $info.address) {
        IconButton(symbol: "mappin.and.ellipse", help: "Open in Google Maps") {
          if let u = Links.googleMaps(info.address) { open(u) }
        }
        .disabled(info.address.isEmpty)
      }
    }
    .workspaceCard()
  }

  private var divider: some View {
    Rectangle().fill(theme.divider).frame(height: 1)
  }
}

private struct FieldRow<Actions: View>: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var monospaced: Bool
  let actions: () -> Actions

  @FocusState private var focused: Bool
  @State private var hovering = false
  @Environment(\.workspaceTheme) private var theme

  init(_ label: String, placeholder: String, text: Binding<String>, monospaced: Bool = false,
       @ViewBuilder actions: @escaping () -> Actions) {
    self.label = label
    self.placeholder = placeholder
    self._text = text
    self.monospaced = monospaced
    self.actions = actions
  }

  var body: some View {
    HStack(spacing: 16) {
      Text(label)
        .font(.system(size: 13))
        .foregroundStyle(focused ? theme.accentInk : theme.muted)
        .frame(width: 112, alignment: .leading)
        .onTapGesture { focused = true }

      TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(theme.placeholder))
        .textFieldStyle(.plain)
        .labelsHidden()
        .font(monospaced ? .system(size: 13, design: .monospaced) : .system(size: 14))
        .foregroundStyle(theme.text)
        .focused($focused)
        .focusEffectDisabled()
        .padding(.horizontal, 10)
        .frame(height: 36)
        .focusRing(isFocused: focused, isHovering: hovering)
        .onHover { hovering = $0 }

      HStack(spacing: 4) { actions() }
        .frame(minWidth: 36, alignment: .trailing)
    }
    .padding(.leading, 20)
    .padding(.trailing, 12)
    .padding(.vertical, 10)
    .animation(.easeOut(duration: 0.15), value: focused)
  }
}

extension FieldRow where Actions == EmptyView {
  init(_ label: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) {
    self.init(label, placeholder: placeholder, text: text, monospaced: monospaced) { EmptyView() }
  }
}

// MARK: - Notes

private struct NotesCard: View {
  @Binding var notes: String
  @FocusState private var focused: Bool
  @State private var hovering = false
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Notes")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(focused ? theme.accentInk : theme.text)
        Text("Plan, renewal dates, client requests, DNS notes. Logins stay in cookies, not here.")
          .font(.system(size: 13))
          .foregroundStyle(theme.faint)
      }

      ZStack(alignment: .topLeading) {
        TextEditor(text: $notes)
          .font(.system(size: 14))
          .lineSpacing(4)
          .scrollContentBackground(.hidden)
          .focused($focused)
          .focusEffectDisabled()
          .padding(.horizontal, 11)
          .padding(.vertical, 10)

        if notes.isEmpty {
          Text("Start typing…")
            .font(.system(size: 14))
            .foregroundStyle(theme.placeholder)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .allowsHitTesting(false)
        }
      }
      .frame(minHeight: 220)
      .focusRing(
        isFocused: focused, isHovering: hovering, cornerRadius: 8,
        restingFill: theme.noteFill, restingStroke: theme.hairline, hoverStroke: theme.hairlineStrong
      )
      .onHover { hovering = $0 }
      .accessibilityLabel("Notes")
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 20)
    .workspaceCard()
    .animation(.easeOut(duration: 0.15), value: focused)
  }
}

// MARK: - Accounts

private struct AccountsCard: View {
  let open: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Accounts")
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)

      VStack(spacing: 0) {
        ForEach(ClientAccount.defaults) { account in
          AccountRow(account: account) { open(account.url) }
        }
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .workspaceCard()
  }
}

private struct AccountRow: View {
  let account: ClientAccount
  let action: () -> Void
  @State private var hovering = false
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Text(account.mono)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(theme.monoChipText)
          .frame(width: 32, height: 32)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.chipFill))
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.divider))

        VStack(alignment: .leading, spacing: 1) {
          Text(account.name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text)
          Text(account.role).font(.system(size: 12)).foregroundStyle(theme.faint)
        }

        Spacer(minLength: 0)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(hovering ? theme.text : theme.faint.opacity(0.7))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? theme.rowHover : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.12), value: hovering)
    .help(account.url)
  }
}

// MARK: - Quick links

private struct QuickLinksCard: View {
  @Binding var links: [QuickLink]
  let open: (String) -> Void
  @State private var showingAdd = false
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Quick links").font(.system(size: 14, weight: .semibold))

      if links.isEmpty {
        Text("Hosting panel, booking system, socials — anything else you open for this client.")
          .font(.system(size: 13))
          .foregroundStyle(theme.faint)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        VStack(spacing: 0) {
          ForEach(links) { link in
            QuickLinkRow(link: link) {
              open(link.url)
            } onRemove: {
              links.removeAll { $0.id == link.id }
            }
          }
        }
        .padding(.horizontal, -12)
      }

      Button {
        showingAdd = true
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
          Text("Add link")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(SecondaryButtonStyle())
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 20)
    .workspaceCard()
    .sheet(isPresented: $showingAdd) {
      AddLinkSheet { links.append($0) }
        .environment(\.workspaceTheme, theme)
    }
  }
}

private struct QuickLinkRow: View {
  let link: QuickLink
  let action: () -> Void
  var onRemove: () -> Void
  @State private var hovering = false
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: "link").font(.system(size: 12)).foregroundStyle(theme.faint)
        VStack(alignment: .leading, spacing: 1) {
          Text(link.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
          Text(URL(string: link.url)?.host() ?? link.url)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.faint)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(hovering ? theme.text : theme.faint.opacity(0.7))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? theme.rowHover : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .contextMenu {
      Button("Copy link") { Pasteboard.copy(link.url) }
      Button("Remove", role: .destructive, action: onRemove)
    }
  }
}

private struct AddLinkSheet: View {
  var onAdd: (QuickLink) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.workspaceTheme) private var theme
  @State private var title = ""
  @State private var urlText = ""
  @FocusState private var focus: Field?
  @State private var hover: Field?

  enum Field { case title, url }

  private var url: URL? { Links.normalized(urlText) }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Add quick link").font(.system(size: 15, weight: .semibold))

      VStack(alignment: .leading, spacing: 6) {
        Text("Name").font(.system(size: 12)).foregroundStyle(focus == .title ? theme.accentInk : theme.muted)
        TextField("Name", text: $title, prompt: Text("Booking system").foregroundStyle(theme.placeholder))
          .textFieldStyle(.plain).labelsHidden()
          .focused($focus, equals: .title).focusEffectDisabled()
          .padding(.horizontal, 10).frame(height: 34)
          .focusRing(
            isFocused: focus == .title, isHovering: hover == .title,
            restingFill: theme.chipFill, restingStroke: theme.hairline, hoverStroke: theme.hairlineStrong
          )
          .onHover { hover = $0 ? .title : nil }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("URL").font(.system(size: 12)).foregroundStyle(focus == .url ? theme.accentInk : theme.muted)
        TextField("URL", text: $urlText, prompt: Text("https://").foregroundStyle(theme.placeholder))
          .textFieldStyle(.plain).labelsHidden()
          .font(.system(size: 13, design: .monospaced))
          .focused($focus, equals: .url).focusEffectDisabled()
          .padding(.horizontal, 10).frame(height: 34)
          .focusRing(
            isFocused: focus == .url, isHovering: hover == .url,
            restingFill: theme.chipFill, restingStroke: theme.hairline, hoverStroke: theme.hairlineStrong
          )
          .onHover { hover = $0 ? .url : nil }
      }

      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .buttonStyle(SecondaryButtonStyle())
          .keyboardShortcut(.cancelAction)
        Button("Add link") {
          guard let url else { return }
          onAdd(QuickLink(title: title.isEmpty ? (url.host() ?? "Link") : title, url: url.absoluteString))
          dismiss()
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
        .disabled(url == nil)
      }
    }
    .padding(24)
    .frame(width: 400)
    .foregroundStyle(theme.text)
    .tint(theme.accent)
    .onAppear { focus = .title }
    .animation(.easeOut(duration: 0.15), value: focus)
  }
}

// MARK: - Buttons

private struct IconButton: View {
  let symbol: String
  let help: String
  var action: () -> Void
  @State private var hovering = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.workspaceTheme) private var theme

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(hovering && isEnabled ? theme.text : theme.faint)
        .frame(width: 36, height: 36)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering && isEnabled ? theme.chipHover : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.4)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.12), value: hovering)
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct CopyIconButton: View {
  let value: String
  let help: String
  @State private var copied = false

  var body: some View {
    IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: copied ? "Copied" : help) {
      Pasteboard.copy(value)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(1.2))
        copied = false
      }
    }
    .disabled(value.isEmpty)
    .contentTransition(.symbolEffect(.replace))
  }
}

private struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PrimaryButtonBody(configuration: configuration)
  }

  struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.workspaceTheme) private var theme

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.onAccent)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.accent.mixed(with: .white, by: hovering && isEnabled ? 0.12 : 0))
        )
        .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
  }
}

private struct SecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    SecondaryButtonBody(configuration: configuration)
  }

  struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.workspaceTheme) private var theme

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? theme.chipHover : theme.chipFill))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.hairline))
        .opacity(configuration.isPressed ? 0.8 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
  }
}

// MARK: - Modifiers

private struct WorkspaceCardModifier: ViewModifier {
  @Environment(\.workspaceTheme) private var theme

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    content
      .background {
        ZStack {
          shape.fill(.ultraThinMaterial)
          shape.fill(theme.cardFill)
        }
      }
      .clipShape(shape)
      .overlay(shape.strokeBorder(theme.hairline, lineWidth: 1))
      .shadow(color: theme.cardShadow, radius: 16, x: 0, y: 8)
  }
}

/// Accent outline + soft outer halo when focused; quiet fill on hover.
private struct FocusRingModifier: ViewModifier {
  var isFocused: Bool
  var isHovering: Bool
  var cornerRadius: CGFloat = 6
  var restingFill: Color = .clear
  var restingStroke: Color = .clear
  var hoverStroke: Color? = nil
  @Environment(\.workspaceTheme) private var theme

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let fill: Color = isFocused ? theme.fieldFocusFill : (isHovering ? theme.fieldHoverFill : restingFill)
    let stroke: Color = isFocused
      ? theme.accent.opacity(0.75)
      : (isHovering ? (hoverStroke ?? restingStroke) : restingStroke)

    content
      .background(shape.fill(fill))
      .overlay(shape.strokeBorder(stroke, lineWidth: 1))
      .background(
        // Halo: a 4pt band just outside the field's edge.
        RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
          .stroke(theme.accent.opacity(isFocused ? theme.haloOpacity : 0), lineWidth: 4)
          .padding(-2)
      )
      .animation(.easeOut(duration: 0.15), value: isFocused)
      .animation(.easeOut(duration: 0.15), value: isHovering)
  }
}

private extension View {
  func workspaceCard() -> some View { modifier(WorkspaceCardModifier()) }

  func focusRing(isFocused: Bool, isHovering: Bool, cornerRadius: CGFloat = 6,
                 restingFill: Color = .clear, restingStroke: Color = .clear, hoverStroke: Color? = nil) -> some View {
    modifier(FocusRingModifier(
      isFocused: isFocused, isHovering: isHovering, cornerRadius: cornerRadius,
      restingFill: restingFill, restingStroke: restingStroke, hoverStroke: hoverStroke
    ))
  }
}

// MARK: - Helpers

private enum Pasteboard {
  static func copy(_ string: String) {
    guard !string.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
  }
}

private enum Links {
  static func normalized(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
    guard let url = URL(string: withScheme), url.host() != nil else { return nil }
    return url
  }

  static func mail(_ address: String) {
    let trimmed = address.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty, let url = URL(string: "mailto:\(trimmed)") { NSWorkspace.shared.open(url) }
  }

  static func googleMaps(_ address: String) -> String? {
    let trimmed = address.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty,
          let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    return "https://www.google.com/maps/search/?api=1&query=\(q)"
  }
}
