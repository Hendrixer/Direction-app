import SwiftUI
import AppKit
import DirectionCore

// The Cut room's notes state and the derived values its views share.
// FilmModel owns the film; this file only adds view state and read-only helpers,
// plus a few director actions composed from FilmModel's store actions.

/// What the Notes side shows while a turnover is cutting.
enum CuttingSide { case progress, readBack, notes }

/// View state for the notes on the Cut room's sheet that outlives a single view: the note being written,
/// the read-back line being corrected, the choice on each open question.
/// One per film, so the titlebar's primary and the snapshot fixtures can see it too.
@MainActor @Observable
final class NotesUI {
    /// The note whose row is open to write in.
    var editingNoteID: String?
    /// The card selected in the Outside tab.
    var selectedOutsideID: String?
    /// The read-back line being corrected, and the correction so far.
    var correctingNoteID: String?
    var correction = ""
    /// The choice picked on each open question, and any words typed instead.
    var choices: [String: String] = [:]
    var answerText: [String: String] = [:]
    /// The question whose "Unlock …" choice is waiting for your confirmation.
    var confirmingUnlock: String?
    /// While cutting, the side can show progress (default), the read-back, or the sheet.
    var cuttingSide: CuttingSide = .progress
    /// Conflict notices closed with ×, by the read-back line that carries them.
    var dismissedConflicts: Set<String> = []
    /// Finished notes, in the order they finished, so rows don't jump around.
    var doneOrder: [String] = []
    /// When this window first saw a turnover start cutting (the store keeps no timestamp).
    var cuttingStarted: [String: Date] = [:]
    /// What VoiceOver last heard about, so changes are announced once.
    var heardProgress: [String: NoteProgress]?
    var heardQuestions: Set<String> = []
    var lastProgressAnnouncement = Date.distantPast
    /// A passage a notice shows on the strip while the pointer is over it (read-only).
    var stripHighlight: ClosedRange<Double>?
    /// Fixed clock and disk for previews and snapshots.
    var clock: Date?
    var previewDisk: (name: String, free: Double)?
    var now: Date { clock ?? Date() }
}

@MainActor private let notesUIByFilm = NSMapTable<FilmModel, NotesUI>.weakToStrongObjects()

extension FilmModel {
    /// The notes' view state for this film.
    var notesUI: NotesUI {
        if let state = notesUIByFilm.object(forKey: self) { return state }
        let state = NotesUI()
        notesUIByFilm.setObject(state, forKey: self)
        return state
    }

    // MARK: Turnover

    /// The open notes turnover. Assemblies belong to onboarding.
    var notesTurnover: Turnover? { openTurnover.flatMap { $0.kind == "assembly" ? nil : $0 } }
    /// "Cut 4": the name the next cut gets.
    var nextCutName: String { "Cut \(cuts.count + 1)" }
    var notesCutName: String { notesCut?.name ?? "this cut" }
    /// True while the Notes side is the "Cut 4 in progress" panel.
    var showsCuttingPanel: Bool {
        guard notesTab == .sheet, let t = notesTurnover, notesUI.cuttingSide == .progress else { return false }
        return isCutting(t)
    }
    /// Approved and past the read-back: cutting, blocked, failed, or about to start.
    func isCutting(_ t: Turnover) -> Bool {
        switch t.state {
        case .cutting, .blocked, .failed: true
        case .readBack: t.readBackApproved
        default: false
        }
    }
    func readBackLine(_ noteID: String, in t: Turnover) -> ReadBackLine? { t.readBack.first { $0.noteID == noteID } }
    func turnoverNotes(_ t: Turnover) -> [ReviewComment] { t.noteIDs.compactMap(note).sorted { ($0.number ?? .max) < ($1.number ?? .max) } }

