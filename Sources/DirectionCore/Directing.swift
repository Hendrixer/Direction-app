import Foundation

// The director–editor relationship: brief, dailies, numbered notes, turnovers,
// read-backs, questions and answers. Editing itself stays in Editing.swift; these
// records describe who asked for what and what the editor did about it.

public enum NoteKind: String, Codable, CaseIterable, Sendable {
    case feeling, story, pace, picture, sound
    public var label: String { rawValue.capitalized }
    /// Murch's order: a higher kind wins when two notes pull against each other.
    public var priority: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

public enum Latitude: String, Codable, CaseIterable, Sendable {
    case exact, faithful, free
    public var label: String {
        switch self { case .exact: "Do what I wrote"; case .faithful: "Read between the lines"; case .free: "Take a pass" }
    }
    public var detail: String {
        switch self {
        case .exact: "Change only what each note names. No options."
        case .faithful: "Interpret the intent. Try Feeling notes two ways."
        case .free: "Also suggest changes you didn't ask for, marked Unasked."
        }
    }
}

public struct BriefReference: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var why: String
    public var path: String?
    public init(id: String = newID("ref"), title: String, why: String, path: String? = nil) { self.id = id; self.title = title; self.why = why; self.path = path }
}

public struct Brief: Codable, Hashable, Sendable {
    public var logline: String = ""
    public var feeling: String = ""
    public var lengthMin: Double?
    public var lengthMax: Double?
    public var audience: String?
    public var mustKeep: [String] = []
    public var references: [BriefReference] = []
    public var avoid: String?
    /// The style it's cut in (styles.md): a folder in the Styles folder, copied into the film as Style/.
    public var style: String?
    public var updatedAt: Double?
    public init() {}
    public var isComplete: Bool { !logline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !feeling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct DailiesSetup: Codable, Hashable, Sendable {
    public var code: String
    public var description: String
    public init(code: String, description: String) { self.code = code; self.description = description }
}

public struct DailiesScene: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var setups: [DailiesSetup]
    public var locked: Bool
    public var lockedAt: Double?
    public init(id: String = newID("scene"), number: Int, title: String, setups: [DailiesSetup] = [], locked: Bool = false) { self.id = id; self.number = number; self.title = title; self.setups = setups; self.locked = locked }
    public var label: String { "\(number) \(title)" }
}

/// What the editor logged about one take. The asset is the take.
public struct TakeInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String { assetID }
    public var assetID: String
    public var sceneID: String?
    public var setupCode: String?
    public var code: String?
    public var caption: String?
    /// Only the director sets this.
    public var circled: Bool = false
    public var circledAt: Double?
    /// The editor's recommendation and its reason. Never a circle.
    public var suggestion: String?
    /// The editor's guess for unsorted takes.
    public var guessSceneID: String?
    public var flags: [String] = []
    public var unusable: Bool = false
    public init(assetID: String) { self.assetID = assetID }
}

public struct Dailies: Codable, Hashable, Sendable {
    public var scenes: [DailiesScene] = []
    public var takes: [String: TakeInfo] = [:]
    public var updatedAt: Double?
    /// Takes that recorded the same moment, found by their sound (footage-index.md › Sync).
    public var syncGroups: [SyncGroup]?
    /// Takes whose sound has been compared, so new footage is compared only against what's there.
    public var syncChecked: [String]?
    /// Pairs the director said aren't in sync; never linked again.
    public var notInSync: [[String]]?
    public init() {}
    public init(scenes: [DailiesScene], takes: [String: TakeInfo]) { self.scenes = scenes; self.takes = takes }
    public func take(_ assetID: String) -> TakeInfo { takes[assetID] ?? TakeInfo(assetID: assetID) }
    public func syncGroup(for assetID: String?) -> SyncGroup? { assetID.flatMap { id in syncGroups?.first { $0.take(id) != nil } } }
    /// The same moment in another take: `time` in `from`'s source seconds, as `to`'s source seconds.
    /// The same take maps to itself; takes that aren't in sync map to nothing.
    public func syncedTime(_ time: Double, from: String, to: String) -> Double? {
        if from == to { return time }
        guard let g = syncGroup(for: from), let a = g.take(from), let b = g.take(to) else { return nil }
        return time + a.offset - b.offset
    }
    public func scene(for assetID: String?) -> DailiesScene? { assetID.flatMap { takes[$0]?.sceneID }.flatMap { id in scenes.first { $0.id == id } } }
    public var lockedAssetIDs: Set<String> {
        let locked = Set(scenes.filter(\.locked).map(\.id))
        return Set(takes.values.filter { $0.sceneID.map(locked.contains) ?? false }.map(\.assetID))
    }
}

