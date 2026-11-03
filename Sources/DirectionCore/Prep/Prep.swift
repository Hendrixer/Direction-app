import Foundation

// Prep (specs/script.md, specs/breakdown.md): the A/V script a film starts from, and the breakdown of it into
// shots by setup. Both live in the film's directing table, beside the brief and the dailies.

/// What a row's sound is.
public enum HeardKind: String, Codable, CaseIterable, Sendable {
    /// Voice-over: recorded on its own, the picture cut to it.
    case voice
    /// Someone talking in shot, with their own sound.
    case onCamera
    /// A sound cue: room tone, a hit, a whoosh.
    case effect
    case music
    case silence
    public var label: String { switch self { case .voice: "VO"; case .onCamera: "On camera"; case .effect: "Sound"; case .music: "Music"; case .silence: "Silence" } }
}

public enum ShotSize: String, Codable, CaseIterable, Sendable {
    case wide, medium, close, detail
    public var label: String { rawValue.capitalized }
}

public enum ShotMove: String, Codable, CaseIterable, Sendable {
    case still, push, pull, pan, tilt, handheld, track
    public var label: String { switch self { case .push: "Slow push"; case .pull: "Pull out"; default: rawValue.capitalized } }
}

/// What a drawn board shows (the board style: line drawings, plainly not footage).
public enum BoardKind: String, Codable, CaseIterable, Sendable {
    case title, screen, wide, medium, close, detail, onCamera, action, made, empty
}

/// The picture half of a row: what we see, not how it's shot.
public struct AVPicture: Codable, Hashable, Sendable {
    public var text: String = ""
    public var size: ShotSize?
    public var move: ShotMove?
    public var board: BoardKind?
    /// The director typed it. The editor leaves it alone unless a note on the row asks.
    public var yours: Bool?
    /// The editor pass that last changed it, so the room can show what changed.
    public var pass: Int?
    public init(text: String = "", size: ShotSize? = nil, move: ShotMove? = nil, board: BoardKind? = nil) { self.text = text; self.size = size; self.move = move; self.board = board }
    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct AVSound: Codable, Hashable, Sendable {
    public var kind: HeardKind = .voice
    /// Who speaks on camera, or the voice's name.
    public var speaker: String?
    public var text: String = ""
    public var yours: Bool?
    /// Said in the speaker's own words, found on the day: the text says what about, not the words.
    public var ownWords: Bool?
    public init(kind: HeardKind = .voice, speaker: String? = nil, text: String = "") { self.kind = kind; self.speaker = speaker; self.text = text }
}

/// The editor asking about a row or a shot, with the director's answer.
public struct PrepQuestion: Codable, Hashable, Sendable {
    public struct Choice: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var detail: String?
        public var recommended: Bool?
        public init(id: String, label: String, detail: String? = nil, recommended: Bool? = nil) { self.id = id; self.label = label; self.detail = detail; self.recommended = recommended }
    }
    public var id: String
    public var text: String
    public var choices: [Choice]
    public var answer: String?
    public var answerText: String?
    public var answeredAt: Double?
    public var createdAt: Double
    public init(id: String = newID("ask"), text: String, choices: [Choice], createdAt: Double = Date().timeIntervalSince1970) { self.id = id; self.text = text; self.choices = choices; self.createdAt = createdAt }
    public var isOpen: Bool { answeredAt == nil }
}

public struct AVRow: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var section: String?
    public var picture: AVPicture
    public var sound: AVSound
    /// How long it plays, from its words (2.5 a second) until the narration is recorded.
    public var seconds: Double
    /// A picture the writer had in mind ("[me at the desk]"), for the editor to start from.
    public var hint: String?
    /// A film from a story: the part of the story this beat came from.
    public var story: String?
    public var question: PrepQuestion?
    public init(id: String = newID("row"), section: String? = nil, picture: AVPicture = .init(), sound: AVSound, seconds: Double? = nil, hint: String? = nil, story: String? = nil) {
        self.id = id; self.section = section; self.picture = picture; self.sound = sound; self.hint = hint; self.story = story
        self.seconds = seconds ?? AVScript.seconds(for: sound)
    }
    /// Words someone says as written: the row's time comes from them.
    public var hasWrittenWords: Bool { [.voice, .onCamera].contains(sound.kind) && sound.ownWords != true && !sound.text.isEmpty }
    /// Nobody has said yet what we hear (a beat of a story, before the editor's pass).
    public var soundUndecided: Bool { sound.text.isEmpty && sound.kind == .voice && sound.speaker == nil && sound.yours != true }
    /// What plays under it, in words: what's said or heard, or the part of the story.
    public var line: String { sound.text.isEmpty ? story ?? "" : sound.text }
}

