import SwiftUI
import AppKit
import DirectionCore

// The Script room (specs/script.md): the A/V script, picture beside sound. The editor writes the picture from
// the film's style; the director types in any cell, leaves notes on rows, turns them over, and OKs it.

/// Room state a snapshot starts from.
struct PrepPreview {
    var selected: [Int] = []
    var editing: Int? = nil
    var editingText = ""
    var tab: PrepSheetTab = .notes
    var shot: String? = nil
    var noteText = ""
    var find = ""
}

enum PrepSheetTab: String { case notes, questions }
enum ScriptFilter: String, CaseIterable { case all, notes, empty, changed, yours }

extension EnvironmentValues {
    @Entry var prepPreview: PrepPreview? = nil
}

struct ScriptRoom: View {
    @Bindable var model: FilmModel
    @Environment(\.prepPreview) private var preview
    var body: some View {
        if let script = model.script { ScriptPage(model: model, script: script, preview: preview) }
        else { ScriptEmpty(model: model) }
    }
}

/// No script yet: bring one in, or a story (start.md › 04, specs/script.md › From a story).
private struct ScriptEmpty: View {
    @Bindable var model: FilmModel
    var body: some View {
        EmptyStateView(art: nil, title: "Start from a script or a story", message: "The editor lays out what we see and hear, beat by beat, in the film\u{2019}s style. You edit it or leave notes, then OK it for the breakdown. Markdown, plain text, Fountain, Final Draft or PDF.") {
            Button("Choose a script\u{2026}") { model.chooseScript(.script) }.buttonStyle(.gate(.normal, .large))
            Button("Choose a story\u{2026}") { model.chooseScript(.story) }.buttonStyle(.gate(.normal, .large))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Gate.Surface.ground)
    }
}

private struct ScriptPage: View {
    @Bindable var model: FilmModel
    var script: AVScript
    @State private var selected: Set<String> = []
    @State private var anchor: String?
    @State private var hovered: String?
    @State private var filter: ScriptFilter = .all
    @State private var tab: PrepSheetTab = .notes
    @State private var noteText = ""
    @State private var noteKind: NoteKind?
    @State private var find = ""
    @State private var hit = 0
    @State private var jump: String?
    @State private var center: String?
    @FocusState private var focus: ScriptCell?
    @FocusState private var findFocus: Bool
    /// Snapshots: a cell drawn as if you were typing in it.
    private var previewFocus: ScriptCell?
    private var previewText: String?

    /// Worked out once a draw: every row reads them.
    private let rowNumber: [String: Int]
    private let noted: Set<String>
    private let firstEmpty: String?

