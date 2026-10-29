import SwiftUI
import AppKit

/// Frame 50: every keyboard shortcut, from the same registry as the menu bar and Settings › Shortcuts.
/// `?` (no text field focused) or Help › Keyboard Shortcuts (⌘/). esc closes.
struct ShortcutsOverlay: View {
    @Bindable var model: FilmModel
    @State private var query = ""
    @State private var store = ShortcutStore.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            Gate.Surface.scrim.ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                head
                grid.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 22)
            }
            .frame(width: 1000)
            .background(Gate.Surface.ground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
            .shadow(color: .black.opacity(0.9), radius: 40, y: 30)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Keyboard shortcuts")
            .accessibilityAddTraits(.isModal)
            .onExitCommand(perform: close)
        }
        .transition(.opacity)
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Keyboard").font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary).accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                    TextField("", text: $query, prompt: Text("Search shortcuts").foregroundColor(Gate.Text.disabled)).textFieldStyle(.plain).font(Gate.Font.body)
                }
                .padding(.horizontal, 10).frame(width: 220, height: Gate.Size.control).background(GateFieldBackground())
            }
            TextRun.line([TextRun("Keys work in the room shown. Change them in ", Gate.Text.tertiary), TextRun("Settings \u{203A} Shortcuts", Gate.Text.secondary), TextRun(".", Gate.Text.tertiary)], size: 12)
                .onTapGesture {
                    UserDefaults.standard.set(SettingsTab.shortcuts.rawValue, forKey: SettingsKey.settingsTab)
                    close(); openSettings()
                }
                .accessibilityAddTraits(.isLink)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 10)
    }

    private var grid: some View {
        let groups = ShortcutGroup.allCases.map { g in (g, ShortcutAction.overlayActions.filter { $0.group == g && matches($0) }) }.filter { !$0.1.isEmpty }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 36, alignment: .top), count: 3)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(groups, id: \.0) { group, actions in
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(group.title).padding(.bottom, 8)
                    ForEach(actions) { row($0) }
                }
            }
        }
    }

    private func row(_ action: ShortcutAction) -> some View {
        let elsewhere = !action.rooms.contains(model.room)
        return HStack(spacing: 4) {
            Text(action.label).font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).lineLimit(1)
            if store.isEdited(action) { Text("Edited").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).padding(.leading, 4) }
            Spacer(minLength: 8)
            KeyCaps(keys: store.caps(action), dimmed: elsewhere)
        }
        .frame(height: 28)
        .help(elsewhere ? "Works in \(roomNames(action))" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(action.label), \(store.caps(action).joined(separator: " "))")
    }

    private func roomNames(_ action: ShortcutAction) -> String {
        Room.allCases.filter { action.rooms.contains($0) }.map(\.title).joined(separator: ", ")
    }

    private func matches(_ action: ShortcutAction) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || action.label.lowercased().contains(q) || store.caps(action).joined(separator: " ").lowercased().contains(q)
    }

    private func close() { withAnimation(Gate.Motion.snap) { model.showShortcuts = false } }
}
