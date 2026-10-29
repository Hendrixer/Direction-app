import Foundation
import GRDB

// Graphics and their words (specs/graphics.md, product-model.md › Graphic, GraphicWord).
// A graphic is a folder the editor writes in the film, `Editor/Graphics/<name>/`, rendered by Direction
// to `Renders/Graphics/<name>-<hash>.mov` and registered as an asset so it can be placed like footage.

/// One field the director may change. `text` is what the page declares; the director's own words
/// (`Graphic.directorWords`) win over it.
public struct GraphicWord: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var text: String
    public var maxLength: Int?
    public var id: String { key }
    public init(key: String, label: String, text: String, maxLength: Int? = nil) { self.key = key; self.label = label; self.text = text; self.maxLength = maxLength }
}

/// The cached ProRes 4444 file for one set of files and words.
public struct GraphicRender: Codable, Hashable, Sendable {
    public var path: String
    public var hash: String
    public var duration: MediaTime
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    public var frames: Int
    public var fileSize: Int64
    public var modifiedAt: Double
    public init(path: String, hash: String, duration: MediaTime, width: Int, height: Int, frameRate: FrameRate, frames: Int, fileSize: Int64, modifiedAt: Double) {
        self.path = path; self.hash = hash; self.duration = duration; self.width = width; self.height = height; self.frameRate = frameRate; self.frames = frames; self.fileSize = fileSize; self.modifiedAt = modifiedAt
    }
}

public struct Graphic: Codable, Hashable, Sendable, Identifiable {
    /// The folder's name under `Editor/Graphics/`; also the graphic's id.
    public var name: String
    public var folder: String
    public var duration: Double
    public var words: [GraphicWord]
    /// Words the director typed, by key. The editor can't change these unless a note asks.
    public var directorWords: [String: String]
    public var directorChangedAt: Double?
    public var assetID: String?
    /// The note this graphic answers (nil for an unasked graphic).
    public var noteID: String?
    public var render: GraphicRender?
    public var updatedAt: Double
    public var id: String { name }
    public init(name: String, folder: String, duration: Double, words: [GraphicWord], directorWords: [String: String] = [:], directorChangedAt: Double? = nil, assetID: String? = nil, noteID: String? = nil, render: GraphicRender? = nil, updatedAt: Double = Date().timeIntervalSince1970) {
        self.name = name; self.folder = folder; self.duration = duration; self.words = words; self.directorWords = directorWords; self.directorChangedAt = directorChangedAt; self.assetID = assetID; self.noteID = noteID; self.render = render; self.updatedAt = updatedAt
    }

    /// What the graphic shows for each word: the director's words, else the page's.
    public var resolvedWords: [String: String] { Dictionary(uniqueKeysWithValues: words.map { ($0.key, directorWords[$0.key] ?? $0.text) }) }
    public func text(_ key: String) -> String? { directorWords[key] ?? words.first { $0.key == key }?.text }
    /// "the title", "the lower third": how History names it.
    public var spokenName: String { "the " + name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").lowercased() }
    /// "Title · Two years.": the first word's label and text, for lists and outlines.
    public var displayName: String { words.first.map { "\($0.label) \u{00B7} \(text($0.key) ?? $0.text)" } ?? name }

    /// Every key must be one of the graphic's words and fit its maximum.
    public func validateDirectorWords(_ values: [String: String]) throws {
        for (key, text) in values {
            guard let field = words.first(where: { $0.key == key }) else { throw DirectionError("unknown_word", "\(name) has no word called \(key).") }
            if let max = field.maxLength, text.count > max { throw DirectionError("too_long", "\(field.label) can be \(max) characters at most.") }
        }
    }

    /// Names are folder names: lowercase letters, digits, dashes and underscores.
    public static func isValidName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.count <= 64, CharacterSet.lowercaseLetters.union(.decimalDigits).contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_" }
    }
}

