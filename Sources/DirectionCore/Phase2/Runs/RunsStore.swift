import Foundation
import GRDB

// The editor's runs and activity (specs/editor.md, product-model.md › Run, Activity).
// Activity is written by whichever process handles the editor's tool call (the MCP server it
// connects to), so a session you run yourself shows up exactly like one Direction started.

/// One job the editor is given. A continuation keeps the job it continues.
public enum EditorJob: String, Codable, Sendable, CaseIterable {
    case logFootage, assemble, turnover, finish
    /// Writing a style the director asked for (styles.md › Making a style).
    case style
    /// Learning a technique from a video the director gave (techniques.md › Learning one).
    case technique
    /// The skill each job follows (plugins/direction/skills/<name>/SKILL.md).
    public var skill: String {
        switch self { case .logFootage: "start-project"; case .assemble: "assemble"; case .turnover: "take-turnover"; case .finish: "finish"; case .style: "make-style"; case .technique: "learn-technique" }
    }
}

public enum EditorRunState: String, Codable, Sendable {
    /// Waiting behind another run, or for your Start when Start work is Ask me first.
    case queued
    case starting, working
    /// The program ended its turn on purpose: a read-back to OK or a question to answer.
    case waitingForYou
    case paused, stopped, failed, done
    /// The program is (or should be) running.
    public var isActive: Bool { self == .starting || self == .working }
    /// Still owns its job: a new run for the same work would duplicate it.
    public var isOpen: Bool { self != .done && self != .stopped }
}

/// Why a run stopped or failed (frame 58's table).
public enum EditorRunReason: String, Codable, Sendable {
    case notInstalled, notSignedIn, offline, programQuit, stoppedWithoutFinishing, spendCap, pausedByQuit, stoppedByYou
}

public struct EditorRun: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var job: EditorJob
    public var state: EditorRunState
    public var reason: EditorRunReason?
    /// The program's last error line (Program quit) or the spend line (Spend cap).
    public var detail: String?
    /// "claudeCode" or "codex".
    public var program: String
    /// `--model`; empty for the program's default.
    public var version: String
    /// The program's own session id, kept so the run can resume with its context.
    public var session: String?
    public var turnoverID: String?
    /// Footage count when a logging run began, so new footage starts a new run.
    public var assetCount: Int?
    public var createdAt: Double
    public var startedAt: Double?
    public var updatedAt: Double
    public var endedAt: Double?
    /// Dollars the program reported across every invocation of this run; nil when it reports none.
    public var spend: Double?
    public var tokens: Int?
    /// The app process that started the program, and the program's own process.
    public var ownerPID: Int32?
    public var pid: Int32?
    public var pausedByQuit = false
    /// Start work is Ask me first: queued until you press Start.
    public var held = false
    public var summary: String?
    public var needsYou: [String] = []
    /// Invocations so far: the first start, then each resume, continue or try again.
    public var invocations = 0
    /// When the last invocation first asked the director something (posted a read-back, asked a question), or
    /// began when it asked nothing new: what the director did since is news to the editor.
    public var askedAt: Double?
    /// The last invocation waited on the director's OK to a read-back.
    public var askedForOK: Bool?
    /// A logging run's batch: the takes it logs (footage-index.md › Logging in batches). Older runs logged everything.
    public var assetIDs: [String]?
    /// A style run: what the director asked for, in their words, and whether to learn from this film's cut.
    public var request: String?
    public var fromFilm: Bool?
    /// A technique job: the folder Direction got the video ready in, and the video itself.
    public var learnFolder: String?
    public var learnVideo: String?
    /// A style learned from videos (styles.md › From a video): the folders each was studied in, inside the
    /// film. Direction removes them, downloads and all, once the style is made.
    public var studies: [String]?
    public init(id: String = newID("run"), job: EditorJob, state: EditorRunState = .queued, program: String, version: String, turnoverID: String? = nil, assetCount: Int? = nil, assetIDs: [String]? = nil, createdAt: Double = Date().timeIntervalSince1970) {
        self.id = id; self.job = job; self.state = state; self.program = program; self.version = version; self.turnoverID = turnoverID; self.assetCount = assetCount; self.assetIDs = assetIDs; self.createdAt = createdAt; self.updatedAt = createdAt
    }
}

/// What the editor is doing, in the director's words: "Watching 01:12:08–01:14:00".
public struct EditorActivity: Codable, Hashable, Sendable, Identifiable {
    public var id: Int64
    public var runID: String?
    public var verb: String
    public var object: String
    /// Shown after the object: "note 3", "−4.2 s · note 1".
    public var detail: String?
    /// The object is a timecode or range, set in SF Mono.
    public var mono: Bool
    /// Seconds in the cut; drives the editor's playhead on the strip.
    public var time: Double?
    public var tool: String
    public var startedAt: Double
    /// The latest call merged into this row.
    public var at: Double
    public var count: Int
    /// The turnover the call was about, when it named one.
    public var turnoverID: String?
    public init(id: Int64, runID: String?, verb: String, object: String, detail: String? = nil, mono: Bool = false, time: Double? = nil, tool: String, startedAt: Double, at: Double, count: Int = 1, turnoverID: String? = nil) {
        self.id = id; self.runID = runID; self.verb = verb; self.object = object; self.detail = detail; self.mono = mono; self.time = time; self.tool = tool; self.startedAt = startedAt; self.at = at; self.count = count; self.turnoverID = turnoverID
    }
}

