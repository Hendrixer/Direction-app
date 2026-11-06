import Foundation
import GRDB
import Darwin

/// Every writer, including another process, enters the same SQLite immediate transaction.
public final class ProjectStore: Sendable {
    public let url: URL
    let database: DatabaseQueue

    public static func create(at url: URL, name: String) throws -> ProjectStore {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw DirectionError("project_exists", "A file or project already exists at \(url.path).") }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do {
            let store = try ProjectStore(url: url, creating: true)
            let p = Project(name: name)
            try store.database.write { db in
                let data = try JSONEncoder.direction.encode(p)
                try db.execute(sql: "INSERT INTO state (id, payload, revision) VALUES (1, ?, 0)", arguments: [data])
                try db.execute(sql: "INSERT INTO revisions (revision, payload, summary, created_at) VALUES (0, ?, ?, ?)", arguments: [data, "Created project", Date().timeIntervalSince1970])
                try Self.event(db, kind: "project.created", revision: 0, summary: "Created \(name)")
            }
            let manifest = JSONValue.object(["format": .string("direction"), "schemaVersion": .number(1), "projectID": .string(p.id)])
            try manifest.data(pretty: true).write(to: url.appendingPathComponent("manifest.json"), options: .atomic)
            return store
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    public convenience init(url: URL) throws { try self.init(url: url, creating: false) }
    private init(url: URL, creating: Bool) throws {
        self.url = url.standardizedFileURL
        let path = url.appendingPathComponent("project.sqlite").path
        if !creating {
            guard FileManager.default.fileExists(atPath: path) else { throw DirectionError("project_not_found", "No Direction project at \(url.path).") }
            let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url.appendingPathComponent("manifest.json")))
            guard manifest["format"].string == "direction", manifest["schemaVersion"].int == 1 else { throw DirectionError("unsupported_project", "Unsupported Direction project format.") }
        }
        var config = Configuration()
        config.busyMode = .timeout(10)
        database = try DatabaseQueue(path: path, configuration: config)
        if creating {
            try database.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = FULL")
            }
            try database.write { db in
                try db.execute(sql: """
                CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL, revision INTEGER NOT NULL);
                CREATE TABLE revisions (revision INTEGER PRIMARY KEY, payload BLOB NOT NULL, summary TEXT NOT NULL, created_at DOUBLE NOT NULL);
                CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, revision INTEGER NOT NULL, summary TEXT NOT NULL, created_at DOUBLE NOT NULL);
                CREATE TABLE idempotency (key TEXT PRIMARY KEY, request BLOB NOT NULL, revision INTEGER NOT NULL);
                CREATE TABLE comments (id TEXT PRIMARY KEY, payload BLOB NOT NULL, cursor INTEGER NOT NULL);
                CREATE TABLE cuts (id TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE TABLE transcripts (id TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE TABLE jobs (id TEXT PRIMARY KEY, payload BLOB NOT NULL);
                PRAGMA user_version = 1;
                """)
            }
        }
        try database.write { db in try Self.ensureDirectingTables(db); try Self.ensurePhase2Tables(db) }
    }

    public func read(revision: Int? = nil) throws -> Project {
        try database.read { db in
            let data = try revision.map { try Data.fetchOne(db, sql: "SELECT payload FROM revisions WHERE revision = ?", arguments: [$0]) } ?? Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1")
            guard let data else { throw DirectionError("revision_not_found", "Project revision not found.") }
            var p = try JSONDecoder().decode(Project.self, from: data)
            // Relinked footage plays from where it is now in every revision (Relink.swift), and graphics
            // play their current render (Phase2/Graphics/GraphicsStore.swift).
            if revision != nil { p = try Self.withCurrentLocations(db, p) }
            return try Self.withCurrentGraphics(db, p)
        }
    }

    public func revision() throws -> Int { try database.read { try Int.fetchOne($0, sql: "SELECT revision FROM state WHERE id = 1") ?? 0 } }
    public func eventCursor() throws -> Int64 { try database.read { try Int64.fetchOne($0, sql: "SELECT COALESCE(MAX(id),0) FROM events") ?? 0 } }

    @discardableResult
    public func update(expectedRevision: Int, key: String, request: Data, summary: String, transform: @Sendable (inout Project) throws -> Void) throws -> Project {
        try database.write { db in try Self.commit(db, expectedRevision: expectedRevision, key: key, request: request, summary: summary, transform: transform) }
    }

    /// `update` inside a transaction the caller already holds.
    static func commit(_ db: Database, expectedRevision: Int, key: String, request: Data, summary: String, transform: @Sendable (inout Project) throws -> Void) throws -> Project {
        guard !key.isEmpty && key.count <= 256 else { throw DirectionError("invalid_idempotency_key", "Provide an idempotency key of 1–256 characters.") }
        if let row = try Row.fetchOne(db, sql: "SELECT request, revision FROM idempotency WHERE key = ?", arguments: [key]) {
            let prior: Data = row["request"], revision: Int = row["revision"]
            guard prior == request else { throw DirectionError("idempotency_conflict", "This idempotency key was used with a different request.") }
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM revisions WHERE revision = ?", arguments: [revision]) else { throw DirectionError("corrupt_project", "Missing idempotent revision.") }
            return try JSONDecoder().decode(Project.self, from: data)
        }
        guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1") else { throw DirectionError("corrupt_project", "Missing project state.") }
        var p = try JSONDecoder().decode(Project.self, from: data)
        guard p.editRevision == expectedRevision else { throw DirectionError("revision_conflict", "Expected revision \(expectedRevision); current revision is \(p.editRevision). Refresh before applying changes.") }
        let before = p
        try transform(&p)
        try LockRules.check(before: before, after: p, dailies: try Self.value(db, DirectingKey.dailies, as: Dailies.self) ?? Dailies(), state: try Self.value(db, DirectingKey.state, as: DirectingState.self) ?? DirectingState())
        try EditReducer.validate(p)
        p.editRevision += 1
        let output = try JSONEncoder.direction.encode(p)
        try db.execute(sql: "UPDATE state SET payload = ?, revision = ? WHERE id = 1", arguments: [output, p.editRevision])
        try db.execute(sql: "INSERT INTO revisions (revision, payload, summary, created_at) VALUES (?, ?, ?, ?)", arguments: [p.editRevision, output, summary, Date().timeIntervalSince1970])
        try db.execute(sql: "INSERT INTO idempotency (key, request, revision) VALUES (?, ?, ?)", arguments: [key, request, p.editRevision])
        try Self.event(db, kind: "edit.committed", revision: p.editRevision, summary: summary)
        return p
    }

    @discardableResult
    public func apply(_ batch: EditBatch) throws -> Project {
        try update(expectedRevision: batch.baseEditRevision, key: batch.idempotencyKey, request: JSONEncoder.direction.encode(batch), summary: batch.summary) { p in p = try EditReducer.apply(batch, to: p) }
    }

    @discardableResult
    /// The first picture into a film with nothing cut yet sets its cuts' size (at the brief's shape, when it has
    /// one), and their rate unless `frameRate` names one (Settings › Cutting › Frame rate for new films).
    public func addAsset(_ asset: MediaAsset, append: Bool, sequenceID: String? = nil, frameRate: FrameRate? = nil, expectedRevision: Int, key: String = UUID().uuidString) throws -> Project {
        let request = try JSONValue.object(["operation": .string("import"), "path": .string(asset.path), "fileSize": .number(Double(asset.fileSize)), "modifiedAt": .number(asset.modifiedAt), "append": .bool(append), "sequenceID": sequenceID.map(JSONValue.string) ?? .null]).data()
        let shape = (try? brief())?.shape
        return try update(expectedRevision: expectedRevision, key: key, request: request, summary: "Imported \(asset.name)") { p in
            guard !p.assets.contains(where: { $0.path == asset.path }) else { throw DirectionError("already_imported", "This file is already in the project.") }
            if !asset.isImage, let v = asset.video.first, v.width > 0, v.height > 0, !p.assets.contains(where: { !$0.isImage && !$0.video.isEmpty }), p.sequences.allSatisfy({ $0.clips.isEmpty }) {
                let size: (width: Int, height: Int) = shape.map { $0.size(footage: (v.width, v.height)) } ?? (v.width / 2 * 2, v.height / 2 * 2)
                for i in p.sequences.indices { p.sequences[i].width = size.width; p.sequences[i].height = size.height; p.sequences[i].frameRate = frameRate ?? .nearest(v.frameRate) }
            }
            p.assets.append(asset)
            if append {
                var op = EditOperation("insert"); op.assetID = asset.id
                p = try EditReducer.apply(EditBatch(baseEditRevision: p.editRevision, sequenceID: sequenceID, operations: [op]), to: p)
            }
        }
    }

    /// `keepingLocks` is the editor's restore: it can't undo a locked scene or anything under picture lock,
    /// checked as direction_edit checks them (TimelineLocks), so color and sound stay open.
    @discardableResult
    public func restore(revision: Int, expectedRevision: Int, key: String, keepingLocks: Bool = false) throws -> Project {
        let prior = try read(revision: revision)
        return try database.write { db in
            let context = keepingLocks ? try editContext(db) : nil
            return try Self.commit(db, expectedRevision: expectedRevision, key: key, request: Data("restore:\(revision)".utf8), summary: "Restored revision \(revision)") { p in
                let before = p, current = p.editRevision
                p = prior; p.editRevision = current
                if let context { try Self.checkLocks(before: before, after: p, context: context) }
            }
        }
    }

    /// The locks between the cut as it stands and a whole project coming back, sequence by sequence. A
    /// sequence it doesn't have counts as emptied.
    static func checkLocks(before: Project, after: Project, context: EditContext) throws {
        var aligned = after
        aligned.sequences = before.sequences.map { b in after.sequences.first { $0.id == b.id } ?? { var gone = b; gone.clips = []; gone.tracks = nil; return gone }() }
        for si in before.sequences.indices { try TimelineLocks.check(before: before, after: aligned, si: si, context: context) }
        if context.state.pictureLocked && after.sequences.count != before.sequences.count { throw DirectionError("picture_locked", "Picture is locked. Finishing changes color and sound, not timing.") }
    }

    public func createCut(name: String, sequenceID: String?, revision: Int?) throws -> ReviewCut {
        try database.write { db in
            let projectData: Data?
            if let revision { projectData = try Data.fetchOne(db, sql: "SELECT payload FROM revisions WHERE revision = ?", arguments: [revision]) }
            else { projectData = try Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1") }
            guard let projectData else { throw DirectionError("revision_not_found", "Review revision not found.") }
            let p = try JSONDecoder().decode(Project.self, from: projectData)
            let cut = ReviewCut(id: newID("cut"), name: name, editRevision: p.editRevision, sequenceID: try p.sequence(sequenceID).id, createdAt: Date().timeIntervalSince1970)
            try db.execute(sql: "INSERT INTO cuts (id, payload) VALUES (?, ?)", arguments: [cut.id, try JSONEncoder.direction.encode(cut)])
            try Self.event(db, kind: "cut.created", revision: p.editRevision, summary: name)
            return cut
        }
    }

    public func cuts() throws -> [ReviewCut] { try records(ReviewCut.self, table: "cuts").sorted { $0.createdAt > $1.createdAt } }
    public func transcripts() throws -> [SourceTranscript] { try records(SourceTranscript.self, table: "transcripts").sorted { ($0.assetID, $0.audioTrackID) < ($1.assetID, $1.audioTrackID) } }
    public func saveTranscript(_ transcript: SourceTranscript) throws {
        let p = try read(), asset = try p.asset(transcript.assetID)
        guard asset.audio.contains(where: { $0.id == transcript.audioTrackID }) else { throw DirectionError("audio_track_not_found", "Transcript must refer to a real source audio track.") }
        guard transcript.words.count <= 200_000, Set(transcript.words.map(\.id)).count == transcript.words.count, transcript.words.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 1_000 && $0.range.isValid && $0.range.end <= asset.duration }) else { throw DirectionError("invalid_transcript", "Transcript words need unique IDs and valid source times inside the recording.") }
        let sorted = transcript.words.sorted { $0.range.start < $1.range.start }
        for i in sorted.indices.dropFirst() where sorted[i].range.start < sorted[i - 1].range.end { throw DirectionError("invalid_transcript", "Word timestamps must not overlap.") }
        try database.write { db in
            var selected = transcript; selected.selectedAt = Date().timeIntervalSince1970
            try db.execute(sql: "INSERT OR REPLACE INTO transcripts (id, payload) VALUES (?, ?)", arguments: [transcript.assetID + ":" + String(transcript.audioTrackID), try JSONEncoder.direction.encode(selected)])
            try Self.event(db, kind: "transcript.updated", revision: p.editRevision, summary: "Transcribed \(asset.name)")
        }
    }

    /// What a note on `range` or at `time` rests on in the footage, and the words under it (3 s either side of a
    /// moment): made with the note, and again when its stretch moves (editNote).
    func restsOn(_ p: Project, _ s: Sequence, range: MediaRange?, time: MediaTime?) throws -> (anchors: [SourceAnchor], words: [TimelineWord]) {
        let around = range ?? time.map { MediaRange(start: max(.zero, $0 - MediaTime(seconds: 3)), duration: MediaTime(seconds: 6)) }
        let words = TranscriptEditing.words(in: s, transcripts: try transcripts()).filter { w in around.map { w.range.intersection($0) != nil } ?? true }
        return (ReviewAnchoring.anchors(project: p, sequence: s, range: range, time: time), Array(words.prefix(500)))
    }

    public func addComment(text: String, author: String = "Director", sequenceID: String?, revision: Int, cutID: String? = nil, range: MediaRange? = nil, time: MediaTime? = nil, region: FrameRegion? = nil, extra: NoteFields? = nil, answers: [NoteAnswer]? = nil) throws -> ReviewComment {
        let p = try read(revision: revision), s = try p.sequence(sequenceID)
        guard (extra?.noteState == .draft || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && text.count <= 20_000 else { throw DirectionError("invalid_comment", "Feedback must contain 1–20,000 characters.") }
        guard range == nil || time == nil else { throw DirectionError("invalid_comment", "Choose a moment or range, not both.") }
        if let r = range { guard r.isValid && r.end <= s.duration else { throw DirectionError("invalid_range", "Feedback range must be inside the reviewed cut.") } }
        if let t = time { guard t.isValid && t >= .zero && t < s.duration else { throw DirectionError("invalid_time", "Feedback moment must be inside the reviewed cut.") } }
        if let region { guard region.isValid && (time != nil || range != nil) else { throw DirectionError("invalid_region", "Frame regions use normalized top-left coordinates and require a moment or range.") } }
        if let cutID { guard try cuts().contains(where: { $0.id == cutID && $0.editRevision == revision && $0.sequenceID == s.id }) else { throw DirectionError("cut_mismatch", "The comment revision/sequence does not match its review cut.") } }
        let rests = try restsOn(p, s, range: range, time: time)
        var comment = ReviewComment(id: newID("feedback"), cutID: cutID, editRevision: revision, sequenceID: s.id, scope: range != nil ? "range" : time != nil ? "moment" : "cut", range: range, time: time, region: region, text: text, author: author, status: "open", anchors: rests.anchors, transcriptContext: rests.words, replies: [], createdAt: Date().timeIntervalSince1970, cursor: 0)
        if let extra {
            comment.kind = extra.kind; comment.noteState = extra.noteState ?? .written; comment.authorRole = extra.authorRole; comment.person = extra.person
            comment.outsideState = extra.authorRole == "outside" ? (extra.outsideState ?? "inbox") : nil
            comment.scriptAction = extra.scriptAction; comment.sceneID = extra.sceneID
        }
        comment.answers = answers
        let numbered = extra?.assignNumber ?? true, outside = extra?.authorRole == "outside"
        return try database.write { db in
            if numbered && !outside { comment.number = try Self.nextNoteNumber(db) }
            try Self.event(db, kind: "feedback.created", revision: revision, summary: "Feedback from \(author)")
            comment.cursor = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO comments (id, payload, cursor) VALUES (?, ?, ?)", arguments: [comment.id, try JSONEncoder.direction.encode(comment), comment.cursor])
            return comment
        }
    }

    public func comments(since: Int64 = 0) throws -> [ReviewComment] {
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM comments WHERE cursor > ? ORDER BY cursor LIMIT 500", arguments: [since]).map { try JSONDecoder().decode(ReviewComment.self, from: $0) } }
    }
    public func comment(_ id: String) throws -> ReviewComment {
        try database.read { db in guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM comments WHERE id = ?", arguments: [id]) else { throw DirectionError("feedback_not_found", "Feedback not found.") }; return try JSONDecoder().decode(ReviewComment.self, from: data) }
    }

    public func reply(commentID: String, text: String, author: String, revision: Int? = nil, status: String? = nil, asDirector: Bool = false) throws -> ReviewComment {
        guard !text.isEmpty && text.count <= 20_000, status == nil || ["open", "addressed", "accepted"].contains(status!) else { throw DirectionError("invalid_reply", "Invalid feedback reply or status.") }
        if status == "accepted" && !asDirector { throw DirectionError("director_action_required", "Only the director can accept feedback in the review UI.") }
        if let revision { _ = try read(revision: revision) }
        return try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM comments WHERE id = ?", arguments: [commentID]) else { throw DirectionError("feedback_not_found", "Feedback not found.") }
            var c = try JSONDecoder().decode(ReviewComment.self, from: data)
            c.replies.append(.init(id: newID("reply"), author: author, text: text, revision: revision, createdAt: Date().timeIntervalSince1970))
            if let status { c.status = status }
            try Self.event(db, kind: "feedback.updated", revision: c.editRevision, summary: "Updated feedback")
            c.cursor = db.lastInsertedRowID
            try db.execute(sql: "UPDATE comments SET payload = ?, cursor = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(c), c.cursor, c.id])
            return c
        }
    }

    public func events(since: Int64 = 0) throws -> [ProjectEvent] {
        try database.read { db in try Row.fetchAll(db, sql: "SELECT * FROM events WHERE id > ? ORDER BY id LIMIT 500", arguments: [since]).map { row in ProjectEvent(id: row["id"], kind: row["kind"], revision: row["revision"], summary: row["summary"], createdAt: row["created_at"]) } }
    }

    public func saveJob(_ job: JobRecord) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO jobs (id, payload) VALUES (?, ?)", arguments: [job.id, try JSONEncoder.direction.encode(job)])
            try Self.event(db, kind: "job.updated", revision: job.revision, summary: job.phase)
        }
    }
    public func jobs() throws -> [JobRecord] {
        var jobs = try records(JobRecord.self, table: "jobs").sorted { $0.createdAt > $1.createdAt }
        for i in jobs.indices where !jobs[i].isTerminal && jobs[i].ownerPID != getpid() {
            if kill(jobs[i].ownerPID, 0) != 0 && errno == ESRCH {
                jobs[i].status = "interrupted"; jobs[i].phase = "The process running this job exited"; jobs[i].updatedAt = Date().timeIntervalSince1970
                DirectionLog.warning("The \(jobs[i].kind) job \(jobs[i].id)\(jobs[i].assetID.map { " on \($0)" } ?? "") stopped: process \(jobs[i].ownerPID) exited before it finished", "jobs")
                try saveJob(jobs[i])
            }
        }
        return jobs
    }
    public func job(_ id: String) throws -> JobRecord { guard let j = try jobs().first(where: { $0.id == id }) else { throw DirectionError("job_not_found", "Job not found.") }; return j }

    private func records<T: Decodable>(_ type: T.Type, table: String) throws -> [T] {
        // Table names are private compile-time constants, never supplied through a tool.
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM \(table)").map { try JSONDecoder().decode(type, from: $0) } }
    }
    static func event(_ db: Database, kind: String, revision: Int, summary: String) throws { try db.execute(sql: "INSERT INTO events (kind, revision, summary, created_at) VALUES (?, ?, ?, ?)", arguments: [kind, revision, summary, Date().timeIntervalSince1970]) }
}
