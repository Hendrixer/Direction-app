import SwiftUI
import AppKit
import DirectionCore

// Frames 10–12. The cut's dialogue as a lined script. The director strikes, holds, moves
// and compares readings; every gesture is a numbered note. Spec: design/spec/specs/script.md.

/// Room state a snapshot starts from. Lines are named by number.
struct ScriptPreview {
    var selection: ClosedRange<Int>? = nil
    var readingsLine: Int? = nil
    var playingTake: String? = nil
    var playingProgress = 0.4
    var editingNoteID: String? = nil
}

extension EnvironmentValues {
    @Entry var scriptPreview: ScriptPreview? = nil
}

enum ScriptFocus: Hashable { case page, find, note }

struct ScriptRoom: View {
    @Bindable var model: FilmModel
    @Environment(\.scriptPreview) private var preview
    var body: some View { ScriptRoomContent(model: model, preview: preview) }
}

/// Builds the document only when the cut, transcripts or dailies change.
@MainActor final class ScriptDocumentCache {
    private var key: [AnyHashable] = []
    private var document = ScriptDocument()
    func document(for model: FilmModel) -> ScriptDocument {
        let strip = model.stripScenes
        let key: [AnyHashable] = [model.sequence, model.transcripts.count, model.transcripts.reduce(0) { $0 + $1.words.count }, model.transcripts.compactMap(\.selectedAt).max() ?? 0, model.dailies, strip.map { "\($0.id):\($0.start):\($0.end)" }]
        if key != self.key {
            self.key = key
            document = ScriptDocument.build(project: model.displayed ?? model.project, sequence: model.sequence, transcripts: model.transcripts, dailies: model.dailies, cutScenes: strip)
        }
        return document
    }
}

struct ScriptRoomContent: View {
    @Bindable var model: FilmModel
    @State private var pending: ScriptPreview?
    @State private var cache = ScriptDocumentCache()
    @State private var player = ReadingPlayer()

    @State private var anchorID: String?
    @State private var extentID: String?
    @State private var readingsLineID: String?
    @State private var readingFocusID: String?
    @State private var editingNoteID: String?
    @State private var editingText = ""
    @State private var hoveredLineID: String?
    @State private var findText = ""
    @State private var findIndex = -1
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var draggingLineID: String?
    @State private var dropAfterID: String?
    @State private var scrollOffset: CGFloat = 0
    @State private var shake: [String: Int] = [:]
    @State private var notice: Notice?
    @State private var scrollRequest: ScrollRequest?
    @AppStorage("scriptFollowPlayback") private var follow = true
    @FocusState private var focus: ScriptFocus?

    struct Notice: Equatable { var id = UUID(); var text: String; var unlockSceneID: String? }
    struct ScrollRequest: Equatable { var id = UUID(); var target: String; var animated = true }

    init(model: FilmModel, preview: ScriptPreview?) {
        self.model = model
        _pending = State(initialValue: preview)
    }

    var body: some View {
        let doc = cache.document(for: model)
        let marks = ScriptMarks(notes: model.scriptNotes, document: doc)
        HStack(spacing: 0) {
            outline(doc).frame(width: 200)
            VStack(spacing: 0) {
                toolbar(doc)
                page(doc, marks)
            }
            .frame(maxWidth: .infinity)
            .background(Gate.Surface.sunken)
            ScriptSidePanel(model: model, document: doc, notes: model.scriptNotes, editingNoteID: $editingNoteID, editingText: $editingText, editorFocus: $focus,
                            onSelect: { selectNote($0, marks) }, onEdit: { startEditing($0) }, onCommit: commitEditing)
                .frame(width: 360)
        }
        .overlay(alignment: .bottomLeading) { noticeView }
        .background { shortcuts(doc) }
        .onAppear { applyPending(doc); revealRequestedLine(doc, marks) }
        .onChange(of: model.selectedLineID) { _, _ in revealRequestedLine(doc, marks) }
    }

