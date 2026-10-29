import Foundation
import SwiftUI
import DirectionCore

// The director never edits text in Script. Each gesture becomes one numbered note with a
// line anchor; nothing changes in the cut until turnover.

extension FilmModel {
    /// Same as Notes: turns over the whole sheet, script notes included.
    var scriptPrimary: PrimaryAction? {
        PrimaryAction(title: "Turn over", icon: "arrow.right", enabled: !readyNotes.isEmpty && openTurnover == nil) { self.sheet = .turnover }
    }

    /// Line-anchored notes still on the sheet, in number order.
    var scriptNotes: [ReviewComment] {
        notes.filter { $0.scriptAction != nil && $0.lifecycle != .dropped && !$0.inInbox && !$0.isUnasked }
            .sorted { ($0.number ?? .max, $0.createdAt) < ($1.number ?? .max, $1.createdAt) }
    }

    /// Why a gesture can't be made on these lines, as the toast says it.
    func scriptRefusal(_ gesture: ScriptGesture, _ lines: [ScriptLine]) -> (String, unlock: String?)? {
        if let s = lines.lazy.compactMap({ l in self.dailies.scenes.first { $0.id == l.sceneID } }).first(where: \.locked) {
            return ("Scene \(s.number) is locked. Unlock it to give notes here.", s.id)
        }
        if gesture == .strike, lines.contains(where: isMustKeep) {
            return ("That line is a must-keep in your brief. Change the brief to cut it.", nil)
        }
        return nil
    }

    func isMustKeep(_ line: ScriptLine) -> Bool {
        let words = ScriptText.normalized(line.text)
        guard words.count >= 3 else { return false }
        return brief.mustKeep.contains { keep in
            let k = ScriptText.normalized(keep)
            return ScriptText.similarity(k, words) == 1 && (k.count >= words.count || words.count - k.count <= 2)
        }
    }

    static func lineLabel(_ lines: [ScriptLine]) -> String {
        guard let first = lines.first, let last = lines.last else { return "Line" }
        return lines.count == 1 ? "Line \(first.number)" : "Lines \(first.number)\u{2013}\(last.number)"
    }

    /// Strike: "Lose “…”." Story.
    @discardableResult
    func strikeLines(_ lines: [ScriptLine]) -> ReviewComment? {
        let label = Self.lineLabel(lines)
        let text = lines.count == 1 ? "Lose \(ScriptText.quoted(lines[0].text))" : "Lose lines \(label.dropFirst(6))."
        return addScriptNote(text, .story, lines, ScriptAction(gesture: .strike, lineText: joined(lines), lineLabel: label), undo: "Strike")
    }

    /// Hold: "Let this breathe." Pace. The words can be edited right after.
    @discardableResult
    func holdLines(_ lines: [ScriptLine]) -> ReviewComment? {
        addScriptNote("Let this breathe.", .pace, lines, ScriptAction(gesture: .hold, lineText: joined(lines), lineLabel: Self.lineLabel(lines)), undo: "Hold")
    }

    /// Move: "Move “…” after “…”." Story.
    @discardableResult
    func moveLine(_ line: ScriptLine, after target: ScriptLine) -> ReviewComment? {
        let text = "Move \(ScriptText.quoted(line.text)) after \(ScriptText.quoted(target.text))"
        return addScriptNote(text, .story, [line], ScriptAction(gesture: .move, lineText: line.text, lineLabel: "Line \(line.number) \u{2192} after \(target.number)", afterText: target.text), undo: "Move")
    }

    /// Choosing another reading: "Use 2A T3’s reading." Feeling.
    @discardableResult
    func useReading(_ assetID: String, label take: String, for line: ScriptLine) -> ReviewComment? {
        addScriptNote("Use \(take)\u{2019}s reading.", .feeling, [line], ScriptAction(gesture: .reading, lineText: line.text, lineLabel: line.label, takeAssetID: assetID), undo: "Choose Reading")
    }

    private func joined(_ lines: [ScriptLine]) -> String { lines.map(\.text).joined(separator: " ") }

    private func addScriptNote(_ text: String, _ kind: NoteKind, _ lines: [ScriptLine], _ action: ScriptAction, undo name: String) -> ReviewComment? {
        guard let first = lines.first, let last = lines.last, duration > 0 else { return nil }
        let start = max(0, min(first.start, duration - 1 / fps)), end = min(duration, max(last.end, start + 1 / fps))
        guard let c = addNote(text: text, kind: kind, range: start...end, scriptAction: action, state: .written) else { return nil }
        registerUndo(name) { $0.dropNote(c.id) }
        return c
    }
}

/// What the script page draws for the notes on the sheet: struck lines, held passages,
/// moves and readings, each with its note number.
struct ScriptMarks {
    struct Tag: Hashable { var noteID: String; var number: Int }
    struct Hold: Hashable { var tag: Tag; var lineIDs: [String] }
    struct Move: Hashable { var tag: Tag; var lineID: String; var afterID: String; var afterNumber: Int }

    var struck: [String: Tag] = [:]
    var holds: [Hold] = []
    var moves: [Move] = []
    /// Gutter tags by line.
    var tags: [String: [Tag]] = [:]
    /// Lines each note marks, for selecting a note's lines.
    var linesOfNote: [String: [String]] = [:]

    init() {}

    init(notes: [ReviewComment], document doc: ScriptDocument) {
        for note in notes {
            guard let action = note.scriptAction, note.lifecycle != .dropped else { continue }
            let tag = Tag(noteID: note.id, number: note.number ?? 0)
            switch action.gesture {
            case .strike:
                let run = doc.run(matching: action.lineText)
                for line in run { struck[line.id] = tag }
                if let first = run.first { tags[first.id, default: []].append(tag) }
                linesOfNote[note.id] = run.map(\.id)
            case .hold:
                let run = doc.run(matching: action.lineText)
                guard let first = run.first else { continue }
                holds.append(Hold(tag: tag, lineIDs: run.map(\.id)))
                tags[first.id, default: []].append(tag)
                linesOfNote[note.id] = run.map(\.id)
            case .move:
                guard let line = doc.run(matching: action.lineText).first, let after = action.afterText.flatMap({ doc.run(matching: $0).first }) else { continue }
                moves.append(Move(tag: tag, lineID: line.id, afterID: after.id, afterNumber: after.number))
                linesOfNote[note.id] = [line.id]
            case .reading:
                guard let line = doc.run(matching: action.lineText).first else { continue }
                tags[line.id, default: []].append(tag)
                linesOfNote[note.id] = [line.id]
            }
        }
    }

    enum Edge { case single, top, middle, bottom }
    func hold(_ lineID: String) -> (Hold, Edge)? {
        guard let h = holds.first(where: { $0.lineIDs.contains(lineID) }), let i = h.lineIDs.firstIndex(of: lineID) else { return nil }
        let edge: Edge = h.lineIDs.count == 1 ? .single : i == 0 ? .top : i == h.lineIDs.count - 1 ? .bottom : .middle
        return (h, edge)
    }
    func move(of lineID: String) -> Move? { moves.first { $0.lineID == lineID } }
    func moves(after lineID: String) -> [Move] { moves.filter { $0.afterID == lineID } }
    func noteIDs(on lineID: String) -> [String] { linesOfNote.filter { $0.value.contains(lineID) }.map(\.key) }
}