    /// Approves the read-back. A correction still open in the panel goes first.
    func startCutting() {
        let ui = notesUI
        if let id = ui.correctingNoteID { sendCorrection(noteID: id) }
        approveReadBack()
        ui.cuttingSide = .progress
    }
    /// Corrections never edit the note: they go to the editor and into the note's thread.
    func sendCorrection(noteID: String) {
        let ui = notesUI, text = ui.correction.trimmingCharacters(in: .whitespacesAndNewlines)
        ui.correctingNoteID = nil; ui.correction = ""
        guard !text.isEmpty else { return }
        adjustReadBack(noteID: noteID, text: text)
        perform { _ = try $0.reply(commentID: noteID, text: text, author: "Director") }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: "Line \(noteNumber(noteID)) sent back to the editor", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    // MARK: Notes

    /// The number a new note will get. Numbers are never reused, even after a drop.
    var nextNoteNumber: Int { (notes.compactMap(\.number).max() ?? 0) + 1 }
    var selectedNote: ReviewComment? { note(selectedNoteID) }
    var editingNote: ReviewComment? { note(notesUI.editingNoteID) }
    func isBeforeTurnover(_ c: ReviewComment) -> Bool { [.draft, .written, .reopened].contains(c.lifecycle) }

    /// Selects a note and seeks to it. Words being written in another note are kept first.
    func showNote(_ c: ReviewComment) { select(c) }
    /// ↑ / ↓ through the sheet: the answered notes, then the notes for the next turnover.
    func selectAdjacentNote(_ step: Int) {
        let list = sheetRows
        guard !list.isEmpty else { return }
        let current = selectedAnswerNoteID ?? selectedNoteID
        let index = list.firstIndex { $0.id == current }.map { $0 + step } ?? (step > 0 ? 0 : list.count - 1)
        let c = list[max(0, min(list.count - 1, index))]
        if sheetAnswers.contains(where: { $0.id == c.id }) { selectAnswer(c, cue: !isPreview) } else { showNote(c) }
    }

    // MARK: Making a note
    // Every note starts by pointing at something: a moment (N), a stretch of the strip, a box on the picture,
    // a scene, or the whole cut. It's a note at once, with no words yet, and its row opens to write in
    // (specs/cut.md › Making a note).

    /// A note just made: selected, and its row opened to write in unless the picture is playing.
    func made(_ c: ReviewComment) {
        notesTab = .sheet
        cancelDrawing()
        if playing || watchingCut { return }
        beginWriting(c)
    }
    /// A note on a stretch of the cut. `open: false` (I and O): it's selected, so the other key moves its other
    /// end, but its row doesn't open, so the keyboard stays with the picture, playing or not.
    func markStretch(_ r: ClosedRange<Double>, open: Bool = true) {
        let lower = max(0, r.lowerBound), upper = min(duration, r.upperBound)
        guard upper - lower >= 1 / fps, let c = addNote(text: "", range: lower...upper, state: .draft) else { return }
        registerUndo("Mark a Stretch") { $0.dropNote(c.id) }
        guard !open else { made(c); return }
        if notesUI.editingNoteID != nil { saveWriting(advance: false) }
        notesTab = .sheet
        cancelDrawing()
        selectedNoteID = c.id
        selectedAnswerNoteID = nil
    }
    /// A note on a box drawn on the picture, at this moment.
    func markBox(_ r: CGRect) {
        let t = min(position, max(0, duration - 1 / fps))
        guard let c = addNote(text: "", time: t, region: r, state: .draft) else { return }
        registerUndo("Draw a Box") { $0.dropNote(c.id) }
        made(c)
    }
    /// A note on the whole cut, or on one scene.
    func noteWholeCut(scene sceneID: String? = nil) {
        guard let c = addNote(text: "", sceneID: sceneID, state: .draft) else { return }
        registerUndo(sceneID == nil ? "Note on the Whole Cut" : "Note on the Scene") { $0.dropNote(c.id) }
        made(c)
    }

    /// Draw a box (R, or the box under the picture): the next drag on the picture makes its note.
    func beginRegion() {
        saveWriting(advance: false)
        pause()
        notesTab = .sheet
        cancelDrawing()
        drawingRegion = true
    }
    /// Mark a stretch (the stretch under the picture): the next drag along the strip makes its note.
    func beginStretch() {
        saveWriting(advance: false)
        pause()
        notesTab = .sheet
        cancelDrawing()
        drawingStretch = true
    }
    /// esc while drawing, or anything that starts something else: nothing is made, and no box or stretch is left
    /// half drawn.
    func cancelDrawing() {
        region = nil; rangeSelection = nil; drawingRegion = false; drawingStretch = false
    }
    var isDrawing: Bool { drawingRegion || drawingStretch }

    /// The selected note's stretch or box can still be moved: yours, and not turned over yet.
    var selectedAnchorEditable: Bool {
        guard let c = selectedNote, !looksBack else { return false }
        return isBeforeTurnover(c) && !c.isOutside
    }
    var stretchEditable: Bool { selectedAnchorEditable && selectedNote?.range != nil }
    var boxEditable: Bool { selectedAnchorEditable && selectedNote?.region != nil }

    /// The stretch on the strip: a notice's passage, one being drawn or pulled, or the selected note's.
    var stripRange: ClosedRange<Double>? {
        if let h = notesUI.stripHighlight { return h }
        if let r = rangeSelection { return r }
        guard let r = selectedNote?.range else { return nil }
        return r.start.seconds...r.end.seconds
    }
    /// The strip let go: a stretch drawn becomes its note; the selected note keeps its moved stretch.
    func finishStretch(new: Bool) {
        guard let r = rangeSelection else { return }
        if new || drawingStretch || !stretchEditable { markStretch(r); return }
        rangeSelection = nil
        if let c = selectedNote { moveStretch(c, to: r) }
    }
    /// The selected note's stretch, pulled or moved: what it rests on in the footage, and the words under it, move
    /// with it. Never shorter than a frame.
    private func moveStretch(_ c: ReviewComment, to r: ClosedRange<Double>) {
        guard let old = c.range else { return }
        let moved = MediaRange(start: max(0, r.lowerBound), end: min(duration, r.upperBound))
        guard moved.end.seconds - moved.start.seconds >= 1 / fps - 1e-9, moved != old else { return }
        perform { _ = try $0.editNote(id: c.id, range: moved) }
        registerUndo("Move Stretch") { m in m.perform { _ = try $0.editNote(id: c.id, range: old) } }
    }

    /// I / O: a stretch starts or ends at the playhead. The selected note's stretch moves; otherwise (or with the
    /// playhead past its other end) it's a new note on the two seconds from (or up to) here, selected so the other
    /// key ends (or starts) it.
    func setStretchEdge(start: Bool) {
        let t = min(max(0, position), duration)
        if stretchEditable, let c = selectedNote, let r = c.range {
            let a = r.start.seconds, b = r.end.seconds, length = start ? b - t : t - a
            if length >= 1 / fps - 1e-9 { moveStretch(c, to: start ? t...b : a...t); return }
        }
        markStretch(start ? t...min(duration, t + 2) : max(0, t - 2)...t, open: false)
    }

    /// The box on the picture: the one being drawn, or the selected note's (±12 frames around its moment).
    var visibleRegion: CGRect? {
        if drawingRegion { return region }
        guard let c = selectedNote, let r = c.region, let t = noteTime(c), abs(position - t) <= 12 / fps else { return nil }
        return region ?? CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }
    /// The picture let go: a box drawn becomes its note; the selected note keeps its moved box.
    func finishBox(new: Bool) {
        guard let r = region else { return }
        if new || drawingRegion { markBox(r); return }
        region = nil
        guard boxEditable, let c = selectedNote else { return }
        let box = FrameRegion(x: r.minX, y: r.minY, width: r.width, height: r.height), old = c.region
        guard box != old else { return }
        perform { _ = try $0.editNote(id: c.id, region: .some(box)) }
        registerUndo("Move Box") { m in m.perform { _ = try $0.editNote(id: c.id, region: .some(old)) } }
    }
    /// Takes a note's box away; the note stays on its moment.
    func removeBox(_ c: ReviewComment) {
        guard let old = c.region, isBeforeTurnover(c) else { return }
        region = nil
        perform { _ = try $0.editNote(id: c.id, region: .some(nil)) }
        registerUndo("Remove Box") { m in m.perform { _ = try $0.editNote(id: c.id, region: .some(old)) } }
    }

    // MARK: Writing a note

    /// Opens a note's row to write in: its words, its kind, the caret at the end. A row that's already open keeps
    /// what's being written in it and only gets the caret back.
    func beginWriting(_ c: ReviewComment) {
        guard isBeforeTurnover(c) else { return }
        // An older cut's notes aren't written there, but clicking one still selects it and finds its moment.
        guard !looksBack else { if selectedNoteID != c.id { select(c) }; return }
        notesTab = .sheet
        guard notesUI.editingNoteID != c.id else { composerFocus += 1; return }
        saveWriting(advance: false)
        if selectedNoteID != c.id { select(c) }
        notesUI.editingNoteID = c.id
        draftText = c.text; draftKind = c.kind
        composerFocus += 1
    }
    /// ↩ in a note's row: its words are kept. A mark from watching through goes on to the next one waiting for
    /// words. A note left with no words stays a mark to write later.
    func saveWriting(advance: Bool = true) {
        guard let c = editingNote else { stopWriting(); return }
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines), kind = draftKind, wasDraft = c.lifecycle == .draft
        stopWriting()
        guard !text.isEmpty, text != c.text || kind != c.kind else { return }
        let old = (c.text, c.kind)
        editNote(c.id, text: text, kind: .some(kind))
        if !wasDraft { registerUndo("Edit Note") { $0.editNote(c.id, text: old.0, kind: .some(old.1)) } }
        guard advance, wasDraft, screeningMarkIDs.contains(c.id) else { return }
        if let next = draftNotes.first(where: { $0.id != c.id && screeningMarkIDs.contains($0.id) }) { beginWriting(next) }
    }
    /// Turn over…, however it's reached: the words open in a row are kept first, so they go over as written.
    func showTurnoverSheet() {
        saveWriting(advance: false)
        sheet = .turnover
    }
    /// esc in a note's row: it closes as it was.
    func stopWriting() {
        notesUI.editingNoteID = nil
        draftText = ""; draftKind = nil
    }
    /// An outside note's Edit first: it joins your notes, open to write in.
    func editOutsideFirst(_ c: ReviewComment) {
        acceptOutside(c.id)
        notesTab = .sheet
        if let accepted = note(c.id) { beginWriting(accepted) }
    }
    /// Drops a note from the sheet (⌫). Its number is retired.
    func dropFromSheet(_ c: ReviewComment) {
        guard isBeforeTurnover(c) else { return }
        let list = sheetNotes, index = list.firstIndex { $0.id == c.id }
        if notesUI.editingNoteID == c.id { stopWriting() }
        dropNote(c.id)
        if selectedNoteID == c.id {
            region = nil; rangeSelection = nil
            let rest = list.filter { $0.id != c.id }
            selectedNoteID = index.flatMap { rest.indices.contains($0) ? rest[$0].id : rest.last?.id }
        }
    }
    /// ⌥1…⌥5: the kind of the note being written, or of the selected written note.
    func setKind(_ kind: NoteKind) {
        if notesUI.editingNoteID != nil { draftKind = draftKind == kind ? nil : kind; return }
        guard let c = selectedNote, [.written, .reopened].contains(c.lifecycle) else { return }
        let old = c.kind
        editNote(c.id, kind: .some(c.kind == kind ? nil : kind))
        registerUndo("Change Kind") { $0.editNote(c.id, kind: .some(old)) }
    }