    // MARK: Selection

    private func selection(_ doc: ScriptDocument) -> [ScriptLine] {
        guard let a = doc.index(of: anchorID) else { return [] }
        let b = doc.index(of: extentID) ?? a
        let scene = doc.lines[a].sceneID
        return Array(doc.lines[min(a, b)...max(a, b)]).filter { $0.sceneID == scene }
    }

    private func select(_ line: ScriptLine, extend: Bool, seek: Bool = true) {
        if extend, anchorID != nil { extentID = line.id } else { anchorID = line.id; extentID = nil }
        readingsLineID = nil
        model.selectedLineID = anchorID
        if seek { model.seek(line.start); follow = true }
    }

    private func step(_ delta: Int, extend: Bool, _ doc: ScriptDocument) {
        guard !doc.lines.isEmpty else { return }
        let from = doc.index(of: extend ? (extentID ?? anchorID) : anchorID) ?? doc.index(of: doc.line(at: model.position)?.id) ?? -1
        let next = doc.lines[max(0, min(doc.lines.count - 1, from + delta))]
        select(next, extend: extend)
        scrollRequest = .init(target: next.id)
    }

    private func applyPending(_ doc: ScriptDocument) {
        guard let p = pending else { return }
        pending = nil
        if let s = p.selection { anchorID = doc.line(number: s.lowerBound)?.id; extentID = s.count > 1 ? doc.line(number: s.upperBound)?.id : nil }
        if let n = p.readingsLine, let line = doc.line(number: n) {
            readingsLineID = line.id
            if let take = p.playingTake, let r = line.reading(take) { readingFocusID = r.id; player.preview(r.id, progress: p.playingProgress) }
        }
        if let id = p.editingNoteID, let note = model.note(id) { editingNoteID = id; editingText = note.text }
    }

    /// Notes opens Script at a line: model.selectedLineID is a line, or a line-anchored note.
    private func revealRequestedLine(_ doc: ScriptDocument, _ marks: ScriptMarks) {
        guard let id = model.selectedLineID, id != anchorID else { return }
        if let line = doc.line(id) { anchorID = line.id; extentID = nil; scrollRequest = .init(target: line.id, animated: false); return }
        if let ids = marks.linesOfNote[id], let first = ids.first {
            anchorID = first; extentID = ids.count > 1 ? ids.last : nil
            model.selectedNoteID = id
            scrollRequest = .init(target: first, animated: false)
        }
    }

    // MARK: Gestures

    /// Striking or holding the same lines again takes the note back (it's dropped; its number stays used).
    private func strike(_ doc: ScriptDocument) {
        let lines = selection(doc)
        guard !lines.isEmpty else { return }
        if let existing = existingNote(.strike, lines, doc) { model.dropNote(existing); return }
        guard !refused(.strike, lines) else { return }
        if let c = model.strikeLines(lines) { model.selectedNoteID = c.id }
    }

    private func hold(_ doc: ScriptDocument) {
        let lines = selection(doc)
        guard !lines.isEmpty else { return }
        if let existing = existingNote(.hold, lines, doc) { model.dropNote(existing); if editingNoteID == existing { editingNoteID = nil }; return }
        guard !refused(.hold, lines) else { return }
        if let c = model.holdLines(lines) { model.selectedNoteID = c.id; startEditing(c) }
    }

    /// An editable note that already makes this gesture on exactly these lines.
    private func existingNote(_ gesture: ScriptGesture, _ lines: [ScriptLine], _ doc: ScriptDocument) -> String? {
        let ids = lines.map(\.id), marks = ScriptMarks(notes: model.scriptNotes, document: doc)
        return model.scriptNotes.first { n in
            n.scriptAction?.gesture == gesture && [.draft, .written, .reopened].contains(n.lifecycle) && marks.linesOfNote[n.id] == ids
        }?.id
    }

