import Foundation
import GRDB

/// Fields a note carries beyond plain feedback.
public struct NoteFields: Sendable {
    public var kind: NoteKind?
    public var noteState: NoteState?
    public var authorRole: String?
    public var person: Person?
    public var outsideState: String?
    public var scriptAction: ScriptAction?
    public var sceneID: String?
    public var assignNumber = true
    public init(kind: NoteKind? = nil, noteState: NoteState? = nil, authorRole: String? = nil, person: Person? = nil, outsideState: String? = nil, scriptAction: ScriptAction? = nil, sceneID: String? = nil, assignNumber: Bool = true) {
        self.kind = kind; self.noteState = noteState; self.authorRole = authorRole; self.person = person; self.outsideState = outsideState; self.scriptAction = scriptAction; self.sceneID = sceneID; self.assignNumber = assignNumber
    }
}

/// An answer the editor delivers with a new cut.
public struct AnswerInput: Codable, Sendable {
    public var noteID: String?
    public var summary: String
    public var delta: String?
    public var start: Double?
    public var end: Double?
    public var options: [NoteOption]?
    public var preferred: String?
    public var unasked: Bool?
    public var kind: NoteKind?
}

enum DirectingKey {
    static let brief = "brief", dailies = "dailies", state = "state", status = "editorStatus"
}