    // MARK: Anchors and words

    func anchorScene(_ c: ReviewComment) -> StripScene? {
        if let t = noteTime(c) { return stripScene(at: t) }
        if let id = c.sceneID { return stripScenes.first { $0.id == id } }
        return nil
    }
    /// Notes the editor can't act on without unlocking a scene.
    func isInLockedScene(_ c: ReviewComment) -> Bool {
        if let id = c.sceneID, let s = scene(id) { return s.locked }
        return anchorScene(c)?.locked ?? false
    }
    /// The anchor's start for compact lists: "00:46:00", "Line 14", "Scene 4".
    func anchorStart(_ c: ReviewComment) -> String {
        if let action = c.scriptAction { return action.lineLabel ?? "Line" }
        if let t = noteTime(c) { return Timecode.format(t, fps: fps) }
        if let s = scene(c.sceneID) { return "Scene \(s.number)" }
        return "Whole cut"
    }
    /// What the note is on, as the icon of the tool under the picture that makes it.
    func anchorIcon(_ c: ReviewComment) -> String? {
        switch c.scriptAction?.gesture {
        case .strike: "strikethrough"
        case .hold: "curlybraces"
        case .move: "arrow.up.and.down"
        case .reading: "quote.opening"
        case nil: NoteAnchor(c).icon
        }
    }
    /// VoiceOver: "Note 2, Feeling, 46 seconds to 58 seconds: I want to feel…"
    func spokenNote(_ c: ReviewComment) -> String {
        let number = c.number.map { "Note \($0)" } ?? "Note"
        var anchor = ""
        if let r = c.range { anchor = "\(Self.spoken(r.start.seconds)) to \(Self.spoken(r.end.seconds))" }
        else if let t = c.time { anchor = Self.spoken(t.seconds) }
        else if let s = scene(c.sceneID) { anchor = "scene \(s.number)" }
        else { anchor = "whole cut" }
        if c.lifecycle == .draft { return "\(number), \(NoteAnchor(c).label.lowercased()), \(anchor), no words yet" }
        let kind = c.kind.map { "\($0.label), " } ?? ""
        let who = c.person.map { ", from \($0.name)" } ?? ""
        return "\(number), \(kind)\(anchor)\(who): \(c.text)"
    }
    /// "46 seconds", "1 minute 12".
    static func spoken(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        if s < 60 { return s == 1 ? "1 second" : "\(s) seconds" }
        let m = s / 60, rest = s % 60
        return (m == 1 ? "1 minute" : "\(m) minutes") + (rest > 0 ? " \(rest)" : "")
    }