    init(model: FilmModel, script: AVScript, preview: PrepPreview?) {
        self.model = model; self.script = script
        rowNumber = Dictionary(script.rows.enumerated().map { ($0.element.id, $0.offset + 1) }, uniquingKeysWith: { a, _ in a })
        firstEmpty = script.rows.first { $0.picture.isEmpty }?.id
        noted = Set(script.notes.filter { $0.state == .written || $0.state == .turnedOver }.flatMap { $0.rowIDs ?? [] })
        if let p = preview {
            _selected = State(initialValue: Set(p.selected.compactMap { script.rows.indices.contains($0 - 1) ? script.rows[$0 - 1].id : nil }))
            previewFocus = p.editing.flatMap { script.rows.indices.contains($0 - 1) ? .picture(script.rows[$0 - 1].id) : nil }
            previewText = p.editingText.isEmpty ? nil : p.editingText
            _tab = State(initialValue: p.tab)
            _noteText = State(initialValue: p.noteText)
            _find = State(initialValue: p.find)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            outline.frame(width: 200)
            VStack(spacing: 0) {
                toolbar
                ScrollViewReader { proxy in
                    ScrollView { page.padding(.bottom, 48) }
                        .focusable().focusEffectDisabled()
                        .onKeyPress(phases: .down) { press in keys(press) }
                        .onChange(of: center) { _, id in if let id { withAnimation(gateAnimation(Gate.Motion.glide)) { proxy.scrollTo(id, anchor: .center) } } }
                        .onChange(of: jump) { _, id in if let id { withAnimation(gateAnimation(Gate.Motion.glide)) { proxy.scrollTo(id, anchor: .top) }; jump = nil } }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Gate.Surface.sunken)
            ScriptSheet(model: model, script: script, selected: orderedSelection, tab: $tab, noteText: $noteText, noteKind: $noteKind)
                .frame(width: 360)
        }
        .background { shortcuts }
        .onChange(of: focus) { _, cell in
            // Typing in a row makes it the row a note goes on, unless it's already among the selected.
            guard let id = cell?.rowID, !selected.contains(id) else { return }
            selected = [id]; anchor = id
        }
        .onChange(of: find) { _, _ in hit = 0; center = hits.first }
    }

    private var orderedSelection: [String] { script.rows.map(\.id).filter(selected.contains) }

    // MARK: Outline

    private var outline: some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel("Sections").padding(.horizontal, 9).padding(.bottom, 8)
            ForEach(Array(script.sections.enumerated()), id: \.element.id) { i, s in
                let rows = script.rows.filter { $0.section == s.id }
                let notes = script.notes.filter { n in n.state == .written && (n.rowIDs ?? []).contains { id in rows.contains { $0.id == id } } }.count
                OutlineRow(title: "\(i + 1) \(s.title)", count: notes > 0 ? "\(notes)" : "\(rows.count)", director: notes > 0) { scroll(rows.first?.id) }
            }
            SectionLabel("Show").padding(.horizontal, 9).padding(.top, 20).padding(.bottom, 8)
            ForEach(ScriptFilter.allCases, id: \.self) { f in
                OutlineRow(title: label(f), icon: icon(f), count: "\(count(f))", director: f == .notes && count(f) > 0, on: filter == f) { filter = f }
            }
            SectionLabel("Style").padding(.horizontal, 9).padding(.top, 20).padding(.bottom, 8)
            Button { model.sheet = .brief } label: {
                HStack { Text(model.styleName ?? "No style").lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Gate.Text.tertiary) }
            }.buttonStyle(.gate(.normal, .regular)).padding(.horizontal, 9)
            Text("The style decides what the picture column reaches for. Change it in the brief.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).padding(.horizontal, 9).padding(.top, 6)
            Spacer()
        }
        .padding(.vertical, 14).padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .hairlineBorder(.trailing)
    }

    private func label(_ f: ScriptFilter) -> String {
        switch f { case .all: "Every row"; case .notes: "With notes"; case .empty: "No picture yet"; case .changed: "Changed by the editor"; case .yours: "Your words" }
    }
    private func icon(_ f: ScriptFilter) -> String? {
        switch f { case .all: nil; case .notes: "text.bubble"; case .empty: "questionmark.circle"; case .changed: "diamond"; case .yours: "character.cursor.ibeam" }
    }
    private func count(_ f: ScriptFilter) -> Int { script.rows.filter { shows($0, f) }.count }
    private func changedThisPass(_ r: AVRow) -> Bool { script.pass > 1 && r.picture.pass == script.pass }
    private func shows(_ r: AVRow, _ f: ScriptFilter) -> Bool {
        switch f {
        case .all: true
        case .notes: noted.contains(r.id)
        case .empty: r.picture.isEmpty
        case .changed: changedThisPass(r)
        case .yours: r.picture.yours == true || r.sound.yours == true
        }
    }

    // MARK: Find

    private var query: String { find.trimmingCharacters(in: .whitespaces).lowercased() }
    private func matches(_ text: String) -> Bool { !query.isEmpty && text.lowercased().contains(query) }
    /// Rows with a match, in the order they're shown.
    private var hits: [String] { query.isEmpty ? [] : script.rows.filter { shows($0, filter) && (matches($0.picture.text) || matches($0.sound.text) || matches($0.story ?? "")) }.map(\.id) }
    private var current: String? { let h = hits; return h.isEmpty ? nil : h[min(hit, h.count - 1)] }
    private func step(_ by: Int) {
        let h = hits
        guard !h.isEmpty else { return }
        hit = (min(hit, h.count - 1) + by + h.count) % h.count
        center = nil; center = h[hit]
    }

    // MARK: Toolbar

    private var toolbar: some View {
        let h = hits
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Gate.Text.disabled)
                TextField("Find a line", text: $find).textFieldStyle(.plain).font(.system(size: 12.5))
                    .focused($findFocus)
                    .onSubmit { step(1) }
                    .onKeyPress(.return, phases: .down) { press in press.modifiers.contains(.shift) ? { step(-1); return .handled }() : .ignored }
                    .onExitCommand { find = ""; findFocus = false }
                if !query.isEmpty {
                    Text(h.isEmpty ? "No matches" : "\(min(hit, h.count - 1) + 1) of \(h.count)")
                        .font(Gate.Font.timecodeSmall).foregroundStyle(h.isEmpty ? Gate.State.alert : Gate.Text.tertiary).fixedSize()
                }
            }
            .padding(.horizontal, 9).frame(width: 300, height: 26).background(GateFieldBackground(focused: findFocus))
            if !query.isEmpty {
                HStack(spacing: 2) {
                    Button { step(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.gate(.ghost, .small)).disabled(h.isEmpty).help("Previous match (\u{21E7}\u{2318}G)").accessibilityLabel("Previous match")
                    Button { step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.gate(.ghost, .small)).disabled(h.isEmpty).help("Next match (\u{2318}G)").accessibilityLabel("Next match")
                }
            }
            Group {
                if focus != nil { Text("\u{21A9} saves \u{00B7} esc puts it back") }
                else if !selected.isEmpty { Text(selected.count == 1 ? "Row \(rowNumber[orderedSelection[0]] ?? 0) selected" : "\(selected.count) rows selected") }
                else if query.isEmpty { Text("Click a row to select it, or its words to type in them.") }
            }
            .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
            Spacer()
            HStack(spacing: 0) {
                Text("\(script.rows.count) rows ").foregroundStyle(Gate.Text.secondary)
                Text("\u{00B7} \(script.isStory ? "runs" : "reads in") about \(Timecode.duration(script.seconds))").foregroundStyle(Gate.Text.disabled)
            }.font(Gate.Font.timecodeSmall).fixedSize()
        }
        .padding(.horizontal, 20).frame(height: 44)
        .background(Gate.Surface.ground)
        .hairlineBorder(.bottom)
    }

    // MARK: The page

    private var page: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let source = script.source {
                HStack(spacing: 8) {
                    Image(systemName: script.isStory ? "text.book.closed" : "doc.text").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary)
                    Text("\(script.isStory ? "The story, from" : "From") \(source.fileName) \u{00B7} \(source.words) words").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                    Spacer()
                    // Came in as the wrong one: the same file, laid out the other way.
                    Button(script.isStory ? "Read as a script\u{2026}" : "Read as a story\u{2026}") { model.readAgain(as: script.isStory ? .script : .story) }
                        .buttonStyle(.gate(.ghost, .small))
                        .help(script.isStory ? "Lay it out as a script, its words said as written" : "Lay it out as a story: the editor writes what we see and hear")
                    Button("Bring in a new draft\u{2026}") { model.chooseScript() }.buttonStyle(.gate(.ghost, .small))
                }.padding(.leading, 46).padding(.bottom, script.storyNotes == nil ? 12 : 4)
                if let notes = script.storyNotes {
                    HStack(spacing: 8) {
                        Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(Gate.Text.disabled)
                        Text(Self.notesLine(notes)).font(Gate.Font.small).foregroundStyle(Gate.Text.disabled).lineLimit(1)
                    }
                    .padding(.leading, 46).padding(.bottom, 12)
                    .help(notes)
                }
            }
            if model.writingPicture, script.rows.contains(where: { $0.picture.isEmpty }) { drafting.padding(.leading, 46).padding(.bottom, 14) }
            header
            let found = Set(hits), now = current
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if let s = group.section { sectionHeading(s, rows: group.rows) }
                ForEach(group.rows, id: \.id) { r in row(r, found: found.contains(r.id), current: now == r.id) }
            }
            if filter == .all {
                Button { model.addRow(after: script.rows.last?.id) } label: { Label("Add a row", systemImage: "plus") }
                    .buttonStyle(.gate(.ghost, .small)).padding(.leading, 40).padding(.top, 10)
            }
        }
        .frame(width: 820).padding(.top, 18)
        .frame(maxWidth: .infinity)
    }

    private var drafting: some View {
        let done = script.rows.filter { !$0.picture.isEmpty }.count
        return HStack(spacing: 10) {
            GemMark()
            Text(script.isStory ? "Laying out what we see and hear, beat by beat, from the style. \(done) of \(script.rows.count)." : "Writing what we see under each line, from the style. \(done) of \(script.rows.count).").font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary)
            GateProgress(value: Double(done) / Double(max(1, script.rows.count)), agent: true).frame(width: 120)
        }
    }

    private var groups: [(section: AVSection?, rows: [AVRow])] {
        let shown = script.rows.filter { shows($0, filter) }
        var out: [(AVSection?, [AVRow])] = []
        for r in shown {
            let s = r.section.flatMap { id in script.sections.first { $0.id == id } }
            if let last = out.last, last.0?.id == s?.id { out[out.count - 1].1.append(r) } else { out.append((s, [r])) }
        }
        return out.map { (section: $0.0, rows: $0.1) }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            Color.clear.frame(width: 30, height: 1)
            SectionLabel("Picture").frame(width: 330, alignment: .leading)
            SectionLabel("Sound").frame(maxWidth: .infinity, alignment: .leading)
            SectionLabel("Time").frame(width: 40, alignment: .trailing)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Gate.Line.strong).frame(height: 1) }
    }

    private func sectionHeading(_ s: AVSection, rows: [AVRow]) -> some View {
        let number = (script.sections.firstIndex { $0.id == s.id } ?? 0) + 1
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("\(number)").font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.disabled).frame(width: 30, alignment: .trailing)
            Text(s.title.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(0.7).foregroundStyle(Gate.Text.secondary)
            Spacer()
            Text(Timecode.duration(script.rows.filter { $0.section == s.id }.reduce(0) { $0 + $1.seconds })).font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.disabled)
        }
        .padding(.top, 18).padding(.bottom, 7)
        .id(s.id)
    }

    @ViewBuilder private func row(_ r: AVRow, found: Bool, current: Bool) -> some View {
        let n = rowNumber[r.id] ?? 0
        let isSel = selected.contains(r.id)
        let notes = noted.contains(r.id) ? script.notes.filter { ($0.state == .written || $0.state == .turnedOver) && ($0.rowIDs ?? []).contains(r.id) } : []
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                HStack(spacing: 5) {
                    if changedThisPass(r) { GemMark(size: 7, solid: true) }
                    if found && !current { Circle().fill(Gate.Text.secondary).frame(width: 4, height: 4) }
                    Text("\(n)").font(Gate.Font.timecodeSmall).foregroundStyle(current ? Gate.Text.primary : Gate.Text.disabled)
                }
                .frame(width: 30, height: 18, alignment: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    // A film from a story: the part of the story the beat came from, above what we see and hear.
                    if let story = r.story {
                        Text(story).font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background { if found && matches(story) { RoundedRectangle(cornerRadius: 5).fill(Gate.Surface.hover).padding(.horizontal, -5).padding(.vertical, -3) } }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        picture(r, notes: notes, found: found && matches(r.picture.text)).frame(width: 330, alignment: .leading)
                        sound(r, found: found && matches(r.sound.text)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(Timecode.duration(r.seconds)).font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.disabled).frame(width: 40, height: 18, alignment: .trailing)
            }
            .padding(.vertical, 9)
            if let q = r.question, q.isOpen { RowQuestion(question: q) { choice in model.answerRow(r.id, choice: choice) }.padding(.leading, 46).padding(.trailing, 56).padding(.bottom, 10) }
        }
        .background {
            if isSel { Gate.Surface.panel.padding(.horizontal, -14) }
            else if hovered == r.id { Gate.Surface.panel.opacity(0.45).padding(.horizontal, -14) }
        }
        .overlay { if current { RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Text.primary, lineWidth: 1.5).padding(.horizontal, -14).padding(.vertical, 1) } }
        .overlay(alignment: .leading) { if !notes.isEmpty { RoundedRectangle(cornerRadius: 1).fill(Gate.Voice.director).frame(width: 2).padding(.vertical, 9).offset(x: -14) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Gate.Line.subtle).frame(height: 1) }
        // Anywhere on a row selects it; its words are for typing.
        .contentShape(Rectangle())
        .onTapGesture { select(r.id, flags: NSEvent.modifierFlags) }
        .onHover { hovered = $0 ? r.id : (hovered == r.id ? nil : hovered) }
        .contextMenu { rowMenu(r) }
        .id(r.id)
    }

    @ViewBuilder private func picture(_ r: AVRow, notes: [PrepNote], found: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if r.picture.isEmpty {
                if r.question != nil { BoardView(kind: .empty).frame(width: 80) }
                else { RoundedRectangle(cornerRadius: 4).fill(Gate.Surface.sunken).overlay(Hatching().clipShape(RoundedRectangle(cornerRadius: 4))).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle)).frame(width: 80, height: 45) }
            } else {
                BoardView(kind: r.picture.board ?? .medium, move: r.picture.move).frame(width: 80)
            }
            VStack(alignment: .leading, spacing: 4) {
                let writing = model.writingPicture && firstEmpty == r.id
                if writing { HStack(spacing: 8) { GateSpinner(); Text("Writing\u{2026}").foregroundStyle(Gate.Voice.agent) }.font(.system(size: 13)) }
                else {
                    ScriptCellText(text: r.picture.text, placeholder: r.question != nil ? "Nothing yet." : (r.hint.map { "Writer\u{2019}s idea: \($0)" } ?? "What do we see?"),
                                   size: 13, found: found, cell: .picture(r.id), focus: $focus, preview: previewFocus == .picture(r.id) ? (previewText ?? r.picture.text) : nil) { model.editPicture(r.id, $0) }
                }
                let how = [r.picture.size?.label, r.picture.move?.label].compactMap { $0 }.joined(separator: " \u{00B7} ")
                if !notes.isEmpty || changedThisPass(r) || r.picture.yours == true || r.question?.isOpen == true || !how.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(notes, id: \.id) { n in Chip("Note \(n.number)", style: .director) }
                        if changedThisPass(r) { Chip("Changed", style: .agent, mono: false) }
                        if r.picture.yours == true { Chip("Your words", style: .plain, icon: "character.cursor.ibeam", mono: false) }
                        if r.question?.isOpen == true { Chip("Question", style: .agent, mono: false) }
                        if !how.isEmpty { Text(how).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func sound(_ r: AVRow, found: Bool) -> some View {
        // A story's beat before anyone says what we hear has no kind yet.
        let undecided = script.isStory && r.soundUndecided
        VStack(alignment: .leading, spacing: 1) {
            if [.voice, .onCamera].contains(r.sound.kind), !undecided {
                let who = (r.sound.speaker.map { r.sound.kind == .onCamera ? $0 : "\($0) (VO)" } ?? r.sound.kind.label).uppercased()
                Text(r.sound.ownWords == true ? "\(who) \u{00B7} OWN WORDS" : who)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.6).foregroundStyle(Gate.Text.tertiary)
            }
            // Cues, and talk found on the day, read as what we hear rather than words to say.
            let cue = ![.voice, .onCamera].contains(r.sound.kind) || r.sound.ownWords == true
            ScriptCellText(text: r.sound.text, placeholder: undecided ? "What do we hear?" : r.sound.ownWords == true ? "What about?" : cue ? r.sound.kind.label + "." : "What\u{2019}s said?", size: cue || undecided ? 13 : 14, italic: cue, secondary: cue,
                           found: found, cell: .sound(r.id), focus: $focus, preview: nil) { model.editSound(r.id, $0) }
        }
    }

    @ViewBuilder private func rowMenu(_ r: AVRow) -> some View {
        Button("Note on This Row") { selected = [r.id]; anchor = r.id; tab = .notes }
        Button("Edit Picture") { focus = .picture(r.id) }
        Button(script.isStory ? "Edit Sound" : "Edit Words") { focus = .sound(r.id) }
        Menu("Sound") {
            ForEach(HeardKind.allCases, id: \.self) { k in
                Toggle(Self.menuLabel(k), isOn: Binding(get: { r.sound.kind == k && !(script.isStory && r.soundUndecided) }, set: { if $0 { model.setSoundKind(r.id, k) } }))
            }
            Divider()
            Toggle("Their Own Words", isOn: Binding(get: { r.sound.ownWords == true }, set: { model.setOwnWords(r.id, $0) }))
                .disabled(![.voice, .onCamera].contains(r.sound.kind))
        }
        Divider()
        Button("Move Up") { model.moveRow(r.id, by: -1) }.disabled(script.rows.first?.id == r.id)
        Button("Move Down") { model.moveRow(r.id, by: 1) }.disabled(script.rows.last?.id == r.id)
        Button("Add a Row After") { model.addRow(after: r.id) }
        Divider()
        Button("Take Out Row", role: .destructive) { model.removeRow(r.id) }
    }

    /// "The editor reads the writer\u{2019}s notes with it: The idea, The rules of the world and 3 more."
    static func notesLine(_ notes: String) -> String {
        let titles = notes.components(separatedBy: "\n").filter { $0.hasPrefix("#") }.map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let named = titles.count > 3 ? titles.prefix(2).joined(separator: ", ") + " and \(titles.count - 2) more" : titles.count > 1 ? titles.dropLast().joined(separator: ", ") + " and " + titles.last! : titles.first
        return "The editor reads the writer\u{2019}s notes with it" + (named.map { ": \($0)." } ?? ".")
    }

    static func menuLabel(_ k: HeardKind) -> String {
        switch k { case .voice: "Voice-Over"; case .onCamera: "On Camera"; case .effect: "Sound Effect"; case .music: "Music"; case .silence: "Silence" }
    }

    // MARK: Actions

    /// Click selects the row, ⇧-click selects through it, ⌘-click adds or takes it out.
    private func select(_ id: String, flags: NSEvent.ModifierFlags) {
        // Typing in another row ends there; a click in this row's own words keeps the caret.
        if let f = focus, f.rowID != id { focus = nil }
        let ids = script.rows.map(\.id)
        if flags.contains(.shift), let a = anchor, let i = ids.firstIndex(of: a), let j = ids.firstIndex(of: id) { selected = Set(ids[min(i, j)...max(i, j)]); return }
        if flags.contains(.command) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id); anchor = id }; return }
        selected = [id]; anchor = id
    }

    private func scroll(_ id: String?) { filter = .all; jump = id }

    /// ↩ types in the selected row's picture; N starts a note on it (the composer is in the sheet).
    private func keys(_ press: KeyPress) -> KeyPress.Result {
        guard !TextInput.hasFocus, focus == nil, press.modifiers.isEmpty else { return .ignored }
        if press.key == .return, let id = orderedSelection.first { focus = .picture(id); return .handled }
        if press.characters.lowercased() == "n", let id = orderedSelection.first ?? script.rows.first?.id { if selected.isEmpty { selected = [id] }; tab = .notes; return .handled }
        if press.key == .escape, !selected.isEmpty { selected = []; return .handled }
        return .ignored
    }

    private var shortcuts: some View {
        Group {
            Button("") { if let id = orderedSelection.first { model.moveRow(id, by: -1) } }.keyboardShortcut(.upArrow, modifiers: .option).disabled(focus != nil)
            Button("") { if let id = orderedSelection.first { model.moveRow(id, by: 1) } }.keyboardShortcut(.downArrow, modifiers: .option).disabled(focus != nil)
            Button("") { findFocus = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { step(1) }.keyboardShortcut("g", modifiers: .command)
            Button("") { step(-1) }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        .opacity(0).frame(width: 0, height: 0)
    }
}

/// Which cell has the caret.
enum ScriptCell: Hashable {
    case picture(String), sound(String)
    var rowID: String { switch self { case .picture(let id), .sound(let id): id } }
}

/// A cell's words, typed in where they are: the same font, size and place as the page, so nothing moves when
/// the caret goes in. ↩ saves, esc puts it back, and leaving the cell saves too.
struct ScriptCellText: View {
    var text: String
    var placeholder: String
    var size: CGFloat
    var italic = false
    var secondary = false
    /// Find has a match in these words.
    var found = false
    var cell: ScriptCell
    var focus: FocusState<ScriptCell?>.Binding
    /// Snapshots: drawn as if focused, with these words.
    var preview: String?
    var commit: (String) -> Void
    @State private var draft = ""
    @State private var loaded = false

    private var focused: Bool { focus.wrappedValue == cell || preview != nil }

    var body: some View {
        let font = Font.system(size: size).italic(italic)
        TextField("", text: $draft, prompt: Text(placeholder).font(font).foregroundStyle(Gate.Text.disabled), axis: .vertical)
            .textFieldStyle(.plain).font(font)
            .foregroundStyle(secondary ? Gate.Text.secondary : Gate.Text.primary)
            .fixedSize(horizontal: false, vertical: true)
            .focused(focus, equals: cell)
            .onSubmit { save(); focus.wrappedValue = nil }
            .onExitCommand { draft = text; focus.wrappedValue = nil }
            .onChange(of: focus.wrappedValue) { old, new in if old == cell, new != cell { save() } }
            .onChange(of: text) { _, t in if focus.wrappedValue != cell { draft = t } }
            .onAppear { if !loaded { draft = preview ?? text; loaded = true } }
            // Drawn outside the words, so they don't move.
            .background {
                if focused { RoundedRectangle(cornerRadius: 6).fill(Gate.Surface.sunken).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Gate.Line.strong)).padding(.horizontal, -6).padding(.vertical, -4) }
                else if found { RoundedRectangle(cornerRadius: 5).fill(Gate.Surface.hover).padding(.horizontal, -5).padding(.vertical, -3) }
            }
            .accessibilityLabel(placeholder)
    }

    private func save() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if t != text { commit(t) }
    }
}

