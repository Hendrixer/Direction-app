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
                .popover(isPresented: $open, arrowEdge: .bottom) {
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
            .popover(isPresented: $asking, arrowEdge: .bottom) { MakeStylePopover(model: model) { asking = false } }
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
    @State private var editing: StyleDraft?

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Every film") {
                let count = house?.rules.count ?? 0
                SettingsRow(label: StyleLibrary.houseName, detail: count == 0 ? "Rules every film follows. Keep one from an answer in Changes, or write one here." : "\(count) rule\(count == 1 ? "" : "s") every film follows. A film\u{2019}s style wins where it says otherwise.", first: true, minHeight: 56) {
                    Button("Edit\u{2026}") { if let house { editing = .init(house) } }.buttonStyle(.gate)
                }
            }
            SettingsGroup(label: "Your styles", note: AnyView(SettingsNote("A style is how a kind of video looks, sounds and moves: its rules, its layouts, the moves Direction makes for it (punch-ins, pushes) and the parts the editor reuses, like titles, captions, transitions and sounds. Pick one in a film\u{2019}s brief. Make one with the editor from the brief, or write one here."))) {
                if styles.isEmpty {
                    SettingsRow(label: "No styles yet", detail: "Make one with the editor from a film\u{2019}s brief, or start one here.", first: true) {
                        Button("New Style\u{2026}") { editing = .new }.buttonStyle(.gate)
                    }
                }
                ForEach(Array(styles.enumerated()), id: \.element.id) { i, s in
                    SettingsRow(label: s.name, detail: [s.summary, StyleDraft.holds(s)].filter { !$0.isEmpty }.joined(separator: "\n"), first: i == 0, minHeight: 56) {
                        Button("Edit\u{2026}") { editing = .init(s) }.buttonStyle(.gate)
                        Button { reveal(s.url) } label: { Image(systemName: "folder") }.buttonStyle(.gate(.normal, .regular, icon: true)).help("Show in Finder")
                    }
                }
            }
            if !styles.isEmpty {
                HStack { Spacer(); Button("New Style\u{2026}") { editing = .new }.buttonStyle(.gate) }.padding(.top, 2)
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
        .sheet(item: $editing, onDismiss: load) { StyleEditSheet(draft: $0, folder: stylesURL) { editing = nil } }
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
    private func reveal(_ url: URL) { if !preview { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}

/// A style being written in Settings: a new one, one of yours, or the house style.
struct StyleDraft: Identifiable {
    var id: String
    var style: Style?
    var name = "", summary = ""
    var rules: [StyleRule] = []
    var isHouse: Bool { style?.isHouse == true }
    static var new: StyleDraft { .init(id: "new-" + UUID().uuidString, style: nil) }
    init(id: String, style: Style?, name: String = "", summary: String = "", rules: [StyleRule] = []) { self.id = id; self.style = style; self.name = name; self.summary = summary; self.rules = rules }
    init(_ s: Style) { self.init(id: s.id, style: s, name: s.name, summary: s.summary, rules: s.rules) }

    /// "12 rules · Talking, Showing, Detail · 3 graphics · a look".
    static func holds(_ s: Style) -> String {
        let rules = s.rules.count, layouts = s.layouts.compactMap(\.name)
        return [rules == 0 ? nil : "\(rules) rule\(rules == 1 ? "" : "s")", layouts.isEmpty ? nil : layouts.joined(separator: ", "), s.contents.line.isEmpty ? nil : s.contents.line].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

/// Name, one sentence and the rules; the style's layouts and moves; the parts are files, so they're shown
/// and opened in Finder.
struct StyleEditSheet: View {
    @State var draft: StyleDraft
    var folder: URL
    /// The style as written, for whoever opened the sheet (the brief picks a new one).
    var saved: (Style) -> Void = { _ in }
    var close: () -> Void
    @State private var error: String?
    @State private var confirmingTrash = false
    @State private var newArea = "general"
    @State private var newText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(draft.isHouse ? StyleLibrary.houseName : draft.style == nil ? "New style" : draft.style!.name).font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                    if draft.isHouse {
                        Text("Every film follows these, under whatever style it\u{2019}s cut in. Where a film\u{2019}s style says otherwise, the style wins; your notes and the brief win over both.")
                            .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        field("Name") { TextField("", text: $draft.name).gateField(focused: false).startPlaceholder("Desk Talk", shown: draft.name.isEmpty) }
                        field("In a sentence") { TextField("", text: $draft.summary).gateField(focused: false).startPlaceholder("Quick explainers: 3-second shots, punch-ins, bold captions.", shown: draft.summary.isEmpty) }
                    }
                    field("Rules", detail: "One sentence each, in your words. Numbers help: \u{201C}Music 25 dB under my voice.\u{201D}") { rulesEditor }
                    if let s = draft.style, !s.isHouse { madeHere(s) }
                    if let error { Text(error).font(Gate.Font.small).foregroundStyle(Gate.State.alert) }
                }
                .padding(20)
            }
            .frame(maxHeight: 560)
            HStack(spacing: 8) {
                if let s = draft.style, !s.isHouse {
                    Button("Move to Trash\u{2026}") { confirmingTrash = true }.buttonStyle(.gate(.ghostDanger))
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([s.url]) }.buttonStyle(.gate(.ghost))
                }
                Spacer()
                Button("Cancel", action: close).buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button(draft.style == nil ? "Make Style" : "Save", action: save).buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
                    .disabled(!draft.isHouse && draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { SystemHairline() }
        }
        .frame(width: 620)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
        .confirmationDialog("Move \u{201C}\(draft.name)\u{201D} to the Trash?", isPresented: $confirmingTrash) {
            Button("Move to Trash", role: .destructive, action: trash)
        } message: { Text("Films that use it keep their own copy.") }
    }

    /// The rules by area, each editable and removable, and a line to add one.
    private var rulesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(StyleRule.areas.map(\.id).filter { a in draft.rules.contains { $0.area == a } }, id: \.self) { area in
                VStack(alignment: .leading, spacing: 4) {
                    Text(StyleRule.label(area)).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    ForEach(draft.rules.indices.filter { draft.rules[$0].area == area }, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            TextField("", text: $draft.rules[i].text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineLimit(1...4)
                            if let kept = draft.rules[i].kept { Text("From \(kept.film)").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1).help(kept.note ?? "") }
                            Button { draft.rules.remove(at: i) } label: { Image(systemName: "minus.circle").font(.system(size: 11)) }
                                .buttonStyle(.plain).foregroundStyle(Gate.Text.tertiary).help("Remove this rule").accessibilityLabel("Remove rule")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(GateFieldBackground())
                    }
                }
            }
            HStack(spacing: 8) {
                Menu(StyleRule.label(newArea)) { ForEach(StyleRule.areas, id: \.id) { a in Button(a.label) { newArea = a.id } } }
                    .menuStyle(.button).buttonStyle(.gate(.normal, .small)).fixedSize()
                TextField("", text: $newText).gateField(focused: false).startPlaceholder("Text never covers my face.", shown: newText.isEmpty).onSubmit(add)
                Button("Add", action: add).buttonStyle(.gate(.normal, .small)).disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// What Direction makes for this style without the editor working it out: its layouts and moves.
    @ViewBuilder private func madeHere(_ s: Style) -> some View {
        let layouts = s.layouts, moves = s.moves
        if !layouts.isEmpty {
            field("Layouts", detail: "Pick them from the Layout button under the picture, or ask the editor to change them.") {
                HStack(spacing: 12) {
                    ForEach(layouts, id: \.self) { l in
                        VStack(spacing: 5) {
                            LayoutGlyph(layout: l, size: CGSize(width: 52, height: 30))
                            Text(l.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                        }
                    }
                }
            }
        }
        if !s.transitions.isEmpty {
            field("Transitions", detail: "Ask for them by name; each brings its sound.") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.transitions, id: \.name) { t in
                        HStack(spacing: 8) {
                            Text(t.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
                            Text(Self.transitionLine(t)).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                        }
                    }
                }
            }
        }
        let lines = Self.moveLines(moves)
        if !lines.isEmpty {
            field("Moves", detail: "Direction makes these itself when the editor asks for them.") {
                Text(lines.joined(separator: " \u{00B7} ")).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        if !s.sources.isEmpty {
            field("Learned from", detail: "What Direction measured in each video. The videos themselves aren\u{2019}t kept.") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(s.sources.enumerated()), id: \.offset) { _, src in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(src.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary).lineLimit(1)
                                if let by = src.by { Text(by).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1) }
                                if let link = src.link, link.contains("://"), let url = URL(string: link) {
                                    Link(destination: url) { Image(systemName: "arrow.up.right.square").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary) }.help("Open the video")
                                }
                            }
                            if let m = src.measured { Text(m.summary).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
        }
        if !s.examples.isEmpty {
            field("Examples", detail: "Moments the editor looks at when it cuts in this style.") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(s.examples) { e in
                            VStack(alignment: .leading, spacing: 5) {
                                Group {
                                    if let image = NSImage(contentsOf: s.url.appendingPathComponent(e.still)) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
                                    else { Gate.Surface.sunken }
                                }
                                .frame(width: 144, height: 81).clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(e.text).font(Gate.Font.caption).foregroundStyle(Gate.Text.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: 144, alignment: .leading)
                        }
                    }
                }
            }
        }
        if !s.structure.isEmpty {
            field("How one runs", detail: "The editor shapes a first cut this way.") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(s.structure.enumerated()), id: \.offset) { _, part in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(part.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
                            Text(Self.sectionLine(part)).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        Text(s.contents.line.isEmpty ? "No parts yet. Graphics, transitions, sounds, fonts and a look go in its folder." : s.contents.line)
            .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
    }

    /// "From 0:08 for about 20 s. A question to camera, then the result."
    static func sectionLine(_ part: StyleSection) -> String {
        func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
        let when = [part.at.map { "From \(clock($0))" }, part.length.map { "for about \(Int($0.rounded())) s" }].compactMap { $0 }.joined(separator: " ")
        return [when.isEmpty ? nil : when + ".", part.what].compactMap { $0 }.joined(separator: " ")
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

    private func add() {
        let words = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        draft.rules.append(StyleRule(area: newArea, text: words)); newText = ""
    }

    private func field<Content: View>(_ label: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                if let detail { Text(detail).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(2) }
            }
            content()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            add()
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            saved(try StyleLibrary.save(id: draft.isHouse ? StyleLibrary.houseID : draft.style?.id, name: draft.isHouse ? nil : name, summary: draft.isHouse ? nil : draft.summary, tokens: nil, guide: nil, rules: draft.rules, in: folder))
            close()
        } catch let e as DirectionError { error = e.message } catch { self.error = error.localizedDescription }
    }

    private func trash() {
        guard let s = draft.style else { return }
        do { try FileManager.default.trashItem(at: s.url, resultingItemURL: nil); close() } catch { self.error = "Couldn\u{2019}t move it to the Trash: \(error.localizedDescription)" }
    }
}
