import Foundation

enum PrepKey { static let script = "script", breakdown = "breakdown" }

/// A picture the editor writes for a row.
public struct PictureInput: Codable, Sendable {
    public var rowID: String
    public var text: String
    public var size: ShotSize?
    public var move: ShotMove?
    public var board: BoardKind?
    public init(rowID: String, text: String, size: ShotSize? = nil, move: ShotMove? = nil, board: BoardKind? = nil) { self.rowID = rowID; self.text = text; self.size = size; self.move = move; self.board = board }
}

/// Words the editor changes for a row, only where a note on it asks.
public struct SoundInput: Codable, Sendable {
    public var rowID: String
    public var kind: HeardKind?
    public var speaker: String?
    public var text: String?
}

public struct SetupInput: Codable, Sendable {
    public var id: String?
    public var name: String
    public var needs: String?
    public var noCamera: Bool?
}

public struct ShotInput: Codable, Sendable {
    public var id: String?
    /// The setup by id, or by name (a setup in this same call).
    public var setupID: String?
    public var setup: String?
    public var rowIDs: [String]?
    public var what: String?
    public var size: ShotSize?
    public var move: ShotMove?
    public var seconds: Double?
    public var source: ShotSource?
    public var board: BoardKind?
    public var makePlan: String?
    public var estimate: Double?
}

extension ProjectStore {
    public func script() throws -> AVScript? { try database.read { try Self.value($0, PrepKey.script, as: AVScript.self) } }
    public func breakdown() throws -> Breakdown? { try database.read { try Self.value($0, PrepKey.breakdown, as: Breakdown.self) } }

    @discardableResult
    func changeScript(_ summary: String, _ change: (inout AVScript) throws -> Void) throws -> AVScript {
        try mutate(PrepKey.script, default: AVScript(), kind: "script.updated", summary: summary) { s in
            try change(&s)
            s.revision += 1; s.updatedAt = Date().timeIntervalSince1970
        }
    }

    @discardableResult
    func changeBreakdown(_ summary: String, _ change: (inout Breakdown) throws -> Void) throws -> Breakdown {
        let b = try mutate(PrepKey.breakdown, default: Breakdown(), kind: "breakdown.updated", summary: summary) { b in
            try change(&b)
            b.updatedAt = Date().timeIntervalSince1970
        }
        if b.isOK { try fillDailies(from: b) }
        return b
    }

    // MARK: Bringing in a script

