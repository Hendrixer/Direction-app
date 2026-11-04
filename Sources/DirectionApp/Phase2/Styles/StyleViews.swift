import SwiftUI
import AppKit
import DirectionCore

// Styles (specs/styles.md): the brief's Style question, asking the editor to make one, and
// Settings › Styles, where the house style and each style's rules can be written by hand.

/// Sample styles for snapshots and previews, so nothing reads the director's own folder there.
enum StyleSamples {
    static let folder = URL(fileURLWithPath: "/tmp/direction-sample-styles", isDirectory: true)
    static func rules(_ list: [(String, String)]) -> JSONValue { .array(list.enumerated().map { i, r in .object(["id": .string("rule-\(i + 1)"), "area": .string(r.0), "text": .string(r.1)]) }) }
    static var styles: [Style] {
        var a = StyleContents(); a.graphics = ["captions", "lower-third", "title"]; a.transitions = ["push.metal"]; a.sounds = ["pop.wav", "whoosh.wav"]; a.look = true
        var b = StyleContents(); b.graphics = ["chapter-card"]; b.music = ["bed.m4a"]
        var c = StyleContents(); c.graphics = ["captions", "keys", "step", "title"]; c.sounds = ["click.wav", "whoosh.wav"]; c.look = true
        let screenLayouts: JSONValue = .array([
            .object(["name": .string("Talking"), "kind": .string("you")]),
            .object(["name": .string("Showing"), "kind": .string("screenAndYou"), "corner": .string("bottomRight"), "size": .string("medium"), "shape": .string("rounded")]),
            .object(["name": .string("Detail"), "kind": .string("screen")]),
        ])
        return [
            Style(id: "desk-screen", url: folder.appendingPathComponent("desk-screen"), name: "Desk + Screen", summary: "Talking to camera, then showing it on screen, you in the corner when it helps.", updatedAt: 0, tokens: .object([
                "format": .number(2), "layouts": screenLayouts,
                "transitions": .array([
                    .object(["name": .string("New section"), "type": .string("slide"), "frames": .number(8), "sound": .string("sounds/whoosh.wav")]),
                    .object(["name": .string("Chapter"), "type": .string("shader"), "file": .string("transitions/glint.metal"), "frames": .number(10), "sound": .string("sounds/whoosh.wav")]),
                ]),
                "moves": .object(["punchIn": .object(["scales": .array([.number(1), .number(1.15)]), "keepIn": .string("thirds")]), "emphasisPunch": .object(["scale": .number(1.32)])]),
                "rules": rules([("pace", "Cut waiting on screen down to its last half second."), ("layouts", "Talking for the talk, Showing when the screen comes in, Detail for code and forms."),
                                ("picture", "Zoom to what I'm talking about whenever its text would be under 24 px at 1080p."), ("captions", "Captions over the screen only where they don't cover what's shown.")]),
            ]), contents: c),
            Style(id: "desk-talk", url: folder.appendingPathComponent("desk-talk"), name: "Desk Talk", summary: "Quick explainers: 3-second shots, punch-ins, bold captions.", updatedAt: 0, tokens: .object([
                "format": .number(2), "rules": rules([("pace", "Tighten every pause longer than 0.35 s to about 0.15 s."), ("picture", "Change framing on every jump cut."), ("avoid", "Dissolves and stock transitions.")]),
            ]), contents: a),
            Style(id: "long-walk", url: folder.appendingPathComponent("long-walk"), name: "Long Walk", summary: "Slow and wide. Shots hold; music carries it.", updatedAt: 0, tokens: .object(["format": .number(2), "rules": rules([("pace", "Let shots hold.")])]), contents: b),
        ]
    }
    static var house: Style {
        Style(id: StyleLibrary.houseID, url: folder.appendingPathComponent(StyleLibrary.houseID), name: StyleLibrary.houseName, summary: "", updatedAt: 0, tokens: .object([
            "format": .number(2), "rules": rules([("graphics", "Text never covers my face."), ("captions", "No captions over full-screen graphics.")]),
        ]), contents: StyleContents())
    }
    static func applied(_ id: String?) -> AppliedStyle { AppliedStyle(house: house, style: styles.first { $0.id == id }) }
}

