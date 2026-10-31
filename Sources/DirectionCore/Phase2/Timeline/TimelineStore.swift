import Foundation
import GRDB

// The editor's edits (agent-timeline.md › Writing). One batch commits as one revision, or nothing does,
// and the revision keeps what each operation did and which note it answered, for Changes and History.
extension ProjectStore {
    static func ensureTimelineTables(_ db: Database) throws {
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS edit_changes (revision INTEGER PRIMARY KEY, payload BLOB NOT NULL)")
    }

    /// Words, locks, latitude and visible notes, read in the edit's own transaction.
    func editContext(_ db: Database) throws -> EditContext {
        let transcripts = try Data.fetchAll(db, sql: "SELECT payload FROM transcripts").compactMap { try? JSONDecoder().decode(SourceTranscript.self, from: $0) }
        let turnovers = try Data.fetchAll(db, sql: "SELECT payload FROM turnovers ORDER BY created_at").compactMap { try? JSONDecoder().decode(Turnover.self, from: $0) }
        let notes = try Data.fetchAll(db, sql: "SELECT payload FROM comments").compactMap { try? JSONDecoder().decode(ReviewComment.self, from: $0) }
        return EditContext(transcripts: transcripts, dailies: try Self.value(db, DirectingKey.dailies, as: Dailies.self) ?? Dailies(), state: try Self.value(db, DirectingKey.state, as: DirectingState.self) ?? DirectingState(), turnoverLatitude: turnovers.last { $0.state.isOpen && $0.kind == "notes" }?.latitude, noteNumbers: Set(notes.filter(\.visibleToEditor).compactMap(\.number)), filmURL: url)
    }

    /// Checks every operation and either returns the predicted result (validateOnly) or commits the batch
    /// as one revision. Errors carry the index of the operation that failed.
    public func edit(_ batch: EditBatch, validateOnly: Bool = false) throws -> EditResult {
        guard !batch.idempotencyKey.isEmpty && batch.idempotencyKey.count <= 256 else { throw DirectionError("bad_argument", "Provide an idempotency key of 1–256 characters.") }
        // Direction's own measurements aren't part of the request, so a retry matches even if they're re-measured.
        var plain = batch; plain.operations = batch.operations.map { var o = $0; o.resolved = nil; return o }
        let request = try JSONEncoder.direction.encode(plain)
        func current(_ db: Database) throws -> Project {
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1") else { throw DirectionError("corrupt_project", "Missing project state.") }
            return try JSONDecoder().decode(Project.self, from: data)
        }
        func checked(_ p: Project, _ db: Database) throws -> (Project, EditResult) {
            guard p.editRevision == batch.baseEditRevision else { throw DirectionError("stale_revision", "This batch is based on revision \(batch.baseEditRevision); the cut is now at \(p.editRevision). Read direction_timeline again and replan.") }
            let (next, result) = try EditReducer.run(batch, on: p, context: try editContext(db))
            do { try EditReducer.validate(next) } catch let e as DirectionError { throw DirectionError(EditReducer.code(e.code), e.message) }
            return (next, result)
        }
        if validateOnly { return try database.read { db in try checked(try current(db), db).1 } }
        return try database.write { db in
            try Self.ensureTimelineTables(db)
            if let row = try Row.fetchOne(db, sql: "SELECT request, revision FROM idempotency WHERE key = ?", arguments: [batch.idempotencyKey]) {
                let prior: Data = row["request"], revision: Int = row["revision"]
                guard prior == request, let data = try Data.fetchOne(db, sql: "SELECT payload FROM edit_changes WHERE revision = ?", arguments: [revision]) else { throw DirectionError("idempotency_conflict", "This idempotency key was used with a different request.") }
                return try JSONDecoder().decode(EditResult.self, from: data)
            }
            let p = try current(db)
            var (next, result) = try checked(p, db)
            next.editRevision = p.editRevision + 1
            let now = Date().timeIntervalSince1970
            result.committed = true; result.editRevision = next.editRevision; result.createdAt = now
            let output = try JSONEncoder.direction.encode(next)
            try db.execute(sql: "UPDATE state SET payload = ?, revision = ? WHERE id = 1", arguments: [output, next.editRevision])
            try db.execute(sql: "INSERT INTO revisions (revision, payload, summary, created_at) VALUES (?, ?, ?, ?)", arguments: [next.editRevision, output, batch.summary, now])
            try db.execute(sql: "INSERT INTO idempotency (key, request, revision) VALUES (?, ?, ?)", arguments: [batch.idempotencyKey, request, next.editRevision])
            try db.execute(sql: "INSERT INTO edit_changes (revision, payload) VALUES (?, ?)", arguments: [next.editRevision, try JSONEncoder.direction.encode(result)])
            try Self.event(db, kind: "edit.committed", revision: next.editRevision, summary: batch.summary)
            return result
        }
    }