    private func move(_ line: ScriptLine, after target: ScriptLine) {
        guard line.id != target.id, !refused(.move, [line, target]) else { return }
        if let c = model.moveLine(line, after: target) { model.selectedNoteID = c.id }
    }

    private func openReadings(_ line: ScriptLine?) {
        guard let line else { return }
        if anchorID != line.id || extentID != nil { anchorID = line.id; extentID = nil }
        readingFocusID = line.reading(line.assetID)?.id
        readingsLineID = line.id
    }

    private func use(_ reading: ScriptReading, for line: ScriptLine, _ doc: ScriptDocument) {
        player.stop()
        readingsLineID = nil
        focus = .page
        guard !refused(.reading, [line]) else { return }
        if let c = model.useReading(reading.assetID, label: doc.takeLabel(reading.assetID), for: line) { model.selectedNoteID = c.id }
    }

    /// Locked scenes and must-keep lines refuse the gesture: the line shakes once and a toast says why.
    private func refused(_ gesture: ScriptGesture, _ lines: [ScriptLine]) -> Bool {
        guard let (text, unlock) = model.scriptRefusal(gesture, lines) else { return false }
        for line in lines { shake[line.id, default: 0] += 1 }
        notice = Notice(text: text, unlockSceneID: unlock)
        AccessibilityNotification.Announcement(text).post()
        return true
    }

    private func startEditing(_ note: ReviewComment) {
        editingNoteID = note.id; editingText = note.text
        model.selectedNoteID = note.id
        DispatchQueue.main.async { focus = .note }
    }

    private func commitEditing() {
        if let id = editingNoteID, let note = model.note(id) {
            let text = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, text != note.text { model.editNote(id, text: text) }
        }
        editingNoteID = nil
        focus = .page
    }

    private func selectNote(_ note: ReviewComment, _ marks: ScriptMarks) {
        model.selectedNoteID = note.id
        if let ids = marks.linesOfNote[note.id], let first = ids.first {
            anchorID = first; extentID = ids.count > 1 ? ids.last : nil
            scrollRequest = .init(target: first)
        }
        if let t = model.noteTime(note) { model.seek(t) }
    }

    // MARK: Outline

    private func outline(_ doc: ScriptDocument) -> some View {
        let current = currentScene(doc)
        let scenes: [(id: String, number: Int, title: String, locked: Bool)] = model.scenes.isEmpty
            ? doc.scenes.map { ($0.id, $0.number, $0.title, $0.locked) }
            : model.scenes.map { ($0.id, $0.number, $0.title, $0.locked) }
        return VStack(alignment: .leading, spacing: 1) {
            SectionLabel("Scenes").frame(height: 10.5).padding(.horizontal, 9).padding(.top, 4).padding(.bottom, 10)
            ForEach(scenes, id: \.id) { s in
                let count = doc.scenes.first { $0.id == s.id }?.lines.count ?? 0
                let on = current?.id == s.id
                Button {
                    if let first = doc.scenes.first(where: { $0.id == s.id }) { scrollRequest = .init(target: "scene-\(first.id)"); if let line = first.lines.first { model.seek(line.start) } }
                } label: {
                    HStack(spacing: 9) {
                        if s.locked { Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Gate.Text.tertiary) }
                        Text("\(s.number) \(s.title)").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(count)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                    }
                    .font(.system(size: 13)).foregroundStyle(on ? Gate.Text.primary : Gate.Text.secondary)
                    .padding(.horizontal, 9).frame(height: 30)
                    .background { if on { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1)) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(count == 0)
                .help(count == 0 ? "No lines from this scene in \(model.watchedCut?.name ?? "the cut")" : "Go to scene \(s.number)")
                .accessibilityLabel("Scene \(s.number), \(s.title), \(count) lines\(s.locked ? ", locked" : "")")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            SectionLabel("Gestures").frame(height: 10.5).padding(.horizontal, 9).padding(.top, 22).padding(.bottom, 8)
            legend("strikethrough", "Strike", "\u{232B}")
            legend("curlybraces", "Hold", "H")
            legend("arrow.up.and.down", "Move", "drag")
            legend("quote.opening", "Readings", "R")
        }
        .padding(.horizontal, 8).padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 1)
        .hairlineBorder(.trailing)
        .background(Gate.Surface.ground)
    }