/// The brief's Style question: one field that opens a searchable list (None first, then your styles),
/// and New Style beside it, to write one or have the editor make one. Picking one gives the film its
/// own copy when the brief is saved.
struct BriefStylePicker: View {
    var model: FilmModel
    @Binding var style: String?
    @State private var styles: [Style] = []
    @State private var open = false
    @State private var asking = false
    @State private var writing: StyleDraft?
    @State private var fromVideo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            picker
            // The film keeps its own copy; when the style has changed since, the director can take the new one.
            if let current, let copy, style == copy.id, current.updatedAt > copy.updatedAt + 1 {
                HStack(spacing: 6) {
                    Text("\(current.name) has changed since this film took it.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                    Button("Use the new version") { model.perform { try $0.refreshStyle() }; load() }.buttonStyle(.gate(.ghost, .small))
                }
            }
        }
    }

    /// The film's own copy of its style, to tell when the one in the Styles folder is newer.
    private var copy: Style? { model.isPreview ? nil : try? model.store?.style() }

    private var picker: some View {
        HStack(spacing: 8) {
            Button { load(); open = true } label: { field }
                .buttonStyle(.plain)
                .gatePopover(isPresented: $open, arrowEdge: .bottom) {
                    StyleList(styles: styles, chosen: style) { picked in style = picked; open = false }
                }
                .accessibilityLabel("Style")
                .accessibilityValue(current.map { "\($0.name). \($0.summary)" } ?? "None")
            Menu {
                Button("Write One\u{2026}") { writing = .new }
                Button("Make One with the Editor\u{2026}") { asking = true }
                Button("Make One from a Video\u{2026}") { fromVideo = true }.disabled(model.learning != nil)
                Divider()
                OpenSettingsButton(tab: .styles) { Text("Your Styles\u{2026}") }
            } label: {
                HStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)); Text("New Style") }
                    .font(Gate.Font.control).foregroundStyle(Gate.Text.primary)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: Gate.Radius.control).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .gatePopover(isPresented: $asking, arrowEdge: .bottom) { MakeStylePopover(model: model) { asking = false } }
        }
        .task { load() }
        .onChange(of: model.runs.runs.filter { $0.job == .style }.map(\.state)) { _, _ in load() }
        .sheet(item: $writing) { StyleEditSheet(draft: $0, folder: SharedSettings.stylesFolder, saved: { style = $0.id; load() }) { writing = nil } }
        .sheet(isPresented: $fromVideo) { StyleFromVideoSheet(model: model) { fromVideo = false } }
    }

    private var current: Style? { style.flatMap { id in styles.first { $0.id == id } } }

    /// What's chosen: its name and sentence on one line, or None.
    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "swatchpalette").font(.system(size: 12, weight: .medium)).foregroundStyle(current == nil ? Gate.Text.disabled : Gate.Voice.director).frame(width: 16)
            Text(current?.name ?? (style == nil ? "None" : style!)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).lineLimit(1).fixedSize()
            Text(current?.summary ?? (style == nil ? "Your house style, the brief and your notes." : "Not in your styles folder; the film keeps its copy.")).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Gate.Text.tertiary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(GateFieldBackground(focused: open))
        .contentShape(Rectangle())
    }

    private func load() { styles = model.isPreview ? StyleSamples.styles : StyleLibrary.list(in: SharedSettings.stylesFolder) }
}

