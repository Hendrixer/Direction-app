import Foundation
import GRDB

// Made media, services and spend (specs/made-media.md).

/// The take a made clip came from: the range a changed shot, slow motion or sharpening worked on, or the take
/// an extended shot continues (`side`).
public struct MadeFrom: Codable, Hashable, Sendable {
    public var assetID: String
    /// Source seconds in the take.
    public var start: Double
    public var end: Double?
    /// An extended shot's side of the take: "tail" continues from `end`, "head" leads into `start`.
    public var side: String?
    public init(assetID: String, start: Double, end: Double? = nil, side: String? = nil) { self.assetID = assetID; self.start = start; self.end = end; self.side = side }
}

/// A frame a new shot or bridge starts or ends on: a still, or a moment of a take.
public struct MadeFrame: Codable, Hashable, Sendable {
    public var assetID: String
    /// Source seconds; nil for a still.
    public var at: Double?
    public init(assetID: String, at: Double? = nil) { self.assetID = assetID; self.at = at }
}

/// Provenance of one made clip, keyed by the footage asset it became. It stays with the film, so
/// Changes, Dailies and History can always say where a clip came from and what it cost.
public struct MadeRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String { assetID }
    public var assetID: String
    public var kind: MadeKind
    public var service: String
    /// OpenRouter's id ("google/lyria-3-clip") and its display name ("Lyria 3 Clip").
    public var version: String
    public var versionName: String
    /// What the editor asked for, in its words.
    public var asked: String
    public var seconds: Double?
    /// What OpenRouter reported for this clip; the estimate when it didn't say.
    public var spend: Double
    public var estimate: Double
    public var noteID: String?
    public var turnoverID: String?
    public var from: MadeFrom?
    public var first: MadeFrame?
    public var last: MadeFrame?
    public var references: [String]
    /// Slow motion's factor.
    public var factor: Int?
    /// "1280 × 720" when Direction sharpened it to the cut's size on this Mac.
    public var sharpenedFrom: String?
    /// The file inside the film package: "Made/music-….wav".
    public var file: String
    /// 1 or 2 when the editor made it two ways.
    public var way: Int?
    public var jobID: String?
    public var createdAt: Double
    public init(assetID: String, kind: MadeKind, service: String = "openrouter", version: String, versionName: String, asked: String, seconds: Double?, spend: Double, estimate: Double, noteID: String?, turnoverID: String?, from: MadeFrom? = nil, first: MadeFrame? = nil, last: MadeFrame? = nil, references: [String] = [], factor: Int? = nil, sharpenedFrom: String? = nil, file: String, way: Int? = nil, jobID: String? = nil, createdAt: Double = Date().timeIntervalSince1970) {
        self.assetID = assetID; self.kind = kind; self.service = service; self.version = version; self.versionName = versionName; self.asked = asked; self.seconds = seconds; self.spend = spend; self.estimate = estimate
        self.noteID = noteID; self.turnoverID = turnoverID; self.from = from; self.first = first; self.last = last; self.references = references; self.factor = factor; self.sharpenedFrom = sharpenedFrom
        self.file = file; self.way = way; self.jobID = jobID; self.createdAt = createdAt
    }
    /// "OpenRouter", or "This Mac" for slow motion and sharpening made here.
    public var serviceName: String { service == "openrouter" ? "OpenRouter" : service == "local" ? "This Mac" : service.capitalized }
    public var isLocal: Bool { service == "local" }
}

/// The money line on a spend question (frame 62). Direction fills in what's been spent and the limit itself,
/// so the director reads its own numbers, not the editor's.
public struct SpendAsk: Codable, Hashable, Sendable {
    public var estimate: Double
    /// Spent in this turnover before this request.
    public var turnoverSpent: Double
    /// The turnover's limit (Settings › Services › Ask before spending more than).
    public var limit: Double
    /// The choice that says yes to the spend.
    public var choiceID: String
    public var kind: MadeKind?
    public var version: String?
    public init(estimate: Double, turnoverSpent: Double, limit: Double, choiceID: String, kind: MadeKind? = nil, version: String? = nil) {
        self.estimate = estimate; self.turnoverSpent = turnoverSpent; self.limit = limit; self.choiceID = choiceID; self.kind = kind; self.version = version
    }
    /// "This turnover would reach $6.10 of your $5.00 limit."
    public var total: Double { turnoverSpent + estimate }
}

extension EditorQuestion {
    /// The director said yes to this spend question's spend.
    public var agreedToSpend: Bool { kind == "spend" && spend != nil && answer?.choiceID == spend?.choiceID }
}

extension ProjectStore {
    static func ensureMadeTables(_ db: Database) throws {
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS made (asset_id TEXT PRIMARY KEY, payload BLOB NOT NULL, created_at DOUBLE NOT NULL)")
    }

    /// Made files are copied into the film package, never linked.
    public var madeDirectory: URL { url.appendingPathComponent("Made") }

    public func madeRecords() throws -> [MadeRecord] {
        try database.read { db in try Data.fetchAll(db, sql: "SELECT payload FROM made ORDER BY created_at").map { try JSONDecoder().decode(MadeRecord.self, from: $0) } }
    }
    public func madeRecord(_ assetID: String) throws -> MadeRecord? {
        try database.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM made WHERE asset_id = ?", arguments: [assetID]).map { try JSONDecoder().decode(MadeRecord.self, from: $0) } }
    }
    public func saveMade(_ record: MadeRecord) throws {
        _ = try read().asset(record.assetID)
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO made (asset_id, payload, created_at) VALUES (?, ?, ?)", arguments: [record.assetID, try JSONEncoder.direction.encode(record), record.createdAt])
            try Self.event(db, kind: "made.created", revision: try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0, summary: "Made \(record.kind.label.lowercased()) with \(record.versionName)")
        }
    }

    /// A spend question needs its money line and a choice that says yes.
    static func validateSpendQuestion(_ q: EditorQuestion) throws {
        guard let spend = q.spend else { throw DirectionError("invalid_question", "A spend question needs spend: {estimate, choiceID}.") }
        guard spend.estimate.isFinite, spend.estimate > 0 else { throw DirectionError("invalid_question", "A spend question\u{2019}s estimate is a positive amount in dollars.") }
        guard q.choices.contains(where: { $0.id == spend.choiceID }) else { throw DirectionError("invalid_question", "spend.choiceID must name the choice that agrees to spend.") }
    }
}
