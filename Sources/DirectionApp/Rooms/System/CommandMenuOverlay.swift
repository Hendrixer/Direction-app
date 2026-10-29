import SwiftUI
import AppKit
import DirectionCore

/// Frame 49: the command menu (⌘K). Every menu bar command, plus notes, scenes, takes, cuts,
/// settings and help, with fuzzy search. ↑↓ move, ↩ runs, ⌘↩ runs and stays, ⇥ narrows, esc clears then closes.
struct CommandMenuOverlay: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    /// Snapshots: a query already typed.
    var initialQuery = ""
    @State private var query = ""
    @State private var selected = 0
    @State private var filter: CommandSection?
    @State private var help: (String, String)?
    @State private var keys = CommandKeys()
    @FocusState private var focused: Bool
    @Environment(\.openSettings) private var openSettingsAction
    @AppStorage(SettingsKey.recentCommands) private var recentRaw = ""

    struct Row: Identifiable { var item: CommandItem; var hits: Set<Int>; var id: String { item.section.title + item.id } }
    struct ResultGroup: Identifiable { var section: CommandSection; var rows: [Row]; var id: Int { section.rawValue } }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: close)
                .accessibilityHidden(true)
            panel.padding(.top, 120)
        }
        .onAppear {
            query = SystemPreview.commandQuery[ObjectIdentifier(model)] ?? initialQuery; focused = true
            if let f = CommandMenuLaunch.pendingFilter { filter = f; CommandMenuLaunch.pendingFilter = nil }
            if !model.isPreview { keys.install { handle($0) } }
        }
        .onDisappear { keys.remove() }
        .onChange(of: query) { _, _ in selected = firstRunnable; help = nil }
        .onChange(of: filter) { _, _ in selected = firstRunnable }
        .transition(.opacity)
    }

    // MARK: Data

    private var catalog: CommandCatalog {
        CommandCatalog(model: model, app: app, openSettings: { tab, row in openSettings(tab, row) }, showHelp: { q, a in help = (q, a) })
    }

    private var groups: [ResultGroup] {
        let all = catalog.items()
        let q = query.trimmingCharacters(in: .whitespaces)
        var out: [ResultGroup] = []
        if q.isEmpty && filter == nil {
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let recent = recentIDs.compactMap { byID[$0] }.prefix(5).map { var i = $0; i.section = .recent; return Row(item: i, hits: []) }
            let suggested = catalog.suggestedIDs().compactMap { byID[$0] }.filter { s in !recent.contains { $0.item.id == s.id } }.map { var i = $0; i.section = .suggested; return Row(item: i, hits: []) }
            if !recent.isEmpty { out.append(ResultGroup(section: .recent, rows: Array(recent))) }
            if !suggested.isEmpty { out.append(ResultGroup(section: .suggested, rows: suggested)) }
            return out
        }
        // "n music is too loud" offers a note at the playhead first.
        if q.lowercased().hasPrefix("n "), q.count > 2 {
            let text = String(q.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let at = FilmActions(model).timecode
            out.append(ResultGroup(section: .actions, rows: [Row(item: CommandItem(id: "action.noteToSelf", section: .actions, icon: "text.bubble", title: "Add note at \(at): \(text)", disabledReason: model.duration > 0 ? nil : "Nothing to watch yet") {
                model.addNote(text: text, time: model.position)
                model.toast = Toast(title: "Note added at \(at)", detail: text)
            }, hits: [])]))
        }
        for section in CommandSection.allCases where section != .recent && section != .suggested {
            if let filter, filter != section { continue }
            let rows = all.filter { $0.section == section }.compactMap { item -> (Row, Int)? in
                if q.isEmpty { return (Row(item: item, hits: []), 0) }
                guard let m = CommandMatcher.match(q, in: item.searchText, synonyms: item.synonyms) else { return nil }
                return (Row(item: item, hits: m.hits), m.score - (item.disabledReason == nil ? 0 : 600))
            }
            .sorted { $0.1 > $1.1 }.map(\.0)
            if rows.isEmpty { continue }
            if let i = out.firstIndex(where: { $0.section == section }) { out[i].rows += rows } else { out.append(ResultGroup(section: section, rows: Array(rows.prefix(q.isEmpty ? 40 : 6)))) }
        }
        return out
    }

    private var flat: [Row] { groups.flatMap(\.rows) }
    private var firstRunnable: Int { flat.firstIndex { $0.item.disabledReason == nil } ?? 0 }
    private var recentIDs: [String] { recentRaw.split(separator: "\n").map(String.init) }

    private var context: String {
        if let filter { return filter.title }
        return "\(model.room.title) · \(model.watchedCut?.name ?? "No cut yet")"
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            input
            if let help { helpCard(help) } else { list }
            footer
        }
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Gate.Surface.panel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
        .overlay(alignment: .top) { Color.white.opacity(0.06).frame(height: 1).padding(.horizontal, 14).padding(.top, 1) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.95), radius: 50, y: 40)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command menu")
    }

    private var input: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
            TextField("", text: $query, prompt: Text("Search commands, notes, scenes, takes").foregroundColor(Gate.Text.disabled))
                .textFieldStyle(.plain).font(.system(size: 16)).foregroundStyle(Gate.Text.primary)
                .focused($focused)
                .accessibilityLabel("Command menu")
            OutlineChip(context)
        }
        .padding(.horizontal, 18).frame(height: 52)
        .overlay(alignment: .bottom) { SystemHairline() }
    }

    @ViewBuilder private var list: some View {
        let groups = self.groups
        let ids = groups.flatMap(\.rows).map(\.id)
        let index = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if ids.isEmpty { noResults }
                    ForEach(groups) { group in
                        SectionLabel(group.section.title).padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 5)
                        ForEach(group.rows) { row in
                            let i = index[row.id] ?? 0
                            rowView(row, selected: i == selected).id(row.id)
                                .onTapGesture { selected = i; run(row.item, keepOpen: false) }
                                .onHover { if $0 { selected = i } }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 400)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selected) { _, i in if ids.indices.contains(i) { proxy.scrollTo(ids[i]) } }
        }
    }

    @ViewBuilder private var noResults: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.disabled).frame(width: 15)
                Text("No matches for \u{201C}\(q)\u{201D}").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary)
            }
            .padding(.horizontal, 12).frame(height: 36)
            Button { close(); FilmActions(model).startNote(text: q) } label: {
                HStack(spacing: 12) {
                    GemMark(size: 8).frame(width: 15)
                    Text("Ask the editor: \u{201C}\(q)\u{201D}").font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                    Spacer()
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.hover))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func rowView(_ row: Row, selected: Bool) -> some View {
        let item = row.item, disabled = item.disabledReason != nil
        return HStack(spacing: 12) {
            Group {
                if item.icon == "mappin" { PinMark(size: 11) } else if item.icon == "diamond" { GemMark(size: 8) } else { Image(systemName: item.icon).font(.system(size: 13, weight: .medium)) }
            }
            .foregroundStyle(Gate.Text.tertiary).frame(width: 15)
            HStack(spacing: 6) {
                if let n = item.number { Text(n).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Voice.director) }
                highlighted(item, hits: row.hits, disabled: disabled).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 12)
            if let reason = item.disabledReason { Text(reason).font(Gate.Font.small).foregroundStyle(Gate.Text.disabled).lineLimit(1).fixedSize() }
            else {
                switch item.trailing {
                case .keys(let k): KeyCaps(keys: k, small: true)
                case .caption(let c): Text(c).font(Gate.Font.small).foregroundStyle(Gate.Text.disabled).lineLimit(1).fixedSize()
                case .none: EmptyView()
                }
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Gate.Surface.hover : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.section.title): \(item.searchText)")
        .accessibilityValue(item.disabledReason ?? "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// Matched characters in 600 text-1 (text-3 when disabled); the title in text-1, the sub in text-3.
    private func highlighted(_ item: CommandItem, hits: Set<Int>, disabled: Bool) -> Text {
        let full = Array(item.searchText), titleCount = item.title.count
        let runs = full.enumerated().map { i, ch -> TextRun in
            let inTitle = i < titleCount, hit = hits.contains(i)
            let color: Color = disabled ? (hit ? Gate.Text.tertiary : Gate.Text.disabled) : hit || inTitle ? Gate.Text.primary : Gate.Text.tertiary
            return TextRun(String(ch), color, hit ? .semibold : .regular)
        }
        return TextRun.line(runs, size: 13)
    }

    private func helpCard(_ help: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                Text(help.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            }
            Text(help.1).font(Gate.Font.body).foregroundStyle(Gate.Text.secondary).cssLineHeight(1.45, size: 13).fixedSize(horizontal: false, vertical: true).padding(.leading, 25)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint(["↑", "↓"], "Move")
            hint(["↩"], "Run")
            hint(["⇥"], filter == nil ? "Narrow to section" : "Next section")
            Spacer(minLength: 8)
            hint(["esc"], help != nil ? "Back" : query.isEmpty ? "Close" : "Clear")
        }
        .font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
        .padding(.horizontal, 16).frame(height: 36)
        .overlay(alignment: .top) { SystemHairline() }
    }

    private func hint(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 6) { KeyCaps(keys: keys, small: true); Text(text) }
    }

    // MARK: Keys and running

    /// Returns true when the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        let rows = flat
        switch event.keyCode {
        case 126: selected = max(0, selected - 1); return true
        case 125: selected = min(max(0, rows.count - 1), selected + 1); return true
        case 36, 76:
            if rows.isEmpty, !query.trimmingCharacters(in: .whitespaces).isEmpty { close(); FilmActions(model).startNote(text: query.trimmingCharacters(in: .whitespaces)); return true }
            if rows.indices.contains(selected) { run(rows[selected].item, keepOpen: event.modifierFlags.contains(.command)) }
            return true
        case 48:
            let present = groups.map(\.section).filter { $0 != .recent && $0 != .suggested }
            let order = CommandSection.allCases.filter { $0 != .recent && $0 != .suggested && (present.contains($0) || filter == $0 || query.isEmpty) }
            if let f = filter, let i = order.firstIndex(of: f) { filter = i + 1 < order.count ? order[i + 1] : nil } else { filter = order.first }
            return true
        case 53:
            if help != nil { help = nil } else if !query.isEmpty { query = "" } else if filter != nil { filter = nil } else { close() }
            return true
        default: return false
        }
    }

    private func run(_ item: CommandItem, keepOpen: Bool) {
        guard item.disabledReason == nil else { NSSound.beep(); return }
        var recent = recentIDs.filter { $0 != item.id && !$0.hasPrefix("help.") }
        if !item.id.hasPrefix("help."), item.id != "action.noteToSelf" { recent.insert(item.id, at: 0) }
        recentRaw = recent.prefix(5).joined(separator: "\n")
        if item.section == .help || (keepOpen && item.keepsOpen) { item.run(); return }
        close()
        DispatchQueue.main.async { MainActor.assumeIsolated { item.run() } }
    }

    private func close() { withAnimation(Gate.Motion.snap) { model.showCommandMenu = false } }

    private func openSettings(_ tab: SettingsTab, _ row: String?) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsKey.settingsTab)
        if let row { UserDefaults.standard.set(row, forKey: SettingsKey.settingsFlash) }
        openSettingsAction()
    }
}

/// The command menu's keys while it's open: arrows, return, tab and esc go to the menu, the rest to the field.
@MainActor
final class CommandKeys {
    private var monitor: Any?
    func install(_ handle: @escaping @MainActor (NSEvent) -> Bool) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard [126, 125, 36, 76, 48, 53].contains(event.keyCode), !event.modifierFlags.contains(.option),
                  event.window?.frameAutosaveName == "DirectionMainWindow" else { return event }
            let used = MainActor.assumeIsolated { handle(event) }
            return used ? nil : event
        }
    }
    func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