    private func legend(_ icon: String, _ name: String, _ key: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 15)
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
            Text(key).font(.system(size: 12)).foregroundStyle(Gate.Text.disabled)
        }
        .font(.system(size: 13)).foregroundStyle(Gate.Text.tertiary)
        .padding(.horizontal, 9).frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(key == "drag" ? "drag a line" : key)")
    }

    private func currentScene(_ doc: ScriptDocument) -> ScriptScene? {
        let line = doc.line(anchorID) ?? doc.line(at: model.position)
        return line.flatMap(doc.scene(of:)) ?? doc.scenes.first { !$0.columns.isEmpty }
    }

    // MARK: Toolbar

    private func toolbar(_ doc: ScriptDocument) -> some View {
        let matches = findMatches(doc)
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.disabled)
                TextField("", text: $findText)
                    .overlay(alignment: .leading) { if findText.isEmpty { Text("Find a line").foregroundStyle(Gate.Text.disabled).allowsHitTesting(false) } }
                    .accessibilityLabel("Find a line")
                    .textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                    .focused($focus, equals: .find)
                    .onSubmit { nextMatch(matches) }
                    .onKeyPress(.escape) { findText = ""; focus = .page; return .handled }
                    .onChange(of: findText) { _, _ in findIndex = -1 }
                if !findText.isEmpty {
                    Text(matches.isEmpty ? "None" : "\(max(1, findIndex + 1)) of \(matches.count)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 220, height: 26)
            .background(GateFieldBackground(focused: focus == .find))
            .help("Find a line (\u{2318}F)")
            HStack(spacing: 8) {
                MiniSwitch(isOn: $follow).accessibilityLabel("Follow playback")
                Text("Follow playback").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            .help("Keep the line that's playing in view")
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                legendSwatch(AnyView(Gate.Steel.ramp[6]), "On camera")
                legendSwatch(AnyView(DashedBar()), "Off camera")
                legendSwatch(AnyView(Gate.Voice.director), "In the cut")
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Gate.Surface.sunken)
        .hairlineBorder(.bottom)
    }

    private func legendSwatch(_ bar: AnyView, _ text: String) -> some View {
        HStack(spacing: 6) { bar.frame(width: 2, height: 12); Text(text) }.font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
    }

    private func findMatches(_ doc: ScriptDocument) -> [ScriptLine] {
        let q = findText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return doc.lines.filter { $0.text.localizedCaseInsensitiveContains(q) || ($0.speaker?.localizedCaseInsensitiveContains(q) ?? false) || "\($0.number)" == q }
    }

    private func nextMatch(_ matches: [ScriptLine]) {
        guard !matches.isEmpty else { NSSound.beep(); return }
        findIndex = (findIndex + 1) % matches.count
        select(matches[findIndex], extend: false)
        scrollRequest = .init(target: matches[findIndex].id)
    }

    // MARK: Page

    @ViewBuilder private func page(_ doc: ScriptDocument, _ marks: ScriptMarks) -> some View {
        if doc.isEmpty { emptyPage(doc) }
        else {
            let selected = selection(doc)
            let selectedIDs = selected.map(\.id)
            let current = doc.line(at: model.position)
            let headScene = currentScene(doc)
            let found = Set(findMatches(doc).map(\.id))
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        headRow(doc, headScene)
                        ForEach(doc.scenes) { scene in
                            ScriptSceneHeading(scene: scene, showsColumns: scene.id != headScene?.id).equatable().id("scene-\(scene.id)")
                            ForEach(scene.lines) { line in
                                lineRow(line, scene, doc, marks, selectedIDs: selectedIDs, selected: selected, current: selectedIDs.isEmpty && line.id == current?.id, found: found.contains(line.id))
                            }
                        }
                    }
                    .frame(width: ScriptMetrics.column)
                    .overlay(alignment: .topLeading) { pageOverlays(doc, marks, selected) }
                    .coordinateSpace(.named(ScriptPageSpace.name))
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
                .onScrollPhaseChange { _, phase in if phase == .interacting { follow = false } }
                .onScrollGeometryChange(for: CGFloat.self, of: { geo in readingsLineID == nil ? 0 : geo.contentOffset.y }, action: { _, y in scrollOffset = y })
                .onChange(of: current?.id) { _, id in
                    guard follow, model.playing, let id else { return }
                    withAnimation(gateAnimation(Gate.Motion.glide)) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.33)) }
                }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    if request.animated { withAnimation(gateAnimation(Gate.Motion.glide)) { proxy.scrollTo(request.target, anchor: UnitPoint(x: 0.5, y: 0.33)) } }
                    else { proxy.scrollTo(request.target, anchor: UnitPoint(x: 0.5, y: 0.33)) }
                }
            }
            .focusable().focusEffectDisabled().focused($focus, equals: .page)
            .onAppear { if focus == nil { focus = .page } }
            .onKeyPress(phases: .down) { press in handleKey(press, doc) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Script of \(model.watchedCut?.name ?? "the cut")")
        }
    }

    private func headRow(_ doc: ScriptDocument, _ scene: ScriptScene?) -> some View {
        HStack(alignment: .bottom, spacing: ScriptMetrics.gap) {
            Color.clear.frame(width: ScriptMetrics.number, height: 1)
            SectionLabel("\(model.watchedCut?.name ?? "This cut") \u{00B7} as cut, \(Timecode.duration(doc.dialogueSeconds)) of dialogue").frame(maxWidth: .infinity, alignment: .leading)
            Group { if let scene, !scene.columns.isEmpty { CoverageHeader(columns: scene.columns) } else { Color.clear.frame(height: 1) } }.frame(width: ScriptMetrics.coverage)
        }
        .padding(.bottom, 8)
    }

    private func lineRow(_ line: ScriptLine, _ scene: ScriptScene, _ doc: ScriptDocument, _ marks: ScriptMarks, selectedIDs: [String], selected: [ScriptLine], current: Bool, found: Bool) -> some View {
        let index = selectedIDs.firstIndex(of: line.id)
        let edge: ScriptLineRow.Selection? = index.map { i in selectedIDs.count == 1 ? .single : i == 0 ? .top : i == selectedIDs.count - 1 ? .bottom : .middle }
        let row = ScriptLineRow(
            line: line,
            coverage: scene.columns.map { scene.coverage(line, $0) },
            showsSpeakerColumn: true,
            current: current,
            selection: edge,
            hovered: hoveredLineID == line.id && draggingLineID == nil,
            dragging: draggingLineID == line.id,
            found: found,
            struck: marks.struck[line.id],
            hold: marks.hold(line.id)?.1,
            movedAfter: marks.move(of: line.id)?.afterNumber,
            tags: marks.tags[line.id] ?? [],
            shake: shake[line.id] ?? 0,
            accessibility: accessibilityLabel(line, scene, doc, marks),
            onTap: { shift in select(line, extend: shift); focus = .page },
            onNumber: { select(line, extend: false); openReadings(line) },
            onTag: { id in if let note = model.note(id) { selectNote(note, marks) } },
            onHover: { inside in if inside { hoveredLineID = line.id } else if hoveredLineID == line.id { hoveredLineID = nil } },
            onGrip: { value in drag(line, value, doc) }
        )
        return row.equatable()
            .id(line.id)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ScriptPageSpace.name)) } action: { rowFrames[line.id] = $0 }
            .contextMenu { lineMenu(line, doc) }
            .accessibilityAction(named: "Strike") { select(line, extend: false, seek: false); strike(doc) }
            .accessibilityAction(named: "Hold") { select(line, extend: false, seek: false); hold(doc) }
            .accessibilityAction(named: "Other readings") { openReadings(line) }
    }

    /// What floats over the page, placed from the rows' measured frames: insertion lines,
    /// the selection toolbar and the readings popover.
    private func pageOverlays(_ doc: ScriptDocument, _ marks: ScriptMarks, _ selected: [ScriptLine]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks.moves, id: \.self) { m in
                if let f = rowFrames[m.afterID] {
                    InsertionLine(tag: m.tag, movingNumber: doc.line(m.lineID)?.number ?? 0).offset(x: ScriptMetrics.textStart, y: f.maxY - 8)
                }
            }
            if let after = dropAfterID, let f = rowFrames[after], let moving = doc.line(draggingLineID) {
                InsertionLine(tag: nil, movingNumber: moving.number).offset(x: ScriptMetrics.textStart, y: f.maxY - 8)
            }
            if readingsLineID == nil, draggingLineID == nil, let first = selected.first.flatMap({ rowFrames[$0.id] }), let last = selected.last.flatMap({ rowFrames[$0.id] }) {
                selectionToolbar(selected, doc, marks)
                    .frame(width: ScriptMetrics.textEnd + 6, alignment: .trailing)
                    .offset(y: (first.minY + last.maxY) / 2 - 18)
            }
            if let line = doc.line(readingsLineID), let f = rowFrames[line.id] {
                readingsPopover(line, doc, row: f)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Above the line so it stays visible; below it when there's no room above.
    @ViewBuilder private func readingsPopover(_ line: ScriptLine, _ doc: ScriptDocument, row: CGRect) -> some View {
        let height = 112 + CGFloat(line.readings.count) * 53
        let below = row.minY + 28 - scrollOffset - height - 1 < 4
        let popover = ReadingsPopover(model: model, document: doc, line: line, player: player, focusID: $readingFocusID,
                                      onUse: { use($0, for: line, doc) }, onClose: { player.stop(); readingsLineID = nil; focus = .page })
            .transition(settleTransition(anchor: below ? .top : .bottom))
        if below { popover.offset(x: 10, y: row.maxY + 1) }
        else { popover.frame(height: max(0, row.minY - 1), alignment: .bottom).offset(x: 10) }
    }

    private func selectionToolbar(_ lines: [ScriptLine], _ doc: ScriptDocument, _ marks: ScriptMarks) -> some View {
        let ids = Set(lines.map(\.id))
        return SelectionToolbar(
            struck: !lines.isEmpty && lines.allSatisfy { marks.struck[$0.id] != nil },
            held: marks.holds.contains { Set($0.lineIDs) == ids },
            canReadings: lines.count == 1,
            strike: { strike(doc) }, hold: { hold(doc) }, readings: { openReadings(lines.first) }
        ) { moveMenu(lines.first, doc) }
    }

    @ViewBuilder private func moveMenu(_ line: ScriptLine?, _ doc: ScriptDocument) -> some View {
        if let line {
            ForEach(doc.scenes) { scene in
                Section("\(scene.number) \(scene.title)") {
                    ForEach(scene.lines.filter { $0.id != line.id }) { target in
                        Button("After line \(target.number): \(target.text.count > 40 ? target.text.prefix(40) + "\u{2026}" : target.text)") { move(line, after: target) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func lineMenu(_ line: ScriptLine, _ doc: ScriptDocument) -> some View {
        Button("Strike") { if !selection(doc).contains(where: { $0.id == line.id }) { select(line, extend: false, seek: false) }; strike(doc) }
        Button("Hold") { if !selection(doc).contains(where: { $0.id == line.id }) { select(line, extend: false, seek: false) }; hold(doc) }
        Menu("Move After") { moveMenu(line, doc) }
        Button("Other Readings") { openReadings(line) }
        Divider()
        Button("Play from Line") { model.seek(line.start); if !model.playing { model.togglePlayback() } }
        Button("Copy Line") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(line.speaker.map { "\($0): \(line.text)" } ?? line.text, forType: .string) }
        Button("Show in Dailies") { model.selectedSceneID = line.sceneID; model.openTakeID = line.assetID; model.go(.dailies) }
    }

    private func emptyPage(_ doc: ScriptDocument) -> some View {
        let running = model.jobs.filter { $0.kind == "transcription" && !$0.isTerminal }
        let total = model.dailies.takes.isEmpty ? (model.project?.assets.count ?? 0) : model.dailies.takes.count
        return VStack(spacing: 0) {
            if !running.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { SectionLabel("Transcribing\u{2026} \(model.transcripts.count) of \(total) takes"); Spacer(); GateSpinner() }.padding(.bottom, 16)
                    ForEach(0..<12, id: \.self) { i in
                        HStack(spacing: ScriptMetrics.gap) {
                            RoundedRectangle(cornerRadius: 3).fill(Gate.Surface.panel).frame(width: 18, height: 10).frame(width: ScriptMetrics.number, alignment: .trailing)
                            RoundedRectangle(cornerRadius: 3).fill(Gate.Surface.panel).frame(width: [320, 260, 380, 300, 220, 340][i % 6], height: 12).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, ScriptMetrics.speaker)
                            Color.clear.frame(width: ScriptMetrics.coverage)
                        }.frame(height: ScriptMetrics.row)
                    }
                }
                .frame(width: ScriptMetrics.column).padding(.top, 28)
                Spacer()
            } else {
                EmptyStateView(title: "No dialogue yet", message: doc.untranscribed.isEmpty ? "Lines appear here once the takes in \(model.watchedCut?.name ?? "the cut") have transcripts." : "\(doc.untranscribed.count == 1 ? "One take" : "\(doc.untranscribed.count) takes") in \(model.watchedCut?.name ?? "the cut") still need a transcript.") {
                    if !doc.untranscribed.isEmpty, model.runtime != nil { Button("Transcribe Takes") { transcribe(doc.untranscribed) }.buttonStyle(.gate) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transcribe(_ ids: [String]) {
        guard let runtime = model.runtime else { return }
        Task {
            for id in ids { _ = try? await runtime.invoke("direction_transcribe", arguments: .object(["assetID": .string(id)])) }
            model.refresh(force: true)
        }
    }

    // MARK: Drag to move

    private func drag(_ line: ScriptLine, _ value: DragGesture.Value?, _ doc: ScriptDocument) {
        guard let value else {
            if let after = doc.line(dropAfterID), draggingLineID == line.id { move(line, after: after) }
            draggingLineID = nil; dropAfterID = nil
            return
        }
        draggingLineID = line.id
        let y = value.location.y
        let frames = doc.lines.compactMap { l in rowFrames[l.id].map { (l, $0) } }
        guard let hit = frames.min(by: { abs($0.1.midY - y) < abs($1.1.midY - y) }) else { return }
        var target: ScriptLine? = y >= hit.1.midY ? hit.0 : doc.index(of: hit.0.id).flatMap { $0 > 0 ? doc.lines[$0 - 1] : nil }
        if let t = target, let i = doc.index(of: line.id), t.id == line.id || (i > 0 && doc.lines[i - 1].id == t.id) { target = nil }
        if dropAfterID != target?.id { withAnimation(gateAnimation(Gate.Motion.glide)) { dropAfterID = target?.id } }
    }

    // MARK: Keys

    private func handleKey(_ press: KeyPress, _ doc: ScriptDocument) -> KeyPress.Result {
        guard !TextInput.hasFocus else { return .ignored }
        if press.modifiers.contains(.command) || press.modifiers.contains(.control) { return .ignored }
        switch press.key {
        case .delete, .deleteForward: strike(doc); return .handled
        case .upArrow: step(-1, extend: press.modifiers.contains(.shift), doc); return .handled
        case .downArrow: step(1, extend: press.modifiers.contains(.shift), doc); return .handled
        case .escape:
            if readingsLineID != nil { player.stop(); readingsLineID = nil } else if anchorID != nil { anchorID = nil; extentID = nil } else { return .ignored }
            return .handled
        case .space:
            if !model.playing, let line = doc.line(anchorID) { model.seek(line.start) }
            follow = true
            model.togglePlayback(); return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "h": hold(doc); return .handled
        case "r": openReadings(doc.line(anchorID) ?? doc.line(at: model.position)); return .handled
        default: return .ignored
        }
    }

    /// ⌘F finds a line.
    private func shortcuts(_ doc: ScriptDocument) -> some View {
        Button("Find a Line") { focus = .find }.keyboardShortcut("f", modifiers: .command).hidden().accessibilityHidden(true)
    }

    // MARK: Notice

    @ViewBuilder private var noticeView: some View {
        if let notice {
            ToastView(toast: Toast(id: notice.id, title: notice.text, actionTitle: notice.unlockSceneID == nil ? nil : "Unlock"),
                      action: notice.unlockSceneID.map { id in { model.lockScene(id, false); self.notice = nil } }) { self.notice = nil }
                .padding(20)
                .transition(.opacity)
                .task(id: notice.id) { try? await Task.sleep(for: .seconds(notice.unlockSceneID == nil ? 5 : 8)); if self.notice?.id == notice.id { self.notice = nil } }
        }
    }

    // MARK: Accessibility

    /// "Line 12, Maya: Editing was the part nobody wanted. Covered by 2A takes 2, 3, 4 and 2B takes 1, 3. In the cut from take 2."
    private func accessibilityLabel(_ line: ScriptLine, _ scene: ScriptScene, _ doc: ScriptDocument, _ marks: ScriptMarks) -> String {
        let speaker = line.speaker.map { ", \($0.capitalized)" } ?? ""
        var out = "Line \(line.number)\(speaker): \(line.text)"
        let covering = scene.columns.filter { line.reading($0.assetID) != nil }
        let bySetup = Dictionary(grouping: covering, by: \.setup).sorted { $0.key < $1.key }.map { "\($0.key) takes \($0.value.map(\.take).joined(separator: ", "))" }
        if !bySetup.isEmpty { out += ". Covered by " + bySetup.joined(separator: " and ") }
        let take = model.dailies.take(line.assetID).code?.replacingOccurrences(of: "T", with: "") ?? doc.takeLabel(line.assetID)
        out += ". In the cut from take \(take)."
        if let s = marks.struck[line.id] { out += " Struck, note \(s.number)." }
        if let h = marks.hold(line.id) { out += " Held, note \(h.0.tag.number)." }
        if let m = marks.move(of: line.id) { out += " Moved after line \(m.afterNumber), note \(m.tag.number)." }
        return out
    }
}

/// The toolbar's small switch, drawn at 85%: steel-9 track when on, never colored.
private struct MiniSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Gate.Steel.ramp[9] : Gate.Surface.hover).overlay { if !isOn { Capsule().strokeBorder(Gate.Line.strong, lineWidth: 1) } }
            Circle().fill(isOn ? Gate.Steel.ramp[2] : Gate.Steel.ramp[8]).frame(width: 12, height: 12).shadow(color: .black.opacity(0.6), radius: 1, y: 1).padding(1.7)
        }
        .frame(width: 27, height: 15.3)
        .frame(width: 32, height: 18)
        .contentShape(Capsule())
        .onTapGesture { withAnimation(gateAnimation(Gate.Motion.snap)) { isOn.toggle() } }
        .accessibilityElement()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAction { isOn.toggle() }
    }
}