/// The dropdown: search at the top, None and every style that matches, ↑↓ and Return to choose.
struct StyleList: View {
    var styles: [Style]
    var chosen: String?
    var pick: (String?) -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    /// None, then the styles whose name, sentence or contents match every word typed.
    private var rows: [Style?] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matching = styles.filter { s in words.allSatisfy { w in "\(s.name) \(s.summary) \(s.contents.line)".lowercased().contains(w) } }
        let none = words.isEmpty || words.allSatisfy { "none no style".contains($0) }
        return (none ? [nil] : []) + matching.map { Optional($0) }
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                TextField("", text: $query, prompt: Text("Search styles").foregroundColor(Gate.Text.disabled))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).focused($focused)
                    .onSubmit { if rows.indices.contains(selected) { pick(rows[selected]?.id) } }
                    .onKeyPress(.downArrow) { selected = min(rows.count - 1, selected + 1); return .handled }
                    .onKeyPress(.upArrow) { selected = max(0, selected - 1); return .handled }
                    .accessibilityLabel("Search styles")
            }
            .padding(.horizontal, 14).frame(height: 42)
            .overlay(alignment: .bottom) { SystemHairline() }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        if rows.isEmpty {
                            Text("No styles match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 40)
                        }
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, s in
                            row(s, selected: i == selected).id(i)
                                .onTapGesture { pick(s?.id) }
                                .onHover { if $0 { selected = i } }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selected) { _, i in proxy.scrollTo(i) }
            }
            HStack {
                Text("\u{2191}\u{2193} to move, \u{21A9} to choose").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled)
                Spacer()
                OpenSettingsButton(tab: .styles) { Text("Your Styles\u{2026}") }.buttonStyle(.gate(.ghost, .small))
            }
            .padding(.horizontal, 12).frame(height: 36)
            .overlay(alignment: .top) { SystemHairline() }
        }
        .frame(width: 460)
        .background(Gate.Surface.panel)
        .onAppear { focused = true; selected = rows.firstIndex { $0?.id == chosen } ?? 0 }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func row(_ s: Style?, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Gate.Voice.director).frame(width: 14).padding(.top, 2)
                .opacity(s?.id == chosen ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(s?.name ?? "None").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).lineLimit(1)
                Text(s?.summary ?? "Your house style, the brief and your notes.").font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let line = s?.contents.line, !line.isEmpty { Text(line).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Gate.Surface.hover : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.map { "\($0.name). \($0.summary)" } ?? "None. Your house style, the brief and your notes.")
        .accessibilityAddTraits(s?.id == chosen ? [.isSelected, .isButton] : .isButton)
    }
}

/// "Make one with the editor": what it should be like, in your words, and whether to learn from this film.
struct MakeStylePopover: View {
    var model: FilmModel
    var done: () -> Void
    @State private var request = ""
    @State private var fromFilm = true
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make a style").font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
            Text("Say how your videos should look, sound and move. Name channels or videos you like and what you like about them.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
            GateTextArea(text: $request, placeholder: "Fast and friendly, like a good tech explainer. Bold yellow captions, a whoosh on every cut to the screen.", minHeight: 92)
            if !model.cuts.isEmpty {
                Toggle("Learn from how \(model.latestCut?.name ?? "this film") is cut", isOn: $fromFilm).toggleStyle(.checkbox).font(Gate.Font.small)
            }
            if failed {
                Text("Direction doesn\u{2019}t start the editor here. Ask your own session: \u{201C}Make me a style\u{201D} (the make-style skill).")
                    .font(Gate.Font.small).foregroundStyle(Gate.State.alert).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("It goes in your styles when it\u{2019}s done.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                Spacer()
                Button("Cancel", action: done).buttonStyle(.gate(.normal, .small)).keyboardShortcut(.cancelAction)
                Button("Make it") {
                    if model.runs.makeStyle(model, request: request.trimmingCharacters(in: .whitespacesAndNewlines), fromFilm: fromFilm && !model.cuts.isEmpty) { done() } else { failed = true }
                }
                .buttonStyle(.gate(.steel, .small)).disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.cuts.isEmpty)
            }
        }
        .padding(16).frame(width: 380)
    }
}

// MARK: Settings › Styles