/// What a film's A/V script was laid out from: a script, whose words are said as written, or a story, where
/// the editor writes what we hear as well as what we see and nobody's words are written for them.
public enum ScriptKind: String, Codable, Sendable {
    case script, story
}

public struct AVSection: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public init(id: String = newID("section"), title: String) { self.id = id; self.title = title }
}

public enum PrepNoteState: String, Codable, Sendable { case written, turnedOver, done, dropped }

/// A note on rows of the script or shots of the breakdown. It waits on the sheet until Turn over.
public struct PrepNote: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var rowIDs: [String]?
    public var shotIDs: [String]?
    public var kind: NoteKind?
    public var text: String
    public var state: PrepNoteState
    /// The editor's answer, first person ("Row 4 is your hands now").
    public var reply: String?
    public var createdAt: Double
    public init(id: String = newID("prepnote"), number: Int, rowIDs: [String]? = nil, shotIDs: [String]? = nil, kind: NoteKind? = nil, text: String, state: PrepNoteState = .written, createdAt: Double = Date().timeIntervalSince1970) {
        self.id = id; self.number = number; self.rowIDs = rowIDs; self.shotIDs = shotIDs; self.kind = kind; self.text = text; self.state = state; self.createdAt = createdAt
    }
}

/// Where the words came from.
public struct ScriptSource: Codable, Hashable, Sendable {
    public var fileName: String
    public var path: String?
    public var words: Int
    public var importedAt: Double
    public init(fileName: String, path: String?, words: Int, importedAt: Double) { self.fileName = fileName; self.path = path; self.words = words; self.importedAt = importedAt }
}

public struct AVScript: Codable, Hashable, Sendable {
    public var sections: [AVSection] = []
    public var rows: [AVRow] = []
    public var notes: [PrepNote] = []
    public var source: ScriptSource?
    /// Laid out from a story (nil: a script).
    public var kind: ScriptKind?
    /// What a story says around the beats the writer numbered (the idea, its rules, questions for the
    /// director), as written: the editor reads it with the beats, and it never becomes rows.
    public var storyNotes: String?
    /// Every change counts up, so the breakdown knows when the script moved on after it.
    public var revision = 0
    /// Editor passes so far: 1 is the first picture column.
    public var pass = 0
    public var okAt: Double?
    public var okRevision: Int?
    public var updatedAt: Double?
    public init() {}

    public var isOK: Bool { okAt != nil }
    public var isStory: Bool { kind == .story }
    /// Changed since the director OK'd it.
    public var changedSinceOK: Bool { okRevision.map { revision > $0 } ?? false }
    public var openNotes: [PrepNote] { notes.filter { $0.state == .written } }
    public var turnedOver: [PrepNote] { notes.filter { $0.state == .turnedOver } }
    public var openQuestions: [AVRow] { rows.filter { $0.question?.isOpen == true } }
    public var seconds: Double { rows.reduce(0) { $0 + $1.seconds } }
    public var words: Int { rows.reduce(0) { $0 + Self.wordCount($1.sound.text) } }
    public func row(_ id: String) -> AVRow? { rows.first { $0.id == id } }
    /// 1-based, in script order.
    public func number(of rowID: String) -> Int? { rows.firstIndex { $0.id == rowID }.map { $0 + 1 } }
    public var nextNoteNumber: Int { (notes.map(\.number).max() ?? 0) + 1 }

    static func wordCount(_ s: String) -> Int { s.split { $0.isWhitespace }.count }
    /// Spoken words at 2.5 a second; a cue with no words, or talk in someone's own words, holds two seconds.
    public static func seconds(for sound: AVSound) -> Double {
        let n = wordCount(sound.text)
        guard [.voice, .onCamera].contains(sound.kind), sound.ownWords != true, n > 0 else { return 2 }
        return max(1.5, (Double(n) / 2.5 * 2).rounded() / 2)
    }
}

