import SwiftUI
import AppKit
import DirectionCore

// The Cut room's notes state and the derived values its views share.
// FilmModel owns the film; this file only adds view state and read-only helpers,
// plus a few director actions composed from FilmModel's store actions.

/// What the Notes side shows while a turnover is cutting.
enum CuttingSide { case progress, readBack, notes }

/// View state for the notes on the Cut room's sheet that outlives a single view: the composer's pinned
/// anchor, the read-back line being corrected, the choice on each open question.
/// One per film, so the titlebar's primary and the snapshot fixtures can see it too.
@MainActor @Observable
final class NotesUI {
    /// The last `FilmModel.composerFocus` value the composer already acted on.
    var handledComposerFocus = 0
    /// The caret is in the composer.
    var composerFocused = false
    /// Once you start typing, a new note's moment stops following the playhead.
    var pinnedTime: Double?
    /// A written note open in the composer ("Editing note 1").
    var editingNoteID: String?
    /// An outside note opened with Edit first.
    var editingOutsideID: String?
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
    /// The composer anchor to restore after a conflict stops highlighting the strip.
    var stripHighlightRestore: (NoteAnchorMode, ClosedRange<Double>?)?
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
    var editingOutside: ReviewComment? { note(notesUI.editingOutsideID) }
    /// The number the composer is writing: the selected draft's, or the next one.
    var composerNoteNumber: Int? {
        if let c = editingNote { return c.number }
        if let c = selectedNote, c.lifecycle == .draft { return c.number }
        return nil
    }
    func isBeforeTurnover(_ c: ReviewComment) -> Bool { [.draft, .written, .reopened].contains(c.lifecycle) }

    /// Selects a note and seeks to it without moving focus into the composer.
    /// Words already in the composer stay there; selecting a draft never throws them away.
    func showNote(_ c: ReviewComment) {
        let words = (draftText, draftKind)
        select(c)
        if !words.0.isEmpty { draftText = words.0; draftKind = words.1 }
        notesUI.handledComposerFocus = composerFocus
    }
    /// ↑ / ↓ through the sheet: the answered notes, then the notes for the next turnover.
    func selectAdjacentNote(_ step: Int) {
        let list = sheetRows
        guard !list.isEmpty else { return }
        let current = selectedAnswerNoteID ?? selectedNoteID
        let index = list.firstIndex { $0.id == current }.map { $0 + step } ?? (step > 0 ? 0 : list.count - 1)
        let c = list[max(0, min(list.count - 1, index))]
        if sheetAnswers.contains(where: { $0.id == c.id }) { selectAnswer(c, cue: !isPreview) } else { showNote(c) }
    }

    /// The composer's moment: pinned once you type, otherwise the playhead.
    var composerTime: Double {
        if let c = selectedNote, c.lifecycle == .draft, let t = noteTime(c) { return t }
        return notesUI.pinnedTime ?? position
    }

