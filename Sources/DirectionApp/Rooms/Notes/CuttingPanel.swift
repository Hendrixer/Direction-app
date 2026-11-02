import SwiftUI
import AppKit
import DirectionCore

/// "Cut 4 in progress": the Notes side while the editor cuts. The stage keeps playing the
/// current cut; each note keeps its number, in the order the editor works.
struct CuttingPanel: View {
    @Bindable var model: FilmModel
    var turnover: Turnover
    @Environment(\.openSettings) private var openSettings
    @State private var width: CGFloat = 0

    private var ui: NotesUI { model.notesUI }
    private var blockers: [EditorQuestion] { model.openQuestions.sorted { $0.createdAt > $1.createdAt } }
    private var failed: Bool { turnover.state == .failed }
    /// A conflict the editor is cutting through right now.
    private var activeConflict: (ReadBackLine, Conflict)? {
        guard !failed, blockers.isEmpty else { return nil }
        for line in turnover.readBack {
            guard let c = line.conflict, !ui.dismissedConflicts.contains(line.noteID) else { continue }
            if turnover.progress[line.noteID] == .working || turnover.progress[c.withNoteID] == .working { return (line, c) }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView {
                VStack(spacing: 0) {
                    // A run Direction started that stopped shows why, and what to do (frame 58).
                    if failed, let run = model.runs.failed, run.turnoverID == turnover.id { EditorStoppedNotice(model: model, run: run) }
                    else if failed { ErrorNotice(model: model, turnover: turnover, openSettings: { openSettings() }) }
                    ForEach(blockers) { q in
                        if q.kind == "cant" { CantNotice(model: model, question: q) }
                        else { QuestionCard(model: model, question: q, primary: false, steel: false).padding(.horizontal, 16).padding(.vertical, 12) }
                    }
                    .transition(.noticeArrival)
                    if let (line, conflict) = activeConflict {
                        ConflictNotice(model: model, turnover: turnover, line: line, conflict: conflict).transition(.opacity)
                    }
                    ForEach(rows, id: \.0.id) { note, status in
                        StepRow(model: model, turnover: turnover, note: note, status: status)
                    }
                }
                // As wide as the panel, never wider: nothing in it can push the rest off to the side.
                .frame(width: width > 0 ? width : nil, alignment: .leading)
                .animation(gateAnimation(Gate.Motion.glide), value: rows.map { "\($0.0.id)\($0.1)" })
                .animation(gateAnimation(Gate.Motion.settle), value: blockers.map(\.id))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            foot
        }
        .onAppear(perform: track)
        .onChange(of: turnover) { _, _ in track() }
        .background {
            if failed { Button("Retry") { model.retryEditor() }.keyboardShortcut("r", modifiers: .command).opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }

    // MARK: Head and foot

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(model.nextCutName) in progress").font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                MoreMenu(label: "More") {
                    Button("Show Read-back") { ui.cuttingSide = .readBack }.disabled(turnover.readBack.isEmpty)
                    Button("Write Notes for the Next Turnover") { ui.cuttingSide = .notes }
                    if !model.runs.startsEditor {
                        Divider()
                        Button("Copy Request for Your Editor") { model.copyEditorRequest() }
                    }
                }
            }
            .frame(height: Gate.Size.controlSmall)
            Text(subline).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 16).padding(.horizontal, 16).padding(.bottom, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBorder(.bottom)
    }

    private var subline: String {
        let total = turnover.noteIDs.count, done = turnover.progress.values.filter { $0 == .done }.count
        let current = min(total, done + 1)
        if failed {
            let stopped = turnover.noteIDs.first { turnover.progress[$0] == .stopped }
            return (stopped.map { "Stopped at note \(model.noteNumber($0))" } ?? "Stopped") + " · \(done) of \(total) done"
        }
        let waiting = Set(blockers.flatMap(\.noteIDs)).count
        if waiting > 0 { return "Cutting \(current) of \(total) · \(waiting == 1 ? "1 note" : "\(waiting) notes") waiting on you" }
        if blockers.contains(where: { $0.noteIDs.isEmpty }) { return "Cutting \(current) of \(total) · waiting for you" }
        let nothingYet = !turnover.progress.values.contains { $0 != .queued }
        if turnover.state == .readBack || nothingYet { return "Turned over \(total) notes at \(model.clockTime(turnover.createdAt)) · starting" }
        let eta = model.remainingSeconds(turnover).map { model.minutesLeft($0) }
        if activeConflict != nil { return (["Cutting \(current) of \(total)"] + [eta].compactMap { $0 }).joined(separator: " · ") }
        var parts = ["Turned over \(total) notes at \(model.clockTime(turnover.createdAt))"]
        if let start = ui.cuttingStarted[turnover.id] { parts.append("started \(model.clockTime(start.timeIntervalSince1970))") }
        if let eta { parts.append(eta) }
        return parts.joined(separator: " · ")
    }