struct StylesPane: View {
    var app: AppModel?
    var preview = false
    @AppStorage(SharedSettings.stylesFolderKey, store: SharedSettings.defaults) private var folder = SharedSettings.defaultStylesFolder
    @State private var styles: [Style] = []
    @State private var house: Style?
    @Environment(\.settingsPages) private var pages

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Every film") {
                let count = house?.rules.count ?? 0
                SettingsLinkRow(label: StyleLibrary.houseName, detail: count == 0 ? "Rules every film follows. Keep one from an answer in the Cut room, or write one here." : "\(count) rule\(count == 1 ? "" : "s") every film follows. A film\u{2019}s style wins where it says otherwise.", first: true) {
                    if let house { open(.init(house)) }
                }
            }
            SettingsGroup(label: "Your styles", note: AnyView(SettingsNote("A style is how a kind of video looks, sounds and moves: its rules, its layouts, the moves Direction makes for it (punch-ins, pushes) and the parts the editor reuses, like titles, captions, transitions and sounds. Pick one in a film\u{2019}s brief. Make one with the editor from the brief, or write one here."))) {
                if styles.isEmpty {
                    SettingsRow(label: "No styles yet", detail: "Make one with the editor from a film\u{2019}s brief, or start one here.", first: true) {
                        Button("New Style") { open(.new) }.buttonStyle(.gate)
                    }
                }
                ForEach(Array(styles.enumerated()), id: \.element.id) { i, s in
                    SettingsLinkRow(label: s.name, detail: [s.summary, StyleDraft.holds(s)].filter { !$0.isEmpty }.joined(separator: "\n"), first: i == 0) { open(.init(s)) }
                }
            }
            if !styles.isEmpty {
                HStack { Spacer(); Button("New Style") { open(.new) }.buttonStyle(.gate) }.padding(.top, 2)
            }
            SettingsGroup(label: "Where they live") {
                SettingsRow(label: "Styles folder", detail: "One folder for each style. Copy one to share it; drop one in to use it.", first: true) {
                    Text(displayPath).font(.system(size: 12)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).frame(width: 230, height: Gate.Size.control, alignment: .leading).background(GateFieldBackground()).help(expanded)
                    Button("Change\u{2026}") { choose() }.buttonStyle(.gate)
                    Button("Show in Finder") { revealFolder() }.buttonStyle(.gate)
                }
            }
        }
        .task(id: folder) { load() }
    }

    /// A style opens as a page in Settings, with Back to the list.
    private func open(_ draft: StyleDraft) {
        let title = draft.isHouse ? StyleLibrary.houseName : draft.isNew ? "New style" : draft.name
        pages?.open(SettingsPage(id: "style:" + draft.id, title: title) { StylePage(draft: draft, folder: stylesURL) })
    }

    private var expanded: String { NSString(string: folder.isEmpty ? SharedSettings.defaultStylesFolder : folder).expandingTildeInPath }
    private var displayPath: String { preview ? "~/Movies/Direction/Styles" : (expanded as NSString).abbreviatingWithTildeInPath }
    private var stylesURL: URL { preview ? StyleSamples.folder : SharedSettings.stylesFolder }
    private func load() {
        styles = preview ? StyleSamples.styles : StyleLibrary.list(in: SharedSettings.stylesFolder)
        house = preview ? StyleSamples.house : StyleLibrary.house(in: SharedSettings.stylesFolder)
    }

    private func choose() {
        guard !preview else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a styles folder"; panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: expanded)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path
    }
    private func revealFolder() {
        guard !preview else { return }
        let url = SharedSettings.stylesFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// A style being written: a new one, one of yours, or the house style.
struct StyleDraft: Identifiable, Hashable {
    var id: String
    var style: Style?
    var name = "", summary = ""
    var rules: [StyleRule] = []
    /// A rule still being typed in the add row, and its kind: it goes in when the style is saved or made.
    var pending = "", pendingArea = "general"
    var isHouse: Bool { style?.isHouse == true }
    var isNew: Bool { style == nil }
    /// What gets written; typing in the add row changes nothing until the rule is added.
    struct Written: Hashable { var name: String, summary: String, rules: [StyleRule] }
    var written: Written { .init(name: name, summary: summary, rules: rules) }
    mutating func addPending() {
        let words = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        rules.append(StyleRule(area: pendingArea, text: words)); pending = ""
    }
    static var new: StyleDraft { .init(id: "new-" + UUID().uuidString, style: nil) }
    init(id: String, style: Style?, name: String = "", summary: String = "", rules: [StyleRule] = []) { self.id = id; self.style = style; self.name = name; self.summary = summary; self.rules = rules }
    init(_ s: Style) { self.init(id: s.id, style: s, name: s.name, summary: s.summary, rules: s.rules) }

    /// "12 rules · Talking, Showing, Detail · 3 graphics · a look".
    static func holds(_ s: Style) -> String {
        let rules = s.rules.count, layouts = s.layouts.compactMap(\.name)
        return [rules == 0 ? nil : "\(rules) rule\(rules == 1 ? "" : "s")", layouts.isEmpty ? nil : layouts.joined(separator: ", "), s.contents.line.isEmpty ? nil : s.contents.line].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// Writes it: the house style, a change to one of yours, or a new one (which needs its name).
    func save(in folder: URL) throws -> Style {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = self.name.trimmingCharacters(in: .whitespaces)
        return try StyleLibrary.save(id: isHouse ? StyleLibrary.houseID : style?.id, name: isHouse || name.isEmpty ? nil : name, summary: isHouse ? nil : summary, tokens: nil, guide: nil, rules: rules, in: folder)
    }
}

/// What a style says, in Settings' own groups: its name and sentence, its rules by kind with a row to add
/// one, then what Direction made or measured for it (how one runs, examples, layouts, transitions, moves,
/// the videos it was learned from and what's in its folder).
struct StyleEditor: View {
    @Binding var draft: StyleDraft
    /// The parts below the rules; a style being made has none yet.
    var showsParts = true

    var body: some View {
        if draft.isHouse {
            SettingsNote("Every film follows these, under whatever style it\u{2019}s cut in. Where a film\u{2019}s style says otherwise, the style wins; your notes and the brief win over both.")
                .padding(.top, 6).padding(.bottom, 4)
        } else {
            SettingsGroup(label: "About") {
                SettingsRow(label: "Name", first: true) {
                    TextField("", text: $draft.name).gateField().startPlaceholder("Desk Talk", shown: draft.name.isEmpty).frame(width: 360)
                }
                SettingsRow(label: "In a sentence", detail: "Shown in the brief beside its name.") {
                    TextField("", text: $draft.summary, axis: .vertical).lineLimit(1...4).gateField()
                        .startPlaceholder("Quick explainers: 3-second shots, punch-ins, bold captions.", shown: draft.summary.isEmpty).frame(width: 360)
                }
            }
        }
        rules
        if showsParts, let s = draft.style, !s.isHouse { StyleParts(style: s) }
    }

    // MARK: Rules

    private var areas: [String] { StyleRule.areas.map(\.id).filter { a in draft.rules.contains { $0.area == a } } }

    @ViewBuilder private var rules: some View {
        Text("Rules").font(Gate.Font.title).foregroundStyle(Gate.Text.primary).padding(.top, 18).accessibilityAddTraits(.isHeader)
        SettingsNote("One sentence each, in your words. Numbers help: \u{201C}Music 25 dB under my voice.\u{201D}").padding(.top, 3)
        ForEach(areas, id: \.self) { area in
            SettingsGroup(label: StyleRule.label(area)) {
                let rules = draft.rules.filter { $0.area == area }
                // Bound by id, not place, so taking one out never leaves a row reading past the end.
                ForEach(rules) { rule in
                    StyleRuleRow(rule: Binding(get: { draft.rules.first { $0.id == rule.id } ?? rule },
                                               set: { new in if let i = draft.rules.firstIndex(where: { $0.id == rule.id }) { draft.rules[i] = new } }),
                                 first: rule.id == rules.first?.id) { draft.rules.removeAll { $0.id == rule.id } }
                }
            }
        }
        SettingsGroup(label: draft.rules.isEmpty ? "Your first rule" : "Another rule") {
            HStack(spacing: 8) {
                GateSelect(options: StyleRule.areas.map { ($0.id, $0.label) }, selection: $draft.pendingArea).fixedSize()
                TextField("", text: $draft.pending).gateField().startPlaceholder("Text never covers my face.", shown: draft.pending.isEmpty).onSubmit { draft.addPending() }
                Button("Add") { draft.addPending() }.buttonStyle(.gate).disabled(draft.pending.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // MARK: Lines

    /// "0:00–2:15", "from 2:15", "about 8 s": where a part of the film usually sits.
    static func sectionTime(_ part: StyleSection) -> String? {
        func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
        switch (part.at, part.length) {
        case let (at?, length?): return "\(clock(at))\u{2013}\(clock(at + length))"
        case let (at?, nil): return "from \(clock(at))"
        case let (nil, length?): return "about \(Int(length.rounded())) s"
        default: return nil
        }
    }

    /// "Punch in 1–1.15× on jump cuts", "Emphasis 1.32×", "Slow push to 1.05× on shots over 8 s", "Pauses over 0.35 s to 0.15 s".
    static func moveLines(_ m: StyleMoves) -> [String] {
        func n(_ v: Double) -> String { String(format: "%g", v) }
        return [
            m.punchIn.map { "Punch in \($0.scales.map(n).joined(separator: "\u{2013}"))\u{00D7} on jump cuts" },
            m.emphasisPunch.map { "Emphasis \(n($0.scale))\u{00D7}" },
            m.slowPush.map { "Slow push to \(n($0.to))\u{00D7} on shots over \(n($0.longerThan)) s" },
            m.tightenPauses.map { "Pauses over \(n($0.longerThan)) s to \(n($0.to)) s" },
            m.screenZoom.map { "Screen zooms \(n($0.min))\u{2013}\(n($0.max))\u{00D7}" },
        ].compactMap { $0 }
    }

    /// "Glint, 10 frames, whoosh under it".
    static func transitionLine(_ t: StyleTransition) -> String {
        let kind = t.type == "shader" ? (t.file.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.capitalized } ?? "Its own") : t.type.prefix(1).uppercased() + t.type.dropFirst()
        return "\(kind), \(t.frames) frames" + (t.sound.map { ", \(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent) under it" } ?? "")
    }
}

/// One rule as text you can click into and change; remove it from its end or its menu.
struct StyleRuleRow: View {
    @Binding var rule: StyleRule
    var first: Bool
    var remove: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("", text: $rule.text, axis: .vertical).textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                .lineSpacing(3).lineLimit(1...8).focused($focused)
                .accessibilityLabel("\(StyleRule.label(rule.area)) rule")
            if let kept = rule.kept {
                Text("From \(kept.film)").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1).fixedSize().help(kept.note ?? "")
            }
            Button(action: remove) { Image(systemName: "trash").font(.system(size: 11)) }
                .buttonStyle(.gate(.ghost, .small, icon: true)).help("Remove this rule").accessibilityLabel("Remove rule")
                .opacity(hovering || focused ? 1 : 0)
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 9)
        .frame(minHeight: 40)
        .background(focused ? Gate.Surface.sunken.opacity(0.6) : .clear)
        .overlay(alignment: .top) { if !first { SystemHairline() } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { Button("Remove Rule", action: remove) }
    }
}

/// What Direction made or measured for a style: groups of rows like the rest of Settings.
struct StyleParts: View {
    var style: Style

    var body: some View {
        let s = style
        if !s.structure.isEmpty {
            SettingsGroup(label: "How one runs", note: AnyView(SettingsNote("The editor shapes a first cut this way."))) {
                ForEach(Array(s.structure.enumerated()), id: \.offset) { i, part in
                    SettingsRow(label: part.name, detail: part.what, first: i == 0) {
                        if let time = StyleEditor.sectionTime(part) { Text(time).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Gate.Text.tertiary) }
                    }
                }
            }
        }
        if !s.examples.isEmpty {
            SettingsGroup(label: "Examples", note: AnyView(SettingsNote("Moments the editor looks at when it cuts in this style."))) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3), alignment: .leading, spacing: 16) {
                    ForEach(s.examples) { e in example(e) }
                }
                .padding(14)
            }
        }
        if !s.layouts.isEmpty {
            SettingsGroup(label: "Layouts", note: AnyView(SettingsNote("Pick one from the Layout button under the picture, or ask the editor to change them."))) {
                HStack(spacing: 18) {
                    ForEach(s.layouts, id: \.self) { l in
                        VStack(spacing: 6) {
                            LayoutGlyph(layout: l, size: CGSize(width: 64, height: 36))
                            Text(l.label).font(Gate.Font.caption).foregroundStyle(Gate.Text.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
            }
        }
        if !s.transitions.isEmpty {
            SettingsGroup(label: "Transitions", note: AnyView(SettingsNote("Ask for them by name; each brings its sound."))) {
                ForEach(Array(s.transitions.enumerated()), id: \.offset) { i, t in
                    SettingsRow(label: t.name, detail: StyleEditor.transitionLine(t), first: i == 0) { EmptyView() }
                }
            }
        }
        let moves = StyleEditor.moveLines(s.moves)
        if !moves.isEmpty {
            SettingsGroup(label: "Moves", note: AnyView(SettingsNote("Direction makes these itself when the editor asks for them."))) {
                ForEach(Array(moves.enumerated()), id: \.offset) { i, line in SettingsRow(label: line, first: i == 0) { EmptyView() } }
            }
        }
        if !s.sources.isEmpty {
            SettingsGroup(label: "Learned from", note: AnyView(SettingsNote("What Direction measured in each video. The videos themselves aren\u{2019}t kept."))) {
                ForEach(Array(s.sources.enumerated()), id: \.offset) { i, src in
                    SettingsRow(label: src.title, detail: [src.by, src.measured?.summary].compactMap { $0 }.joined(separator: "\n"), first: i == 0, minHeight: 56) {
                        if let link = src.link, link.contains("://"), let url = URL(string: link) {
                            Link(destination: url) { Image(systemName: "arrow.up.right.square").font(.system(size: 12)) }
                                .buttonStyle(.gate(.ghost, .small, icon: true)).help("Open the video")
                        }
                    }
                }
            }
        }
        SettingsGroup(label: "In its folder") {
            SettingsRow(label: s.contents.line.isEmpty ? "Nothing yet" : s.contents.line, detail: "Graphics, transitions, sounds, fonts and a look go in its folder.", first: true) { EmptyView() }
        }
    }

    private func example(_ e: StyleExample) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let image = NSImage(contentsOf: style.url.appendingPathComponent(e.still)) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clearOfGrain() }
                else { Gate.Surface.sunken }
            }
            .frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.chip, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
            Text(e.text).font(.system(size: 11.5)).foregroundStyle(Gate.Text.secondary).cssLineHeight(1.4, size: 11.5)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true).help(e.text)
        }
    }
}