/// Where a shot's picture comes from.
public enum ShotSource: String, Codable, CaseIterable, Sendable {
    case shoot, screen, make, have, sound
    public var label: String { switch self { case .shoot: "Shoot"; case .screen: "Screen"; case .make: "Make"; case .have: "Have it"; case .sound: "Sound" } }
}

/// What to do about a shot that didn't come in.
public enum MissingChoice: String, Codable, Sendable { case make, pickup, without }

public struct BreakdownSetup: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The first half of every shot number in it: 2 for 2A, 2B…
    public var number: Int
    public var name: String
    /// What it takes: "After dark · lamp off · the chat app open on the monitor".
    public var needs: String?
    /// Screen recordings, made shots, footage you have: nothing to set up a camera for.
    public var noCamera: Bool?
    public init(id: String = newID("setup"), number: Int, name: String, needs: String? = nil, noCamera: Bool? = nil) { self.id = id; self.number = number; self.name = name; self.needs = needs; self.noCamera = noCamera }
}

public struct BreakdownShot: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The slate: setup number and letter, 2C. Fixed once the breakdown is OK'd.
    public var code: String
    public var setupID: String
    public var rowIDs: [String]
    public var what: String
    public var size: ShotSize?
    public var move: ShotMove?
    public var seconds: Double
    public var source: ShotSource
    public var board: BoardKind?
    /// Have it: the footage, and the part of it that plays.
    public var haveAssetID: String?
    public var haveRange: MediaRange?
    /// Make: how the editor will make it, and what it should cost (nil: free, like a graphic).
    public var makePlan: String?
    public var estimate: Double?
    public var missing: MissingChoice?
    public var question: PrepQuestion?
    /// Fields the director set by hand; the editor leaves them alone unless a note on the shot asks.
    public var yours: [String]?
    /// The editor pass that last changed it.
    public var pass: Int?
    /// Added after the breakdown was OK'd.
    public var addedAfterOK: Bool?
    public init(id: String = newID("shot"), code: String = "", setupID: String, rowIDs: [String], what: String, size: ShotSize? = nil, move: ShotMove? = nil, seconds: Double, source: ShotSource, board: BoardKind? = nil) {
        self.id = id; self.code = code; self.setupID = setupID; self.rowIDs = rowIDs; self.what = what; self.size = size; self.move = move; self.seconds = seconds; self.source = source; self.board = board
    }
    func isYours(_ field: String) -> Bool { yours?.contains(field) == true }
}

public struct Breakdown: Codable, Hashable, Sendable {
    public var setups: [BreakdownSetup] = []
    public var shots: [BreakdownShot] = []
    public var notes: [PrepNote] = []
    /// The script revision it was last made from.
    public var scriptRevision: Int?
    public var pass = 0
    public var okAt: Double?
    public var updatedAt: Double?
    public init() {}

    public var isOK: Bool { okAt != nil }
    public var openNotes: [PrepNote] { notes.filter { $0.state == .written } }
    public var turnedOver: [PrepNote] { notes.filter { $0.state == .turnedOver } }
    public func shot(_ id: String) -> BreakdownShot? { shots.first { $0.id == id } }
    public func setup(_ id: String) -> BreakdownSetup? { setups.first { $0.id == id } }
    public func shots(in setupID: String) -> [BreakdownShot] { shots.filter { $0.setupID == setupID }.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending } }
    public func shot(code: String) -> BreakdownShot? { shots.first { $0.code.caseInsensitiveCompare(code) == .orderedSame } }
    public var nextNoteNumber: Int { (notes.map(\.number).max() ?? 0) + 1 }
    /// What making costs, for shots still to make.
    public var estimate: Double { shots.filter { $0.source == .make }.compactMap(\.estimate).reduce(0, +) }
}

/// How a shot stands against the footage (specs/breakdown.md › Coverage).
public enum ShotCoverage: Hashable, Sendable {
    /// Nothing shot for its setup yet.
    case planned
    /// Takes are in: their asset ids, circled first.
    case got([String])
    /// Its setup was shot and it wasn't.
    case missing
    /// Have it, but the footage isn't added.
    case needsFootage
    case toMake
    public var isIn: Bool { if case .got = self { return true }; return false }
}