    /// Brings in a script file. A second time it's a new draft: rows whose words are unchanged keep their
    /// picture and notes, new words get new rows, and rows whose words are gone go.
    @discardableResult
    public func importScript(from url: URL) throws -> AVScript {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
            throw DirectionError("script_unreadable", "Direction can\u{2019}t read \(url.lastPathComponent). Bring in a text, Markdown or Fountain file.")
        }
        return try importScript(text, fileName: url.lastPathComponent, path: url.path)
    }

    @discardableResult
    public func importScript(_ text: String, fileName: String, path: String? = nil) throws -> AVScript {
        let read = ScriptImport.read(text, fileName: fileName)
        guard !read.rows.isEmpty else { throw DirectionError("script_empty", "\(fileName) has no words Direction can use.") }
        return try changeScript("Brought in \(fileName)") { s in
            let old = s.rows
            func key(_ r: AVRow) -> String { r.sound.text.lowercased().filter { $0.isLetter || $0.isNumber } }
            var unused = Dictionary(grouping: old.filter { !key($0).isEmpty }, by: key)
            s.sections = read.sections
            s.rows = read.rows.map { new in
                guard var kept = unused[key(new)]?.first else { return new }
                unused[key(new)]?.removeFirst()
                kept.section = new.section; kept.sound.kind = new.sound.kind; kept.sound.speaker = new.sound.speaker
                if kept.picture.isEmpty { kept.picture = new.picture }
                if kept.hint == nil { kept.hint = new.hint }
                return kept
            }
            let ids = Set(s.rows.map(\.id))
            for i in s.notes.indices where s.notes[i].state != .done {
                if let rows = s.notes[i].rowIDs, !rows.contains(where: ids.contains) { s.notes[i].state = .dropped }
            }
            s.source = ScriptSource(fileName: fileName, path: path, words: read.words, importedAt: Date().timeIntervalSince1970)
        }
    }

    // MARK: The director's hand

    /// The director types in a cell. What they type is theirs: the editor keeps it.
    @discardableResult
    public func editRow(_ id: String, picture: String? = nil, size: ShotSize?? = nil, move: ShotMove?? = nil, sound: String? = nil, soundKind: HeardKind? = nil, speaker: String?? = nil) throws -> AVScript {
        try changeScript("Changed row") { s in
            guard let i = s.rows.firstIndex(where: { $0.id == id }) else { throw DirectionError("row_not_found", "There\u{2019}s no row \(id).") }
            if let picture { s.rows[i].picture.text = picture; s.rows[i].picture.yours = true; s.rows[i].picture.pass = nil }
            if let size { s.rows[i].picture.size = size; s.rows[i].picture.yours = true }
            if let move { s.rows[i].picture.move = move; s.rows[i].picture.yours = true }
            if let sound {
                s.rows[i].sound.text = sound; s.rows[i].sound.yours = true
                s.rows[i].seconds = AVScript.seconds(for: s.rows[i].sound)
            }
            if let soundKind { s.rows[i].sound.kind = soundKind; s.rows[i].sound.yours = true; s.rows[i].seconds = AVScript.seconds(for: s.rows[i].sound) }
            if let speaker { s.rows[i].sound.speaker = speaker }
        }
    }

    /// A new, empty row after another (or at the top). Returns its id.
    public func addRow(after id: String?, kind: HeardKind = .voice) throws -> (AVScript, String) {
        let row = AVRow(sound: AVSound(kind: kind, text: ""))
        let s = try changeScript("Added a row") { s in
            var r = row
            let at = id.flatMap { id in s.rows.firstIndex { $0.id == id } }
            r.section = at.map { s.rows[$0].section } ?? s.rows.first?.section
            s.rows.insert(r, at: at.map { $0 + 1 } ?? 0)
        }
        return (s, row.id)
    }

    @discardableResult
    public func removeRow(_ id: String) throws -> AVScript {
        try changeScript("Took out a row") { s in
            guard s.rows.contains(where: { $0.id == id }) else { throw DirectionError("row_not_found", "There\u{2019}s no row \(id).") }
            s.rows.removeAll { $0.id == id }
            for i in s.notes.indices where s.notes[i].state == .written {
                s.notes[i].rowIDs?.removeAll { $0 == id }
                if s.notes[i].rowIDs?.isEmpty == true { s.notes[i].state = .dropped }
            }
        }
    }

    /// Moves a row before another (nil: to the end), into that row's section.
    @discardableResult
    public func moveRow(_ id: String, before other: String?) throws -> AVScript {
        try changeScript("Moved a row") { s in
            guard let from = s.rows.firstIndex(where: { $0.id == id }) else { throw DirectionError("row_not_found", "There\u{2019}s no row \(id).") }
            var row = s.rows.remove(at: from)
            let to = other.flatMap { o in s.rows.firstIndex { $0.id == o } } ?? s.rows.count
            row.section = to < s.rows.count ? s.rows[to].section : s.rows.last?.section ?? row.section
            s.rows.insert(row, at: to)
        }
    }

    @discardableResult
    public func addScriptNote(rowIDs: [String], kind: NoteKind?, text: String) throws -> PrepNote {
        var note: PrepNote!
        try changeScript("Wrote a note on the script") { s in
            let ids = rowIDs.filter { id in s.rows.contains { $0.id == id } }
            guard !ids.isEmpty else { throw DirectionError("row_not_found", "The note has no rows.") }
            note = PrepNote(number: s.nextNoteNumber, rowIDs: ids, kind: kind, text: text)
            s.notes.append(note)
        }
        return note
    }

    @discardableResult
    public func editScriptNote(_ id: String, text: String?, kind: NoteKind?? = nil, drop: Bool = false) throws -> AVScript {
        try changeScript(drop ? "Dropped a note" : "Changed a note") { s in
            guard let i = s.notes.firstIndex(where: { $0.id == id }) else { throw DirectionError("note_not_found", "There\u{2019}s no note \(id).") }
            guard s.notes[i].state == .written else { throw DirectionError("note_turned_over", "Note \(s.notes[i].number) is with the editor.") }
            if drop { s.notes[i].state = .dropped; return }
            if let text { s.notes[i].text = text }
            if let kind { s.notes[i].kind = kind }
        }
    }

    /// Turn over: the written notes go to the editor for a pass.
    @discardableResult
    public func turnOverScriptNotes() throws -> AVScript {
        try changeScript("Turned over notes on the script") { s in
            guard s.notes.contains(where: { $0.state == .written && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw DirectionError("no_notes", "There are no notes to turn over.") }
            for i in s.notes.indices where s.notes[i].state == .written { s.notes[i].state = s.notes[i].text.trimmingCharacters(in: .whitespaces).isEmpty ? .dropped : .turnedOver }
        }
    }

    @discardableResult
    public func answerRowQuestion(_ rowID: String, choiceID: String?, text: String?) throws -> AVScript {
        try changeScript("Answered the editor") { s in
            guard let i = s.rows.firstIndex(where: { $0.id == rowID }), s.rows[i].question != nil else { throw DirectionError("question_not_found", "Row \(rowID) has no question.") }
            s.rows[i].question?.answer = choiceID; s.rows[i].question?.answerText = text?.nilIfEmpty; s.rows[i].question?.answeredAt = Date().timeIntervalSince1970
        }
    }

    /// OK: the script is ready to break down. It can still change; the breakdown follows.
    @discardableResult
    public func okScript() throws -> AVScript {
        try changeScript("OK\u{2019}d the script") { s in
            guard !s.rows.isEmpty else { throw DirectionError("script_empty", "There\u{2019}s no script to OK.") }
            s.okAt = Date().timeIntervalSince1970
            s.okRevision = s.revision + 1
        }
    }

    // MARK: The editor's pass

    /// A new editor pass begins: what it changes is marked as its own.
    @discardableResult
    public func beginScriptPass() throws -> AVScript { try changeScript("The editor started on the script") { $0.pass += 1 } }

    /// The editor writes pictures, answers notes and asks about rows. A row the director typed in, or words
    /// from the script, change only where a turned-over note on that row asks. Returns what it refused.
    public func updateScript(pictures: [PictureInput] = [], sounds: [SoundInput] = [], replies: [String: String] = [:], questions: [String: PrepQuestion] = [:]) throws -> (AVScript, refused: [String]) {
        var refused: [String] = []
        let s = try changeScript("The editor wrote the script\u{2019}s picture") { s in
            let noted = Set(s.notes.filter { $0.state == .turnedOver }.flatMap { $0.rowIDs ?? [] })
            if s.pass == 0 { s.pass = 1 }
            for p in pictures {
                guard let i = s.rows.firstIndex(where: { $0.id == p.rowID }) else { refused.append("\(p.rowID): no such row"); continue }
                if s.rows[i].picture.yours == true, !noted.contains(p.rowID) { refused.append("Row \(i + 1): the director wrote this picture; change it only when a note on the row asks"); continue }
                s.rows[i].picture = AVPicture(text: p.text, size: p.size, move: p.move, board: p.board ?? Self.board(for: p))
                s.rows[i].picture.pass = s.pass
                if s.rows[i].question?.isOpen == false { s.rows[i].question = nil }
            }
            for w in sounds {
                guard let i = s.rows.firstIndex(where: { $0.id == w.rowID }) else { refused.append("\(w.rowID): no such row"); continue }
                if w.text != nil, !noted.contains(w.rowID) { refused.append("Row \(i + 1): the words are the script\u{2019}s; change them only when a note on the row asks"); continue }
                if let k = w.kind { s.rows[i].sound.kind = k }
                if let sp = w.speaker { s.rows[i].sound.speaker = sp.nilIfEmpty }
                if let t = w.text { s.rows[i].sound.text = t }
                s.rows[i].seconds = AVScript.seconds(for: s.rows[i].sound)
            }
            for (id, reply) in replies {
                guard let i = s.notes.firstIndex(where: { $0.id == id || "\($0.number)" == id }) else { refused.append("\(id): no such note"); continue }
                guard s.notes[i].state == .turnedOver else { refused.append("Note \(s.notes[i].number) isn\u{2019}t turned over"); continue }
                s.notes[i].reply = reply; s.notes[i].state = .done
            }
            for (rowID, q) in questions {
                guard let i = s.rows.firstIndex(where: { $0.id == rowID }) else { refused.append("\(rowID): no such row"); continue }
                s.rows[i].question = q
            }
        }
        return (s, refused)
    }

    /// A board for a picture the editor didn't give one.
    static func board(for p: PictureInput) -> BoardKind {
        let t = p.text.lowercased()
        if t.contains("types on") || t.hasPrefix("title") || t.hasPrefix("black.") { return .title }
        if t.contains("screen recording") || t.contains("app ") || t.contains(" app") { return .screen }
        switch p.size { case .wide: return .wide; case .medium: return .medium; case .close: return .close; case .detail: return .detail; case nil: return .medium }
    }

    // MARK: The breakdown, by the editor

    @discardableResult
    public func beginBreakdownPass() throws -> Breakdown { try changeBreakdown("The editor started on the breakdown") { $0.pass += 1 } }

    /// The editor lays out setups and shots. Before the director's OK, shot numbers follow the setups and
    /// the script; after it they're slates and never change, and new shots take the next letter.
    public func updateBreakdown(setups: [SetupInput] = [], shots: [ShotInput] = [], remove: [String] = [], replies: [String: String] = [:], questions: [String: PrepQuestion] = [:]) throws -> (Breakdown, refused: [String]) {
        let script = try self.script() ?? AVScript()
        var refused: [String] = []
        let b = try changeBreakdown("The editor broke down the script") { b in
            let noted = Set(b.notes.filter { $0.state == .turnedOver }.flatMap { $0.shotIDs ?? [] })
            if b.pass == 0 { b.pass = 1 }
            for input in setups {
                if let id = input.id, let i = b.setups.firstIndex(where: { $0.id == id }) {
                    b.setups[i].name = input.name; b.setups[i].needs = input.needs?.nilIfEmpty ?? b.setups[i].needs; b.setups[i].noCamera = input.noCamera ?? b.setups[i].noCamera
                } else if !b.setups.contains(where: { $0.name.caseInsensitiveCompare(input.name) == .orderedSame }) {
                    b.setups.append(BreakdownSetup(id: input.id ?? newID("setup"), number: (b.setups.map(\.number).max() ?? 0) + 1, name: input.name, needs: input.needs?.nilIfEmpty, noCamera: input.noCamera))
                }
            }
            func setupID(_ input: ShotInput) -> String? {
                if let id = input.setupID, b.setups.contains(where: { $0.id == id }) { return id }
                return input.setup.flatMap { name in b.setups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id }
            }
            for input in shots {
                if let id = input.id, let i = b.shots.firstIndex(where: { $0.id == id }) {
                    var shot = b.shots[i]
                    let mayChange = { (field: String) in !shot.isYours(field) || noted.contains(id) }
                    if let v = input.what, mayChange("what") { shot.what = v }
                    if let v = input.size, mayChange("size") { shot.size = v }
                    if let v = input.move, mayChange("move") { shot.move = v }
                    if let v = input.seconds { shot.seconds = v }
                    if let v = input.source, mayChange("source") { shot.source = v }
                    if let v = input.board { shot.board = v }
                    if let v = input.rowIDs { shot.rowIDs = v.filter { r in script.rows.contains { $0.id == r } } }
                    if let v = setupID(input), v != shot.setupID {
                        if b.isOK { refused.append("\(shot.code): its number is its slate now; add a new shot in the other setup instead") } else { shot.setupID = v }
                    }
                    if input.makePlan != nil { shot.makePlan = input.makePlan?.nilIfEmpty }
                    if input.estimate != nil { shot.estimate = input.estimate }
                    shot.pass = b.pass
                    if shot.question?.isOpen == false { shot.question = nil }
                    b.shots[i] = shot
                } else {
                    guard let sid = setupID(input) else { refused.append("\(input.what ?? "A shot"): name a setup from this breakdown"); continue }
                    let rows = (input.rowIDs ?? []).filter { r in script.rows.contains { $0.id == r } }
                    let seconds = input.seconds ?? rows.compactMap { r in script.row(r)?.seconds }.reduce(0, +)
                    var shot = BreakdownShot(id: input.id ?? newID("shot"), setupID: sid, rowIDs: rows, what: input.what ?? "", size: input.size, move: input.move, seconds: max(seconds, 1), source: input.source ?? .shoot, board: input.board)
                    shot.makePlan = input.makePlan?.nilIfEmpty; shot.estimate = input.estimate; shot.pass = b.pass
                    if b.isOK { shot.addedAfterOK = true }
                    b.shots.append(shot)
                }
            }
            for id in remove {
                guard let shot = b.shot(id) else { continue }
                if b.isOK, shot.isYours("source") || shot.haveAssetID != nil { refused.append("\(shot.code): the director set this one up; ask before taking it out"); continue }
                b.shots.removeAll { $0.id == id }
            }
            // Setups stay while they're empty: the editor lays them out first and fills them a page at a time.
            for (id, reply) in replies {
                guard let i = b.notes.firstIndex(where: { $0.id == id || "\($0.number)" == id }) else { refused.append("\(id): no such note"); continue }
                guard b.notes[i].state == .turnedOver else { refused.append("Note \(b.notes[i].number) isn\u{2019}t turned over"); continue }
                b.notes[i].reply = reply; b.notes[i].state = .done
            }
            for (shotID, q) in questions {
                guard let i = b.shots.firstIndex(where: { $0.id == shotID }) else { refused.append("\(shotID): no such shot"); continue }
                b.shots[i].question = q
            }
            Self.number(&b, script: script)
            b.scriptRevision = script.revision
        }
        return (b, refused)
    }

    /// Setups numbered in the order they're first needed (no-camera ones after), shots lettered by their first
    /// row. Once OK'd, numbers already given stay, so slates never change.
    static func number(_ b: inout Breakdown, script: AVScript) {
        func firstRow(_ shot: BreakdownShot) -> Int { shot.rowIDs.compactMap { script.number(of: $0) }.min() ?? Int.max }
        func firstRow(setup: BreakdownSetup) -> Int { b.shots.filter { $0.setupID == setup.id }.map(firstRow).min() ?? Int.max }
        if !b.isOK {
            let ordered = b.setups.sorted { a, c in
                let (na, nc) = (a.noCamera == true, c.noCamera == true)
                return na != nc ? !na : firstRow(setup: a) < firstRow(setup: c)
            }
            b.setups = ordered.enumerated().map { i, s in var s = s; s.number = i + 1; return s }
            for setup in b.setups {
                let mine = b.shots.indices.filter { b.shots[$0].setupID == setup.id }.sorted { firstRow(b.shots[$0]) < firstRow(b.shots[$1]) }
                for (n, i) in mine.enumerated() { b.shots[i].code = "\(setup.number)\(letter(n))" }
            }
        } else {
            for i in b.shots.indices where b.shots[i].code.isEmpty {
                guard let setup = b.setup(b.shots[i].setupID) else { continue }
                let used = Set(b.shots.filter { $0.setupID == setup.id }.map(\.code))
                b.shots[i].code = (0..<26).map { "\(setup.number)\(letter($0))" }.first { !used.contains($0) } ?? "\(setup.number)\(b.shots.count)"
            }
        }
        let setupNumber = Dictionary(b.setups.map { ($0.id, $0.number) }, uniquingKeysWith: { a, _ in a })
        b.shots.sort { a, c in (setupNumber[a.setupID] ?? 0, a.code.count, a.code) < (setupNumber[c.setupID] ?? 0, c.code.count, c.code) }
    }

    static func letter(_ n: Int) -> String { n < 26 ? String(UnicodeScalar(UInt8(65 + n))) : "Z\(n - 25)" }

    // MARK: The breakdown, by the director

    @discardableResult
    public func editShot(_ id: String, what: String? = nil, size: ShotSize?? = nil, move: ShotMove?? = nil, source: ShotSource? = nil) throws -> Breakdown {
        try changeBreakdown("Changed a shot") { b in
            guard let i = b.shots.firstIndex(where: { $0.id == id }) else { throw DirectionError("shot_not_found", "There\u{2019}s no shot \(id).") }
            var yours = Set(b.shots[i].yours ?? [])
            if let what { b.shots[i].what = what; yours.insert("what") }
            if let size { b.shots[i].size = size; yours.insert("size") }
            if let move { b.shots[i].move = move; yours.insert("move") }
            if let source { b.shots[i].source = source; yours.insert("source"); if source != .have { b.shots[i].haveAssetID = nil; b.shots[i].haveRange = nil } }
            b.shots[i].yours = yours.sorted()
        }
    }

    /// Have it: footage the director already has plays as this shot. It's filed in Dailies under the shot.
    @discardableResult
    public func attachFootage(shotID: String, assetID: String, range: MediaRange? = nil) throws -> Breakdown {
        _ = try read().asset(assetID)
        let b = try changeBreakdown("Added footage you have") { b in
            guard let i = b.shots.firstIndex(where: { $0.id == shotID }) else { throw DirectionError("shot_not_found", "There\u{2019}s no shot \(shotID).") }
            b.shots[i].source = .have; b.shots[i].haveAssetID = assetID; b.shots[i].haveRange = range
            b.shots[i].yours = Array(Set((b.shots[i].yours ?? []) + ["source"])).sorted()
        }
        if let shot = b.shot(shotID) { try file(assetID: assetID, in: shot, take: nil, breakdown: b) }
        return b
    }

    @discardableResult
    public func decideMissing(shotID: String, _ choice: MissingChoice?) throws -> Breakdown {
        try changeBreakdown("Decided about a missing shot") { b in
            guard let i = b.shots.firstIndex(where: { $0.id == shotID }) else { throw DirectionError("shot_not_found", "There\u{2019}s no shot \(shotID).") }
            b.shots[i].missing = choice
        }
    }

    @discardableResult
    public func addBreakdownNote(shotIDs: [String], kind: NoteKind?, text: String) throws -> PrepNote {
        var note: PrepNote!
        try changeBreakdown("Wrote a note on the breakdown") { b in
            let ids = shotIDs.filter { id in b.shots.contains { $0.id == id } }
            guard !ids.isEmpty else { throw DirectionError("shot_not_found", "The note has no shots.") }
            note = PrepNote(number: b.nextNoteNumber, shotIDs: ids, kind: kind, text: text)
            b.notes.append(note)
        }
        return note
    }

    @discardableResult
    public func editBreakdownNote(_ id: String, text: String?, drop: Bool = false) throws -> Breakdown {
        try changeBreakdown(drop ? "Dropped a note" : "Changed a note") { b in
            guard let i = b.notes.firstIndex(where: { $0.id == id }) else { throw DirectionError("note_not_found", "There\u{2019}s no note \(id).") }
            guard b.notes[i].state == .written else { throw DirectionError("note_turned_over", "Note \(b.notes[i].number) is with the editor.") }
            if drop { b.notes[i].state = .dropped } else if let text { b.notes[i].text = text }
        }
    }

    @discardableResult
    public func turnOverBreakdownNotes() throws -> Breakdown {
        try changeBreakdown("Turned over notes on the breakdown") { b in
            guard b.notes.contains(where: { $0.state == .written && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw DirectionError("no_notes", "There are no notes to turn over.") }
            for i in b.notes.indices where b.notes[i].state == .written { b.notes[i].state = b.notes[i].text.trimmingCharacters(in: .whitespaces).isEmpty ? .dropped : .turnedOver }
        }
    }

    @discardableResult
    public func answerShotQuestion(_ shotID: String, choiceID: String?, text: String?) throws -> Breakdown {
        try changeBreakdown("Answered the editor") { b in
            guard let i = b.shots.firstIndex(where: { $0.id == shotID }), b.shots[i].question != nil else { throw DirectionError("question_not_found", "Shot \(shotID) has no question.") }
            b.shots[i].question?.answer = choiceID; b.shots[i].question?.answerText = text?.nilIfEmpty; b.shots[i].question?.answeredAt = Date().timeIntervalSince1970
        }
    }

    /// OK: shot numbers become slates, and Dailies gets a scene per setup and a setup per shot.
    @discardableResult
    public func okBreakdown() throws -> Breakdown {
        try changeBreakdown("OK\u{2019}d the breakdown") { b in
            guard !b.shots.isEmpty else { throw DirectionError("breakdown_empty", "There are no shots to OK.") }
            b.setups.removeAll { s in !b.shots.contains { $0.setupID == s.id } }
            b.okAt = Date().timeIntervalSince1970
        }
    }

    // MARK: Dailies, coverage, slates

    static func sceneID(_ setup: BreakdownSetup) -> String { "scene-" + setup.id }

    /// Each setup a Dailies scene, each shot a setup in it, so takes, circles and the assembly work as always.
    func fillDailies(from b: Breakdown) throws {
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Laid out Dailies from the breakdown") { d in
            for setup in b.setups.sorted(by: { $0.number < $1.number }) {
                let id = Self.sceneID(setup), setups = b.shots(in: setup.id).map { DailiesSetup(code: $0.code, description: $0.what) }
                if let i = d.scenes.firstIndex(where: { $0.id == id }) { d.scenes[i].number = setup.number; d.scenes[i].title = setup.name; d.scenes[i].setups = setups }
                else { d.scenes.append(DailiesScene(id: id, number: setup.number, title: setup.name, setups: setups)) }
            }
            let ours = Set(b.setups.map(Self.sceneID))
            let used = Set(d.takes.values.compactMap(\.sceneID))
            d.scenes.removeAll { $0.id.hasPrefix("scene-setup-") && !ours.contains($0.id) && !used.contains($0.id) }
            d.scenes.sort { $0.number < $1.number }
        }
    }

    /// Puts a take in its shot's setup in Dailies, numbered by its slate or next in line.
    func file(assetID: String, in shot: BreakdownShot, take: Int?, breakdown b: Breakdown) throws {
        guard let setup = b.setup(shot.setupID) else { return }
        try mutate(DirectingKey.dailies, default: Dailies(), kind: "dailies.updated", summary: "Filed \(shot.code) by its slate") { d in
            var t = d.takes[assetID] ?? { var t = TakeInfo(assetID: assetID); t.unlogged = true; return t }()
            t.sceneID = Self.sceneID(setup); t.setupCode = shot.code
            let taken = d.takes.values.filter { $0.setupCode == shot.code && $0.assetID != assetID }.compactMap { $0.code.flatMap { Int($0.dropFirst()) } }
            t.code = "T\(take ?? ((taken.max() ?? 0) + 1))"
            d.takes[assetID] = t
        }
    }

    /// Takes whose slate (said at the head, or in the file name) names a shot go to it. Returns asset → shot.
    @discardableResult
    public func fileBySlate() throws -> [String: String] {
        guard let b = try breakdown(), b.isOK else { return [:] }
        let p = try read(), dailies = try dailies()
        let open = p.footage(film: url).filter { dailies.takes[$0.id]?.setupCode == nil }
        guard !open.isEmpty else { return [:] }
        let transcripts = Dictionary(try transcripts().map { ($0.assetID, $0) }, uniquingKeysWith: { a, _ in a })
        var filed: [String: String] = [:]
        for asset in open {
            let head = transcripts[asset.id]?.words.filter { $0.range.start.seconds < Slate.headSeconds }.map(\.text) ?? []
            guard let mark = Slate.spoken(head) ?? Slate.fileName(asset.name), let shot = b.shot(code: mark.code) else { continue }
            try file(assetID: asset.id, in: shot, take: mark.take, breakdown: b)
            filed[asset.id] = shot.code
        }
        return filed
    }

    public func coverage() throws -> [String: ShotCoverage] {
        guard let b = try breakdown() else { return [:] }
        return Self.coverage(b, dailies: try dailies())
    }

    /// How each shot stands (specs/breakdown.md › Coverage). A shot is missing once its setup has been shot.
    public static func coverage(_ b: Breakdown, dailies: Dailies) -> [String: ShotCoverage] {
        let takes = Dictionary(grouping: dailies.takes.values.filter { !$0.unusable && $0.setupCode != nil }) { $0.setupCode!.uppercased() }
        var out: [String: ShotCoverage] = [:]
        for shot in b.shots {
            if let t = takes[shot.code.uppercased()], !t.isEmpty {
                out[shot.id] = .got(t.sorted { ($0.circled ? 0 : 1, $0.code ?? "") < ($1.circled ? 0 : 1, $1.code ?? "") }.map(\.assetID))
                continue
            }
            switch shot.source {
            case .have: out[shot.id] = .needsFootage
            case .make: out[shot.id] = .toMake
            default:
                let shotInSetup = b.shots(in: shot.setupID).contains { takes[$0.code.uppercased()]?.isEmpty == false }
                out[shot.id] = shotInSetup ? .missing : .planned
            }
        }
        return out
    }
}