extension ProjectStore {
    static func ensureDirectingTables(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS directing (key TEXT PRIMARY KEY, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS turnovers (id TEXT PRIMARY KEY, payload BLOB NOT NULL, created_at DOUBLE NOT NULL);
        CREATE TABLE IF NOT EXISTS questions (id TEXT PRIMARY KEY, payload BLOB NOT NULL, created_at DOUBLE NOT NULL);
        """)
    }

    // MARK: Key-value records

    static func value<T: Decodable>(_ db: Database, _ key: String, as type: T.Type) throws -> T? {
        try Data.fetchOne(db, sql: "SELECT payload FROM directing WHERE key = ?", arguments: [key]).map { try JSONDecoder().decode(type, from: $0) }
    }
    static func setValue<T: Encodable>(_ db: Database, _ key: String, _ value: T) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO directing (key, payload) VALUES (?, ?)", arguments: [key, try JSONEncoder.direction.encode(value)])
    }
    private func currentRevision(_ db: Database) throws -> Int { try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0 }

    public func brief() throws -> Brief { try database.read { try Self.value($0, DirectingKey.brief, as: Brief.self) } ?? Brief() }
    public func saveBrief(_ brief: Brief) throws {
        var b = brief; b.updatedAt = Date().timeIntervalSince1970
        try database.write { db in try Self.setValue(db, DirectingKey.brief, b); try Self.event(db, kind: "brief.updated", revision: try currentRevision(db), summary: "Updated the brief") }
    }

    public func dailies() throws -> Dailies { try database.read { try Self.value($0, DirectingKey.dailies, as: Dailies.self) } ?? Dailies() }
    public func directingState() throws -> DirectingState { try database.read { try Self.value($0, DirectingKey.state, as: DirectingState.self) } ?? DirectingState() }
    public func editorStatus() throws -> EditorStatus? { try database.read { try Self.value($0, DirectingKey.status, as: EditorStatus.self) } }

    @discardableResult
    func mutate<T: Codable>(_ key: String, default value: T, kind: String, summary: String, _ change: (inout T) throws -> Void) throws -> T {
        try database.write { db in
            var current = try Self.value(db, key, as: T.self) ?? value
            try change(&current)
            try Self.setValue(db, key, current)
            try Self.event(db, kind: kind, revision: try currentRevision(db), summary: summary)
            return current
        }
    }

    // MARK: Dailies (director side)

    public func setCircle(assetID: String, circled: Bool) throws {
        _ = try read().asset(assetID)
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: circled ? "Circled a take" : "Uncircled a take") { d in
            var t = d.take(assetID); t.circled = circled; t.circledAt = circled ? Date().timeIntervalSince1970 : nil; d.takes[assetID] = t
        }
    }
    public func setTakeScene(assetID: String, sceneID: String?) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Moved a take") { d in
            if let sceneID { guard d.scenes.contains(where: { $0.id == sceneID }) else { throw DirectionError("scene_not_found", "Scene not found.") } }
            var t = d.take(assetID); t.sceneID = sceneID; t.guessSceneID = nil; d.takes[assetID] = t
        }
    }
    public func setUnusable(assetID: String, unusable: Bool) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: unusable ? "Marked a take not usable" : "Marked a take usable") { d in var t = d.take(assetID); t.unusable = unusable; if unusable { t.circled = false }; d.takes[assetID] = t }
    }
    public func lockScene(id: String, locked: Bool) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "lock.updated", summary: locked ? "Locked a scene" : "Unlocked a scene") { d in
            guard let i = d.scenes.firstIndex(where: { $0.id == id }) else { throw DirectionError("scene_not_found", "Scene not found.") }
            d.scenes[i].locked = locked; d.scenes[i].lockedAt = locked ? Date().timeIntervalSince1970 : nil
        }
    }
    public func renameScene(id: String, title: String) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Renamed a scene") { d in
            guard let i = d.scenes.firstIndex(where: { $0.id == id }) else { throw DirectionError("scene_not_found", "Scene not found.") }
            d.scenes[i].title = title
        }
    }

    /// The editor logs footage: scenes, setups, take codes, captions, suggestions and guesses. It can't circle.
    public func logDailies(_ update: Dailies) throws -> Dailies {
        let assets = Set(try read().assets.map(\.id))
        return try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "The editor logged footage") { d in
            var scenes: [DailiesScene] = []
            for var s in update.scenes {
                if let old = d.scenes.first(where: { $0.id == s.id }) { s.locked = old.locked; s.lockedAt = old.lockedAt }
                else { s.locked = false; s.lockedAt = nil }
                scenes.append(s)
            }
            for old in d.scenes where old.locked && !scenes.contains(where: { $0.id == old.id }) { scenes.append(old) }
            d.scenes = scenes.sorted { $0.number < $1.number }
            for (id, var t) in update.takes {
                guard assets.contains(id) else { throw DirectionError("asset_not_found", "Take \(id) is not footage in this film.") }
                let old = d.take(id)
                t.assetID = id; t.circled = old.circled; t.circledAt = old.circledAt
                if old.unusable && !t.unusable { t.unusable = old.unusable }
                if let s = old.sceneID, d.scenes.first(where: { $0.id == s })?.locked == true { t.sceneID = s }
                d.takes[id] = t
            }
            d.updatedAt = Date().timeIntervalSince1970
        }
    }

    // MARK: Directing state

    public func updateDirectingState(summary: String, _ change: (inout DirectingState) throws -> Void) throws -> DirectingState {
        try mutate(DirectingKey.state, default: DirectingState(), kind: "directing.updated", summary: summary, change)
    }
    public func setEditorStatus(phase: String, detail: String?, progress: Double?, agent: String?) throws {
        let status = EditorStatus(phase: phase, detail: detail, progress: progress, agent: agent, updatedAt: Date().timeIntervalSince1970)
        try database.write { db in try Self.setValue(db, DirectingKey.status, status); try Self.event(db, kind: "editor.status", revision: try currentRevision(db), summary: phase) }
    }
    public func lockPicture(cutID: String?, locked: Bool) throws {
        if locked {
            let open = try notes().filter { $0.visibleToEditor && ![.accepted, .dropped].contains($0.lifecycle) && !$0.inInbox }
            guard open.isEmpty else { throw DirectionError("notes_open", "Accept or drop every open note before locking picture.") }
        }
        _ = try updateDirectingState(summary: locked ? "Locked picture" : "Unlocked picture") { s in
            s.pictureLocked = locked; s.pictureLockedAt = locked ? Date().timeIntervalSince1970 : nil; s.pictureLockedCutID = locked ? cutID : nil
            if locked && s.finishing == nil { s.finishing = FinishingItem.defaults }
        }
    }
    public func updateFinishing(_ items: [FinishingItem]) throws -> DirectingState {
        try updateDirectingState(summary: "Updated finishing") { s in
            var current = s.finishing ?? FinishingItem.defaults
            for item in items { if let i = current.firstIndex(where: { $0.id == item.id }) { current[i] = item } else { current.append(item) } }
            s.finishing = current
        }
    }

    // MARK: Notes

    public func notes() throws -> [ReviewComment] {
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM comments ORDER BY cursor").map { try JSONDecoder().decode(ReviewComment.self, from: $0) } }
    }
    static func nextNoteNumber(_ db: Database) throws -> Int {
        let all = try Data.fetchAll(db, sql: "SELECT payload FROM comments").compactMap { try? JSONDecoder().decode(ReviewComment.self, from: $0) }
        return (all.compactMap(\.number).max() ?? 0) + 1
    }

    @discardableResult
    func modifyNote(_ id: String, kind: String = "feedback.updated", summary: String = "Updated a note", _ change: (inout ReviewComment, Database) throws -> Void) throws -> ReviewComment {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM comments WHERE id = ?", arguments: [id]) else { throw DirectionError("feedback_not_found", "Note not found.") }
            var c = try JSONDecoder().decode(ReviewComment.self, from: data)
            try change(&c, db)
            c.updatedAt = Date().timeIntervalSince1970
            try Self.event(db, kind: kind, revision: c.editRevision, summary: summary)
            c.cursor = db.lastInsertedRowID
            try db.execute(sql: "UPDATE comments SET payload = ?, cursor = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(c), c.cursor, c.id])
            return c
        }
    }

    /// Notes can be rewritten until they're turned over; after that they can only be replied to.
    public func editNote(id: String, text: String? = nil, kind: NoteKind?? = nil, region: FrameRegion?? = nil) throws -> ReviewComment {
        try modifyNote(id) { c, _ in
            guard [.draft, .written, .reopened].contains(c.lifecycle) || c.inInbox else { throw DirectionError("note_turned_over", "This note was turned over. Reply to it instead.") }
            if let text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, text.count <= 20_000 else { throw DirectionError("invalid_comment", "A note needs words.") }
                c.text = text
                if c.noteState == .draft { c.noteState = .written }
            }
            if let kind { c.kind = kind }
            if let region { c.region = region }
        }
    }
    public func dropNote(id: String) throws {
        try modifyNote(id, summary: "Dropped a note") { c, _ in
            guard ![.answered, .accepted].contains(c.lifecycle) else { throw DirectionError("note_answered", "Answered notes can't be dropped.") }
            c.noteState = .dropped
        }
    }
    public func restoreNote(id: String) throws {
        try modifyNote(id, summary: "Restored a note") { c, _ in guard c.noteState == .dropped else { return }; c.noteState = c.text.isEmpty ? .draft : .written }
    }
    public func acceptOutside(id: String, text: String? = nil) throws {
        try modifyNote(id, summary: "Accepted an outside note") { c, db in
            guard c.isOutside else { throw DirectionError("not_outside", "Only outside notes wait in the inbox.") }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { c.text = text }
            c.outsideState = "accepted"; c.noteState = .written
            if c.number == nil { c.number = try Self.nextNoteNumber(db) }
        }
    }
    public func declineOutside(id: String) throws {
        try modifyNote(id, summary: "Declined an outside note") { c, _ in guard c.isOutside else { throw DirectionError("not_outside", "Only outside notes wait in the inbox.") }; c.outsideState = "declined" }
    }

    // MARK: Answers (director side)

    public func acceptAnswer(noteID: String) throws {
        try modifyNote(noteID, summary: "Accepted an answer") { c, _ in
            guard var answer = c.answers?.last else { throw DirectionError("no_answer", "This note has no answer yet.") }
            if let options = answer.options, !options.isEmpty, answer.pick == nil { answer.pick = answer.preferred ?? options.first?.label }
            answer.state = "accepted"; c.answers![c.answers!.count - 1] = answer
            c.status = "accepted"; c.noteState = .accepted
            c.replies.append(.init(id: newID("reply"), author: "Director", text: "Accepted", revision: answer.revision, createdAt: Date().timeIntervalSince1970))
        }
    }
    public func pickOption(noteID: String, label: String) throws {
        try modifyNote(noteID, summary: "Picked option \(label)") { c, _ in
            guard var answer = c.answers?.last, let options = answer.options, options.contains(where: { $0.label == label }) else { throw DirectionError("no_options", "This answer has no option \(label).") }
            answer.pick = label; c.answers![c.answers!.count - 1] = answer
        }
    }
    /// "Not quite": reopens the note for the next turnover with the director's words.
    public func reopenAnswer(noteID: String, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DirectionError("invalid_reply", "Say what's not right yet.") }
        try modifyNote(noteID, summary: "Reopened a note") { c, _ in
            if var answer = c.answers?.last { answer.state = "reopened"; c.answers![c.answers!.count - 1] = answer }
            c.status = "open"; c.noteState = .reopened; c.turnoverID = nil
            c.replies.append(.init(id: newID("reply"), author: "Director", text: text, revision: c.answers?.last?.revision, createdAt: Date().timeIntervalSince1970))
        }
    }

    // MARK: Turnovers

    public func turnovers() throws -> [Turnover] {
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM turnovers ORDER BY created_at").map { try JSONDecoder().decode(Turnover.self, from: $0) } }
    }
    public func turnover(_ id: String) throws -> Turnover {
        guard let t = try turnovers().first(where: { $0.id == id }) else { throw DirectionError("turnover_not_found", "Turnover not found.") }
        return t
    }
    static func saveTurnover(_ db: Database, _ t: Turnover, summary: String, revision: Int) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO turnovers (id, payload, created_at) VALUES (?, ?, ?)", arguments: [t.id, try JSONEncoder.direction.encode(t), t.createdAt])
        try event(db, kind: "turnover.updated", revision: revision, summary: summary)
    }
    @discardableResult
    public func modifyTurnover(_ id: String, summary: String, _ change: (inout Turnover) throws -> Void) throws -> Turnover {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM turnovers WHERE id = ?", arguments: [id]) else { throw DirectionError("turnover_not_found", "Turnover not found.") }
            var t = try JSONDecoder().decode(Turnover.self, from: data)
            try change(&t)
            t.updatedAt = Date().timeIntervalSince1970
            try Self.saveTurnover(db, t, summary: summary, revision: try currentRevision(db))
            return t
        }
    }

    /// Hands the written notes to the editor at once, the way a director hands over a notes sheet.
    public func turnOver(noteIDs: [String], kind: String = "notes", latitude: Latitude, waitForOK: Bool, cutID: String?, sequenceID: String?) throws -> Turnover {
        try database.write { db in
            let existing = try Data.fetchAll(db, sql: "SELECT payload FROM turnovers").map { try JSONDecoder().decode(Turnover.self, from: $0) }
            guard !existing.contains(where: { $0.state.isOpen }) else { throw DirectionError("turnover_open", "The editor is still working on the last turnover.") }
            if kind == "notes" { guard !noteIDs.isEmpty else { throw DirectionError("no_notes", "Write at least one note to turn over.") } }
            let now = Date().timeIntervalSince1970
            let t = Turnover(id: newID("turnover"), number: existing.count + 1, kind: kind, noteIDs: noteIDs, baseRevision: try currentRevision(db), baseCutID: cutID, sequenceID: sequenceID, latitude: latitude, waitForOK: waitForOK, state: .waiting, progress: Dictionary(uniqueKeysWithValues: noteIDs.map { ($0, .queued) }), createdAt: now, updatedAt: now)
            for id in noteIDs {
                guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM comments WHERE id = ?", arguments: [id]) else { throw DirectionError("feedback_not_found", "Note \(id) not found.") }
                var c = try JSONDecoder().decode(ReviewComment.self, from: data)
                guard c.visibleToEditor, [.written, .reopened].contains(c.lifecycle) else { throw DirectionError("note_not_ready", "Note \(c.number.map(String.init) ?? id) isn't ready to turn over.") }
                c.noteState = .turnedOver; c.turnoverID = t.id; c.updatedAt = now
                try Self.event(db, kind: "feedback.updated", revision: c.editRevision, summary: "Turned over a note")
                c.cursor = db.lastInsertedRowID
                try db.execute(sql: "UPDATE comments SET payload = ?, cursor = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(c), c.cursor, c.id])
            }
            try Self.saveTurnover(db, t, summary: kind == "assembly" ? "Asked for the assembly" : "Turned over \(noteIDs.count) notes", revision: t.baseRevision)
            return t
        }
    }
    public func approveReadBack(turnoverID: String) throws -> Turnover {
        try modifyTurnover(turnoverID, summary: "Approved the read-back") { t in
            guard t.state == .readBack else { throw DirectionError("no_readback", "There's no read-back waiting.") }
            t.readBackApproved = true; t.state = .cutting
        }
    }
    public func adjustReadBack(turnoverID: String, noteID: String, text: String) throws -> Turnover {
        try modifyTurnover(turnoverID, summary: "Corrected a read-back line") { t in
            guard t.noteIDs.contains(noteID) else { throw DirectionError("feedback_not_found", "That note isn't in this turnover.") }
            t.adjustments[noteID] = text; t.readBackApproved = false
        }
    }
    public func flipConflict(turnoverID: String, noteID: String) throws -> Turnover {
        try modifyTurnover(turnoverID, summary: "Flipped a conflict") { t in
            if let i = t.flipped.firstIndex(of: noteID) { t.flipped.remove(at: i) } else { t.flipped.append(noteID) }
        }
    }
    public func cancelTurnover(_ id: String) throws {
        let t = try modifyTurnover(id, summary: "Took the notes back") { t in
            guard [.waiting, .readBack].contains(t.state) else { throw DirectionError("turnover_started", "The editor already started cutting.") }
            t.state = .cancelled
        }
        for noteID in t.noteIDs { try modifyNote(noteID) { c, _ in if c.noteState == .turnedOver { c.noteState = .written; c.turnoverID = nil } } }
    }

    /// The editor reports where it is. Cutting can't start before an OK when the director asked to wait.
    public func reportTurnover(id: String, state: TurnoverState?, readBack: [ReadBackLine]?, progress: [String: NoteProgress]?, phase: String?, percent: Double?, message: String?) throws -> Turnover {
        try modifyTurnover(id, summary: phase ?? "The editor updated the turnover") { t in
            guard t.state.isOpen else { throw DirectionError("turnover_closed", "This turnover is closed.") }
            if let readBack {
                for line in readBack where !t.noteIDs.contains(line.noteID) { throw DirectionError("feedback_not_found", "Read-back line refers to a note outside this turnover.") }
                t.readBack = readBack; t.adjustments = [:]
                t.readBackApproved = !t.waitForOK
                t.state = t.waitForOK ? .readBack : .cutting
            }
            if let state {
                if state == .cutting && t.waitForOK && !t.readBackApproved && t.kind == "notes" { throw DirectionError("readback_not_approved", "The director asked to OK the read-back before cutting.") }
                guard state != .delivered else { throw DirectionError("invalid_state", "Use direction_turnover_complete to deliver a cut.") }
                t.state = state
            }
            if let progress { for (k, v) in progress where t.noteIDs.contains(k) { t.progress[k] = v } }
            if let phase { t.phase = phase }
            if let percent { t.percent = max(0, min(1, percent)) }
            if let message { t.message = message }
        }
    }

    /// Delivers the new cut: names it, records an answer on each note and closes the turnover.
    public func completeTurnover(id: String, revision: Int?, sequenceID: String?, answers: [AnswerInput]) throws -> (Turnover, ReviewCut) {
        let t = try turnover(id)
        guard t.state.isOpen else { throw DirectionError("turnover_closed", "This turnover is closed.") }
        let priorCuts = try cuts().count
        let name = t.kind == "assembly" || priorCuts == 0 ? "Assembly" : "Cut \(priorCuts + 1)"
        let cut = try createCut(name: name, sequenceID: sequenceID ?? t.sequenceID, revision: revision)
        for a in answers {
            let range = a.start.flatMap { s in a.end.map { MediaRange(start: s, end: $0) } }
            var answer = NoteAnswer(cutID: cut.id, revision: cut.editRevision, summary: a.summary, delta: a.delta, range: range, options: a.options, preferred: a.preferred)
            if let noteID = a.noteID {
                guard t.noteIDs.contains(noteID) else { throw DirectionError("feedback_not_found", "Answer refers to a note outside this turnover.") }
                try modifyNote(noteID, summary: "Answered a note") { c, _ in
                    c.answers = (c.answers ?? []) + [answer]; c.status = "addressed"; c.noteState = .answered
                    c.replies.append(.init(id: newID("reply"), author: "Editor", text: a.summary, revision: cut.editRevision, createdAt: Date().timeIntervalSince1970))
                }
            } else if a.unasked == true {
                answer.state = "unreviewed"
                _ = try addComment(text: a.summary, author: "Editor", sequenceID: cut.sequenceID, revision: cut.editRevision, cutID: cut.id, range: range, extra: NoteFields(kind: a.kind, noteState: .answered, authorRole: "editor"), answers: [answer])
            }
        }
        let closed = try modifyTurnover(id, summary: "\(name) is ready") { t in
            t.state = .delivered; t.resultCutID = cut.id; t.percent = 1
            for k in t.noteIDs where t.progress[k] != .cant { t.progress[k] = .done }
        }
        return (closed, cut)
    }

    // MARK: Questions

    public func questions() throws -> [EditorQuestion] {
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM questions ORDER BY created_at").map { try JSONDecoder().decode(EditorQuestion.self, from: $0) } }
    }
    public func ask(_ q: EditorQuestion) throws -> EditorQuestion {
        guard !q.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, q.text.count <= 4_000 else { throw DirectionError("invalid_question", "A question needs words.") }
        guard (q.kind == "question" && (2...4).contains(q.choices.count)) || (q.kind == "cant" && q.choices.count <= 4) else { throw DirectionError("invalid_question", "Questions carry 2–4 concrete choices; can't-do reports up to 4.") }
        var question = q; question.answer = nil; question.createdAt = Date().timeIntervalSince1970
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO questions (id, payload, created_at) VALUES (?, ?, ?)", arguments: [question.id, try JSONEncoder.direction.encode(question), question.createdAt])
            try Self.event(db, kind: "question.created", revision: try currentRevision(db), summary: q.kind == "cant" ? "The editor can't do a note" : "The editor has a question")
        }
        return question
    }
    public func answerQuestion(id: String, choiceID: String?, text: String?) throws -> EditorQuestion {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM questions WHERE id = ?", arguments: [id]) else { throw DirectionError("question_not_found", "Question not found.") }
            var q = try JSONDecoder().decode(EditorQuestion.self, from: data)
            if let choiceID { guard q.choices.contains(where: { $0.id == choiceID }) else { throw DirectionError("invalid_choice", "Pick one of the editor's choices.") } }
            let words = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard choiceID != nil || !(words ?? "").isEmpty else { throw DirectionError("invalid_answer", "Pick a choice or say what you want.") }
            q.answer = QuestionAnswer(choiceID: choiceID, text: words?.isEmpty == false ? words : nil, at: Date().timeIntervalSince1970)
            try db.execute(sql: "UPDATE questions SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(q), q.id])
            try Self.event(db, kind: "question.answered", revision: try currentRevision(db), summary: "You answered the editor")
            return q
        }
    }
}

/// Locked material is untouchable: the editor can't change a locked scene, and nothing can move a frame after picture lock.
enum LockRules {
    static func check(before: Project, after: Project, dailies: Dailies, state: DirectingState) throws {
        let lockedAssets = dailies.lockedAssetIDs
        guard state.pictureLocked || !lockedAssets.isEmpty else { return }
        for old in before.sequences {
            guard let new = after.sequences.first(where: { $0.id == old.id }) else {
                if state.pictureLocked { throw DirectionError("picture_locked", "Picture is locked. Unlock it from the Film menu to change the edit.") }
                continue
            }
            let newClips = Dictionary(new.clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            if state.pictureLocked {
                let timing = { (c: Clip) in "\(c.assetID ?? "")|\(c.start.seconds)|\(c.sourceRange.start.seconds)|\(c.sourceRange.duration.seconds)|\(c.speed)|\(c.layer)" }
                guard old.clips.count == new.clips.count, old.clips.allSatisfy({ c in newClips[c.id].map { timing($0) == timing(c) } ?? false }) else {
                    throw DirectionError("picture_locked", "Picture is locked. Finishing can change color and sound, not timing.")
                }
            }
            for c in old.clips where c.assetID.map(lockedAssets.contains) ?? false {
                guard let n = newClips[c.id], n.sourceRange == c.sourceRange, n.speed == c.speed, n.grade == c.grade, n.framing == c.framing, n.audioOverrides == c.audioOverrides, n.layer == c.layer else {
                    let scene = dailies.scene(for: c.assetID)
                    throw DirectionError("scene_locked", "\(scene?.label ?? "That scene") is locked. The director has to unlock it first.")
                }
            }
        }
    }
}