    /// The director's own edit, made in the app (layouts.md): carried out on the latest cut as it is, as one
    /// revision that the cut then plays, so Screening shows it at once. It needs no note. Refused while the
    /// editor is making the next cut (the latest cut isn't the cut as it stands).
    public func directorEdit(_ operations: [EditOperation], summary: String, expectedRevision: Int) throws -> EditResult {
        try database.write { db in
            try Self.ensureTimelineTables(db)
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1") else { throw DirectionError("corrupt_project", "Missing project state.") }
            let p = try JSONDecoder().decode(Project.self, from: data)
            guard var cut = try Data.fetchAll(db, sql: "SELECT payload FROM cuts").compactMap({ try? JSONDecoder().decode(ReviewCut.self, from: $0) }).max(by: { $0.createdAt < $1.createdAt }) else {
                throw DirectionError("no_cut", "There\u{2019}s no cut yet.")
            }
            guard p.editRevision == expectedRevision else { throw DirectionError("stale_revision", "The cut changed while that was measured. Try again.") }
            guard cut.editRevision == p.editRevision else { throw DirectionError("editor_working", "The editor is making the next cut. This changes the latest cut once it\u{2019}s handed back.") }
            let batch = EditBatch(baseEditRevision: p.editRevision, sequenceID: cut.sequenceID, idempotencyKey: newID("director"), summary: summary, operations: operations, byDirector: true)
            var (next, result) = try EditReducer.run(batch, on: p, context: try editContext(db))
            do { try EditReducer.validate(next) } catch let e as DirectionError { throw DirectionError(EditReducer.code(e.code), e.message) }
            next.editRevision = p.editRevision + 1
            let now = Date().timeIntervalSince1970
            result.committed = true; result.editRevision = next.editRevision; result.createdAt = now
            try record(db, next, result, summary: summary, now: now)
            cut.editRevision = next.editRevision
            try db.execute(sql: "UPDATE cuts SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(cut), cut.id])
            return result
        }
    }

    /// Undo for the director's edit: while nothing has changed since, the cut goes back to what it was before
    /// it, as a new revision the cut plays.
    public func undoDirectorEdit(revision: Int) throws {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1") else { throw DirectionError("corrupt_project", "Missing project state.") }
            let p = try JSONDecoder().decode(Project.self, from: data)
            guard p.editRevision == revision, let made = try Data.fetchOne(db, sql: "SELECT payload FROM edit_changes WHERE revision = ?", arguments: [revision]),
                  let did = try? JSONDecoder().decode(EditResult.self, from: made), did.byDirector == true,
                  let old = try Data.fetchOne(db, sql: "SELECT payload FROM revisions WHERE revision = ?", arguments: [revision - 1]) else {
                throw DirectionError("cut_moved_on", "The cut has changed since, so that can\u{2019}t be undone by itself.")
            }
            var next = p
            let before = try JSONDecoder().decode(Project.self, from: old)
            guard let i = next.sequences.firstIndex(where: { $0.id == did.sequenceID }), let back = before.sequences.first(where: { $0.id == did.sequenceID }) else { return }
            next.sequences[i] = back
            next.editRevision = p.editRevision + 1
            let now = Date().timeIntervalSince1970, summary = "Undid \(did.summary.prefix(1).lowercased() + did.summary.dropFirst())"
            var result = did
            result.editRevision = next.editRevision; result.baseEditRevision = p.editRevision; result.summary = summary; result.operations = []; result.warnings = []; result.createdAt = now
            result.oldLength = did.newLength; result.newLength = did.oldLength; result.delta = -did.delta
            try record(db, next, result, summary: summary, now: now)
            if var cut = try Data.fetchAll(db, sql: "SELECT payload FROM cuts").compactMap({ try? JSONDecoder().decode(ReviewCut.self, from: $0) }).max(by: { $0.createdAt < $1.createdAt }), cut.editRevision == revision {
                cut.editRevision = next.editRevision
                try db.execute(sql: "UPDATE cuts SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(cut), cut.id])
            }
        }
    }

    private func record(_ db: Database, _ next: Project, _ result: EditResult, summary: String, now: Double) throws {
        let output = try JSONEncoder.direction.encode(next)
        try db.execute(sql: "UPDATE state SET payload = ?, revision = ? WHERE id = 1", arguments: [output, next.editRevision])
        try db.execute(sql: "INSERT INTO revisions (revision, payload, summary, created_at) VALUES (?, ?, ?, ?)", arguments: [next.editRevision, output, summary, now])
        try db.execute(sql: "INSERT INTO edit_changes (revision, payload) VALUES (?, ?)", arguments: [next.editRevision, try JSONEncoder.direction.encode(result)])
        try Self.event(db, kind: "edit.committed", revision: next.editRevision, summary: summary)
    }

    /// What one revision's batch did, operation by operation, with notes. nil for revisions made another way.
    public func editRecord(revision: Int) throws -> EditResult? {
        try database.read { db in
            guard try db.tableExists("edit_changes"), let data = try Data.fetchOne(db, sql: "SELECT payload FROM edit_changes WHERE revision = ?", arguments: [revision]) else { return nil }
            return try JSONDecoder().decode(EditResult.self, from: data)
        }
    }
    /// Every recorded batch after `revision` up to `through`, oldest first: what Changes shows between two cuts.
    public func editRecords(after revision: Int = -1, through last: Int = .max) throws -> [EditResult] {
        try database.read { db in
            guard try db.tableExists("edit_changes") else { return [] }
            return try Data.fetchAll(db, sql: "SELECT payload FROM edit_changes WHERE revision > ? AND revision <= ? ORDER BY revision", arguments: [revision, last]).map { try JSONDecoder().decode(EditResult.self, from: $0) }
        }
    }
}
