import SwiftUI
import AppKit
import DirectionCore

/// The editor's read-back (`.readback`): one plain line per note with concrete numbers,
/// conflicts called out, nothing cut until you say so. Click a line to correct it.
struct ReadBackBody: View {
    @Bindable var model: FilmModel
    var turnover: Turnover
    var onLeave: () -> Void
    @State private var overflows = false
    @State private var arrived = false

    private var readOnly: Bool { model.isCutting(turnover) }

    var body: some View {
        GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        GemMark(size: 8)
                        Text("Here\u{2019}s what I\u{2019}ll do").fontWeight(.medium).foregroundStyle(Gate.Text.primary)
                        Spacer(minLength: 0)
                        Text(turnover.latitude.label).foregroundStyle(Gate.Text.disabled).lineLimit(1)
                    }
                    .font(.system(size: 12.5)).lineHeight(12.5, 1.45)
                    ForEach(Array(model.turnoverNotes(turnover).enumerated()), id: \.element.id) { index, note in
                        let line = model.readBackLine(note.id, in: turnover)
                        Group {
                            ReadBackLineView(model: model, turnover: turnover, note: note, line: line, readOnly: readOnly, onLeave: onLeave)
                            if let line, let conflict = line.conflict {
                                ConflictCallout(model: model, turnover: turnover, line: line, conflict: conflict, readOnly: readOnly)
                            }
                        }
                        .opacity(arrived ? 1 : 0)
                        .animation(reduceMotion ? nil : Gate.Motion.settle.delay(Double(index) * 0.04), value: arrived)
                    }
                }
                .padding(14)
                .prismEdge(Gate.Radius.card)
                .padding(.vertical, 14).padding(.horizontal, 12)
                .background(GeometryReader { inner in Color.clear.onAppear { overflows = inner.size.height > outer.size.height }.onChange(of: inner.size.height) { _, h in overflows = h > outer.size.height } })
                .animation(gateAnimation(Gate.Motion.settle), value: model.notesUI.correctingNoteID)
            }
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, overflows ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 28)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read-back for \(model.nextCutName)")
        .onAppear { arrived = true }
    }

    private var reduceMotion: Bool { model.isPreview || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// One `.rb-line`: amber number, the plan, the quoted note, and the delta or a flag.
struct ReadBackLineView: View {
    @Bindable var model: FilmModel
    var turnover: Turnover
    var note: ReviewComment
    var line: ReadBackLine?
    var readOnly: Bool
    var onLeave: () -> Void
    @State private var hovered = false
    @State private var focusRequest = 0

    private var ui: NotesUI { model.notesUI }
    private var editing: Bool { ui.correctingNoteID == note.id }
    private var pending: String? { turnover.adjustments[note.id] }
    private var number: String { note.number.map(String.init) ?? "–" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(note.isOutside ? Gate.Text.secondary : Gate.Voice.director)
                .lineHeight(12, 1.5, mono: true)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if let line {
                    Text(line.plan).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
                        .lineHeight(12.5, 1.45).fixedSize(horizontal: false, vertical: true)
                        .opacity(pending == nil ? 1 : 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Gate.Surface.hover).frame(height: 10).padding(.vertical, 4).frame(maxWidth: 200)
                }
                Text(source).font(.system(size: 11.5)).foregroundStyle(Gate.Text.disabled).lineLimit(1).truncationMode(.tail)
                    .lineHeight(11.5, 1.45).padding(.top, 2)
                if let pending, !editing {
                    Text("Your correction: \u{201C}\(pending)\u{201D}").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
                        .lineLimit(2).padding(.top, 4)
                }
                if editing { correction }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !editing { trailing }
        }
        .padding(.vertical, editing ? 8 : 2)
        .padding(.horizontal, editing ? 6 : 0)
        .background {
            if editing {
                RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(Gate.Surface.raised)
                    .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(Gate.Line.strong, lineWidth: 1))
            }
        }
        .padding(.horizontal, editing ? -6 : 0)
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
            if inside, !model.playing, let t = model.noteTime(note) { model.seek(t) }
        }
        .onTapGesture { if !readOnly && !editing { beginEditing() } }
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel("\(number), \(line?.plan ?? "reading back"), \(line?.delta ?? ""), for note: \(note.text)")
        .accessibilityAction(named: "Correct this line") { if !readOnly { beginEditing() } }
    }

    /// "“Cold open takes too long to get to her face.”" · Priya Shah
    private var source: String {
        let inner = note.text.replacingOccurrences(of: "\u{201C}", with: "\u{2018}").replacingOccurrences(of: "\u{201D}", with: "\u{2019}")
        let quoted = "\u{201C}\(inner)\u{201D}"
        return note.person.map { "\(quoted) · \($0.name)" } ?? quoted
    }

    @ViewBuilder private var trailing: some View {
        if let line {
            if line.twoWays { Chip("2 ways", style: .agent) }
            else if let delta = line.delta { Text(delta).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).lineHeight(11, 1.6, mono: true).fixedSize() }
        }
    }

    @ViewBuilder private var correction: some View {
        NoteField(text: Binding(get: { ui.correction }, set: { ui.correction = $0 }), placeholder: "What should change?", label: "Correction for note \(number)", footage: model.footageNames,
                  minHeight: 52, maxHeight: 120, focusToken: focusRequest,
                  onSubmit: send, onEscape: cancel)
            .padding(.top, 8)
            .onAppear { focusRequest += 1 }
        Text("Say what to change and the editor rewrites this line. If it\u{2019}s right as it is, start cutting instead.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel", action: cancel).buttonStyle(.gate(.ghost, .small))
            Button(action: send) { HStack(spacing: 5) { Text("Update line"); KeyHint("↩") } }.buttonStyle(.gate(.normal, .small))
                .disabled(ui.correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.top, 8)
    }

    private func beginEditing() {
        if ui.correctingNoteID != note.id { ui.correction = "" }
        ui.correctingNoteID = note.id
    }
    private func send() { model.sendCorrection(noteID: note.id); onLeave() }
    private func cancel() { ui.correctingNoteID = nil; ui.correction = ""; onLeave() }
}

