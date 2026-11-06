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
    public var rule: RuleSuggestion?
    public init(noteID: String? = nil, summary: String, delta: String? = nil, start: Double? = nil, end: Double? = nil, options: [NoteOption]? = nil, preferred: String? = nil, unasked: Bool? = nil, kind: NoteKind? = nil, rule: RuleSuggestion? = nil) {
        self.noteID = noteID; self.summary = summary; self.delta = delta; self.start = start; self.end = end; self.options = options; self.preferred = preferred; self.unasked = unasked; self.kind = kind; self.rule = rule
    }
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
    /// A brief that names another style gives the film its own copy of it (styles.md).
    public func saveBrief(_ brief: Brief, styles: URL = SharedSettings.stylesFolder) throws {
        var b = brief; b.updatedAt = Date().timeIntervalSince1970
        if let id = b.style, !StyleLibrary.isSafe(id) { throw DirectionError("style_not_found", "There's no style \(id).") }
        if b.style != (try self.brief()).style || (b.style != nil && StyleLibrary.film(url, id: b.style) == nil) {
            try StyleLibrary.use(b.style.map { try StyleLibrary.read(styles.appendingPathComponent($0, isDirectory: true)) }, film: url)
        }
        try database.write { db in try Self.setValue(db, DirectingKey.brief, b); try Self.event(db, kind: "brief.updated", revision: try currentRevision(db), summary: "Updated the brief") }
    }

    /// The film's style, from its own copy.
    public func style() throws -> Style? { StyleLibrary.film(url, id: try brief().style) }

    /// What the film follows: the house style, with the film's own style over it.
    public func appliedStyle(styles: URL = SharedSettings.stylesFolder) throws -> AppliedStyle { StyleLibrary.applied(try style(), folder: styles) }

    /// Keeps a rule (styles.md › Keep as a rule): in this film's style, which the film's copy follows, or in
    /// the house style; `replacing` takes out rules it stands in for. A note's answer remembers where it went.
    @discardableResult
    public func keepRule(_ text: String, area: String?, inFilmStyle: Bool, replacing: [String] = [], noteID: String? = nil, styles: URL = SharedSettings.stylesFolder) throws -> KeptRule {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, words.count <= 300 else { throw DirectionError("invalid_rule", "A rule is one sentence of up to 300 characters.") }
        let filmStyle = try brief().style
        var target = StyleLibrary.houseID
        if inFilmStyle {
            guard let id = filmStyle, let s = try? StyleLibrary.read(styles.appendingPathComponent(id, isDirectory: true)) else {
                throw DirectionError("style_not_found", "This film\u{2019}s style isn\u{2019}t in your Styles folder any more. Keep it in your house style.")
            }
            target = s.id
        }
        let note = try noteID.flatMap { id in try comments().first { $0.id == id } }
        let rule = StyleRule(area: area ?? "general", text: words, kept: .init(film: try read().name, note: note?.text))
        let gone = Set(replacing)
        if !gone.isEmpty {
            if let id = filmStyle, (try? StyleLibrary.read(styles.appendingPathComponent(id, isDirectory: true)))?.rules.contains(where: { gone.contains($0.id) }) == true { try StyleLibrary.remove(rules: gone, from: id, folder: styles) }
            if StyleLibrary.house(in: styles).rules.contains(where: { gone.contains($0.id) }) { try StyleLibrary.remove(rules: gone, from: StyleLibrary.houseID, folder: styles) }
        }
        let saved = try StyleLibrary.keep(rule, in: target, folder: styles)
        if filmStyle != nil, target != StyleLibrary.houseID || !gone.isEmpty { try? refreshStyle(styles: styles) }
        let kept = KeptRule(id: rule.id, styleID: saved.id, styleName: saved.name)
        if let noteID {
            try modifyNote(noteID, summary: "Kept a rule") { c, _ in
                guard var answers = c.answers, !answers.isEmpty else { return }
                answers[answers.count - 1].keptRule = kept
                c.answers = answers
            }
        }
        return kept
    }
    /// Copies the film's style again from the Styles folder, for changes made there since it was picked.
    public func refreshStyle(styles: URL = SharedSettings.stylesFolder) throws {
        guard let id = try brief().style else { return }
        try StyleLibrary.use(try StyleLibrary.read(styles.appendingPathComponent(id, isDirectory: true)), film: url)
        try database.write { db in try Self.event(db, kind: "brief.updated", revision: try currentRevision(db), summary: "Updated the style") }
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

    /// A take two logging runs left unlogged goes to Unsorted with what Direction knows, so logging
    /// can finish and the director can place it (footage-index.md › Logging in batches).
    public func logUnplaced(assetID: String, caption: String) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Put a take the editor didn\u{2019}t log in Unsorted") { d in
            guard !d.isLogged(assetID) else { return }
            // A take filed from the folders, or circled before logging, keeps where it is and what the director did.
            var t = d.take(assetID); t.unlogged = nil
            if t.caption == nil { t.caption = caption }
            t.flags.append("Not logged by the editor")
            d.takes[assetID] = t
        }
    }

    // MARK: Sync (footage-index.md › Sync)

    /// Direction's sync pass: groups found among the takes it checked. Groups the director has
    /// already shaped (their sound take) keep it when the same takes come back together.
    /// `replacing`: `checked` is every take with sound now (a whole pass), so takes compared before
    /// that aren't footage any more drop off the list.
    public func saveSync(_ groups: [SyncGroup], checked: [String], replacing: Bool = false) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: groups.isEmpty ? "Compared the takes' sound" : "Found \(groups.count == 1 ? "takes" : "\(groups.count) sets of takes") in sync") { d in
            let previous = d.syncGroups ?? []
            d.syncGroups = groups.map { g in
                guard let old = previous.first(where: { Set($0.takes.map(\.assetID)) == Set(g.takes.map(\.assetID)) }), old.soundAssetID != g.soundAssetID else { return g }
                return Self.resound(g, to: old.soundAssetID)
            }
            d.syncChecked = Array(replacing ? Set(checked) : Set(d.syncChecked ?? []).union(checked)).sorted()
        }
    }

    /// Not in Sync: the take leaves its group, and Direction won't link it with those takes again.
    public func unsync(assetID: String) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Took a take out of sync") { d in
            guard let i = d.syncGroups?.firstIndex(where: { $0.take(assetID) != nil }), var g = d.syncGroups?[i] else { return }
            let others = g.takes.map(\.assetID).filter { $0 != assetID }
            d.notInSync = (d.notInSync ?? []) + others.map { [assetID, $0].sorted() }
            g.takes.removeAll { $0.assetID == assetID }
            if g.takes.count < 2 { d.syncGroups?.remove(at: i); return }
            if g.soundAssetID == assetID { g = Self.resound(g, to: g.takes.max { $0.match < $1.match }!.assetID) }
            d.syncGroups?[i] = g
        }
    }

    /// Use This Take's Sound: the cut's sound comes from this take; offsets move to its clock.
    public func setSyncSound(assetID: String) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Chose which take's sound to use") { d in
            guard let i = d.syncGroups?.firstIndex(where: { $0.take(assetID) != nil }) else { throw DirectionError("not_in_sync", "That take isn't in sync with another.") }
            let g = d.syncGroups![i]
            d.syncGroups?[i] = Self.resound(g, to: assetID)
        }
    }

    static func resound(_ g: SyncGroup, to assetID: String) -> SyncGroup {
        guard let base = g.take(assetID) else { return g }
        var out = g; out.soundAssetID = assetID
        out.takes = g.takes.map { SyncedTake(assetID: $0.assetID, offset: (($0.offset - base.offset) * 1000).rounded() / 1000, match: $0.match) }
            .sorted { ($0.assetID != assetID ? 1 : 0, $0.assetID) < ($1.assetID != assetID ? 1 : 0, $1.assetID) }
        return out
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
            d.scenes[i].locked = locked; d.scenes[i].lockedAt = locked ? Date().timeIntervalSince1970 : nil; d.scenes[i].lockedWithPicture = locked ? false : nil
        }
    }
    /// The director adds a scene; it takes the next number.
    @discardableResult
    public func addScene(title: String) throws -> DailiesScene {
        var created: DailiesScene?
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Added a scene") { d in
            let scene = DailiesScene(number: (d.scenes.map(\.number).max() ?? 0) + 1, title: title)
            d.scenes.append(scene); created = scene
        }
        return created!
    }
    /// Deletes a scene. Its takes go back to Unsorted; nothing on disk changes. Returns what undo needs.
    @discardableResult
    public func deleteScene(id: String) throws -> (DailiesScene, [String]) {
        var removed: (DailiesScene, [String])?
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Deleted a scene") { d in
            guard let i = d.scenes.firstIndex(where: { $0.id == id }) else { throw DirectionError("scene_not_found", "Scene not found.") }
            guard !d.scenes[i].locked else { throw DirectionError("scene_locked", "\(d.scenes[i].label) is locked. Unlock it before deleting it.") }
            let takes = d.takes.values.filter { $0.sceneID == id }.map(\.assetID)
            for t in takes { d.takes[t]?.sceneID = nil }
            for (k, t) in d.takes where t.guessSceneID == id { d.takes[k]?.guessSceneID = nil }
            removed = (d.scenes.remove(at: i), takes)
        }
        return removed!
    }
    /// Puts a deleted scene and its takes back (undo).
    public func restoreScene(_ scene: DailiesScene, takes: [String]) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Restored a scene") { d in
            if !d.scenes.contains(where: { $0.id == scene.id }) { d.scenes.append(scene); d.scenes.sort { $0.number < $1.number } }
            for t in takes where d.takes[t] != nil { d.takes[t]?.sceneID = scene.id }
        }
    }
    /// Moves a take to another setup of its scene.
    public func setTakeSetup(assetID: String, setupCode: String?) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Moved a take to another setup") { d in
            var t = d.take(assetID)
            if let code = setupCode, let scene = d.scenes.first(where: { $0.id == t.sceneID }), !scene.setups.contains(where: { $0.code == code }) {
                guard let i = d.scenes.firstIndex(where: { $0.id == scene.id }) else { return }
                d.scenes[i].setups.append(DailiesSetup(code: code, description: ""))
            }
            t.setupCode = setupCode; d.takes[assetID] = t
        }
    }
    public func renameScene(id: String, title: String) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Renamed a scene") { d in
            guard let i = d.scenes.firstIndex(where: { $0.id == id }) else { throw DirectionError("scene_not_found", "Scene not found.") }
            d.scenes[i].title = title
        }
    }

    /// Takes as the director filed them in their folders (dailies.md › From your folders): their scenes and
    /// setups are made or found by number and code, and a take already in a scene stays where it is.
    @discardableResult
    public func fileTakes(_ placed: [String: FootagePlace]) throws -> Dailies {
        guard !placed.isEmpty else { return try dailies() }
        return try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Filed takes as their folders say") { d in
            for (assetID, place) in placed.sorted(by: { $0.value.folder < $1.value.folder }) {
                var t = d.take(assetID)
                guard t.sceneID == nil else { continue }
                let i: Int
                if let found = d.scenes.firstIndex(where: { $0.number == place.scene }) { i = found }
                else { var s = DailiesScene(number: place.scene, title: place.sceneTitle); s.folder = place.folder.components(separatedBy: "/").first; d.scenes.append(s); i = d.scenes.count - 1 }
                if let code = place.setupCode, !d.scenes[i].setups.contains(where: { $0.code == code }) { d.scenes[i].setups.append(DailiesSetup(code: code, description: place.setupDescription ?? "")) }
                t.sceneID = d.scenes[i].id; t.guessSceneID = nil; t.folder = place.folder
                if let code = place.setupCode { t.setupCode = code }
                if let n = place.take { t.code = "T\(n)" }
                d.takes[assetID] = t
            }
            d.scenes.sort { $0.number < $1.number }
            for i in d.scenes.indices { d.scenes[i].setups.sort { $0.code.localizedStandardCompare($1.code) == .orderedAscending } }
            d.updatedAt = Date().timeIntervalSince1970
        }
    }

    /// The editor logs footage: scenes, setups, take codes, captions, suggestions and guesses. It can't circle.
    public func logDailies(_ update: Dailies) throws -> Dailies {
        let assets = Set(try read().assets.map(\.id))
        return try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "The editor logged footage") { d in
            var scenes: [DailiesScene] = []
            for var s in update.scenes {
                if let old = d.scenes.first(where: { $0.id == s.id }) {
                    s.locked = old.locked; s.lockedAt = old.lockedAt; s.lockedWithPicture = old.lockedWithPicture; s.folder = old.folder
                    // A scene from the director's folders keeps its number, title and setups; the editor adds setups and fills in what they are.
                    if old.folder != nil {
                        s.number = old.number; s.title = old.title
                        s.setups = old.setups.map { o in o.description.isEmpty ? (s.setups.first { $0.code == o.code } ?? o) : o } + s.setups.filter { n in !old.setups.contains { $0.code == n.code } }
                    }
                }
                else { s.locked = false; s.lockedAt = nil; s.lockedWithPicture = nil }
                scenes.append(s)
            }
            // A scene is never dropped by logging: the editor logs in batches, and the director's scenes stay.
            for old in d.scenes where !scenes.contains(where: { $0.id == old.id }) { scenes.append(old) }
            d.scenes = scenes.sorted { $0.number < $1.number }
            for (id, var t) in update.takes {
                guard assets.contains(id) else { throw DirectionError("asset_not_found", "Take \(id) is not footage in this film.") }
                let old = d.take(id)
                t.assetID = id; t.circled = old.circled; t.circledAt = old.circledAt; t.unlogged = nil
                if old.unusable && !t.unusable { t.unusable = old.unusable }
                if let s = old.sceneID, d.scenes.first(where: { $0.id == s })?.locked == true { t.sceneID = s }
                // Filed by the director's folders: the scene, setup and take they say stay.
                if let folder = old.folder, old.sceneID != nil {
                    t.folder = folder; t.sceneID = old.sceneID; t.guessSceneID = nil
                    if let v = old.setupCode { t.setupCode = v }; if let v = old.code { t.code = v }
                }
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
    /// Locking picture locks every scene still open with it; unlocking picture opens those again, and keeps the
    /// ones the director locked on their own.
    public func lockPicture(cutID: String?, locked: Bool) throws {
        if locked {
            let open = try notes().filter { $0.visibleToEditor && ![.accepted, .dropped].contains($0.lifecycle) && !$0.inInbox }
            guard open.isEmpty else { throw DirectionError("notes_open", "Accept or drop every open note before locking picture.") }
            if try dailies().scenes.contains(where: { !$0.locked }) {
                try mutate(DirectingKey.dailies, default: Dailies(), kind: "lock.updated", summary: "Locked every scene with the picture") { d in
                    let now = Date().timeIntervalSince1970
                    for i in d.scenes.indices where !d.scenes[i].locked { d.scenes[i].locked = true; d.scenes[i].lockedAt = now; d.scenes[i].lockedWithPicture = true }
                }
            }
        }
        _ = try updateDirectingState(summary: locked ? "Locked picture" : "Unlocked picture") { s in
            s.pictureLocked = locked; s.pictureLockedAt = locked ? Date().timeIntervalSince1970 : nil; s.pictureLockedCutID = locked ? cutID : nil
            if locked && s.finishing == nil { s.finishing = FinishingItem.defaults }
        }
        guard !locked else { return }
        // A film locked before scenes knew why they locked: the ones that locked in a moment picture locked.
        let times = try database.read { db in try Double.fetchAll(db, sql: "SELECT created_at FROM events WHERE kind = 'directing.updated' AND summary = 'Locked picture'") }
        func withPicture(_ s: DailiesScene) -> Bool {
            s.locked && (s.lockedWithPicture == true || (s.lockedWithPicture == nil && s.lockedAt.map { at in times.contains { abs($0 - at) < 10 } } ?? false))
        }
        if try dailies().scenes.contains(where: withPicture) {
            try mutate(DirectingKey.dailies, default: Dailies(), kind: "lock.updated", summary: "Unlocked the scenes that locked with the picture") { d in
                for i in d.scenes.indices where withPicture(d.scenes[i]) { d.scenes[i].locked = false; d.scenes[i].lockedAt = nil; d.scenes[i].lockedWithPicture = nil }
            }
        }
    }
    /// The revision a cut plays and delivers: its own, or once picture is locked on it, the newest one whose
    /// picture is still the cut's, so the color, sound and graphics finished after the lock come with it.
    public func playedRevision(of cut: ReviewCut) throws -> Int {
        let state = try directingState()
        guard state.pictureLocked, state.pictureLockedCutID == cut.id else { return cut.editRevision }
        let head = try read()
        guard head.editRevision > cut.editRevision, let now = try? head.sequence(cut.sequenceID), let locked = try? read(revision: cut.editRevision),
              let then = try? locked.sequence(cut.sequenceID), TimelineLocks.samePicture(then, now, graphics: TimelineLocks.graphics(locked).union(TimelineLocks.graphics(head))) else { return cut.editRevision }
        return head.editRevision
    }
    public func updateFinishing(_ items: [FinishingItem]) throws -> DirectingState {
        try updateDirectingState(summary: "Updated finishing") { s in
            var current = s.finishing ?? FinishingItem.defaults
            for item in items { if let i = current.firstIndex(where: { $0.id == item.id }) { current[i] = item } else { current.append(item) } }
            s.finishing = current
        }
    }

    /// The director's credits (finish.md › 36, Write credits), kept in the film for the finish job to roll
    /// at the end. The titles item is the director's, and it's done.
    @discardableResult
    public func saveCredits(_ text: String) throws -> DirectingState {
        let credits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credits.isEmpty, credits.count <= 2_000 else { throw DirectionError("invalid_credits", "Write the credits in 1 to 2,000 characters.") }
        return try updateDirectingState(summary: "Wrote the credits") { $0.write(credits: credits) }
    }

    /// Copies a license into the film's Licenses folder under a name of its own, never over another
    /// file, and records it. The licenses item is done once one is on file.
    @discardableResult
    public func addLicense(from source: URL) throws -> LicenseFile {
        let fm = FileManager.default, folder = url.appendingPathComponent("Licenses", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent, ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension
        var target = folder.appendingPathComponent(source.lastPathComponent), n = 2
        while fm.fileExists(atPath: target.path) { target = folder.appendingPathComponent("\(base) \(n)\(ext)"); n += 1 }
        try fm.copyItem(at: source, to: target)
        let file = LicenseFile(path: "Licenses/" + target.lastPathComponent, original: source.lastPathComponent, addedAt: Date().timeIntervalSince1970)
        do { _ = try updateDirectingState(summary: "Added the license \(source.lastPathComponent)") { $0.add(license: file) } }
        catch { try? fm.removeItem(at: target); throw error }
        return file
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
        try database.write { db in try Self.changeNote(db, id, kind: kind, summary: summary, change) }
    }
    @discardableResult
    static func changeNote(_ db: Database, _ id: String, kind: String = "feedback.updated", summary: String = "Updated a note", _ change: (inout ReviewComment, Database) throws -> Void) throws -> ReviewComment {
        guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM comments WHERE id = ?", arguments: [id]) else { throw DirectionError("feedback_not_found", "Note not found.") }
        var c = try JSONDecoder().decode(ReviewComment.self, from: data)
        try change(&c, db)
        c.updatedAt = Date().timeIntervalSince1970
        try event(db, kind: kind, revision: c.editRevision, summary: summary)
        c.cursor = db.lastInsertedRowID
        try db.execute(sql: "UPDATE comments SET payload = ?, cursor = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(c), c.cursor, c.id])
        return c
    }

    /// Notes can be rewritten until they're turned over; after that they can only be replied to.
    /// `range`: a stretch pulled longer, shorter or along the cut. What it rests on in the footage, and the words
    /// under it, move with it.
    public func editNote(id: String, text: String? = nil, kind: NoteKind?? = nil, region: FrameRegion?? = nil, range: MediaRange? = nil) throws -> ReviewComment {
        var moved: (anchors: [SourceAnchor], words: [TimelineWord])?
        if let range {
            let note = try comment(id), p = try read(revision: note.editRevision), s = try p.sequence(note.sequenceID)
            guard note.range != nil else { throw DirectionError("invalid_range", "Only a note on a stretch of the cut has a stretch to move.") }
            guard range.isValid && range.end <= s.duration else { throw DirectionError("invalid_range", "Feedback range must be inside the reviewed cut.") }
            moved = try restsOn(p, s, range: range, time: nil)
        }
        return try modifyNote(id) { c, _ in
            guard [.draft, .written, .reopened].contains(c.lifecycle) || c.inInbox else { throw DirectionError("note_turned_over", "This note was turned over. Reply to it instead.") }
            if let text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, text.count <= 20_000 else { throw DirectionError("invalid_comment", "A note needs words.") }
                c.text = text
                if c.noteState == .draft { c.noteState = .written }
            }
            if let kind { c.kind = kind }
            if let region { c.region = region }
            if let range, let moved { c.range = range; c.anchors = moved.anchors; c.transcriptContext = moved.words }
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
            // Accepting without a pick keeps what plays.
            if answer.pick == nil { answer.pick = answer.optionInCut }
            answer.state = "accepted"; c.answers![c.answers!.count - 1] = answer
            c.status = "accepted"; c.noteState = .accepted
            c.replies.append(.init(id: newID("reply"), author: "Director", text: "Accepted", revision: answer.revision, createdAt: Date().timeIntervalSince1970))
        }
    }
    /// Use A / Use B: puts that option's version in its cut as a new revision, so Screening and Play
    /// changes play it, and records the pick. Using the other one switches back. Options that aren't
    /// versions of the cut (looks) only record the pick. `record: false` leaves no pick, for Undo of a
    /// first pick.
    public func pickOption(noteID: String, label: String, record: Bool = true) throws {
        guard let note = try notes().first(where: { $0.id == noteID }) else { throw DirectionError("feedback_not_found", "Note not found.") }
        guard let answer = note.answers?.last, let options = answer.options, let option = options.first(where: { $0.label == label }) else { throw DirectionError("no_options", "This answer has no option \(label).") }
        let versions = options.contains { $0.revision != nil }
        let playing = answer.optionInCut.flatMap { l in options.first { $0.label == l } }
        // The playing version: its own revision, or the cut it was delivered in.
        let fromRevision = playing?.revision ?? answer.revision
        var swap: (cut: ReviewCut, head: Int, result: OptionSwap.Result)?
        if versions && playing?.label != label {
            let cuts = try cuts()
            guard let cut = cuts.first(where: { $0.id == answer.cutID }) else { throw DirectionError("cut_not_found", "This answer\u{2019}s cut is gone.") }
            guard cuts.first?.id == cut.id else { throw DirectionError("cut_moved_on", "\(cut.name) isn\u{2019}t the latest cut, so its options can\u{2019}t change it. Reply in the latest cut instead.") }
            guard let toRevision = option.revision else { throw DirectionError("no_version", "The editor didn\u{2019}t keep a separate version of option \(label).") }
            let head = try read()
            if let result = try OptionSwap.swap(try head.sequence(cut.sequenceID), from: try read(revision: fromRevision).sequence(cut.sequenceID), to: try read(revision: toRevision).sequence(cut.sequenceID)) {
                swap = (cut, head.editRevision, result)
            }
        }
        let summary = "Used option \(label)" + (note.number.map { " for note \($0)" } ?? "")
        try database.write { db in
            if let swap {
                let sequenceID = swap.cut.sequenceID, sequence = swap.result.sequence
                let p: Project
                do {
                    p = try Self.commit(db, expectedRevision: swap.head, key: newID("pick"), request: Data("pick:\(noteID):\(label)".utf8), summary: summary) { p in
                        guard let i = p.sequences.firstIndex(where: { $0.id == sequenceID }) else { throw DirectionError("sequence_not_found", "Sequence not found.") }
                        p.sequences[i] = sequence
                    }
                } catch let e as DirectionError where e.code == "scene_locked" {
                    throw DirectionError(e.code, "Option \(label) changes a locked scene. Unlock the scene to use it.")
                } catch let e as DirectionError where e.code == "picture_locked" {
                    throw DirectionError(e.code, "Picture is locked, so option \(label) can\u{2019}t go in. Unlock picture to use it.")
                }
                // The cut plays the new revision; answers after the swapped stretch move with it.
                var cut = swap.cut; cut.editRevision = p.editRevision
                try db.execute(sql: "UPDATE cuts SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(cut), cut.id])
                let at = swap.result.at.seconds, oldEnd = at + swap.result.removed.seconds, d = swap.result.inserted.seconds - swap.result.removed.seconds
                if d != 0 {
                    for data in try Data.fetchAll(db, sql: "SELECT payload FROM comments") {
                        var c = try JSONDecoder().decode(ReviewComment.self, from: data)
                        guard c.id != noteID, var a = c.answers?.last, a.cutID == cut.id, let r = a.range, r.start.seconds >= oldEnd - 1e-6 else { continue }
                        a.range = MediaRange(start: r.start.seconds + d, end: r.end.seconds + d); c.answers![c.answers!.count - 1] = a
                        try db.execute(sql: "UPDATE comments SET payload = ? WHERE id = ?", arguments: [try JSONEncoder.direction.encode(c), c.id])
                    }
                }
            }
            try Self.changeNote(db, noteID, summary: summary) { c, _ in
                guard var a = c.answers?.last else { return }
                if let swap {
                    // Both versions stay playable side by side.
                    a.options = a.options?.map { o in var o = o; if o.revision == nil { o.revision = fromRevision }; return o }
                    // Play changes covers what changed between the two, where it sits now.
                    let at = swap.result.at.seconds, oldEnd = at + swap.result.removed.seconds, newEnd = at + swap.result.inserted.seconds
                    if let r = a.range {
                        let end = r.end.seconds >= oldEnd - 1e-6 ? r.end.seconds + newEnd - oldEnd : r.end.seconds
                        a.range = MediaRange(start: min(r.start.seconds, at), end: max(end, newEnd))
                    } else { a.range = MediaRange(start: at, end: newEnd) }
                }
                if versions { a.inCut = label }
                a.pick = record ? label : nil
                c.answers![c.answers!.count - 1] = a
            }
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

    /// Undo for Accept: back to an unreviewed answer.
    public func unacceptAnswer(noteID: String) throws {
        try modifyNote(noteID, summary: "Took back an accept") { c, _ in
            guard c.status == "accepted", var answer = c.answers?.last else { return }
            answer.state = "unreviewed"; c.answers![c.answers!.count - 1] = answer
            c.status = "addressed"; c.noteState = .answered
            if c.replies.last?.author == "Director" { c.replies.removeLast() }
        }
    }
    /// Undo for Reply: the answer stands again and the director's words are withdrawn.
    public func undoReopen(noteID: String, turnoverID: String?) throws {
        try modifyNote(noteID, summary: "Took back a reply") { c, _ in
            guard c.noteState == .reopened, var answer = c.answers?.last else { return }
            answer.state = "unreviewed"; c.answers![c.answers!.count - 1] = answer
            c.status = "addressed"; c.noteState = .answered; c.turnoverID = turnoverID
            if c.replies.last?.author == "Director" { c.replies.removeLast() }
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
        // Two ways are two revisions, so the director can put either one in the cut. Choices that aren't
        // versions of the cut (looks) carry none.
        let delivered = try revision ?? self.revision()
        // Everything is checked before anything is written, so a mistake leaves no cut or answers behind
        // and the editor can send it again.
        if t.kind == "notes", t.waitForOK, !t.readBackApproved { throw DirectionError("readback_not_approved", "The director asked to OK the read-back before cutting.") }
        var rules: [Int: RuleSuggestion] = [:]
        for (i, a) in answers.enumerated() {
            if let noteID = a.noteID, !t.noteIDs.contains(noteID) { throw DirectionError("feedback_not_found", "Answer refers to a note outside this turnover.") }
            if var rule = a.rule {
                rule.text = rule.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rule.text.isEmpty, rule.text.count <= 300, rule.scope == nil || ["style", "house"].contains(rule.scope!) else { throw DirectionError("invalid_rule", "A rule is one sentence of up to 300 characters; scope is style or house.") }
                rules[i] = rule
            }
            guard let options = a.options, !options.isEmpty else { continue }
            let kept = options.compactMap(\.revision)
            guard Set(options.map(\.label)).count == options.count, kept.isEmpty || kept.count == options.count, kept.allSatisfy({ $0 <= delivered }) else {
                throw DirectionError("invalid_options", "Give each option its own label. Two versions of the cut each need the revision you committed them at, so the director can put either one in; looks carry none.")
            }
        }
        // Every note the director still has open gets an answer, one the editor couldn't do included,
        // or it would stay turned over with nothing to read.
        let answered = Set(answers.compactMap(\.noteID))
        let unanswered = try notes().filter { t.noteIDs.contains($0.id) && !answered.contains($0.id) && ![.accepted, .dropped].contains($0.lifecycle) }
        guard unanswered.isEmpty else {
            let which = unanswered.compactMap(\.number).sorted().map { "#\($0)" }.joined(separator: ", ")
            throw DirectionError("note_unanswered", "Answer every note in the turnover\(which.isEmpty ? "" : " (\(which) \(unanswered.count == 1 ? "has" : "have") none)"); for one you couldn't do, say why and what would.")
        }
        let priorCuts = try cuts().count
        let name = t.kind == "assembly" || priorCuts == 0 ? "Assembly" : "Cut \(priorCuts + 1)"
        let cut = try createCut(name: name, sequenceID: sequenceID ?? t.sequenceID, revision: revision)
        for (i, a) in answers.enumerated() {
            let range = a.start.flatMap { s in a.end.map { MediaRange(start: s, end: $0) } }
            var answer = NoteAnswer(cutID: cut.id, revision: cut.editRevision, summary: a.summary, delta: a.delta, range: range, options: a.options, preferred: a.preferred)
            answer.rule = rules[i]
            if let noteID = a.noteID {
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
        guard (["question", "spend"].contains(q.kind) && (2...4).contains(q.choices.count)) || (q.kind == "cant" && q.choices.count <= 4) else { throw DirectionError("invalid_question", "Questions carry 2–4 concrete choices; can't-do reports up to 4.") }
        if q.kind == "spend" { try Self.validateSpendQuestion(q) }
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

/// A lock keeps the cut: the editor can't recut a locked scene, and nothing can move a frame after picture
/// lock. Color and sound stay open under both, and after picture lock so do the graphics over the picture.
enum LockRules {
    static func check(before: Project, after: Project, dailies: Dailies, state: DirectingState) throws {
        let lockedAssets = dailies.lockedAssetIDs
        guard state.pictureLocked || !lockedAssets.isEmpty else { return }
        let graphics = TimelineLocks.graphics(before).union(TimelineLocks.graphics(after))
        for old in before.sequences {
            guard let new = after.sequences.first(where: { $0.id == old.id }) else {
                if state.pictureLocked { throw DirectionError("picture_locked", "Picture is locked. Unlock it from the Film menu to change the edit.") }
                continue
            }
            let newClips = Dictionary(new.clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            if state.pictureLocked {
                let timing = { (c: Clip) in "\(c.assetID ?? "")|\(c.start.seconds)|\(c.sourceRange.start.seconds)|\(c.sourceRange.duration.seconds)|\(c.speed)|\(c.layer)" }
                let was = old.clips.filter { !TimelineLocks.isGraphic($0, graphics) }, now = new.clips.filter { !TimelineLocks.isGraphic($0, graphics) }
                guard was.count == now.count, was.allSatisfy({ c in newClips[c.id].map { timing($0) == timing(c) } ?? false }) else {
                    throw DirectionError("picture_locked", "Picture is locked. Finishing can change color, sound and the graphics over the picture, not timing.")
                }
            }
            for c in old.clips where c.assetID.map(lockedAssets.contains) ?? false {
                guard let n = newClips[c.id], n.sourceRange == c.sourceRange, n.speed == c.speed, n.framing == c.framing, n.layer == c.layer else {
                    let scene = dailies.scene(for: c.assetID)
                    throw DirectionError("scene_locked", "\(scene?.label ?? "That scene") is locked. The director has to unlock it first.")
                }
            }
        }
    }
}