/// Settings › Styles › a style: a page in the window, saved as you change it like every other setting. A new
/// one is made with Make Style once it has a name.
struct StylePage: View {
    @State private var draft: StyleDraft
    var folder: URL
    @Environment(\.settingsPages) private var pages
    @Environment(\.settingsPreview) private var preview
    /// What's in the style's folder now, so opening the page writes nothing.
    @State private var last: StyleDraft.Written
    @State private var error: String?
    @State private var confirmingTrash = false

    init(draft: StyleDraft, folder: URL) {
        _draft = State(initialValue: draft); _last = State(initialValue: draft.written); self.folder = folder
    }

    var body: some View {
        SettingsPageLayout(title: title, subtitle: draft.isHouse ? nil : draft.summary, footShown: draft.isNew) {
            if let s = draft.style, !s.isHouse {
                Button("Show in Finder") { if !preview { NSWorkspace.shared.activateFileViewerSelecting([s.url]) } }.buttonStyle(.gate(.ghost, .small))
                Button("Move to Trash\u{2026}") { confirmingTrash = true }.buttonStyle(.gate(.ghostDanger, .small))
            }
        } content: {
            StyleEditor(draft: $draft, showsParts: !draft.isNew)
            if let error { Text(error).font(Gate.Font.small).foregroundStyle(Gate.State.alert).padding(.top, 8) }
        } foot: {
            Button("Cancel") { pages?.back() }.buttonStyle(.gate)
            Button("Make Style", action: make).buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // Changes are kept a moment after the last one, and when the page closes (with a rule still being typed).
        .task(id: draft.written) {
            guard !draft.isNew, draft.written != last else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, draft.written != last else { return }
            write()
        }
        .onDisappear {
            guard !draft.isNew else { return }
            draft.addPending()
            if draft.written != last { write() }
        }
        .confirmationDialog("Move \u{201C}\(draft.name)\u{201D} to the Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive, action: trash)
        } message: { Text("Films that use it keep their own copy.") }
    }

    private var title: String { draft.isHouse ? StyleLibrary.houseName : draft.isNew && draft.name.isEmpty ? "New style" : draft.name.isEmpty ? (draft.style?.name ?? "") : draft.name }

    private func write() {
        guard !preview else { last = draft.written; return }
        do { _ = try draft.save(in: folder); last = draft.written; error = nil }
        catch let e as DirectionError { error = e.message } catch { self.error = error.localizedDescription }
    }

    private func make() {
        guard !preview else { return }
        draft.addPending()
        do {
            let made = try draft.save(in: folder)
            draft = StyleDraft(made); last = draft.written; error = nil
            // The window's title follows the page, which now has its name.
            if let i = pages?.stack.indices.last { pages?.stack[i].title = made.name }
        } catch let e as DirectionError { error = e.message } catch { self.error = error.localizedDescription }
    }

    private func trash() {
        guard let s = draft.style, !preview else { return }
        do { try FileManager.default.trashItem(at: s.url, resultingItemURL: nil); last = draft.written; draft.pending = ""; pages?.back() }
        catch { self.error = "Couldn\u{2019}t move it to the Trash: \(error.localizedDescription)" }
    }
}

/// New Style from a film's brief: a sheet over the brief, made with its name, sentence and first rules.
struct StyleEditSheet: View {
    @State var draft: StyleDraft
    var folder: URL
    /// The style as written, for whoever opened the sheet (the brief picks a new one).
    var saved: (Style) -> Void = { _ in }
    var close: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SystemSheetHead(title: "New style", subtitle: "How a kind of video looks, sounds and moves, in your words. The editor adds what it learns as it cuts in it.")
            // The groups line up with the heading's 22 pt margin.
            ScrollView { SettingsPane { StyleEditor(draft: $draft, showsParts: false) }.padding(.horizontal, -6) }
                .frame(maxHeight: 520)
            SystemSheetFoot {
                if let error { Text(error).font(Gate.Font.small).foregroundStyle(Gate.State.alert).lineLimit(2) }
                Spacer()
                Button("Cancel", action: close).buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button("Make Style", action: make).buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 640)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
    }

    private func make() {
        draft.addPending()
        do { saved(try draft.save(in: folder)); close() }
        catch let e as DirectionError { error = e.message } catch { self.error = error.localizedDescription }
    }
}