/// `.conflict`: two notes pull against each other. The higher kind wins; you can flip it.
struct ConflictCallout: View {
    var model: FilmModel
    var turnover: Turnover
    var line: ReadBackLine
    var conflict: Conflict
    var readOnly: Bool
    var body: some View {
        let words = model.conflictWords(line: line, conflict: conflict, in: turnover)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Voice.agent)
                .frame(width: 16).padding(.top, 2)
            Text(attributed(words)).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).lineHeight(12, 1.45)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { _ in flip(); return .handled })
        }
        .padding(.vertical, 10).padding(.horizontal, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(Gate.Surface.sunken)
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(words.title) \(words.detail)")
        .accessibilityAction(named: "Flip it") { flip() }
    }

    private func attributed(_ words: (title: String, detail: String)) -> AttributedString {
        var title = AttributedString(words.title)
        title.foregroundColor = Gate.Text.primary
        title.font = .system(size: 12, weight: .medium)
        var out = title + AttributedString(" \(words.detail)")
        if !readOnly {
            var link = AttributedString("Flip it")
            link.foregroundColor = Gate.Text.primary
            link.underlineStyle = .single
            link.link = URL(string: "direction-flip://\(line.noteID)")
            out += AttributedString(" ") + link
        }
        return out
    }
    private func flip() { model.flipConflict(noteID: line.noteID) }
}

