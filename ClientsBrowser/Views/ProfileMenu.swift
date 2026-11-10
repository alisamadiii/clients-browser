import SwiftUI

/// Client switcher button in the tab strip.
struct ProfileButton: View {
  @Environment(BrowserController.self) private var controller
  @State private var confirmDelete = false

  var body: some View {
    let current = controller.profile
    Menu {
      ForEach(controller.store.profiles) { p in
        Button {
          controller.switchProfile(p.id)
        } label: {
          Label {
            Text(p.name)
          } icon: {
            Image(systemName: p.id == current?.id ? "checkmark.circle.fill" : "circle.fill")
          }
        }
        .tint(Color(hex: p.color))
      }
      Divider()
      Button("New Client…") { controller.showNewProfile = true }
      Button("Switch Client…") { controller.showProfileSwitcher = true }
      if let current {
        Divider()
        Button("Edit “\(current.name)”…") { controller.editingProfile = current }
        Button("Delete “\(current.name)”…", role: .destructive) { confirmDelete = true }
      }
    } label: {
      HStack(spacing: 6) {
        Circle().fill(Color(hex: current?.color ?? "#2F6BFF")).frame(width: 10, height: 10)
        Text(current?.name ?? "Client").font(.system(size: 12, weight: .semibold)).lineLimit(1)
      }
      .padding(.horizontal, 8)
      .frame(height: 28)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("Switch client (⌘⇧P)")
    .confirmationDialog(
      "Delete “\(current?.name ?? "")”?",
      isPresented: $confirmDelete,
      titleVisibility: .visible
    ) {
      Button("Delete Client and All Its Logins", role: .destructive) {
        if let id = current?.id { Task { await controller.deleteProfile(id) } }
      }
    } message: {
      Text("Every cookie, saved login and tab for this client is removed from this Mac. The last backup string still contains them.")
    }
  }
}

/// New / edit client sheet.
struct ProfileEditor: View {
  @Environment(BrowserController.self) private var controller
  @Environment(\.dismiss) private var dismiss
  let profile: Profile?
  @State private var name = ""
  @State private var color = Profile.palette[0]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(profile == nil ? "New Client" : "Edit Client").font(.title3.bold())
      TextField("Client name", text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)
      HStack(spacing: 8) {
        ForEach(Profile.palette, id: \.self) { hex in
          Circle()
            .fill(Color(hex: hex))
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.primary, lineWidth: hex == color ? 2 : 0).padding(-3))
            .onTapGesture { color = hex }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(profile == nil ? "Create" : "Save", action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 360)
    .onAppear {
      if let profile {
        name = profile.name
        color = profile.color
      } else {
        let used = Set(controller.store.profiles.map(\.color))
        color = Profile.palette.first { !used.contains($0) } ?? Profile.palette[0]
      }
    }
  }

  private func save() {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    if let profile {
      controller.store.renameProfile(profile.id, name: trimmed, color: color)
    } else {
      controller.createProfile(name: trimmed, color: color)
    }
    dismiss()
  }
}

/// ⌘⇧P: type to filter, Enter to switch.
struct ProfileSwitcher: View {
  @Environment(BrowserController.self) private var controller
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var selection: UUID?
  @FocusState private var focused: Bool

  private var matches: [Profile] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    let all = controller.store.profiles
    return q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Switch to client…", text: $query)
          .textFieldStyle(.plain)
          .font(.title3)
          .focused($focused)
          .onSubmit(choose)
          .onKeyPress(.downArrow) { move(1); return .handled }
          .onKeyPress(.upArrow) { move(-1); return .handled }
      }
      .padding(14)
      Divider()
      List(matches, selection: $selection) { p in
        HStack(spacing: 10) {
          Circle().fill(Color(hex: p.color)).frame(width: 10, height: 10)
          Text(p.name)
          Spacer()
          if p.id == controller.profile?.id { Text("current").font(.caption).foregroundStyle(.secondary) }
        }
        .tag(p.id)
        .contentShape(Rectangle())
        .onTapGesture { selection = p.id; choose() }
      }
      .listStyle(.plain)
      .frame(height: 260)
    }
    .frame(width: 420)
    .onAppear {
      focused = true
      selection = controller.profile?.id ?? matches.first?.id
    }
    .onChange(of: query) { _, _ in selection = matches.first?.id }
    .onExitCommand { dismiss() }
  }

  private func move(_ d: Int) {
    let m = matches
    guard !m.isEmpty else { return }
    let i = m.firstIndex { $0.id == selection } ?? -1
    selection = m[max(0, min(m.count - 1, i + d))].id
  }

  private func choose() {
    guard let id = selection ?? matches.first?.id else { return }
    controller.switchProfile(id)
    dismiss()
  }
}