    private var foot: some View {
        HStack(spacing: 8) {
            if failed {
                let stopped = turnover.noteIDs.first { turnover.progress[$0] == .stopped }
                let again = model.runs.startsEditor ? "Try again" : "Retry"
                Text(stopped.map { "\(again) picks up at note \(model.noteNumber($0))." } ?? "\(again) picks up where it stopped.")
                Spacer(minLength: 0)
                Text("\u{2318}R").font(.system(size: 12, design: .monospaced))
            } else {
                Text("You can keep watching \(model.notesCutName). Nothing changes in it.")
            }
        }
        .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45)
        .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBorder(.top)
    }

    // MARK: Rows

    /// Done first (in the order they finished), then blocked, then the note being cut, then the queue.
    private var rows: [(ReviewComment, NoteProgress)] {
        let notes = turnover.noteIDs.compactMap(model.note)
        func status(_ c: ReviewComment) -> NoteProgress { turnover.progress[c.id] ?? .queued }
        let order = ui.doneOrder
        let done = notes.filter { status($0) == .done }.sorted { a, b in
            (order.firstIndex(of: a.id) ?? .max, a.number ?? .max) < (order.firstIndex(of: b.id) ?? .max, b.number ?? .max)
        }
        let blocked = notes.filter { [.cant, .stopped].contains(status($0)) }
        let working = notes.filter { status($0) == .working }
        let queued = notes.filter { status($0) == .queued }
        return (done + blocked + working + queued).map { ($0, status($0)) }
    }

    /// Remembers when cutting began and the order notes finish in; the store keeps neither.
    private func track() {
        let ui = model.notesUI
        if ui.cuttingStarted[turnover.id] == nil, turnover.state == .cutting, !turnover.progress.values.contains(.done) { ui.cuttingStarted[turnover.id] = ui.now }
        for id in turnover.noteIDs where turnover.progress[id] == .done && !ui.doneOrder.contains(id) { ui.doneOrder.append(id) }
        model.announceProgress(turnover)
    }
}