extension ProjectStore {
    static func ensureGraphicTables(_ db: Database) throws {
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS graphics (
            name TEXT PRIMARY KEY,
            folder TEXT NOT NULL,
            words BLOB NOT NULL,
            director_words BLOB NOT NULL,
            asset_id TEXT,
            note_id TEXT,
            payload BLOB NOT NULL
        );
        """)
    }

    /// Everything else about a graphic, kept beside the columns the spec names.
    private struct GraphicExtra: Codable { var duration: Double; var directorChangedAt: Double?; var render: GraphicRender?; var updatedAt: Double }

    // MARK: Folders

    /// `<film>.direction/Editor/Graphics`: where the editor writes graphics.
    public var graphicsFolder: URL { url.appendingPathComponent("Editor/Graphics", isDirectory: true) }
    /// `<film>.direction/Renders/Graphics`: Direction's cache of rendered graphics.
    public var graphicRendersFolder: URL { url.appendingPathComponent("Renders/Graphics", isDirectory: true) }

    // MARK: Reading

    public func graphics() throws -> [Graphic] {
        try database.read { db in try Row.fetchAll(db, sql: "SELECT * FROM graphics ORDER BY name").map(Self.graphic(from:)) }
    }
    public func graphic(_ name: String) throws -> Graphic? {
        try database.read { db in try Row.fetchOne(db, sql: "SELECT * FROM graphics WHERE name = ?", arguments: [name]).map(Self.graphic(from:)) }
    }
    public func graphic(assetID: String) throws -> Graphic? {
        try database.read { db in try Row.fetchOne(db, sql: "SELECT * FROM graphics WHERE asset_id = ?", arguments: [assetID]).map(Self.graphic(from:)) }
    }
    static func graphic(from row: Row) throws -> Graphic {
        let extra = try JSONDecoder().decode(GraphicExtra.self, from: row["payload"] as Data)
        return Graphic(name: row["name"], folder: row["folder"], duration: extra.duration, words: try JSONDecoder().decode([GraphicWord].self, from: row["words"] as Data),
                       directorWords: try JSONDecoder().decode([String: String].self, from: row["director_words"] as Data), directorChangedAt: extra.directorChangedAt,
                       assetID: row["asset_id"], noteID: row["note_id"], render: extra.render, updatedAt: extra.updatedAt)
    }

    // MARK: Writing

    static func writeGraphic(_ db: Database, _ g: Graphic) throws {
        let extra = GraphicExtra(duration: g.duration, directorChangedAt: g.directorChangedAt, render: g.render, updatedAt: g.updatedAt)
        try db.execute(sql: "INSERT OR REPLACE INTO graphics (name, folder, words, director_words, asset_id, note_id, payload) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       arguments: [g.name, g.folder, try JSONEncoder.direction.encode(g.words), try JSONEncoder.direction.encode(g.directorWords), g.assetID, g.noteID, try JSONEncoder.direction.encode(extra)])
    }
    private func revisionNow(_ db: Database) throws -> Int { try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0 }

    /// Records a checked (and possibly rendered) graphic for the editor.
    public func saveGraphic(_ graphic: Graphic, summary: String) throws {
        var g = graphic; g.updatedAt = Date().timeIntervalSince1970
        try database.write { db in try Self.writeGraphic(db, g); try Self.event(db, kind: "graphic.updated", revision: try revisionNow(db), summary: summary) }
    }

    /// The director fixes words directly, without a turnover (open-questions.md › 14). Every key must be
    /// one of the graphic's words and fit its maximum. Pass the render made with these words.
    @discardableResult
    public func setDirectorWords(_ name: String, _ words: [String: String], render: GraphicRender?) throws -> Graphic {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM graphics WHERE name = ?", arguments: [name]) else { throw DirectionError("graphic_not_found", "There's no graphic called \(name).") }
            var g = try Self.graphic(from: row)
            try g.validateDirectorWords(words)
            g.directorWords = words
            g.directorChangedAt = words.isEmpty ? nil : Date().timeIntervalSince1970
            if let render { g.render = render }
            g.updatedAt = Date().timeIntervalSince1970
            try Self.writeGraphic(db, g)
            try Self.event(db, kind: "graphic.words", revision: try revisionNow(db), summary: "You changed the words of \(g.spokenName)")
            return g
        }
    }

    /// Undo for a words change: the director's earlier words and their render, exactly as they were.
    public func restoreDirectorWords(_ name: String, _ words: [String: String], changedAt: Double?, render: GraphicRender?, summary: String? = nil) throws {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM graphics WHERE name = ?", arguments: [name]) else { throw DirectionError("graphic_not_found", "There's no graphic called \(name).") }
            var g = try Self.graphic(from: row)
            g.directorWords = words; g.directorChangedAt = changedAt
            if let render { g.render = render }
            g.updatedAt = Date().timeIntervalSince1970
            try Self.writeGraphic(db, g)
            try Self.event(db, kind: "graphic.words", revision: try revisionNow(db), summary: summary ?? "Put back the words of \(g.spokenName)")
        }
    }

    /// Puts a render in the film's assets so it can be placed like footage: a new asset the first time,
    /// and an update only when its length or picture size changed (a words change keeps both, so it
    /// makes no new revision). Returns the asset id and the edit revision after.
    @discardableResult
    public func registerGraphicAsset(_ name: String, _ asset: MediaAsset) throws -> (assetID: String, editRevision: Int) {
        for attempt in 0..<3 {
            let p = try read(), existingID = try graphic(name)?.assetID
            if let id = existingID, let old = p.assets.first(where: { $0.id == id }), old.duration == asset.duration, old.video == asset.video { return (id, p.editRevision) }
            let id = existingID.flatMap { id in p.assets.contains { $0.id == id } ? id : nil } ?? asset.id
            var fresh = asset; fresh.id = id; fresh.bookmark = nil
            let entry = fresh
            let request = try JSONEncoder.direction.encode(["graphic": name, "path": asset.path, "duration": String(asset.duration.seconds)])
            do {
                let after = try update(expectedRevision: p.editRevision, key: newID("graphic"), request: request, summary: existingID == nil ? "Added the graphic \(name)" : "Rendered the graphic \(name) again") { p in
                    if let i = p.assets.firstIndex(where: { $0.id == id }) { p.assets[i] = entry } else { p.assets.append(entry) }
                }
                return (id, after.editRevision)
            } catch let e as DirectionError where e.code == "revision_conflict" && attempt < 2 { continue }
        }
        throw DirectionError("revision_conflict", "The film kept changing while the graphic was added. Try again.")
    }

    // MARK: The words lock (product-model.md › Agent rules; agent-timeline.md › words_are_yours)

    /// Checks the editor's new words against the director's. The editor changes words by changing what
    /// its page declares; a director-set word it changes or drops needs a note, written after the
    /// director's change, that names the graphic. Returns the director's words that still stand.
    public func checkGraphicWords(_ name: String, declared: [GraphicWord], noteID: String?) throws -> [String: String] {
        guard let g = try graphic(name), !g.directorWords.isEmpty else { return [:] }
        let before = Dictionary(g.words.map { ($0.key, $0.text) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(declared.map { ($0.key, $0.text) }, uniquingKeysWith: { a, _ in a })
        let changed = g.directorWords.keys.filter { before[$0] != now[$0] }.sorted()
        guard !changed.isEmpty else { return g.directorWords }
        guard let noteID, let note = try? comment(noteID), Self.note(note, names: g) else {
            let labels = changed.compactMap { k in g.words.first { $0.key == k }?.label }.joined(separator: ", ")
            throw DirectionError("words_are_yours", "The director set the words of \(name) (\(labels)). Keep \(changed.map { "\($0): \u{201C}\(g.directorWords[$0] ?? "")\u{201D}" }.joined(separator: "; ")) in your page, or answer a note that asks for new words and names the graphic.")
        }
        var standing = g.directorWords
        for key in changed { standing[key] = nil }
        return standing
    }

    /// A note names a graphic when the director wrote it (or replied on it) after changing the words,
    /// and it mentions the graphic: its name, a word's label, or the words themselves.
    static func note(_ note: ReviewComment, names g: Graphic) -> Bool {
        let since = g.directorChangedAt ?? 0
        var texts = note.createdAt > since ? [note.text] : []
        texts += note.replies.filter { $0.author == "Director" && $0.createdAt > since }.map(\.text)
        let terms = ([g.name, g.name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")] + g.words.map(\.label) + Array(g.directorWords.values))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 3 }
        return texts.contains { t in terms.contains { t.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
    }

    // MARK: Renders in every cut

    /// A graphic's words are the director's to fix in place, so every revision of the film plays its
    /// current render: a cut pinned to an older revision shows the new words without a new cut.
    static func withCurrentGraphics(_ db: Database, _ project: Project) throws -> Project {
        let rows = try Row.fetchAll(db, sql: "SELECT asset_id, payload FROM graphics WHERE asset_id IS NOT NULL")
        guard !rows.isEmpty else { return project }
        var p = project
        for row in rows {
            guard let id: String = row["asset_id"], let i = p.assets.firstIndex(where: { $0.id == id }),
                  let render = try JSONDecoder().decode(GraphicExtra.self, from: row["payload"] as Data).render else { continue }
            p.assets[i].path = render.path; p.assets[i].fileSize = render.fileSize; p.assets[i].modifiedAt = render.modifiedAt
            // The bookmark points at the file first registered; the current render is found by path.
            p.assets[i].bookmark = nil
        }
        return p
    }
}