/// Takes that recorded the same moment: two cameras, a camera and a screen recording, a camera
/// and a sound recorder. Their clocks line up as: sound take's time = take's time + offset.
public struct SyncGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The take whose sound the cut uses. Its offset is 0.
    public var soundAssetID: String
    public var takes: [SyncedTake]
    /// "sound": their sound matched.
    public var method: String
    public var createdAt: Double
    public init(id: String, soundAssetID: String, takes: [SyncedTake], method: String, createdAt: Double) { self.id = id; self.soundAssetID = soundAssetID; self.takes = takes; self.method = method; self.createdAt = createdAt }
    public func take(_ assetID: String) -> SyncedTake? { takes.first { $0.assetID == assetID } }
}

public struct SyncedTake: Codable, Hashable, Sendable {
    public var assetID: String
    /// Seconds: sound take's time = this take's time + offset.
    public var offset: Double
    /// How closely its sound matched, 0–1.
    public var match: Double
    public init(assetID: String, offset: Double, match: Double) { self.assetID = assetID; self.offset = offset; self.match = match }
}

public enum NoteState: String, Codable, Sendable {
    case draft, written, turnedOver, answered, accepted, reopened, dropped
}

public enum ScriptGesture: String, Codable, Sendable { case strike, hold, move, reading }

public struct ScriptAction: Codable, Hashable, Sendable {
    public var gesture: ScriptGesture
    public var lineText: String
    public var lineLabel: String?
    public var afterText: String?
    public var takeAssetID: String?
    public init(gesture: ScriptGesture, lineText: String, lineLabel: String? = nil, afterText: String? = nil, takeAssetID: String? = nil) { self.gesture = gesture; self.lineText = lineText; self.lineLabel = lineLabel; self.afterText = afterText; self.takeAssetID = takeAssetID }
}

public struct Person: Codable, Hashable, Sendable {
    public var name: String
    public var role: String?
    public init(name: String, role: String? = nil) { self.name = name; self.role = role }
    public var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
}

public struct NoteOption: Codable, Hashable, Sendable {
    public var label: String
    public var summary: String
    public var revision: Int?
    public var cutID: String?
    public var delta: String?
    public init(label: String, summary: String, revision: Int? = nil, cutID: String? = nil, delta: String? = nil) { self.label = label; self.summary = summary; self.revision = revision; self.cutID = cutID; self.delta = delta }
}

/// What the editor did for one note in one cut.
/// A rule the editor offers with an answer: the note said something the director wants every time.
public struct RuleSuggestion: Codable, Hashable, Sendable {
    public var text: String
    public var area: String?
    /// style (this film's style) or house (every film).
    public var scope: String?
    /// Rules this one takes the place of, by id, in the film's style or the house style.
    public var replaces: [String]?
    public init(text: String, area: String? = nil, scope: String? = nil, replaces: [String]? = nil) { self.text = text; self.area = area; self.scope = scope; self.replaces = replaces }
}

/// A rule the director kept from an answer, and the style it went into.
public struct KeptRule: Codable, Hashable, Sendable {
    public var id: String
    public var styleID: String
    public var styleName: String
    public init(id: String, styleID: String, styleName: String) { self.id = id; self.styleID = styleID; self.styleName = styleName }
}

public struct NoteAnswer: Codable, Hashable, Sendable {
    public var cutID: String
    public var revision: Int
    public var summary: String
    public var delta: String?
    /// Where the change is in the new cut, for Play changes.
    public var range: MediaRange?
    public var options: [NoteOption]?
    public var preferred: String?
    public var pick: String?
    /// The option the cut plays, once the director has used one (Use A / Use B puts it in).
    public var inCut: String?
    public var state: String = "unreviewed"
    public var createdAt: Double
    /// A lasting rule the editor read in the note, offered for the director to keep (styles.md › Keep as a rule).
    public var rule: RuleSuggestion?
    /// Where the director kept it.
    public var keptRule: KeptRule?
    public init(cutID: String, revision: Int, summary: String, delta: String? = nil, range: MediaRange? = nil, options: [NoteOption]? = nil, preferred: String? = nil, createdAt: Double = Date().timeIntervalSince1970) {
        self.cutID = cutID; self.revision = revision; self.summary = summary; self.delta = delta; self.range = range; self.options = options; self.preferred = preferred; self.createdAt = createdAt
    }