/// `.step`: one note's progress. The working row has a prism bar; blocked rows an alert bar.
struct StepRow: View {
    var model: FilmModel
    var turnover: Turnover
    var note: ReviewComment
    var status: NoteProgress
    private var failed: Bool { turnover.state == .failed }
    private var plan: String? { status == .working ? model.readBackLine(note.id, in: turnover)?.plan : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                NoteNumber(note: note).lineHeight(14, 1.25, mono: true).frame(width: 26, alignment: .leading)
                Mentions.text(note.text, footage: model.footageNames).font(Gate.Font.body).foregroundStyle(status == .queued ? Gate.Text.tertiary : Gate.Text.primary)
                    .lineHeight(13, 1.4).lineLimit(2).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                statusLabel
            }
            if let plan {
                Text(plan).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
        }
        .padding(.top, 11).padding(.bottom, 12).padding(.leading, 14).padding(.trailing, 16)
        .background(background)
        .overlay(alignment: .leading) {
            if status == .working { Rectangle().fill(Gate.Voice.prism).frame(width: 2) }
            else if [.cant, .stopped].contains(status) { Gate.State.alert.frame(width: 2) }
        }
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .onTapGesture { if let t = model.noteTime(note) ?? model.anchorScene(note)?.start { model.pause(); model.seek(t) } }
        .contextMenu {
            Button("Play from Note") { if let t = model.noteTime(note) { model.seek(t); if !model.playing { model.togglePlayback() } } }
            if let n = note.number { Button("Copy Link to Note \(n)") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("direction://note/\(note.id)", forType: .string) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note \(note.number.map(String.init) ?? ""), \(note.text) \(statusText).")
        .animation(gateAnimation(Gate.Motion.settle), value: status)
    }

    private var background: Color {
        switch status {
        case .working: Gate.Surface.panel
        case .cant, .stopped: Gate.State.alert.opacity(0.06)
        default: .clear
        }
    }

    private var statusText: String {
        switch status {
        case .done: "Done"
        case .working: "Cutting"
        case .queued: failed ? "Waiting" : "Queued"
        case .cant: "Needs you"
        case .stopped: "Stopped"
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            switch status {
            case .done: Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            case .working: GemMark(size: 7)
            case .cant: Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
            case .stopped: Image(systemName: "exclamationmark.triangle").font(.system(size: 9.5, weight: .semibold))
            case .queued: EmptyView()
            }
            Text(statusText)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(statusColor)
        .lineHeight(11, 1.6, mono: true)
        .fixedSize()
    }

    private var statusColor: Color {
        switch status {
        case .done: Gate.State.approve
        case .working: Gate.Text.primary
        case .cant, .stopped: Gate.State.alert
        case .queued: Gate.Text.disabled
        }
    }
}

/// `.notice.voice`: two notes pull against each other and the editor says which it follows.
struct ConflictNotice: View {
    @Bindable var model: FilmModel
    var turnover: Turnover
    var line: ReadBackLine
    var conflict: Conflict

    private var winner: String {
        let flipped = turnover.flipped.contains(line.noteID)
        return flipped ? (conflict.following == line.noteID ? conflict.withNoteID : line.noteID) : conflict.following
    }
    private var loser: String { winner == line.noteID ? conflict.withNoteID : line.noteID }
    private var range: ClosedRange<Double>? { conflict.range.flatMap(Self.parseRange) }

    var body: some View {
        let first = line.noteID, other = conflict.withNoteID
        Notice(tone: .voice) {
            HStack(spacing: 8) {
                GemMark(size: 8)
                Text("Notes \(model.noteNumber(first)) and \(model.noteNumber(other)) pull against each other").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 0)
                Button { model.notesUI.dismissedConflicts.insert(line.noteID); endHighlight() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                    .buttonStyle(.gate(.ghost, .small, icon: true)).help("Dismiss. The decision stays.")
            }
            NoticeText(text: words, small: model.readBackLine(loser, in: turnover).map { "Note \(model.noteNumber(loser)) still lands: \($0.plan)" })
            HStack(spacing: 0) {
                segment(conflict.following)
                segment(conflict.following == first ? other : first)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Gate.Surface.canvas).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Which note wins\(conflict.range.map { " between \($0)" } ?? "")")
            Text(help).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineHeight(12, 1.45).fixedSize(horizontal: false, vertical: true)
        }
        .onHover { $0 ? beginHighlight() : endHighlight() }
        .onDisappear(perform: endHighlight)
        .animation(gateAnimation(Gate.Motion.snap), value: winner)
    }

    private var words: String {
        let w = model.note(winner), l = model.note(loser)
        let between = conflict.range.map { r in "Between " + r.replacingOccurrences(of: "\u{2013}", with: " and ") } ?? "Here"
        var first = "\(between), notes \(model.noteNumber(winner)) and \(model.noteNumber(loser)) pull different ways."
        if let given = conflict.detail, !given.hasPrefix("Following") { first = given }
        let second: String
        if turnover.flipped.contains(line.noteID) { second = "I\u{2019}m following \(model.noteNumber(winner)), as you asked." }
        else if let wk = w?.kind, let lk = l?.kind, wk != lk { second = "I\u{2019}m following \(model.noteNumber(winner)), because \(wk.label) comes before \(lk.label)." }
        else if let k = w?.kind { second = "Both are \(k.label) notes. I\u{2019}m following the later one, note \(model.noteNumber(winner))." }
        else { second = "I\u{2019}m following \(model.noteNumber(winner))." }
        return first + " " + second
    }
    private var help: String {
        let scene = range.flatMap { model.stripScene(at: $0.lowerBound + 0.01) }.map { "scene \($0.number)" } ?? "that passage"
        return "Switching re-cuts \(scene) only. You can also change it in the read-back next time."
    }

    private func segment(_ noteID: String) -> some View {
        let on = winner == noteID
        return Button { if !on { model.flipConflict(noteID: line.noteID) } } label: {
            HStack(spacing: 6) {
                Text(model.noteNumber(noteID)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Voice.director)
                    .padding(.horizontal, 5).frame(height: 16).background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Voice.directorWash))
                Text("Follow \(model.note(noteID)?.kind?.label ?? "note \(model.noteNumber(noteID))")").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(on ? Gate.Text.primary : Gate.Text.tertiary)
            }
            .padding(.horizontal, 11).frame(height: 24)
            .background { if on { RoundedRectangle(cornerRadius: 7).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Gate.Line.subtle, lineWidth: 1)).shadow(color: .black.opacity(0.5), radius: 1, y: 1) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Shows the overlap on the strip while the pointer is over the notice.
    private func beginHighlight() {
        guard let range, model.notesUI.stripHighlightRestore == nil else { return }
        model.notesUI.stripHighlightRestore = (model.anchorMode, model.rangeSelection)
        model.rangeSelection = range; model.anchorMode = .range
    }
    private func endHighlight() { model.endStripHighlight() }

    /// "00:25–00:46" or "00:25:00–00:46:12" → seconds.
    static func parseRange(_ text: String) -> ClosedRange<Double>? {
        let parts = text.split { $0 == "\u{2013}" || $0 == "-" }.map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let a = seconds(parts[0]), let b = seconds(parts[1]), b > a else { return nil }
        return a...b
    }
    static func seconds(_ tc: String) -> Double? {
        let n = tc.split(separator: ":").compactMap { Double($0) }
        switch n.count {
        case 2: return n[0] * 60 + n[1]
        case 3: return n[0] * 60 + n[1] + n[2] / 24
        case 4: return n[0] * 3600 + n[1] * 60 + n[2] + n[3] / 24
        default: return nil
        }
    }
}

/// `.notice.err`: what happened, what's safe, what to do. Never blames you.
struct ErrorNotice: View {
    var model: FilmModel
    var turnover: Turnover
    var openSettings: () -> Void
    private var message: String {
        turnover.message ?? "Something went wrong while I was cutting \(model.nextCutName). \(model.notesCutName) and your notes are safe."
    }
    private var aboutSpace: Bool { ["disk", "space", "room"].contains { message.localizedCaseInsensitiveContains($0) } }

    var body: some View {
        Notice(tone: .error) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.State.alert)
                Text("\(model.nextCutName) stopped").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 0)
                Text(model.clockTime(turnover.updatedAt)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
            }
            NoticeText(text: message, small: aboutSpace ? model.freeSpaceLine : nil)
            HStack(spacing: 8) {
                if aboutSpace {
                    Button(action: openSettings) { Label("Free up space\u{2026}", systemImage: "externaldrive") }.buttonStyle(.gate)
                }
                Button("Copy details", action: copyDetails).buttonStyle(.gate(.ghost))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.nextCutName) stopped")
        .onAppear {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: "\(model.nextCutName) stopped. \(message)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private func copyDetails() {
        let progress = turnover.noteIDs.map { "note \(model.noteNumber($0)): \(turnover.progress[$0]?.rawValue ?? "queued")" }.joined(separator: ", ")
        let details = "Turnover \(turnover.number) (\(turnover.id)) stopped at \(model.clockTime(turnover.updatedAt)).\n\(message)\nProgress: \(progress)\nPhase: \(turnover.phase ?? "–")"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(details, forType: .string)
        model.toast = Toast(title: "Copied the details")
    }
}

extension FilmModel {
    /// Puts back the director's own range after a notice showed its passage on the strip.
    func endStripHighlight() {
        guard let (mode, selection) = notesUI.stripHighlightRestore else { return }
        notesUI.stripHighlightRestore = nil
        anchorMode = mode; rangeSelection = selection
    }