    /// The sheet head's status line.
    var sheetStatus: String {
        if looksBack, let cut = watchedCut { return "Looking back \u{00B7} \(ChangesFormat.dayAndTime(cut.createdAt)) \u{00B7} \(cutSummary(cut))" }
        if let t = notesTurnover {
            switch t.state {
            case .waiting: return "Turned over · waiting for the editor to pick it up"
            case .readBack where !t.readBackApproved: return "Turned over · the editor read it back"
            default: return "Turned over · the editor is cutting \(nextCutName)"
            }
        }
        let written = sheetNotes.filter { [.written, .reopened].contains($0.lifecycle) }.count
        let drafts = draftNotes.count, outside = inbox.count
        // A cut just in, nothing written on it yet: how it came out against the one before.
        if written + drafts + outside == 0, !reviewAnswers.isEmpty, let cut = reviewCut, let d = cutDuration(cut) {
            guard let before = cutBefore(cut), let p = cutDuration(before) else { return Timecode.duration(d) }
            return "\(Timecode.duration(d)) \u{00B7} \(ChangesFormat.lengthChange(d - p, than: before.name))"
        }
        if written + drafts + outside == 0 { return "Nothing written yet" }
        if drafts == 0 && outside == 0 { return written == 1 ? "1 note, ready to turn over" : "\(written) notes, ready to turn over" }
        var parts = written > 0 || drafts == 0 ? ["\(written) written"] : []
        if drafts > 0 { parts.append(drafts == 1 ? "1 waiting for words" : "\(drafts) waiting for words") }
        if outside > 0 { parts.append("\(outside) from people you shared with") }
        return parts.joined(separator: " · ")
    }