    /// The option the cut plays now. Until the director uses one, it's the version the editor delivered:
    /// the option without its own revision, or else the one committed last.
    public var optionInCut: String? {
        guard let options, !options.isEmpty else { return nil }
        if let inCut { return inCut }
        let unkept = options.filter { $0.revision == nil }
        if unkept.count == 1 { return unkept[0].label }
        if unkept.isEmpty { return options.max { $0.revision! < $1.revision! }?.label }
        return pick ?? preferred ?? options.first?.label
    }
}

public enum TurnoverState: String, Codable, Sendable {
    /// Turned over; the editor hasn't picked it up yet.
    case waiting
    /// The editor posted a read-back and waits for the director's OK.
    case readBack
    case cutting, blocked, failed, delivered, cancelled
    public var isOpen: Bool { ![.delivered, .cancelled].contains(self) }
}

public struct Conflict: Codable, Hashable, Sendable {
    public var withNoteID: String
    public var following: String
    public var range: String?
    public var detail: String?
    public init(withNoteID: String, following: String, range: String? = nil, detail: String? = nil) { self.withNoteID = withNoteID; self.following = following; self.range = range; self.detail = detail }
}

public struct ReadBackLine: Codable, Hashable, Sendable {
    public var noteID: String
    public var plan: String
    public var delta: String?
    public var twoWays: Bool = false
    public var conflict: Conflict?
    public var cantYet: String?
    public init(noteID: String, plan: String, delta: String? = nil, twoWays: Bool = false, conflict: Conflict? = nil, cantYet: String? = nil) { self.noteID = noteID; self.plan = plan; self.delta = delta; self.twoWays = twoWays; self.conflict = conflict; self.cantYet = cantYet }
}

public enum NoteProgress: String, Codable, Sendable { case queued, working, done, cant, stopped }

public struct Turnover: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    /// "notes" for a notes session, "assembly" for the first cut from circles.
    public var kind: String
    public var noteIDs: [String]
    public var baseRevision: Int
    public var baseCutID: String?
    public var sequenceID: String?
    public var latitude: Latitude
    public var waitForOK: Bool
    public var state: TurnoverState
    public var readBack: [ReadBackLine] = []
    public var readBackApproved: Bool = false
    /// Director corrections to read-back lines, by note ID. The editor rewrites those lines.
    public var adjustments: [String: String] = [:]
    /// Conflicts the director flipped, by note ID of the line that carried the conflict.
    public var flipped: [String] = []
    public var progress: [String: NoteProgress] = [:]
    public var phase: String?
    public var percent: Double?
    public var message: String?
    public var resultCutID: String?
    public var createdAt: Double
    public var updatedAt: Double
    public init(id: String, number: Int, kind: String, noteIDs: [String], baseRevision: Int, baseCutID: String?, sequenceID: String?, latitude: Latitude, waitForOK: Bool, state: TurnoverState, readBack: [ReadBackLine] = [], readBackApproved: Bool = false, progress: [String: NoteProgress] = [:], resultCutID: String? = nil, createdAt: Double, updatedAt: Double) {
        self.id = id; self.number = number; self.kind = kind; self.noteIDs = noteIDs; self.baseRevision = baseRevision; self.baseCutID = baseCutID; self.sequenceID = sequenceID; self.latitude = latitude; self.waitForOK = waitForOK; self.state = state; self.readBack = readBack; self.readBackApproved = readBackApproved; self.progress = progress; self.resultCutID = resultCutID; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct QuestionChoice: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var detail: String?
    public var assetID: String?
    public var recommended: Bool = false
    public init(id: String, label: String, detail: String? = nil, assetID: String? = nil, recommended: Bool = false) { self.id = id; self.label = label; self.detail = detail; self.assetID = assetID; self.recommended = recommended }
}

public struct QuestionAnswer: Codable, Hashable, Sendable {
    public var choiceID: String?
    public var text: String?
    public var at: Double
}