/// A row in the room's left list.
struct OutlineRow: View {
    var title: String
    var icon: String? = nil
    var count: String? = nil
    var director = false
    var on = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary).frame(width: 14) }
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let count { Text(count).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(director ? Gate.Voice.director : Gate.Text.disabled) }
            }
            .font(.system(size: 13)).foregroundStyle(on ? Gate.Text.primary : Gate.Text.secondary)
            .padding(.horizontal, 9).frame(height: 30)
            .background(on ? RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised) : nil)
            .overlay(on ? RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle) : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The editor asking about a row or a shot, with its choices.
struct RowQuestion: View {
    var question: PrepQuestion
    var answer: (String?) -> Void
    @State private var choice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) { GemMark().padding(.top, 5); Text(question.text).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true) }
            VStack(spacing: 8) {
                ForEach(question.choices) { c in
                    Button { choice = c.id } label: {
                        HStack(spacing: 10) {
                            RadioDot(on: (choice ?? question.choices.first { $0.recommended == true }?.id) == c.id)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
                                if let d = c.detail { Text(d).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary) }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.raised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((choice ?? question.choices.first { $0.recommended == true }?.id) == c.id ? Gate.Text.primary : Gate.Line.subtle, lineWidth: (choice ?? question.choices.first { $0.recommended == true }?.id) == c.id ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            HStack { Spacer(); Button("Answer") { answer(choice ?? question.choices.first { $0.recommended == true }?.id ?? question.choices.first?.id) }.buttonStyle(.gate(.normal, .small)) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Gate.Surface.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Gate.Voice.agent.opacity(0.35)))
    }
}