    // MARK: Time

    func clockTime(_ seconds: Double) -> String { Self.clockFormatter.string(from: Date(timeIntervalSince1970: seconds)) }
    /// "just now", "2 min ago", "1 h ago", "Yesterday", "Oct 12".
    func ago(_ seconds: Double) -> String {
        let now = notesUI.now, then = Date(timeIntervalSince1970: seconds), delta = now.timeIntervalSince(then)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60)) min ago" }
        if Calendar.current.isDate(then, inSameDayAs: now) { return "\(Int(delta / 3600)) h ago" }
        if Calendar.current.isDate(then, inSameDayAs: now.addingTimeInterval(-86_400)) { return "Yesterday" }
        return Self.dayFormatter.string(from: then)
    }
    private static let clockFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private static let dayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
}

// MARK: On-device heuristics

/// Proposes a kind from a note's words. Runs on this Mac; the editor never sees the text.
enum KindSuggester {
    private static let cues: [(NoteKind, [String])] = [
        (.feeling, ["feel", "feels", "feeling", "tired", "proud", "sad", "emotion", "mood", "breathe", "sit", "moved", "warm", "lonely", "quiet", "heart", "joy", "tense", "alone"]),
        (.story, ["lose", "line", "say", "says", "said", "story", "order", "earlier", "later", "move", "show", "explain", "understand", "why", "scene", "start", "end", "reveal", "team"]),
        (.pace, ["long", "short", "pace", "faster", "slower", "quicker", "beat", "beats", "trim", "drags", "drag", "sooner", "rushed", "hold", "linger", "pause", "pauses", "montage"]),
        (.picture, ["tighter", "wider", "tight", "wide", "frame", "framing", "crop", "sky", "shot", "close", "closer", "color", "colour", "light", "dark", "bright", "focus", "look", "reframe", "angle", "logo", "bigger", "smaller"]),
        (.sound, ["music", "sound", "audio", "loud", "louder", "quieter", "mix", "voice", "hear", "noise", "db", "score", "song", "volume", "room", "tone"]),
    ]