public struct EditorQuestion: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var turnoverID: String?
    /// "question" asks the director to decide; "cant" reports a note the editor can't do as written;
    /// "spend" asks to go over the turnover's spend limit (made-media.md).
    public var kind: String
    public var noteIDs: [String]
    public var text: String
    public var detail: String?
    public var choices: [QuestionChoice]
    public var allowsText: Bool
    public var answer: QuestionAnswer?
    public var createdAt: Double
    /// A spend question's money line and the choice that says yes.
    public var spend: SpendAsk? = nil
    public init(id: String, turnoverID: String?, kind: String, noteIDs: [String], text: String, detail: String?, choices: [QuestionChoice], allowsText: Bool, answer: QuestionAnswer?, createdAt: Double) {
        self.id = id; self.turnoverID = turnoverID; self.kind = kind; self.noteIDs = noteIDs; self.text = text; self.detail = detail; self.choices = choices; self.allowsText = allowsText; self.answer = answer; self.createdAt = createdAt
    }
}

public struct FinishingItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    /// todo, working, done, needsYou, blocked
    public var state: String
    public var by: [String]
    public var progress: Double?
    public init(id: String, title: String, detail: String, state: String = "todo", by: [String], progress: Double? = nil) { self.id = id; self.title = title; self.detail = detail; self.state = state; self.by = by; self.progress = progress }
    public static let defaults: [FinishingItem] = [
        .init(id: "color", title: "Color", detail: "Match shots across scenes to the brief's look.", by: ["editor"]),
        .init(id: "sound", title: "Sound mix", detail: "Dialogue first, music under.", by: ["editor"]),
        .init(id: "captions", title: "Captions", detail: "Captions from the transcript. Check names.", by: ["editor", "you"]),
        .init(id: "titles", title: "Titles and credits", detail: "Opening title and end card.", by: ["you"]),
        .init(id: "licenses", title: "Music licenses", detail: "Every track needs a license before you publish.", by: ["you"]),
        .init(id: "deliver", title: "Deliver", detail: "Master, web, vertical and captions.", by: ["editor", "you"]),
    ]
}

public struct EditorStatus: Codable, Hashable, Sendable {
    public var phase: String
    public var detail: String?
    public var progress: Double?
    public var agent: String?
    public var updatedAt: Double
}

public struct DirectingState: Codable, Hashable, Sendable {
    public var latitude: Latitude = .faithful
    public var waitForOK: Bool = true
    public var pictureLocked: Bool = false
    public var pictureLockedAt: Double?
    public var pictureLockedCutID: String?
    public var finishing: [FinishingItem]?
    public var deliveredAt: Double?
    public var deliveredPaths: [String]?
    public var editorPaused: Bool = false
    /// The director's standing instructions to the editor (Settings › Editor).
    public var preferences: EditorPreferences?
    /// How a camera and a screen recording in sync share the frame, chosen in Dailies (layouts.md).
    public var layout: FrameLayout?
    public init() {}
}

public struct EditorPreferences: Codable, Hashable, Sendable {
    /// Cut Feeling notes two ways when latitude allows.
    public var twoWaysForFeeling = true
    /// Ask instead of choosing when a note could mean two things.
    public var askBeforeGuessing = true
    /// Which kind wins a conflict, strongest first.
    public var conflictOrder: [NoteKind] = NoteKind.allCases
    /// Seconds of untouched picture either side of a change in Play changes.
    public var handleSeconds: Double = 2
    public init(twoWaysForFeeling: Bool = true, askBeforeGuessing: Bool = true, conflictOrder: [NoteKind] = NoteKind.allCases, handleSeconds: Double = 2) {
        self.twoWaysForFeeling = twoWaysForFeeling; self.askBeforeGuessing = askBeforeGuessing; self.conflictOrder = conflictOrder; self.handleSeconds = handleSeconds
    }
}

extension ReviewComment {
    /// The lifecycle the director sees, derived from the stored status and note state.
    public var lifecycle: NoteState {
        if noteState == .dropped { return .dropped }
        if status == "accepted" { return .accepted }
        if noteState == .reopened { return .reopened }
        if status == "addressed" || !(answers ?? []).isEmpty { return .answered }
        return noteState ?? .written
    }
    public var isOutside: Bool { authorRole == "outside" }
    public var isUnasked: Bool { authorRole == "editor" }
    public var inInbox: Bool { isOutside && (outsideState ?? "inbox") == "inbox" }
    /// Notes the editor is allowed to see.
    public var visibleToEditor: Bool { noteState != .draft && noteState != .dropped && !(isOutside && outsideState != "accepted") }
    public var latestAnswer: NoteAnswer? { answers?.last }
}