/// One call's activity before it's stored.
public struct ActivityInput: Hashable, Sendable {
    public var verb: String
    public var object: String
    public var detail: String?
    public var mono = false
    public var time: Double?
    public var tool: String
    public var turnoverID: String?
    public init(verb: String, object: String, detail: String? = nil, mono: Bool = false, time: Double? = nil, tool: String, turnoverID: String? = nil) {
        self.verb = verb; self.object = object; self.detail = detail; self.mono = mono; self.time = time; self.tool = tool; self.turnoverID = turnoverID
    }
}

extension ProjectStore {
    static func ensureRunTables(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS editor_runs (id TEXT PRIMARY KEY, payload BLOB NOT NULL, created_at DOUBLE NOT NULL);
        CREATE TABLE IF NOT EXISTS editor_activity (id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT, payload BLOB NOT NULL, at DOUBLE NOT NULL);
        """)
    }

    private static func revisionNow(_ db: Database) throws -> Int { try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0 }

    // MARK: Activity

    /// Records one call. Consecutive calls with the same verb and object (in the same run) merge
    /// into one row with the latest time. Emits an event so the app refreshes.
    @discardableResult
    public func recordActivity(_ input: ActivityInput, runID: String?, at: Double = Date().timeIntervalSince1970) throws -> EditorActivity {
        try database.write { db in
            var row: EditorActivity
            if let last = try Row.fetchOne(db, sql: "SELECT id, payload FROM editor_activity ORDER BY id DESC LIMIT 1"),
               var prior = try? JSONDecoder().decode(EditorActivity.self, from: last["payload"] as Data),
               prior.runID == runID, prior.verb == input.verb, prior.object == input.object {
                prior.at = at; prior.count += 1
                if let t = input.time { prior.time = t }
                if let d = input.detail { prior.detail = d }
                if let t = input.turnoverID { prior.turnoverID = t }
                row = prior
                try db.execute(sql: "UPDATE editor_activity SET payload = ?, at = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(row), at, row.id])
            } else {
                try db.execute(sql: "INSERT INTO editor_activity (run_id, payload, at) VALUES (?, ?, ?)", arguments: [runID, Data("{}".utf8), at])
                row = EditorActivity(id: db.lastInsertedRowID, runID: runID, verb: input.verb, object: input.object, detail: input.detail, mono: input.mono, time: input.time, tool: input.tool, startedAt: at, at: at, count: 1, turnoverID: input.turnoverID)
                try db.execute(sql: "UPDATE editor_activity SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(row), row.id])
            }
            try Self.event(db, kind: "editor.activity", revision: try Self.revisionNow(db), summary: "\(input.verb) \(input.object)")
            return row
        }
    }

    /// Newest first. With a run, only that run's rows.
    public func activity(runID: String? = nil, limit: Int = 200) throws -> [EditorActivity] {
        try database.read { db in
            let rows = runID == nil
                ? try Data.fetchAll(db, sql: "SELECT payload FROM editor_activity ORDER BY id DESC LIMIT ?", arguments: [limit])
                : try Data.fetchAll(db, sql: "SELECT payload FROM editor_activity WHERE run_id = ? ORDER BY id DESC LIMIT ?", arguments: [runID, limit])
            return rows.compactMap { try? JSONDecoder().decode(EditorActivity.self, from: $0) }
        }
    }

    // MARK: Runs

    public func saveRun(_ run: EditorRun) throws {
        var r = run; r.updatedAt = Date().timeIntervalSince1970
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO editor_runs (id, payload, created_at) VALUES (?, ?, ?)", arguments: [r.id, try JSONEncoder.direction.encode(r), r.createdAt])
            try Self.event(db, kind: "editor.run", revision: try Self.revisionNow(db), summary: "\(r.job.rawValue) \(r.state.rawValue)")
        }
    }

    /// Oldest first.
    public func runs() throws -> [EditorRun] {
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM editor_runs ORDER BY created_at, rowid").compactMap { try? JSONDecoder().decode(EditorRun.self, from: $0) } }
    }
    public func run(_ id: String) throws -> EditorRun? {
        try database.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM editor_runs WHERE id = ?", arguments: [id]).flatMap { try? JSONDecoder().decode(EditorRun.self, from: $0) } }
    }
    /// Reads, changes and saves one run in a single transaction.
    @discardableResult
    public func updateRun(_ id: String, _ change: (inout EditorRun) throws -> Void) throws -> EditorRun {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM editor_runs WHERE id = ?", arguments: [id]) else { throw DirectionError("run_not_found", "That run isn't in this film.") }
            var r = try JSONDecoder().decode(EditorRun.self, from: data)
            try change(&r)
            r.updatedAt = Date().timeIntervalSince1970
            try db.execute(sql: "UPDATE editor_runs SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(r), r.id])
            try Self.event(db, kind: "editor.run", revision: try Self.revisionNow(db), summary: "\(r.job.rawValue) \(r.state.rawValue)")
            return r
        }
    }
}