    static func suggest(_ text: String) -> NoteKind? {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count >= 3 else { return nil }
        var best: (NoteKind, Int)?
        for (kind, cues) in cues {
            let score = words.filter(cues.contains).count
            if score > 0, score > (best?.1 ?? 0) { best = (kind, score) }
        }
        return best?.0
    }
}

/// "Love the ridge shot." asks for nothing; it can't be turned over until it's made a note.
enum ReactionDetector {
    private static let asks = ["can", "could", "should", "would", "make", "more", "less", "bigger", "smaller", "cut", "lose", "move", "change", "try", "show", "add", "remove", "tighter", "shorter", "longer", "earlier", "later", "why", "need", "needs", "want", "fix"]
    private static let praise = ["love", "loved", "great", "beautiful", "nice", "perfect", "amazing", "lovely", "works", "gorgeous", "wow", "good", "brilliant", "favorite", "favourite"]
    static func isReaction(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        guard !text.contains("?"), words.count <= 12 else { return false }
        return words.contains(where: praise.contains) && !words.contains(where: asks.contains)
    }
}

/// What a note points at, and the tool under the picture that makes it (specs/cut.md › Making a note).
enum NoteAnchor: CaseIterable {
    case moment, stretch, box, scene, wholeCut
    init(_ c: ReviewComment) {
        if c.region != nil { self = .box }
        else if c.range != nil { self = .stretch }
        else if c.time != nil { self = .moment }
        else if c.sceneID != nil { self = .scene }
        else { self = .wholeCut }
    }
    var icon: String {
        switch self {
        case .moment: "mappin"
        case .stretch: "arrow.left.and.right"
        case .box: "viewfinder"
        case .scene: "film"
        case .wholeCut: "text.bubble"
        }
    }
    var label: String {
        switch self {
        case .moment: "Mark"
        case .stretch: "Stretch"
        case .box: "Box"
        case .scene: "Scene"
        case .wholeCut: "Whole cut"
        }
    }
    /// What a note with no words yet is, in "Remove this …": a mark, a stretch, a box, or a note (on a scene or
    /// the whole cut).
    var unwritten: String {
        switch self {
        case .moment: "mark"
        case .stretch: "stretch"
        case .box: "box"
        case .scene, .wholeCut: "note"
        }
    }
}