/// The read-back foot: the length after these changes, then the two answers to it: change a line, or
/// start cutting (the same as the titlebar's Start cutting).
struct ReadBackFoot: View {
    var model: FilmModel
    var turnover: Turnover
    var body: some View {
        let estimate = model.estimatedLength(turnover)
        let over = model.brief.lengthMax.map { estimate > $0 + 0.5 } ?? false
        VStack(alignment: .leading, spacing: 10) {
            Text(lengthText(estimate, over: over)).font(Gate.Font.small).foregroundStyle(over ? Gate.State.alert : Gate.Text.tertiary).lineHeight(12, 1.45)
                .fixedSize(horizontal: false, vertical: true)
            if !model.isCutting(turnover) {
                Text("Nothing is cut until you say so. Click a line to change it.")
                    .font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(action: adjust) { Label("Change a line", systemImage: "arrowshape.turn.up.left") }.buttonStyle(.gate(.ghost))
                    Spacer(minLength: 0)
                    if turnover.state == .readBack {
                        Button { model.startCutting() } label: { HStack(spacing: 6) { Text("Looks right, start cutting"); KeyHint("\u{2318}\u{21A9}") } }
                            .buttonStyle(.gate(.normal))
                    }
                }
            }
        }
        .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBorder(.top)
    }

    private func lengthText(_ estimate: Double, over: Bool) -> String {
        var text = "About \(Timecode.duration(estimate)) after these changes."
        if let lo = model.brief.lengthMin, let hi = model.brief.lengthMax { text += " Target \(Timecode.duration(lo))\u{2013}\(Timecode.duration(hi))." }
        if over, let hi = model.brief.lengthMax { text += " \(Timecode.duration(estimate)) is over your \(Timecode.duration(hi)) target." }
        return text
    }
    private func adjust() {
        let ui = model.notesUI
        let first = model.turnoverNotes(turnover).first { turnover.adjustments[$0.id] == nil } ?? model.turnoverNotes(turnover).first
        if let first { ui.correction = ""; ui.correctingNoteID = first.id }
    }
}

/// Turned over in the app, but no editor has picked it up. Turning over doesn't wake it.
struct WaitingBody: View {
    @Bindable var model: FilmModel
    var turnover: Turnover
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Direction starts the editor itself: nothing to copy (specs/editor.md).
                if model.runs.startsEditor { EditorWaitingNotice(model: model, turnover: turnover) } else {
                Notice(tone: .plain, inset: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                        Text("Your editor hasn\u{2019}t picked this up yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    }
                    NoticeText(text: "Turning over in Direction doesn\u{2019}t wake your editor. Ask it to pick up these notes, and its read-back appears here before anything is cut.",
                               small: "Turned over at \(model.clockTime(turnover.createdAt)) · \(turnover.latitude.label)")
                    HStack(spacing: 8) {
                        Button { model.copyEditorRequest() } label: { Label("Copy request for your editor", systemImage: "doc.on.doc") }.buttonStyle(.gate)
                        Button("Take notes back") { model.takeNotesBack(); model.stopWriting(); model.cancelDrawing() }.buttonStyle(.gate(.ghost))
                            .help("Return these notes to written so you can change them")
                    }
                }
                }
                SectionLabel("Turned over")
                CompactNoteList(model: model, notes: model.turnoverNotes(turnover))
            }
            .padding(.vertical, 14).padding(.horizontal, 12)
        }
    }
}

extension FilmModel {
    /// The cut's length after every timed delta in the read-back.
    func estimatedLength(_ t: Turnover) -> Double {
        duration + t.readBack.compactMap { line in line.delta.flatMap(Self.seconds(fromDelta:)) }.reduce(0, +)
    }
    /// "−4.2 s" → −4.2. dB, crop and anything else isn't time.
    static func seconds(fromDelta text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasSuffix(" s") || t.hasSuffix("s") && !t.hasSuffix("dBs") else { return nil }
        let number = t.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)
        return Double(number)
    }
    /// The conflict's words, with the winner flipped when you asked.
    func conflictWords(line: ReadBackLine, conflict: Conflict, in t: Turnover) -> (title: String, detail: String) {
        let a = noteNumber(line.noteID), b = noteNumber(conflict.withNoteID)
        let range = conflict.range.map { " at \($0)" } ?? ""
        let flipped = t.flipped.contains(line.noteID)
        let winner = flipped ? (conflict.following == line.noteID ? conflict.withNoteID : line.noteID) : conflict.following
        let loser = winner == line.noteID ? conflict.withNoteID : line.noteID
        let detail: String
        if !flipped, let given = conflict.detail, given.hasPrefix("Following") { detail = given }
        else { detail = "Following \(noteNumber(winner)) (\(note(winner)?.kind?.label ?? "your call")) over \(noteNumber(loser)) (\(note(loser)?.kind?.label ?? "the other")) there." }
        return ("Notes \(a) and \(b) overlap\(range).", detail)
    }
}
