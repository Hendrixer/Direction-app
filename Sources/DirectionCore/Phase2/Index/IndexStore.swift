import Foundation
import GRDB

// Shots, sounds, contact sheets and search (specs/footage-index.md).
// Everything here is Direction's own work on the editor's behalf: rebuilt from the footage at
// any time, never part of an edit revision. Writes post `index.updated` so open windows refresh.
extension ProjectStore {
    static func ensureIndexTables(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS index_takes (asset_id TEXT PRIMARY KEY, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS index_shots (id TEXT PRIMARY KEY, asset_id TEXT NOT NULL, number INTEGER NOT NULL, payload BLOB NOT NULL, print BLOB);
        CREATE INDEX IF NOT EXISTS index_shots_by_asset ON index_shots(asset_id, number);
        CREATE TABLE IF NOT EXISTS index_sounds (asset_id TEXT NOT NULL, start DOUBLE NOT NULL, payload BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS index_sounds_by_asset ON index_sounds(asset_id, start);
        CREATE TABLE IF NOT EXISTS index_vectors (shot_id TEXT NOT NULL, asset_id TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, start DOUBLE NOT NULL, vector BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS index_vectors_by_asset ON index_vectors(asset_id);
        CREATE VIRTUAL TABLE IF NOT EXISTS index_fts USING fts5(text, shot_id UNINDEXED, asset_id UNINDEXED, kind UNINDEXED, start UNINDEXED, tokenize = 'porter unicode61');
        CREATE TABLE IF NOT EXISTS index_meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS index_screen (asset_id TEXT NOT NULL, start DOUBLE NOT NULL, payload BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS index_screen_by_asset ON index_screen(asset_id, start);
        CREATE TABLE IF NOT EXISTS index_watched (id INTEGER PRIMARY KEY AUTOINCREMENT, revision INTEGER NOT NULL, start DOUBLE NOT NULL, end DOUBLE NOT NULL, created_at DOUBLE NOT NULL);
        """)
    }

    /// The film package's own `Index/` folder: contact sheets and keyframes live with the film.
    public var indexFolder: URL { url.appendingPathComponent("Index", isDirectory: true) }

    /// Bumped whenever shots or search rows change, so a search cache knows when to reload.
    private func bumpGeneration(_ db: Database) throws {
        try db.execute(sql: "INSERT INTO index_meta (key, value) VALUES ('generation', 1) ON CONFLICT(key) DO UPDATE SET value = value + 1")
    }
    private func indexEvent(_ db: Database, _ summary: String) throws {
        try Self.event(db, kind: "index.updated", revision: try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0, summary: summary)
    }

    // MARK: Takes

    public func indexTakes() throws -> [String: TakeIndex] {
        try database.read { db in
            var out: [String: TakeIndex] = [:]
            for data in try Data.fetchAll(db, sql: "SELECT payload FROM index_takes") { let t = try JSONDecoder().decode(TakeIndex.self, from: data); out[t.assetID] = t }
            return out
        }
    }
    public func takeIndex(_ assetID: String) throws -> TakeIndex? {
        try database.read { db in try Data.fetchOne(db, sql: "SELECT payload FROM index_takes WHERE asset_id = ?", arguments: [assetID]).map { try JSONDecoder().decode(TakeIndex.self, from: $0) } }
    }
    public func saveTakeIndex(_ take: TakeIndex, summary: String? = nil) throws {
        var t = take; t.updatedAt = Date().timeIntervalSince1970
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO index_takes (asset_id, payload) VALUES (?, ?)", arguments: [t.assetID, try JSONEncoder.direction.encode(t)])
            try indexEvent(db, summary ?? "Looked at a take")
        }
    }
    /// Forgets a take's index so it's looked at again from the start.
    public func clearIndex(assetID: String) throws {
        try database.write { db in
            for table in ["index_takes", "index_shots", "index_sounds", "index_screen", "index_vectors", "index_fts"] {
                // Table names are compile-time constants, never from a tool.
                try db.execute(sql: "DELETE FROM \(table) WHERE asset_id = ?", arguments: [assetID])
            }
            try bumpGeneration(db)
            try indexEvent(db, "Cleared a take's index")
        }
    }

    // MARK: Shots

    /// Replaces a take's shots, their feature prints and search rows in one write.
    public func replaceShots(assetID: String, _ shots: [Shot], prints: [String: [Float]] = [:]) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM index_shots WHERE asset_id = ?", arguments: [assetID])
            try db.execute(sql: "DELETE FROM index_screen WHERE asset_id = ?", arguments: [assetID])
            try db.execute(sql: "DELETE FROM index_vectors WHERE asset_id = ?", arguments: [assetID])
            try db.execute(sql: "DELETE FROM index_fts WHERE asset_id = ?", arguments: [assetID])
            for s in shots {
                try db.execute(sql: "INSERT INTO index_shots (id, asset_id, number, payload, print) VALUES (?, ?, ?, ?, ?)", arguments: [s.id, assetID, s.number, try JSONEncoder.direction.encode(s), prints[s.id].map(Self.vectorData)])
            }
            try bumpGeneration(db)
            try indexEvent(db, "Found \(shots.count) shots")
        }
    }
    public func updateShot(_ shot: Shot) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE index_shots SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(shot), shot.id])
            try indexEvent(db, "Described a shot")
        }
    }
    public func shots(assetID: String? = nil) throws -> [Shot] {
        try database.read { db in
            let rows = assetID == nil ? try Data.fetchAll(db, sql: "SELECT payload FROM index_shots ORDER BY asset_id, number")
                : try Data.fetchAll(db, sql: "SELECT payload FROM index_shots WHERE asset_id = ? ORDER BY number", arguments: [assetID])
            return try rows.map { try JSONDecoder().decode(Shot.self, from: $0) }
        }
    }
    public func shot(_ id: String) throws -> Shot {
        guard let s = try database.read({ db in try Data.fetchOne(db, sql: "SELECT payload FROM index_shots WHERE id = ?", arguments: [id]) }) else { throw DirectionError("shot_not_found", "Shot \(id) not found.") }
        return try JSONDecoder().decode(Shot.self, from: s)
    }
    /// Vision feature prints, one per shot (its middle keyframe), for "more like this shot".
    public func featurePrints() throws -> [String: [Float]] {
        try database.read { db in
            var out: [String: [Float]] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, print FROM index_shots WHERE print IS NOT NULL") { let d: Data = row["print"]; out[row["id"]] = Self.vector(d) }
            return out
        }
    }

    // MARK: Sounds

    public func replaceSounds(assetID: String, _ sounds: [IndexSound]) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM index_sounds WHERE asset_id = ?", arguments: [assetID])
            for s in sounds { try db.execute(sql: "INSERT INTO index_sounds (asset_id, start, payload) VALUES (?, ?, ?)", arguments: [assetID, s.start, try JSONEncoder.direction.encode(s)]) }
            try indexEvent(db, "Listened to a take")
        }
    }
    public func sounds(assetID: String? = nil) throws -> [IndexSound] {
        try database.read { db in
            let rows = assetID == nil ? try Data.fetchAll(db, sql: "SELECT payload FROM index_sounds ORDER BY asset_id, start")
                : try Data.fetchAll(db, sql: "SELECT payload FROM index_sounds WHERE asset_id = ? ORDER BY start", arguments: [assetID])
            return try rows.map { try JSONDecoder().decode(IndexSound.self, from: $0) }
        }
    }

    // MARK: Text on screen

    public func replaceScreenText(assetID: String, _ stretches: [ScreenText]) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM index_screen WHERE asset_id = ?", arguments: [assetID])
            for s in stretches { try db.execute(sql: "INSERT INTO index_screen (asset_id, start, payload) VALUES (?, ?, ?)", arguments: [assetID, s.start, try JSONEncoder.direction.encode(s)]) }
            try indexEvent(db, "Read the text on screen")
        }
    }
    /// A take's stretches of text on screen (or every take's), in time order.
    public func screenText(assetID: String? = nil) throws -> [ScreenText] {
        try database.read { db in
            let rows = assetID == nil ? try Data.fetchAll(db, sql: "SELECT payload FROM index_screen ORDER BY asset_id, start")
                : try Data.fetchAll(db, sql: "SELECT payload FROM index_screen WHERE asset_id = ? ORDER BY start", arguments: [assetID])
            return try rows.map { try JSONDecoder().decode(ScreenText.self, from: $0) }
        }
    }

    // MARK: Search rows

    /// Replaces a take's search rows: words go into FTS5, rows with a vector into index_vectors.
    public func replaceSearchRows(assetID: String, _ rows: [IndexSearchRow]) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM index_vectors WHERE asset_id = ?", arguments: [assetID])
            try db.execute(sql: "DELETE FROM index_fts WHERE asset_id = ?", arguments: [assetID])
            for r in rows {
                try db.execute(sql: "INSERT INTO index_fts (text, shot_id, asset_id, kind, start) VALUES (?, ?, ?, ?, ?)", arguments: [r.text, r.shotID, assetID, r.kind.rawValue, r.start])
                if let v = r.vector { try db.execute(sql: "INSERT INTO index_vectors (shot_id, asset_id, kind, text, start, vector) VALUES (?, ?, ?, ?, ?, ?)", arguments: [r.shotID, assetID, r.kind.rawValue, r.text, r.start, Self.vectorData(v)]) }
            }
            try bumpGeneration(db)
            try indexEvent(db, "Made a take searchable")
        }
    }
    /// Every row with a vector, for ranking by meaning.
    public func searchVectors() throws -> [IndexSearchRow] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT shot_id, asset_id, kind, text, start, vector FROM index_vectors").map { row in
                let d: Data = row["vector"]
                return IndexSearchRow(shotID: row["shot_id"], assetID: row["asset_id"], kind: IndexSearchRow.Kind(rawValue: row["kind"]) ?? .picture, text: row["text"], start: row["start"], vector: Self.vector(d))
            }
        }
    }
    /// Rows containing one word (porter-stemmed, so "laughing" finds "laughs"), with their bm25 rank.
    public func searchWord(_ token: String, kind: IndexSearchRow.Kind? = nil) throws -> [(row: IndexSearchRow, rank: Double)] {
        let cleaned = token.filter { $0.isLetter || $0.isNumber || $0 == "'" }.replacingOccurrences(of: "'", with: "")
        guard !cleaned.isEmpty else { return [] }
        return try database.read { db in
            try Row.fetchAll(db, sql: "SELECT text, shot_id, asset_id, kind, start, bm25(index_fts) AS rank FROM index_fts WHERE index_fts MATCH ? LIMIT 5000", arguments: ["text:\"\(cleaned)\""]).compactMap { row in
                let k = IndexSearchRow.Kind(rawValue: row["kind"]) ?? .picture
                if let kind, k != kind { return nil }
                let start: Double = row["start"] ?? 0
                return (IndexSearchRow(shotID: row["shot_id"], assetID: row["asset_id"], kind: k, text: row["text"], start: start, vector: nil), row["rank"] ?? 0)
            }
        }
    }
    /// Changes whenever any take's shots or search rows change.
    public func searchGeneration() throws -> Int64 {
        try database.read { db in try Int64.fetchOne(db, sql: "SELECT value FROM index_meta WHERE key = 'generation'") ?? 0 }
    }

    // MARK: Watching

    /// The editor watched a passage of the cut; the turnover's delivery check reads these.
    public func recordWatched(revision: Int, start: Double, end: Double) throws {
        try database.write { db in
            try db.execute(sql: "INSERT INTO index_watched (revision, start, end, created_at) VALUES (?, ?, ?, ?)", arguments: [revision, start, end, Date().timeIntervalSince1970])
        }
    }
    public func watchedRanges(since: Double = 0) throws -> [WatchedRange] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT revision, start, end, created_at FROM index_watched WHERE created_at >= ? ORDER BY id", arguments: [since]).map { WatchedRange(revision: $0["revision"], start: $0["start"], end: $0["end"], at: $0["created_at"]) }
        }
    }

    /// Dollars spent describing shots through OpenRouter, for Settings › Services' spending meter.
    public func lookingSpend() throws -> Double { try indexTakes().values.reduce(0) { $0 + ($1.spend ?? 0) } }

    // MARK: Vectors as blobs

    static func vectorData(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }
    static func vector(_ d: Data) -> [Float] {
        d.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }
}