    /// VoiceOver hears what changed: blockers at once, progress at most every 10 s.
    func announceProgress(_ t: Turnover) {
        let ui = notesUI
        defer { ui.heardProgress = t.progress; ui.heardQuestions.formUnion(openQuestions.map(\.id)) }
        guard let heard = ui.heardProgress, !isPreview else { return }
        func say(_ text: String, _ priority: NSAccessibilityPriorityLevel) {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: text, .priority: priority.rawValue])
        }
        for q in openQuestions where !ui.heardQuestions.contains(q.id) {
            let notes = q.noteIDs.map(noteNumber).joined(separator: " and ")
            if q.kind == "cant" { say("The editor can\u{2019}t do note \(notes): \(q.text)", .high) }
            else { say(notes.isEmpty ? "The editor has a question." : "The editor has a question about note \(notes).", .medium) }
        }
        let finished = t.noteIDs.filter { t.progress[$0] == .done && heard[$0] != .done }
        if let last = finished.last, ui.now.timeIntervalSince(ui.lastProgressAnnouncement) >= 10 {
            ui.lastProgressAnnouncement = ui.now
            let done = t.progress.values.filter { $0 == .done }.count
            say("Note \(noteNumber(last)) done. \(done) of \(t.noteIDs.count) notes cut.", .low)
        }
    }
    /// Seconds left, from how long finished notes took. nil until there's something to go on.
    func remainingSeconds(_ t: Turnover) -> Double? {
        let total = t.noteIDs.count, done = t.progress.values.filter { $0 == .done }.count
        guard done > 0, done < total, let start = notesUI.cuttingStarted[t.id] else { return nil }
        let elapsed = notesUI.now.timeIntervalSince(start)
        guard elapsed > 1 else { return nil }
        return elapsed / Double(done) * Double(total - done)
    }
    /// "about 4 min left", "less than a minute left".
    func minutesLeft(_ seconds: Double, suffix: Bool = true) -> String {
        let text = seconds < 60 ? "less than a minute" : "about \(max(1, Int((seconds / 60).rounded()))) min"
        return suffix ? "\(text) left" : text
    }
    /// "Macintosh HD has 1.2 GB free."
    var freeSpaceLine: String? {
        if let disk = notesUI.previewDisk { return "\(disk.name) has \(String(format: "%.1f", disk.free / 1e9)) GB free." }
        guard let url, let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return "\(values.volumeLocalizedName ?? "This disk") has \(String(format: "%.1f", Double(free) / 1e9)) GB free."
    }
}