    /// Add / Save / Accept in the composer.
    func writeComposer() {
        let ui = notesUI, text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let c = editingOutside {
            acceptOutside(c.id, text: text)
            if let kind = draftKind, let accepted = note(c.id) { editNote(accepted.id, kind: .some(kind)) }
            clearComposer()
            return
        }
        if let c = editingNote {
            let old = (c.text, c.kind)
            editNote(c.id, text: text, kind: .some(draftKind))
            registerUndo("Edit Note") { $0.editNote(c.id, text: old.0, kind: .some(old.1)) }
            clearComposer()
            return
        }
        if let c = selectedNote, c.lifecycle == .draft {
            submitComposer()
            ui.pinnedTime = nil
            if let next = note(selectedNoteID), next.lifecycle == .draft {
                showNote(next)
                composerFocus += 1 // keep writing: the next draft takes the field
            }
            return
        }
        let time = min(composerTime, max(0, duration - 1 / fps))
        let added: ReviewComment?
        switch anchorMode {
        case .moment: added = addNote(text: text, kind: draftKind, time: time)
        case .range: added = addNote(text: text, kind: draftKind, range: rangeSelection ?? time...min(duration, time + 1))
        case .region: added = addNote(text: text, kind: draftKind, time: time, region: region)
        case .scene: added = addNote(text: text, kind: draftKind, sceneID: stripScene(at: time).flatMap { s in dailies.scenes.first { $0.id == s.id }?.id })
        case .wholeCut: added = addNote(text: text, kind: draftKind)
        }
        if let added { registerUndo("Add Note") { $0.dropNote(added.id) } }
        clearComposer()
    }
    func clearComposer() {
        draftText = ""; draftKind = nil; region = nil; drawingRegion = false; rangeSelection = nil; anchorMode = .moment
        let ui = notesUI
        ui.pinnedTime = nil; ui.editingNoteID = nil; ui.editingOutsideID = nil
    }
    /// esc: stop writing. A draft keeps its mark.
    func cancelComposer() {
        if drawingRegion { cancelRegion(); return }
        clearComposer()
    }
    func editInComposer(_ c: ReviewComment) {
        guard isBeforeTurnover(c), c.lifecycle != .draft else { if c.lifecycle == .draft { select(c) }; return }
        select(c)
        notesTab = .sheet
        let ui = notesUI
        ui.editingOutsideID = nil; ui.editingNoteID = c.id
        draftText = c.text; draftKind = c.kind
        composerFocus += 1
    }
    func editOutsideFirst(_ c: ReviewComment) {
        notesTab = .sheet
        selectedNoteID = nil
        let ui = notesUI
        ui.editingNoteID = nil; ui.editingOutsideID = c.id
        draftText = c.text; draftKind = c.kind
        composerFocus += 1
    }
    /// Drops a note from the sheet (⌫). Its number is retired.
    func dropFromSheet(_ c: ReviewComment) {
        guard isBeforeTurnover(c) else { return }
        let list = sheetNotes, index = list.firstIndex { $0.id == c.id }
        dropNote(c.id)
        if selectedNoteID == c.id {
            let rest = list.filter { $0.id != c.id }
            selectedNoteID = index.flatMap { rest.indices.contains($0) ? rest[$0].id : rest.last?.id }
        }
        if notesUI.editingNoteID == c.id { clearComposer() }
    }
    /// ⌥1…⌥5: the composer's kind, or the selected written note's.
    func setKind(_ kind: NoteKind, composer: Bool) {
        if !composer, let c = selectedNote, [.written, .reopened].contains(c.lifecycle), notesUI.editingNoteID == nil {
            let old = c.kind
            editNote(c.id, kind: .some(c.kind == kind ? nil : kind))
            registerUndo("Change Kind") { $0.editNote(c.id, kind: .some(old)) }
        } else {
            draftKind = draftKind == kind ? nil : kind
        }
    }

    // MARK: Region

    /// R: draw a region on the picture for the note being written.
    func beginRegion() {
        pause()
        anchorMode = .region
        drawingRegion = true
        notesTab = .sheet
        if notesUI.pinnedTime == nil, !(selectedNote?.lifecycle == .draft) { notesUI.pinnedTime = position }
    }
    func cancelRegion() {
        region = nil; drawingRegion = false
        if anchorMode == .region { anchorMode = .moment }
    }
    /// The region shows while you draw it, while the composer holds it, and for ±12 frames around a selected note.
    var visibleRegion: CGRect? {
        if drawingRegion || anchorMode == .region { return region }
        guard let c = selectedNote, let r = c.region, let t = noteTime(c), abs(position - t) <= 12 / fps else { return nil }
        return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
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
    func anchorIcon(_ c: ReviewComment) -> String? {
        switch c.scriptAction?.gesture {
        case .strike: "strikethrough"
        case .hold: "curlybraces"
        case .move: "arrow.up.and.down"
        case .reading: "quote.opening"
        case nil: nil
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
        if c.lifecycle == .draft { return "\(number), draft from screening, \(anchor)" }
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
        if drafts > 0 { parts.append("\(drafts) from your screening, waiting for words") }
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
