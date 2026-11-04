import Foundation

// MARK: - Edit functions
//
// The editor reads the cut as OpenTimelineIO and changes it only through these named operations
// (agent-timeline.md). Each is one editorial act; Direction does the frame math, keeps picture and sound
// in sync, checks locks and records which note the change answers.

/// One edit function. In JSON the function is `op`. Batches written before edit functions name it `type`
/// and keep their old shapes: insert places without rippling, trim takes a source `range`, move takes `at`
/// and `layer`. Times are cut seconds (or `{value,timescale}`), ranges `{start,end}` in seconds (or
/// `{start,duration}`), and `frames` count frames at the cut's rate.
public struct EditOperation: Hashable, Sendable {
    public var type: String
    /// Named with `type`: the shapes from before edit functions.
    public var legacy: Bool
    /// The note this operation answers, over the batch's `notes`.
    public var note: Int?
    public var assetID: String?
    public var clipID: String?
    public var at: MediaTime?
    public var range: MediaRange?
    public var sourceRange: MediaRange?
    public var layer: Int?
    public var track: String?
    public var speed: Double?
    public var rate: Double?
    public var ripple: Bool?
    public var grade: ColorGrade?
    public var framing: Framing?
    public var audioTrackID: Int32?
    public var audio: AudioSettings?
    public var text: String?
    public var width: Int?
    public var height: Int?
    public var frameRate: FrameRate?
    /// `move`: `{at}`, `{before: clip}` or `{after: clip}`. `tightenPauses`: the pause length to keep, in seconds.
    public var to: JSONValue?
    public var edge: String?
    public var frames: Int?
    public var editPoint: String?
    public var lead: String?
    public var withAssetID: String?
    public var alignOn: String?
    public var wordIDs: [String]?
    public var longerThan: Double?
    public var seconds: Double?
    public var scale: Double?
    public var x: Double?
    public var y: Double?
    public var follow: String?
    public var keepIn: String?
    public var exposure: Double?
    public var contrast: Double?
    public var saturation: Double?
    public var temperature: Double?
    public var tint: Double?
    public var toClipID: String?
    public var lut: String?
    public var target: String?
    public var effect: String?
    public var params: [String: JSONValue]?
    /// Keys by parameter, times in cut seconds.
    public var keys: [String: [Keyframe]]?
    public var effectID: String?
    /// `transition`'s kind (JSON `type`, since `op` names the function).
    public var transitionType: String?
    public var cover: String?
    public var graphic: String?
    public var aboveLook: Bool?
    public var madeID: String?
    public var dB: Double?
    /// `fade` in and out, in frames (JSON `in` and `out`).
    public var fadeIn: Int?
    public var fadeOut: Int?
    public var under: String?
    public var attack: Double?
    public var release: Double?
    public var endOn: JSONValue?
    /// `placeMusic`: which of a library song's parts play ("Drums", "Bass"), and the moment of the song, in its own
    /// seconds, that plays at `at`.
    public var parts: [String]?
    public var from: Double?
    /// `parts`: where each part of a song is heard, by part, in cut seconds; [] for nowhere.
    public var heard: [String: [MediaRange]]?
    /// `pin` and `zoomThrough`: four corners [[x, y], …] as fractions of the frame (y down), top left first, clockwise.
    public var corners: [[Double]]?
    /// `layout`: how the screen and the camera share the frame over `range`.
    public var layout: FrameLayout?
    /// `layout` by the name of one of the style's layouts ("Showing"), until Direction's tools look it up.
    public var layoutName: String?
    /// `punchIn`: the framings in turn on each jump cut; `slowPush`: where it starts and ends.
    public var scales: [Double]?
    /// `zoomTo`: where to look: "action", {x, y} (fractions of the picture) or {text} (words on screen).
    public var focus: JSONValue?
    /// `transition` by the name of one of the style's ("Chapter"), until Direction's tools look it up;
    /// `technique` by its name.
    public var transitionName: String?
    /// `technique`: one of its named variants.
    public var variant: String?
    /// What Direction's tools measured before the batch runs: face keys, a matched balance, a checked
    /// shader, quiet stretches, a graphic's render. Never taken from the editor.
    public var resolved: ResolvedValues?

    public init(_ type: String) { self.type = type; legacy = true }
    public init(op: String) { type = op; legacy = false }
}

public struct ResolvedValues: Codable, Hashable, Sendable {
    /// Keys in source seconds (reframe's follow: x and y; stabilize: dx, dy, rotation).
    public var keys: [String: [Keyframe]]?
    public var grade: ColorGrade?
    public var source: String?
    /// Quiet stretches in cut time, for tightenPauses.
    public var quiet: [MediaRange]?
    public var assetID: String?
    /// `layout`: the cameras and screens in sync, and the faces in the cameras.
    public var layout: LayoutMeasure?
    /// Moves (`punchIn`, `emphasisPunch`, `slowPush`): where the face is in each take they frame.
    public var faces: [String: FaceTrack]?
    /// Screen zooms: what changed on each screen recording, the style's zoom, and words found on screen ([x, y, w, h]).
    public var activity: [String: [ActivitySample]]?
    public var zoom: StyleMoves.Zoom?
    public var box: [Double]?
    /// pixelGrid: where the subject is in each square over time.
    public var data: String?
    /// A style's transition: the sound under it, and its level.
    public var sound: MediaAsset?
    public var soundDB: Double?
    public var warnings: [String]?
    public init(keys: [String: [Keyframe]]? = nil, grade: ColorGrade? = nil, source: String? = nil, quiet: [MediaRange]? = nil, assetID: String? = nil, layout: LayoutMeasure? = nil, faces: [String: FaceTrack]? = nil, warnings: [String]? = nil) { self.keys = keys; self.grade = grade; self.source = source; self.quiet = quiet; self.assetID = assetID; self.layout = layout; self.faces = faces; self.warnings = warnings }
}

extension EditOperation: Codable {
    static let argumentNames: Set<String> = ["op", "type", "note", "assetID", "clipID", "at", "range", "sourceRange", "layer", "track", "speed", "rate", "ripple", "grade", "framing", "audioTrackID", "audio", "text", "width", "height", "frameRate", "to", "edge", "frames", "editPoint", "lead", "withAssetID", "alignOn", "wordIDs", "longerThan", "seconds", "scale", "x", "y", "follow", "keepIn", "exposure", "contrast", "saturation", "temperature", "tint", "toClipID", "lut", "target", "effect", "params", "keys", "effectID", "cover", "graphic", "aboveLook", "madeID", "dB", "in", "out", "under", "attack", "release", "endOn", "parts", "from", "heard", "corners", "layout", "scales", "focus", "name", "variant", "resolved"]

    public init(from decoder: Decoder) throws { try self.init(json: JSONValue(from: decoder)) }
    public func encode(to encoder: Encoder) throws { try json.encode(to: encoder) }

    /// Reads one operation, with errors that name the argument.
    public init(json o: JSONValue) throws {
        guard case .object(let f) = o else { throw DirectionError("bad_argument", "Each operation is an object like {\"op\": \"trim\", …}.") }
        guard let name = f["op"]?.string ?? f["type"]?.string, !name.isEmpty else { throw DirectionError("bad_argument", "Name the operation with op.") }
        if let unknown = f.keys.first(where: { !Self.argumentNames.contains($0) }) { throw DirectionError("bad_argument", "\(name) doesn't take \(unknown). direction_edit_catalog lists each operation's arguments.") }
        func bad(_ k: String, _ what: String) -> DirectionError { .init("bad_argument", "\(k) must be \(what).") }
        func value(_ k: String) -> JSONValue? { guard let v = f[k], v != .null else { return nil }; return v }
        func str(_ k: String) throws -> String? { try value(k).map { guard let s = $0.string else { throw bad(k, "text") }; return s } }
        func num(_ k: String) throws -> Double? { try value(k).map { guard let n = $0.double, n.isFinite else { throw bad(k, "a number") }; return n } }
        func int(_ k: String) throws -> Int? { try num(k).map { guard $0.rounded() == $0, abs($0) < 1e9 else { throw bad(k, "a whole number") }; return Int($0) } }
        func bool(_ k: String) throws -> Bool? { try value(k).map { guard let b = $0.bool else { throw bad(k, "true or false") }; return b } }
        func decoded<T: Decodable>(_ k: String, _ t: T.Type, _ what: String) throws -> T? { try value(k).map { v in do { return try v.decode(t) } catch { throw bad(k, what) } } }
        type = name; legacy = f["op"] == nil
        note = try int("note"); assetID = try str("assetID"); clipID = try str("clipID")
        at = try value("at").map { try Self.time($0, "at") }
        range = try value("range").map { try Self.range($0, "range") }
        sourceRange = try value("sourceRange").map { try Self.range($0, "sourceRange") }
        layer = try int("layer"); track = try str("track"); speed = try num("speed"); rate = try num("rate"); ripple = try bool("ripple")
        grade = try decoded("grade", ColorGrade.self, "a full balance {exposure, contrast, saturation, temperature, tint}")
        framing = try decoded("framing", Framing.self, "a full framing {fit, scale, offsetX, offsetY, opacity}")
        audioTrackID = try int("audioTrackID").flatMap(Int32.init(exactly:))
        audio = try decoded("audio", AudioSettings.self, "full audio settings, as direction_inspect shows them")
        text = try str("text"); width = try int("width"); height = try int("height")
        frameRate = try decoded("frameRate", FrameRate.self, "{numerator, denominator}")
        to = value("to"); edge = try str("edge"); frames = try int("frames"); editPoint = try str("editPoint"); lead = try str("lead")
        withAssetID = try str("withAssetID"); alignOn = try str("alignOn")
        wordIDs = try decoded("wordIDs", [String].self, "a list of word ids from direction_transcript")
        longerThan = try num("longerThan"); seconds = try num("seconds"); scale = try num("scale"); x = try num("x"); y = try num("y")
        follow = try str("follow"); keepIn = try str("keepIn")
        exposure = try num("exposure"); contrast = try num("contrast"); saturation = try num("saturation"); temperature = try num("temperature"); tint = try num("tint")
        toClipID = try str("toClipID"); lut = try str("lut"); target = try str("target"); effect = try str("effect")
        params = try value("params").map { guard case .object(let p) = $0 else { throw bad("params", "an object") }; return p }
        keys = try decoded("keys", [String: [Keyframe]].self, "{param: [{t, v}]}, t in cut seconds")
        effectID = try str("effectID"); transitionType = legacy ? nil : try str("type")
        cover = try str("cover"); graphic = try str("graphic"); aboveLook = try bool("aboveLook"); madeID = try str("madeID")
        dB = try num("dB"); fadeIn = try int("in"); fadeOut = try int("out"); under = try str("under"); attack = try num("attack"); release = try num("release")
        endOn = value("endOn")
        parts = try decoded("parts", [String].self, "a list of a song's parts, like [\"Drums\", \"Bass\"]")
        from = try num("from")
        if let v = value("heard") {
            guard case .object(let o) = v else { throw bad("heard", "{part: [{start, end}]}, in cut seconds") }
            heard = try o.mapValues { list in
                guard let items = list.array else { throw bad("heard", "{part: [{start, end}]}, each part a list of stretches") }
                return try items.map { try Self.range($0, "heard") }
            }
        }
        corners = try decoded("corners", [[Double]].self, "four [x, y] corners, fractions of the frame from its top left, top left first and clockwise")
        if let v = value("layout"), let n = v.string ?? (v["kind"] == .null ? v["name"].string : nil) { layoutName = n }
        else { layout = try decoded("layout", FrameLayout.self, "the name of one of the style's layouts, or {kind: screenAndYou|you|screen|sideBySide, corner?: topLeft|topRight|bottomLeft|bottomRight, size?: small|medium|large, shape?: circle|rounded|wide, screen?: full|framed}") }
        scales = try decoded("scales", [Double].self, "a list of scales, like [1, 1.15]")
        focus = value("focus")
        if let f = focus { guard f.string == "action" || (f["x"].double != nil && f["y"].double != nil) || f["text"].string?.isEmpty == false else { throw bad("focus", "\"action\", {x, y} or {text}") } }
        transitionName = try str("name"); variant = try str("variant")
        resolved = try decoded("resolved", ResolvedValues.self, "Direction's own measurements")
    }

    public var json: JSONValue {
        var f: [String: JSONValue] = [legacy ? "type" : "op": .string(type)]
        func put(_ k: String, _ v: String?) { if let v { f[k] = .string(v) } }
        func put(_ k: String, _ v: Double?) { if let v { f[k] = .number(v) } }
        func put(_ k: String, _ v: Int?) { if let v { f[k] = .number(Double(v)) } }
        func put(_ k: String, _ v: Bool?) { if let v { f[k] = .bool(v) } }
        func put<T: Encodable>(_ k: String, any v: T?) { if let v, let j = try? JSONValue.wrapping(v) { f[k] = j } }
        put("note", note); put("assetID", assetID); put("clipID", clipID); put("at", any: at); put("range", any: range); put("sourceRange", any: sourceRange)
        put("layer", layer); put("track", track); put("speed", speed); put("rate", rate); put("ripple", ripple); put("grade", any: grade); put("framing", any: framing)
        put("audioTrackID", audioTrackID.map(Int.init)); put("audio", any: audio); put("text", text); put("width", width); put("height", height); put("frameRate", any: frameRate)
        if let to { f["to"] = to }; put("edge", edge); put("frames", frames); put("editPoint", editPoint); put("lead", lead); put("withAssetID", withAssetID); put("alignOn", alignOn)
        put("wordIDs", any: wordIDs); put("longerThan", longerThan); put("seconds", seconds); put("scale", scale); put("x", x); put("y", y); put("follow", follow); put("keepIn", keepIn)
        put("exposure", exposure); put("contrast", contrast); put("saturation", saturation); put("temperature", temperature); put("tint", tint)
        put("toClipID", toClipID); put("lut", lut); put("target", target); put("effect", effect); if let params { f["params"] = .object(params) }; put("keys", any: keys); put("effectID", effectID)
        if !legacy { put("type", transitionType) }
        put("cover", cover); put("graphic", graphic); put("aboveLook", aboveLook); put("madeID", madeID); put("dB", dB); put("in", fadeIn); put("out", fadeOut)
        put("under", under); put("attack", attack); put("release", release); if let endOn { f["endOn"] = endOn }; put("parts", any: parts); put("from", from); put("heard", any: heard); put("corners", any: corners); put("layout", any: layout); if layout == nil { put("layout", layoutName) }; put("scales", any: scales); if let focus { f["focus"] = focus }; put("name", transitionName); put("variant", variant); put("resolved", any: resolved)
        return .object(f)
    }

    static func time(_ v: JSONValue, _ k: String) throws -> MediaTime {
        if let s = v.double, s.isFinite { return MediaTime(seconds: s) }
        if let value = v["value"].double, value.rounded() == value, abs(value) < 9e15, let scale = v["timescale"].int, scale > 0, scale <= Int(Int32.max) { return MediaTime(value: Int64(value), timescale: Int32(scale)) }
        throw DirectionError("bad_argument", "\(k) is a time in seconds, like 4.2.")
    }
    static func range(_ v: JSONValue, _ k: String) throws -> MediaRange {
        guard case .object = v else { throw DirectionError("bad_argument", "\(k) is {start, end} in seconds.") }
        let start = try time(v["start"], k + ".start")
        if v["end"] != .null { let end = try time(v["end"], k + ".end"); guard end > start else { throw DirectionError("bad_argument", "\(k) ends after it starts.") }; return .init(start: start, duration: end - start) }
        guard v["duration"] != .null else { throw DirectionError("bad_argument", "\(k) is {start, end} in seconds.") }
        return .init(start: start, duration: try time(v["duration"], k + ".duration"))
    }
}

public struct EditBatch: Codable, Hashable, Sendable {
    public var baseEditRevision: Int
    public var sequenceID: String?
    public var idempotencyKey: String
    public var summary: String
    /// Note numbers the batch answers. Any operation may name its own `note`.
    public var notes: [Int]?
    public var operations: [EditOperation]
    /// The director's own change, made in the app (a layout): it needs no note, and what it sets is theirs.
    public var byDirector: Bool?
    public init(baseEditRevision: Int, sequenceID: String? = nil, idempotencyKey: String = UUID().uuidString, summary: String = "Edited sequence", notes: [Int]? = nil, operations: [EditOperation], byDirector: Bool? = nil) { self.baseEditRevision = baseEditRevision; self.sequenceID = sequenceID; self.idempotencyKey = idempotencyKey; self.summary = summary; self.notes = notes; self.operations = operations; self.byDirector = byDirector }
}

/// What an edit needs to know beyond the project: words, locks, latitude and the notes the editor can see.
public struct EditContext: Sendable {
    public var transcripts: [SourceTranscript]
    public var dailies: Dailies
    public var state: DirectingState
    /// The open notes turnover's latitude. nil when none is open (an assembly, or your own session).
    public var turnoverLatitude: Latitude?
    public var noteNumbers: Set<Int>
    /// The film package, for camera LUT paths.
    public var filmURL: URL?
    public init(transcripts: [SourceTranscript] = [], dailies: Dailies = .init(), state: DirectingState = .init(), turnoverLatitude: Latitude? = nil, noteNumbers: Set<Int> = [], filmURL: URL? = nil) { self.transcripts = transcripts; self.dailies = dailies; self.state = state; self.turnoverLatitude = turnoverLatitude; self.noteNumbers = noteNumbers; self.filmURL = filmURL }
}

// MARK: - Results

public struct SecondsRange: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = end }
}

/// One changed passage: where it is in the new cut, where it was in the old one, and the scenes it touches.
public struct EditChange: Codable, Hashable, Sendable {
    public var new: SecondsRange
    public var old: SecondsRange
    public var tracks: [String]
    public var scenes: [Int]
}

/// What one operation did, so Changes and History can say "Trimmed scene 1, −4.2 s, for note 1".
public struct OperationResult: Codable, Hashable, Sendable {
    public var index: Int
    public var op: String
    public var notes: [Int]
    /// No note asked for it (latitude "Take a pass").
    public var unasked: Bool
    public var summary: String
    /// Seconds this operation added to (+) or took from (−) the cut.
    public var delta: Double
    public var deltaText: String
    public var changes: [EditChange]
    public var effectID: String?
    public var clipIDs: [String]?
    public var warnings: [String]?
}

public struct EditResult: Codable, Hashable, Sendable {
    public var committed: Bool
    public var editRevision: Int
    public var baseEditRevision: Int
    public var sequenceID: String
    public var summary: String
    public var notes: [Int]
    public var oldLength: Double
    public var newLength: Double
    public var delta: Double
    public var operations: [OperationResult]
    public var warnings: [String]
    public var createdAt: Double?
    /// The director made it in the app.
    public var byDirector: Bool? = nil
}

/// "−4.2 s", "+1.6 s" (true minus sign, product-model › Formats).
public func deltaText(_ seconds: Double) -> String {
    guard abs(seconds) >= 0.05 else { return "0 s" }
    return (seconds < 0 ? "\u{2212}" : "+") + String(format: "%.1f s", abs(seconds))
}
/// "−6 dB".
public func dbText(_ dB: Double) -> String { (dB < 0 ? "\u{2212}" : dB > 0 ? "+" : "") + String(format: "%g dB", abs(dB)) }

/// How an operation moved cut time: [at, at + removed) became `inserted` seconds.
struct Splice: Hashable, Sendable {
    var at: Double, removed: Double, inserted: Double
    func forward(_ t: Double) -> Double { t <= at ? t : t >= at + removed ? t - removed + inserted : at + min(t - at, inserted) }
    func backward(_ t: Double) -> Double { Splice(at: at, removed: inserted, inserted: removed).forward(t) }
}

struct LocalChange {
    /// In the cut before the operation.
    var before: (Double, Double)
    /// In the cut after it; nil means `before` carried through the operation's own splices.
    var after: (Double, Double)?
    var tracks: [String]
}

struct Outcome {
    var summary: String
    var changes: [LocalChange] = []
    var splices: [Splice] = []
    var effectID: String? = nil
    var clipIDs: [String] = []
    var warnings: [String] = []
}

// MARK: - The reducer

public enum EditReducer {
    /// Applies a batch and returns the project, for callers that don't need the change list.
    public static func apply(_ batch: EditBatch, to original: Project) throws -> Project { try run(batch, on: original, context: nil).project }

    /// Applies every operation in order, or none. With a context it also checks locks and notes per
    /// operation, so an error names the operation that failed.
    public static func run(_ batch: EditBatch, on original: Project, context: EditContext?) throws -> (project: Project, result: EditResult) {
        guard (1...1_000).contains(batch.operations.count) else { throw DirectionError("bad_argument", "Send between 1 and 1,000 operations.") }
        guard let si = original.sequences.firstIndex(where: { batch.sequenceID == nil || $0.id == batch.sequenceID }) else { throw DirectionError("bad_argument", "Sequence not found.") }
        var w = EditWork(project: original, si: si, context: context)
        w.director = batch.byDirector == true
        struct Step { var op: EditOperation; var outcome: Outcome; var notes: [Int]; var unasked: Bool; var delta: Double }
        var steps: [Step] = []
        for (i, op) in batch.operations.enumerated() {
            do {
                let (notes, unasked) = try noteCheck(op, batch, context)
                if let context { try TimelineLocks.gate(op, w, context) }
                w.forNote = !notes.isEmpty
                try w.checkLayoutLock(op)
                let before = w.project, oldLength = w.s.duration.seconds
                // Choosing what a synced clip plays by hand takes it out of sync.
                let byHand = ["slip", "replaceTake", "speed", "freeze"].contains(op.type) ? op.clipID : nil
                var outcome = try w.perform(op)
                if let id = byHand, let k = w.s.clips.firstIndex(where: { $0.id == id }) { w.s.clips[k].synced = nil }
                let followed = w.relineSynced()
                try w.checkSongs()
                outcome.changes += followed.changes
                outcome.warnings += w.normalizeTransitions() + (op.resolved?.warnings ?? []) + followed.warnings
                try validate(w.project)
                if let context { try TimelineLocks.check(before: before, after: w.project, si: si, context: context) }
                steps.append(.init(op: op, outcome: outcome, notes: notes, unasked: unasked, delta: w.s.duration.seconds - oldLength))
            } catch let e as DirectionError { throw DirectionError(code(e.code), e.message, index: i) }
        }
        // Each change lands in the old cut (back through earlier operations) and the new one (forward through later ones).
        let splices = steps.map(\.outcome.splices), oldSequence = original.sequences[si], newSequence = w.s
        let dailies = context?.dailies ?? Dailies()
        func r3(_ x: Double) -> Double { (x * 1_000).rounded() / 1_000 }
        var results: [OperationResult] = []
        for (i, step) in steps.enumerated() {
            let changes = step.outcome.changes.map { ch -> EditChange in
                var old = ch.before
                for k in (0..<i).reversed() { for sp in splices[k].reversed() { old = (sp.backward(old.0), sp.backward(old.1)) } }
                var new = ch.after ?? splices[i].reduce(ch.before) { p, sp in (sp.forward(p.0), sp.forward(p.1)) }
                for k in steps.indices where k > i { for sp in splices[k] { new = (sp.forward(new.0), sp.forward(new.1)) } }
                let scenes = Set(sceneNumbers(old, in: oldSequence, dailies) + sceneNumbers(new, in: newSequence, dailies)).sorted()
                return EditChange(new: .init(start: r3(new.0), end: r3(max(new.0, new.1))), old: .init(start: r3(old.0), end: r3(max(old.0, old.1))), tracks: ch.tracks, scenes: scenes)
            }
            results.append(OperationResult(index: i, op: step.op.type, notes: step.notes, unasked: step.unasked, summary: step.outcome.summary, delta: r3(step.delta), deltaText: deltaText(step.delta), changes: changes, effectID: step.outcome.effectID, clipIDs: step.outcome.clipIDs.isEmpty ? nil : step.outcome.clipIDs, warnings: step.outcome.warnings.isEmpty ? nil : step.outcome.warnings))
        }
        let oldLength = oldSequence.duration.seconds, newLength = newSequence.duration.seconds
        var result = EditResult(committed: false, editRevision: original.editRevision, baseEditRevision: original.editRevision, sequenceID: newSequence.id, summary: batch.summary, notes: Array(Set(results.flatMap(\.notes))).sorted(), oldLength: r3(oldLength), newLength: r3(newLength), delta: r3(newLength - oldLength), operations: results, warnings: results.flatMap { $0.warnings ?? [] }, createdAt: nil)
        if batch.byDirector == true { result.byDirector = true }
        return (w.project, result)
    }

    /// Spec error codes for everything the operations and validation throw (agent-timeline.md › errors).
    static func code(_ c: String) -> String {
        switch c {
        case "overlapping_clips": "overlap"
        case "asset_not_found", "missing_asset": "missing_media"
        case "unknown_operation": "unknown_op"
        case "scene_locked", "picture_locked", "overlap", "unknown_op", "missing_media", "no_words", "look_is_yours", "words_are_yours", "layout_is_yours", "stale_revision", "shader_too_slow", "shader_invalid", "not_in_sync": c
        default: "bad_argument"
        }
    }

    static func noteCheck(_ op: EditOperation, _ batch: EditBatch, _ context: EditContext?) throws -> ([Int], Bool) {
        let notes = op.note.map { [$0] } ?? batch.notes ?? []
        guard let context, batch.byDirector != true else { return (notes, false) }
        for n in notes where !context.noteNumbers.contains(n) { throw DirectionError("bad_argument", "There's no note \(n) you can see.") }
        guard notes.isEmpty, let latitude = context.turnoverLatitude else { return (notes, false) }
        guard latitude == .free else { throw DirectionError("bad_argument", "Say which note this answers with notes or note. A change no note asked for needs latitude “Take a pass”.") }
        return ([], true)
    }

    static func sceneNumbers(_ r: (Double, Double), in s: Sequence, _ dailies: Dailies) -> [Int] {
        let a = min(r.0, r.1), b = max(r.0, r.1)
        return s.clips.filter { c in c.layer == 0 && (b > a ? c.start.seconds < b && c.end.seconds > a : c.start.seconds <= a && c.end.seconds >= a) }.compactMap { dailies.scene(for: $0.assetID)?.number }
    }

    /// A clip cut down to part of itself. A new head loses its transition, J-cut and fade in; a new tail its L-cut and fade out.
    public static func trimmed(_ c: Clip, to o: MediaRange) -> Clip {
        var p = c
        if c.hold != nil { p.hold = o.duration }
        else { p.sourceRange = .init(start: c.sourceTime(at: o.start), duration: o.duration.scaled(by: c.speed)) }
        if o.start > c.start { p.transition = nil; p.soundLead = nil; p.fadeIn = nil }
        if o.end < c.end { p.soundTail = nil; p.fadeOut = nil }
        p.start = o.start
        return p
    }
    static func reIDed(_ effects: [ClipEffect]?) -> [ClipEffect]? { effects?.map { var e = $0; e.id = newID("fx"); return e } }

    /// Splits a clip in two at a cut time. The right half is a new clip with its own effect ids.
    public static func split(_ c: Clip, at t: MediaTime) -> (Clip, Clip) {
        let left = trimmed(c, to: .init(start: c.start, duration: t - c.start))
        var right = trimmed(c, to: .init(start: t, duration: c.end - t))
        right.id = newID("clip"); right.effects = reIDed(c.effects)
        return (left, right)
    }

    public static func removing(_ range: MediaRange, from clips: [Clip], ripple: Bool) -> [Clip] {
        var result: [Clip] = []
        for clip in clips {
            guard let overlap = clip.range.intersection(range) else {
                var c = clip
                if ripple && c.start >= range.end { c.start = c.start - range.duration }
                result.append(c); continue
            }
            let hasLeft = clip.start < overlap.start
            if hasLeft { result.append(trimmed(clip, to: .init(start: clip.start, duration: overlap.start - clip.start))) }
            if clip.end > overlap.end {
                var right = trimmed(clip, to: .init(start: overlap.end, duration: clip.end - overlap.end))
                if hasLeft { right.id = newID("clip"); right.effects = reIDed(clip.effects) }
                if ripple { right.start = overlap.end - range.duration }
                result.append(right)
            }
        }
        return result
    }

    /// Every clip inside a range, trimmed to it, with starts relative to the range. Partial pieces are new clips.
    static func cutOut(_ r: MediaRange, from clips: [Clip]) -> [Clip] {
        clips.compactMap { c in
            guard let o = c.range.intersection(r) else { return nil }
            var p = trimmed(c, to: o)
            if o != c.range { p.id = newID("clip"); p.effects = reIDed(c.effects) }
            p.start = o.start - r.start
            return p
        }
    }

    public static func validate(_ p: Project) throws {
        guard p.schemaVersion == 1 else { throw DirectionError("unsupported_project", "Unsupported project format.") }
        for a in p.assets {
            guard a.duration.isValid && a.duration > .zero else { throw DirectionError("invalid_asset", "Asset duration must be positive.") }
            for stream in a.audio { try validateAudio(stream.settings) }
        }
        for s in p.sequences {
            guard (16...7680).contains(s.width), (16...7680).contains(s.height), s.width % 2 == 0, s.height % 2 == 0, s.frameRate.numerator > 0, s.frameRate.denominator > 0, (1...120).contains(s.frameRate.value) else { throw DirectionError("invalid_format", "Use even canvas dimensions from 16 to 7680 and a frame rate from 1 to 120.") }
            guard Set(s.clips.map(\.id)).count == s.clips.count else { throw DirectionError("duplicate_clip_id", "Clip IDs must be unique within a sequence.") }
            for c in s.clips {
                guard c.start.isValid, c.start >= .zero, c.sourceRange.isValid, c.speed.isFinite, (0.1...8).contains(c.speed), (0...1_000).contains(c.layer) else { throw DirectionError("invalid_clip", "Invalid clip range, speed, or layer.") }
                if let h = c.hold { guard h.isValid && h > .zero else { throw DirectionError("invalid_clip", "A freeze needs a length.") } }
                if let id = c.assetID { let a = try p.asset(id); guard a.isImage || c.sourceRange.end.seconds <= a.duration.seconds + 1e-6 else { throw DirectionError("source_out_of_bounds", "\(c.name) extends past the source duration.") } }
                else if c.kind != .title { throw DirectionError("missing_asset", "A media clip must reference an asset.") }
                let g = c.grade
                guard g.exposure.isFinite && (-5...5).contains(g.exposure), g.contrast.isFinite && (0...4).contains(g.contrast), g.saturation.isFinite && (0...3).contains(g.saturation), g.temperature.isFinite && (-3_000...3_000).contains(g.temperature), g.tint.isFinite && (-100...100).contains(g.tint) else { throw DirectionError("invalid_grade", "Color values are outside supported ranges.") }
                let f = c.framing
                guard f.scale.isFinite && (0.05...10).contains(f.scale), f.offsetX.isFinite && (-2...2).contains(f.offsetX), f.offsetY.isFinite && (-2...2).contains(f.offsetY), f.opacity.isFinite && (0...1).contains(f.opacity) else { throw DirectionError("invalid_framing", "Framing values are outside supported ranges.") }
                for audio in c.audioOverrides.values { try validateAudio(audio) }
                guard [c.gainDB, c.fadeIn, c.fadeOut, c.soundLead, c.soundTail].allSatisfy({ $0?.isFinite ?? true }), (c.gainDB ?? 0) >= -96 && (c.gainDB ?? 0) <= 24, (c.fadeIn ?? 0) >= 0, (c.fadeOut ?? 0) >= 0, c.blend.map(EditCatalog.blendModes.contains) ?? true else { throw DirectionError("invalid_clip", "\(c.name) has sound or blend settings outside supported ranges.") }
                if let t = c.transition { guard EditCatalog.transitions.contains(t.type), t.frames > 0, t.before >= 0, t.after >= 0, t.isDip || t.type == "dissolve" || t.source != nil else { throw DirectionError("invalid_clip", "Invalid transition on \(c.name).") } }
            }
            let groups = Dictionary(grouping: s.clips, by: { "\($0.kind.rawValue):\($0.layer)" })
            for group in groups.values { let ordered = group.sorted { $0.start < $1.start }; for i in ordered.indices.dropFirst() where ordered[i].start.seconds < ordered[i - 1].end.seconds - 1e-9 { throw DirectionError("overlap", "\(ordered[i - 1].name) and \(ordered[i].name) would overlap on \(ordered[i].trackName). Put one on another track.") } }
        }
    }

    public static func validateAudio(_ a: AudioSettings) throws {
        let e = a.effects
        guard a.gainDB.isFinite && (-96...24).contains(a.gainDB), a.fadeIn.isFinite && (0...120).contains(a.fadeIn), a.fadeOut.isFinite && (0...120).contains(a.fadeOut), e.highPassHz.isFinite && (0...5_000).contains(e.highPassHz), e.bassDB.isFinite && (-24...24).contains(e.bassDB), e.trebleDB.isFinite && (-24...24).contains(e.trebleDB), e.thresholdDB.isFinite && (-60...0).contains(e.thresholdDB) else { throw DirectionError("invalid_audio", "Audio settings are outside supported ranges.") }
    }
}

// MARK: - Operations

struct EditWork {
    var project: Project
    let si: Int
    let context: EditContext?
    /// The batch is the director's (EditBatch.byDirector).
    var director = false
    /// The operation being carried out answers a note.
    var forNote = false
    typealias Track = (audio: Bool, layer: Int)

    var s: Sequence { get { project.sequences[si] } set { project.sequences[si] = newValue } }
    var frame: Double { Double(s.frameRate.denominator) / Double(s.frameRate.numerator) }
    func frames(_ n: Int) -> MediaTime { MediaTime(value: Int64(n) * Int64(s.frameRate.denominator), timescale: s.frameRate.numerator) }
    /// n frames in seconds, exactly: 15 frames at 30 fps is 0.5, not 15 × (1/30).
    func secs(_ n: Int) -> Double { Double(n) * Double(s.frameRate.denominator) / Double(s.frameRate.numerator) }
    func snap(_ t: MediaTime) -> MediaTime { frames(Int((t.seconds / frame).rounded())) }
    func snapUp(_ t: MediaTime) -> MediaTime { frames(Int((t.seconds / frame - 1e-6).rounded(.up))) }
    func snapDown(_ t: MediaTime) -> MediaTime { frames(Int((t.seconds / frame + 1e-6).rounded(.down))) }
    func snap(_ r: MediaRange) -> MediaRange { let a = snap(r.start), b = snap(r.end); return .init(start: a, duration: b - a) }
    func bad(_ m: String) -> DirectionError { .init("bad_argument", m) }
    func tc(_ t: MediaTime) -> String { CutTimecode.string(t.seconds, rate: s.frameRate.value) }
    func tc(_ t: Double) -> String { CutTimecode.string(t, rate: s.frameRate.value) }
    var transcripts: [SourceTranscript] { context?.transcripts ?? [] }

    func clipIndex(_ id: String?, _ arg: String = "clipID") throws -> Int {
        guard let id, !id.isEmpty else { throw bad("\(arg) is required.") }
        guard let i = s.clips.firstIndex(where: { $0.id == id }) else { throw bad("There's no clip \(id) in this cut. Read direction_timeline for ids.") }
        return i
    }
    func asset(_ id: String?, _ arg: String = "assetID") throws -> MediaAsset {
        guard let id, !id.isEmpty else { throw bad("\(arg) is required.") }
        guard let a = project.assets.first(where: { $0.id == id }) ?? project.assets.first(where: { $0.madeID == id }) else { throw DirectionError("missing_media", "There's no footage or made clip \(id) in this film.") }
        return a
    }
    func assetOf(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in project.assets.first { $0.id == id } } }
    /// What was placed for the frame before its shape changed: titles, graphics and layouts.
    func placedForFrame(_ was: String) -> String? {
        let titles = s.clips.filter { $0.kind == .title }.count
        let graphics = s.clips.filter { $0.kind == .video && assetOf($0)?.graphic != nil }.count
        let layouts = Set(s.clips.compactMap { $0.layout?.layout }).count
        let parts = [(titles, "title"), (graphics, "graphic"), (layouts, "layout")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        guard !parts.isEmpty else { return nil }
        let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        return "\(list) \(titles + graphics + layouts == 1 ? "was" : "were") placed for \(was). Look at \(titles + graphics + layouts == 1 ? "it" : "them") in the new shape."
    }
    /// "1A T2", or the clip's name.
    func label(_ c: Clip) -> String {
        if let t = c.assetID.flatMap({ context?.dailies.takes[$0] }), let code = t.code { return [t.setupCode, code].compactMap { $0 }.joined(separator: " ") }
        return c.title ?? c.name
    }
    func hasSound(_ c: Clip) -> Bool { c.hold == nil && !(assetOf(c)?.audio.isEmpty ?? true) }
    func parseTrack(_ name: String?) throws -> Track {
        guard let name, let first = name.first, first == "V" || first == "A", let n = Int(name.dropFirst()), (1...1_001).contains(n) else { throw bad("Tracks are V1, V2… for picture and A1, A2… for sound.") }
        return (first == "A", n - 1)
    }
    func name(_ t: Track) -> String { (t.audio ? "A" : "V") + String(t.layer + 1) }
    func on(_ c: Clip, _ t: Track) -> Bool { (c.kind == .audio) == t.audio && c.layer == t.layer }
    func track(of c: Clip) -> Track { (c.kind == .audio, c.layer) }
    func free(_ t: Track, _ r: MediaRange, except: String? = nil) -> Bool { !s.clips.contains { $0.id != except && on($0, t) && $0.start.seconds < r.end.seconds - 1e-9 && $0.end.seconds > r.start.seconds + 1e-9 } }
    func firstFree(audio: Bool, from: Int, _ r: MediaRange) -> Int { var l = from; while !free((audio, l), r) && l < 1_000 { l += 1 }; return l }
    func tracksTouching(_ a: Double, _ b: Double) -> [String] {
        Array(Set(s.clips.filter { $0.start.seconds < max(b, a + 1e-9) && $0.end.seconds > a }.flatMap { c -> [String] in c.kind == .video && c.layer == 0 && hasSound(c) ? ["V1", "A1"] : [c.trackName] })).sorted()
    }

    /// "<left>|<right>": two clips that meet at a cut on one track. "|<right>" is a clip's head on its own.
    func editPoint(_ value: String?, needsLeft: Bool = true) throws -> (left: Int?, right: Int) {
        guard let value, let bar = value.firstIndex(of: "|") else { throw bad("editPoint is \"<left clip>|<right clip>\".") }
        let l = String(value[..<bar]), r = String(value[value.index(after: bar)...])
        let ri = try clipIndex(r, "editPoint")
        if l.isEmpty { guard !needsLeft else { throw bad("Name both clips at the edit point.") }; return (nil, ri) }
        let li = try clipIndex(l, "editPoint"), a = s.clips[li], b = s.clips[ri]
        guard on(a, track(of: b)), abs(a.end.seconds - b.start.seconds) < frame / 2 else { throw bad("\(l) and \(r) don't meet at a cut on one track.") }
        return (li, ri)
    }

    /// Seconds of cut time the source has past a clip's out point (or before its in point). Stills, titles and freezes never run out.
    func handleAfter(_ c: Clip) -> Double { guard c.hold == nil, let a = assetOf(c), !a.isImage else { return .infinity }; return (a.duration - c.sourceRange.end).seconds / c.speed }
    func handleBefore(_ c: Clip) -> Double { guard c.hold == nil, let a = assetOf(c), !a.isImage else { return .infinity }; return c.sourceRange.start.seconds / c.speed }
    func framesText(_ seconds: Double) -> String { let n = Int((seconds / frame + 1e-6).rounded(.down)); return n == 1 ? "1 frame" : "\(n) frames" }

    func sourceRange(_ r: MediaRange?, of a: MediaAsset) throws -> MediaRange {
        guard let r else { return .init(start: .zero, duration: a.isImage ? MediaTime(seconds: 5) : snapDown(a.duration)) }
        var out = snap(r)
        if !a.isImage && out.end > a.duration { out.duration = snapDown(a.duration) - out.start }
        guard out.isValid else { throw bad("sourceRange needs a start and a later end, inside \(a.name).") }
        guard a.isImage || r.end.seconds <= a.duration.seconds + frame else { throw bad("\(a.name) is only \(String(format: "%.2f", a.duration.seconds)) s long.") }
        return out
    }

    // Time and ripples

    mutating func spliceTrackKeys(_ sp: Splice) { s.tracks = Self.spliced(s.tracks, sp) }
    /// Track keys are in cut seconds, so they move with a splice.
    static func spliced(_ tracks: [String: TrackSettings]?, _ sp: Splice) -> [String: TrackSettings]? {
        guard var tracks else { return nil }
        func moved(_ k: [Keyframe]) -> [Keyframe] { k.map { Keyframe(t: sp.forward($0.t), v: $0.v, ease: $0.ease) } }
        for (name, var t) in tracks { t.gainKeys = t.gainKeys.map(moved); t.effects = t.effects?.map { e in var e = e; e.keys = e.keys?.mapValues(moved); return e }; tracks[name] = t }
        return tracks
    }
    @discardableResult mutating func removeRange(_ r: MediaRange, ripple: Bool) -> Splice? {
        s.clips = EditReducer.removing(r, from: s.clips, ripple: ripple)
        guard ripple else { return nil }
        let sp = Splice(at: r.start.seconds, removed: r.duration.seconds, inserted: 0); spliceTrackKeys(sp); return sp
    }
    /// Ripple removal on every clip but one, which has already been changed to its new length.
    mutating func removeRange(_ r: MediaRange, except id: String) -> Splice {
        let kept = s.clips.filter { $0.id == id }
        s.clips = kept + EditReducer.removing(r, from: s.clips.filter { $0.id != id }, ripple: true)
        let sp = Splice(at: r.start.seconds, removed: r.duration.seconds, inserted: 0); spliceTrackKeys(sp); return sp
    }
    /// Opens a gap on every track: clips across it are split, everything after it moves later.
    @discardableResult mutating func insertGap(at t: MediaTime, _ d: MediaTime) -> Splice {
        var out: [Clip] = []
        for c in s.clips {
            if c.start.seconds >= t.seconds - 1e-9 { var c = c; c.start = c.start + d; out.append(c) }
            else if c.end.seconds > t.seconds + 1e-9 { var (l, r) = EditReducer.split(c, at: t); r.start = r.start + d; out += [l, r] }
            else { out.append(c) }
        }
        s.clips = out
        let sp = Splice(at: t.seconds, removed: 0, inserted: d.seconds); spliceTrackKeys(sp); return sp
    }
    /// Moves clips that start at or after `pivot`: on every track for the story, or on one track.
    mutating func shift(from pivot: MediaTime, by d: MediaTime, except id: String?, track: Track?) -> Splice? {
        for i in s.clips.indices where s.clips[i].id != id && s.clips[i].start.seconds >= pivot.seconds - 1e-9 && (track.map { on(s.clips[i], $0) } ?? true) { s.clips[i].start = s.clips[i].start + d }
        guard track == nil else { return nil }
        let sp = d.seconds >= 0 ? Splice(at: pivot.seconds, removed: 0, inserted: d.seconds) : Splice(at: pivot.seconds + d.seconds, removed: -d.seconds, inserted: 0)
        spliceTrackKeys(sp); return sp
    }
    func lengthened(_ c: Clip, by d: MediaTime, head: Bool) -> Clip {
        var c = c
        if let h = c.hold { c.hold = h + d; return c }
        let ds = d.scaled(by: c.speed)
        if head { c.sourceRange.start = c.sourceRange.start - ds }
        c.sourceRange.duration = c.sourceRange.duration + ds
        return c
    }

    /// Dissolves need a clip on each side with handle to spare. Edits that take that away drop them, with a warning.
    mutating func normalizeTransitions() -> [String] {
        var warnings: [String] = []
        for i in s.clips.indices {
            guard let t = s.clips[i].transition else { continue }
            let r = s.clips[i]
            let left = s.clips.first { $0.id != r.id && on($0, track(of: r)) && abs($0.end.seconds - r.start.seconds) < frame / 2 }
            if !t.isDip {
                guard let left, handleAfter(left) + 1e-6 >= t.after, handleBefore(r) + 1e-6 >= t.before, t.after <= r.duration.seconds + 1e-6 else { s.clips[i].transition = nil; warnings.append("The \(t.type == "shader" ? "transition" : t.type) into \(label(r)) no longer had picture on both sides, so it's a straight cut now."); continue }
            } else if left == nil && t.before > 0 { s.clips[i].transition?.before = 0 }
        }
        return warnings
    }

    // MARK: Dispatch

    mutating func perform(_ op: EditOperation) throws -> Outcome {
        switch op.type {
        case "insert": return try insert(op, overwrite: false)
        case "overwrite": return try insert(op, overwrite: true)
        case "removeRange": return try removeRangeOp(op)
        case "remove": return try remove(op)
        case "move": return try move(op)
        case "split": return try split(op)
        case "trim": return try trim(op)
        case "roll": return try roll(op)
        case "slip": return try slip(op)
        case "slide": return try slide(op)
        case "splitEdit": return try splitEdit(op)
        case "replaceTake": return try replaceTake(op)
        case "removeWords": return try removeWords(op)
        case "tightenPauses": return try tightenPauses(op)
        case "speed": return try speed(op)
        case "freeze": return try freeze(op)
        case "reframe": return try reframe(op)
        case "balance", "color", "matchBalance": return try balance(op)
        case "frame":
            let i = try clipIndex(op.clipID); guard let framing = op.framing else { throw bad("frame takes a full framing.") }
            s.clips[i].framing = framing; return change("Framed \(label(s.clips[i]))", s.clips[i])
        case "cameraLUT": return try cameraLUT(op)
        case "addEffect": return try addEffect(op)
        case "setEffect": return try setEffect(op)
        case "removeEffect": return try removeEffect(op)
        case "transition": return try transition(op)
        case "removeTransition":
            let (_, ri) = try editPoint(op.editPoint, needsLeft: false)
            guard s.clips[ri].transition != nil else { throw bad("There's no transition into \(s.clips[ri].id).") }
            s.clips[ri].transition = nil
            return change("Took the transition out before \(label(s.clips[ri]))", s.clips[ri], head: true)
        case "cutaway": return try cutaway(op)
        case "layout": return try layout(op)
        case "punchIn": return try punchIn(op)
        case "emphasisPunch": return try emphasisPunch(op)
        case "slowPush": return try slowPush(op)
        case "autoZoom": return try autoZoom(op)
        case "technique": throw bad("\(op.transitionName ?? "A technique") is set up from the Techniques folder by Direction's tools; send it through direction_edit.")
        case "zoomTo": return try zoomTo(op)
        case "pin": return try pin(op)
        case "zoomThrough": return try zoomThrough(op)
        case "syncSound": return try syncSound(op)
        case "placeGraphic": return try placeGraphic(op)
        case "placeMade": return try placeMade(op)
        case "gain": return try gain(op)
        case "fade": return try fade(op)
        case "duck": return try duck(op)
        case "placeMusic": return try placeMusic(op)
        case "parts": return try partsOp(op)
        case "audio": return try audio(op)
        case "format":
            let was = FilmShape.label(width: s.width, height: s.height)
            if let width = op.width { s.width = width }; if let height = op.height { s.height = height }; if let rate = op.frameRate { s.frameRate = rate }
            var out = Outcome(summary: "Changed the format to \(s.width)×\(s.height)", changes: [.init(before: (0, s.duration.seconds), after: (0, s.duration.seconds), tracks: ["all"])])
            if FilmShape.label(width: s.width, height: s.height) != was, let placed = placedForFrame(was) { out.warnings.append(placed) }
            return out
        case "rename":
            if let name = op.text, !name.isEmpty { s.name = name }
            return .init(summary: "Renamed the cut")
        case "duplicateSequence":
            var copy = s; copy.id = newID("sequence"); copy.name = op.text ?? s.name + " copy"; if let w = op.width { copy.width = w }; if let h = op.height { copy.height = h }; project.sequences.append(copy)
            return .init(summary: "Duplicated \(s.name) as \(copy.name)")
        case "title":
            guard let text = op.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2_000 else { throw bad("Provide 1–2,000 title characters.") }
            var clip = Clip(assetID: nil, name: text, kind: .title, layer: op.layer ?? 100, start: op.at ?? .zero, sourceRange: op.range ?? .init(start: 0, end: 3))
            clip.title = text; s.clips.append(clip)
            return .init(summary: "Added a title", changes: [.init(before: (clip.start.seconds, clip.end.seconds), after: (clip.start.seconds, clip.end.seconds), tracks: [clip.trackName])], clipIDs: [clip.id])
        case "look", "setLook", "applyLook", "removeLook": throw DirectionError("look_is_yours", "The look is the director's. Propose looks with direction_make_look, as options or in a question.")
        default: throw DirectionError("unknown_op", "There's no operation \(op.type). direction_edit_catalog lists them.")
        }
    }

    func change(_ summary: String, _ c: Clip, head: Bool = false) -> Outcome {
        let a = head ? c.start.seconds - (c.transition?.before ?? 0) : c.start.seconds, b = head ? c.start.seconds + (c.transition?.after ?? frame) : c.end.seconds
        return .init(summary: summary, changes: [.init(before: (a, b), after: (a, b), tracks: [c.trackName])])
    }

    // MARK: Story

    mutating func insert(_ op: EditOperation, overwrite: Bool) throws -> Outcome {
        let a = try asset(op.assetID)
        let src = try sourceRange(op.sourceRange ?? op.range, of: a)
        let place: Track
        if let t = op.track {
            place = try parseTrack(t)
            if !place.audio && a.video.isEmpty { throw bad("\(a.name) has no picture; put it on an A track.") }
            if place.audio && a.audio.isEmpty { throw bad("\(a.name) has no sound.") }
        } else { place = (a.video.isEmpty, op.layer ?? 0) }
        let at = snap(op.at ?? s.duration)
        guard at >= .zero else { throw bad("at is a time in the cut.") }
        if let speed = op.speed { guard speed.isFinite, (0.1...8).contains(speed) else { throw bad("speed is 0.1 to 8.") } }
        let clip = Clip(assetID: a.id, name: a.name, kind: place.audio ? .audio : .video, layer: place.layer, start: at, sourceRange: src, speed: op.speed ?? 1)
        let d = clip.duration, span = (at.seconds, at.seconds + d.seconds)
        var out = Outcome(summary: overwrite ? "Put \(label(clip)) over \(tc(at))–\(tc(clip.end)) on \(name(place))" : "Inserted \(label(clip)) at \(tc(at))", clipIDs: [clip.id])
        if overwrite {
            s.clips = s.clips.filter { !on($0, place) } + EditReducer.removing(clip.range, from: s.clips.filter { on($0, place) }, ripple: false)
            out.changes = [.init(before: span, after: span, tracks: [name(place)])]
        } else if op.legacy {
            out.changes = [.init(before: (at.seconds, at.seconds), after: span, tracks: [name(place)])]
        } else {
            out.splices = [insertGap(at: at, d)]
            out.changes = [.init(before: (at.seconds, at.seconds), after: span, tracks: [name(place)])]
        }
        s.clips.append(clip)
        return out
    }

    mutating func removeRangeOp(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is required: {start, end} in cut seconds.") }
        var r = snap(raw)
        if r.end > s.duration && r.end.seconds <= s.duration.seconds + frame { r.duration = s.duration - r.start }
        guard r.isValid, r.end <= s.duration else { throw bad("range must fall inside the cut, 0–\(String(format: "%.2f", s.duration.seconds)) s.") }
        let ripple = op.ripple ?? true, tracks = tracksTouching(r.start.seconds, r.end.seconds)
        var out = Outcome(summary: "Removed \(tc(r.start))–\(tc(r.end))")
        if let sp = removeRange(r, ripple: ripple) { out.splices = [sp] }
        out.changes = [.init(before: (r.start.seconds, r.end.seconds), after: ripple ? (r.start.seconds, r.start.seconds) : (r.start.seconds, r.end.seconds), tracks: tracks)]
        return out
    }

    mutating func remove(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        let ripple = op.ripple ?? false, all = op.legacy || c.layer == 0
        var out = Outcome(summary: "Removed \(label(c))")
        if ripple && all {
            out.changes = [.init(before: (c.start.seconds, c.end.seconds), after: (c.start.seconds, c.start.seconds), tracks: tracksTouching(c.start.seconds, c.end.seconds))]
            if let sp = removeRange(c.range, ripple: true) { out.splices = [sp] }
        } else {
            s.clips.remove(at: i)
            if ripple { _ = shift(from: c.end, by: .zero - c.duration, except: nil, track: track(of: c)) }
            out.changes = [.init(before: (c.start.seconds, c.end.seconds), after: (c.start.seconds, ripple ? c.start.seconds : c.end.seconds), tracks: [c.trackName])]
            if ripple && !all { out.warnings.append("Only \(c.trackName) closed up; other tracks didn't move.") }
        }
        return out
    }

    mutating func move(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        if op.legacy && op.to == nil {
            guard let t = op.at else { throw bad("move takes to: {at}, {before: clip} or {after: clip}.") }
            s.clips[i].start = t; if let layer = op.layer { s.clips[i].layer = layer }
            return .init(summary: "Moved \(label(c))", changes: [.init(before: (c.start.seconds, c.end.seconds), after: (t.seconds, t.seconds + c.duration.seconds), tracks: [c.trackName, s.clips[i].trackName])])
        }
        guard let to = op.to, case .object = to else { throw bad("to is {at}, {before: clip} or {after: clip}.") }
        if let other = to["before"].string ?? to["after"].string, other == c.id { throw bad("A clip can't move next to itself.") }
        let d = c.duration
        if c.layer == 0 {
            // The story: lift everything over the clip, close the gap, and put it all back at the destination.
            let tracks = tracksTouching(c.start.seconds, c.end.seconds)
            let pieces = EditReducer.cutOut(c.range, from: s.clips)
            let out = removeRange(c.range, ripple: true)!
            let dest: MediaTime
            if let b = to["before"].string { dest = s.clips[try clipIndex(b, "to.before")].start }
            else if let a = to["after"].string { dest = s.clips[try clipIndex(a, "to.after")].end }
            else if let t = to["at"].double { dest = snap(MediaTime(seconds: out.forward(t))) }
            else { throw bad("to is {at}, {before: clip} or {after: clip}.") }
            guard dest >= .zero, dest <= s.duration else { throw bad("to.at must be inside the cut.") }
            let back = insertGap(at: dest, d)
            for p in pieces { var p = p; p.start = dest + p.start; s.clips.append(p) }
            return .init(summary: "Moved \(label(c)) to \(tc(dest))", changes: [.init(before: (c.start.seconds, c.end.seconds), after: (dest.seconds, dest.seconds + d.seconds), tracks: tracks)], splices: [out, back])
        }
        // Over the story, a clip just moves, on its track or another.
        var dest: MediaTime
        if let b = to["before"].string { dest = s.clips[try clipIndex(b, "to.before")].start - d }
        else if let a = to["after"].string { dest = s.clips[try clipIndex(a, "to.after")].end }
        else if let t = to["at"].double { dest = snap(MediaTime(seconds: t)) }
        else { throw bad("to is {at}, {before: clip} or {after: clip}.") }
        guard dest >= .zero else { throw bad("That would start \(label(c)) before the cut does.") }
        dest = snap(dest)
        // A song's part takes the stretch of the song it's in with it; a new track is that part's.
        let together = withSong(i), delta = dest - c.start
        guard together.allSatisfy({ s.clips[$0].start + delta >= .zero }) else { throw bad("That would start \(song(of: c) ?? label(c)) before the cut does.") }
        var tracks = Set(together.map { s.clips[$0].trackName })
        if let t = to["track"].string {
            let p = try parseTrack(t); guard p.audio == (c.kind == .audio) else { throw bad("Picture stays on V tracks and sound on A tracks.") }
            for k in together where s.clips[k].assetID == c.assetID { s.clips[k].layer = p.layer }
        }
        for k in together { s.clips[k].start = s.clips[k].start + delta }
        tracks.formUnion(together.map { s.clips[$0].trackName })
        let span = (together.map { s.clips[$0].start.seconds - delta.seconds }.min()!, together.map { s.clips[$0].end.seconds - delta.seconds }.max()!)
        return .init(summary: "Moved \(songLabel(c, together.count)) to \(tc(dest))", changes: [.init(before: span, after: (span.0 + delta.seconds, span.1 + delta.seconds), tracks: tracks.sorted())])
    }

    mutating func split(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard let raw = op.at else { throw bad("at is the cut time to split at.") }
        let t = snap(raw)
        guard t.seconds > c.start.seconds + 1e-9 && t.seconds < c.end.seconds - 1e-9 else { throw bad("Split inside the clip, between \(tc(c.start)) and \(tc(c.end)).") }
        let (l, r) = EditReducer.split(c, at: t)
        s.clips.replaceSubrange(i...i, with: [l, r])
        return .init(summary: "Split \(label(c)) at \(tc(t))", changes: [.init(before: (t.seconds, t.seconds), after: (t.seconds, t.seconds), tracks: [c.trackName])], clipIDs: [r.id])
    }

    mutating func trim(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        if op.edge == nil, let r = op.range {
            // The old shape: a new source range.
            s.clips[i].sourceRange = r
            if op.ripple == true { let delta = s.clips[i].end - c.end; for k in s.clips.indices where k != i && s.clips[k].start >= c.end { s.clips[k].start = s.clips[k].start + delta } }
            return .init(summary: "Trimmed \(label(c))", changes: [.init(before: (c.start.seconds, c.end.seconds), after: (c.start.seconds, s.clips[i].end.seconds), tracks: [c.trackName])])
        }
        guard let edge = op.edge, edge == "head" || edge == "tail" else { throw bad("edge is head or tail.") }
        guard let n = op.frames, n != 0 else { throw bad("frames is a whole number: positive lengthens, negative shortens.") }
        // A song's part trims where it stands, so the song's other parts stay in time with what follows it.
        let d = frames(abs(n)), ds = d.seconds, ripple = op.ripple ?? (song(of: c) == nil), story = c.layer == 0
        let summary = "\(n > 0 ? "Extended" : "Trimmed") \(label(c))’s \(edge), \(deltaText(secs(n)))"
        if n < 0 { guard c.duration.seconds - ds >= frame - 1e-9 else { throw bad("\(c.id) is only \(framesText(c.duration.seconds)) long.") } }
        if n > 0 {
            let h = edge == "tail" ? handleAfter(c) : handleBefore(c)
            guard h + 1e-6 >= ds else { throw bad("\(label(c)) has only \(framesText(h)) \(edge == "tail" ? "after its out point" : "before its in point").") }
        }
        var out = Outcome(summary: summary)
        let start = c.start.seconds, end = c.end.seconds
        if edge == "tail" {
            if n > 0 {
                if ripple, let sp = shift(from: c.end, by: d, except: c.id, track: story ? nil : track(of: c)) { out.splices = [sp] }
                s.clips[i] = lengthened(c, by: d, head: false)
                out.changes = [.init(before: (end, end), after: (end, end + ds), tracks: [c.trackName])]
            } else if ripple && story {
                out.splices = [removeRange(.init(start: c.end - d, duration: d), ripple: true)!]
                restoreEdges(of: c, tail: true)
                out.changes = [.init(before: (end - ds, end), after: (end - ds, end - ds), tracks: tracksTouching(end - ds, end))]
            } else {
                s.clips[i] = lengthened(c, by: .zero - d, head: false)
                if ripple { _ = shift(from: c.end, by: .zero - d, except: c.id, track: track(of: c)) }
                out.changes = [.init(before: (end - ds, end), after: (end - ds, ripple ? end - ds : end), tracks: [c.trackName])]
            }
        } else if n > 0 {
            if ripple {
                if let sp = shift(from: c.start, by: d, except: c.id, track: story ? nil : track(of: c)) { out.splices = [sp] }
                s.clips[i] = lengthened(c, by: d, head: true)
                out.changes = [.init(before: (start, start), after: (start, start + ds), tracks: [c.trackName])]
            } else {
                guard start - ds >= -1e-9 else { throw bad("There's no room before \(label(c)) to extend its head; use ripple.") }
                var l = lengthened(c, by: d, head: true); l.start = c.start - d; s.clips[i] = l
                out.changes = [.init(before: (start - ds, start), after: (start - ds, start), tracks: [c.trackName])]
            }
        } else if ripple && story {
            out.splices = [removeRange(.init(start: c.start, duration: d), ripple: true)!]
            restoreEdges(of: c, tail: false)
            out.changes = [.init(before: (start, start + ds), after: (start, start), tracks: tracksTouching(start, start + ds))]
        } else {
            var l = lengthened(c, by: .zero - d, head: true)
            if ripple { s.clips[i] = l; _ = shift(from: c.end, by: .zero - d, except: c.id, track: track(of: c)) }
            else { l.start = c.start + d; s.clips[i] = l }
            out.changes = [.init(before: (start, start + ds), after: (start, ripple ? start : start + ds), tracks: [c.trackName])]
        }
        return out
    }
    /// A trim keeps the clip's own transition, J- and L-cuts and fades on the edge it trimmed.
    mutating func restoreEdges(of c: Clip, tail: Bool) {
        guard let i = s.clips.firstIndex(where: { $0.id == c.id }) else { return }
        if tail { s.clips[i].soundTail = c.soundTail; s.clips[i].fadeOut = c.fadeOut } else { s.clips[i].transition = c.transition; s.clips[i].soundLead = c.soundLead; s.clips[i].fadeIn = c.fadeIn }
    }

    mutating func roll(_ op: EditOperation) throws -> Outcome {
        let (li, r) = try editPoint(op.editPoint); let l = li!
        guard let n = op.frames, n != 0 else { throw bad("frames moves the cut: positive later, negative earlier.") }
        let d = frames(abs(n)), ds = d.seconds
        var L = s.clips[l], R = s.clips[r]
        let cut = R.start.seconds
        if n > 0 {
            guard handleAfter(L) + 1e-6 >= ds else { throw bad("\(label(L)) has only \(framesText(handleAfter(L))) after its out point.") }
            guard R.duration.seconds - ds >= frame - 1e-9 else { throw bad("\(label(R)) is only \(framesText(R.duration.seconds)) long.") }
            L = lengthened(L, by: d, head: false); R = lengthened(R, by: .zero - d, head: true); R.start = R.start + d
        } else {
            guard handleBefore(R) + 1e-6 >= ds else { throw bad("\(label(R)) has only \(framesText(handleBefore(R))) before its in point.") }
            guard L.duration.seconds - ds >= frame - 1e-9 else { throw bad("\(label(L)) is only \(framesText(L.duration.seconds)) long.") }
            L = lengthened(L, by: .zero - d, head: false); R = lengthened(R, by: d, head: true); R.start = R.start - d
        }
        s.clips[l] = L; s.clips[r] = R
        let span = (min(cut, R.start.seconds), max(cut, R.start.seconds))
        return .init(summary: "Rolled the cut from \(label(L)) to \(label(R)) \(framesText(ds)) \(n > 0 ? "later" : "earlier")", changes: [.init(before: span, after: span, tracks: [R.trackName])])
    }

    mutating func slip(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard let n = op.frames, n != 0 else { throw bad("frames slips the take: positive shows later footage.") }
        let ds = secs(abs(n)), together = withSong(i)
        // A song's parts slip together, so they still play the same moment of it.
        for k in together {
            let x = s.clips[k]
            if n > 0 { guard handleAfter(x) + 1e-6 >= ds else { throw bad("\(label(x)) has only \(framesText(handleAfter(x))) after its out point.") } }
            else { guard handleBefore(x) + 1e-6 >= ds else { throw bad("\(label(x)) has only \(framesText(handleBefore(x))) before its in point.") } }
        }
        for k in together { s.clips[k].sourceRange.start = s.clips[k].sourceRange.start + frames(n).scaled(by: s.clips[k].speed) }
        if together.count > 1 {
            let span = (together.map { s.clips[$0].start.seconds }.min()!, together.map { s.clips[$0].end.seconds }.max()!)
            return .init(summary: "Slipped \(song(of: c)!) \(framesText(ds)) \(n > 0 ? "later" : "earlier") in the song", changes: [.init(before: span, after: span, tracks: Set(together.map { s.clips[$0].trackName }).sorted())])
        }
        return change("Slipped \(label(c)) \(framesText(ds)) \(n > 0 ? "later" : "earlier") in the take", c)
    }

    mutating func slide(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i], t = track(of: c)
        if let g = song(of: c) { throw bad("\(g)\u{2019}s parts play in time together: move it with move, or say where each part is heard with parts.") }
        guard let n = op.frames, n != 0 else { throw bad("frames slides the clip: positive later, negative earlier.") }
        let d = frames(abs(n)), ds = d.seconds
        let li = s.clips.firstIndex { $0.id != c.id && on($0, t) && abs($0.end.seconds - c.start.seconds) < frame / 2 }
        let ri = s.clips.firstIndex { $0.id != c.id && on($0, t) && abs($0.start.seconds - c.end.seconds) < frame / 2 }
        if n > 0 {
            if let ri { let R = s.clips[ri]; guard R.duration.seconds - ds >= frame - 1e-9 else { throw bad("\(label(R)) is only \(framesText(R.duration.seconds)) long.") }; var r = lengthened(R, by: .zero - d, head: true); r.start = R.start + d; s.clips[ri] = r }
            else { guard free(t, .init(start: c.end, duration: d), except: c.id) else { throw DirectionError("overlap", "There's no room after \(label(c)).") } }
            if let li { let L = s.clips[li]; guard handleAfter(L) + 1e-6 >= ds else { throw bad("\(label(L)) has only \(framesText(handleAfter(L))) after its out point.") }; s.clips[li] = lengthened(L, by: d, head: false) }
            s.clips[i].start = c.start + d
        } else {
            guard c.start.seconds - ds >= -1e-9 else { throw bad("That would slide \(label(c)) before the cut starts.") }
            if let li { let L = s.clips[li]; guard L.duration.seconds - ds >= frame - 1e-9 else { throw bad("\(label(L)) is only \(framesText(L.duration.seconds)) long.") }; s.clips[li] = lengthened(L, by: .zero - d, head: false) }
            else { guard free(t, .init(start: c.start - d, duration: d), except: c.id) else { throw DirectionError("overlap", "There's no room before \(label(c)).") } }
            if let ri { let R = s.clips[ri]; guard handleBefore(R) + 1e-6 >= ds else { throw bad("\(label(R)) has only \(framesText(handleBefore(R))) before its in point.") }; var r = lengthened(R, by: d, head: true); r.start = R.start - d; s.clips[ri] = r }
            s.clips[i].start = c.start - d
        }
        let span = (min(c.start.seconds, s.clips[i].start.seconds), max(c.end.seconds, s.clips[i].end.seconds))
        return .init(summary: "Slid \(label(c)) \(framesText(ds)) \(n > 0 ? "later" : "earlier")", changes: [.init(before: span, after: span, tracks: [c.trackName])])
    }

    mutating func splitEdit(_ op: EditOperation) throws -> Outcome {
        let (li, r) = try editPoint(op.editPoint); let l = li!
        guard let lead = op.lead, lead == "sound" || lead == "picture" else { throw bad("lead is sound (a J-cut) or picture (an L-cut).") }
        guard let n = op.frames, n >= 0 else { throw bad("frames is how far the sound leads or carries; 0 makes it a straight cut again.") }
        let L = s.clips[l], R = s.clips[r], N = secs(n)
        guard hasSound(L) || hasSound(R) else { throw bad("Neither clip has sound.") }
        if n == 0 { s.clips[l].soundTail = nil; s.clips[r].soundLead = nil }
        else if lead == "sound" {
            guard handleBefore(R) + 1e-6 >= N else { throw bad("\(label(R)) has only \(framesText(handleBefore(R))) before its in point for its sound to lead.") }
            guard L.duration.seconds - N >= frame - 1e-9 else { throw bad("\(label(L)) is shorter than that.") }
            s.clips[r].soundLead = N; s.clips[l].soundTail = -N
        } else {
            guard handleAfter(L) + 1e-6 >= N else { throw bad("\(label(L)) has only \(framesText(handleAfter(L))) after its out point for its sound to carry.") }
            guard R.duration.seconds - N >= frame - 1e-9 else { throw bad("\(label(R)) is shorter than that.") }
            s.clips[l].soundTail = N; s.clips[r].soundLead = -N
        }
        let cut = R.start.seconds
        let summary = n == 0 ? "Made the cut into \(label(R)) straight" : lead == "sound" ? "J-cut: \(label(R))’s sound starts \(framesText(N)) early" : "L-cut: \(label(L))’s sound carries \(framesText(N)) over"
        return .init(summary: summary, changes: [.init(before: (cut - N, cut + N), after: (cut - N, cut + N), tracks: ["A1"])])
    }

    mutating func replaceTake(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard c.hold == nil, c.kind != .title, let old = assetOf(c) else { throw bad("replaceTake swaps the footage of a clip.") }
        let new = try asset(op.withAssetID, "withAssetID")
        guard c.kind == .audio || !new.video.isEmpty else { throw bad("\(new.name) has no picture.") }
        let align = op.alignOn ?? "words"
        guard ["words", "head", "tail"].contains(align) else { throw bad("alignOn is words, head or tail.") }
        var src: MediaRange, warnings: [String] = []
        let length = c.sourceRange.duration
        switch align {
        case "head":
            let start = min(c.sourceRange.start, new.isImage ? c.sourceRange.start : max(.zero, new.duration - length))
            src = .init(start: start, duration: new.isImage ? length : min(length, new.duration - start))
        case "tail":
            let end = new.isImage ? c.sourceRange.end : max(min(new.duration, new.duration - (old.duration - c.sourceRange.end)), min(length, new.duration))
            let start = max(.zero, end - length)
            src = .init(start: start, duration: end - start)
        default:
            let oldWords = TranscriptEditing.sourceWords(old.id, transcripts).filter { c.sourceRange.contains(MediaTime(seconds: ($0.range.start.seconds + $0.range.end.seconds) / 2)) }
            let newWords = TranscriptEditing.sourceWords(new.id, transcripts)
            guard !oldWords.isEmpty else { throw DirectionError("no_words", "\(label(c)) has no transcript to line up. Transcribe it, or align on head or tail.") }
            guard !newWords.isEmpty else { throw DirectionError("no_words", "\(new.name) has no transcript. Transcribe it, or align on head or tail.") }
            let pairs = TranscriptEditing.align(oldWords.map(\.text), newWords.map(\.text))
            guard let first = pairs.first, let last = pairs.last, pairs.count >= max(1, oldWords.count / 2) else { throw bad("\(new.name) doesn't have this line.") }
            if pairs.count < oldWords.count { warnings.append("\(new.name) reads it differently: \(pairs.count) of \(oldWords.count) words match.") }
            // The first matched word lands where the old take's did; the tail keeps the same room after the last one.
            let startOffset = oldWords[first.0].range.start - c.sourceRange.start
            let start = newWords[first.1].range.start - startOffset
            guard start.seconds >= -frame / 2 else { throw bad("\(new.name) starts only \(String(format: "%.2f", newWords[first.1].range.start.seconds)) s before the line; there isn't enough take before it.") }
            let room = c.sourceRange.end - oldWords[last.0].range.end
            var end = newWords[last.1].range.end + (room > .zero ? room : .zero)
            if end > new.duration { end = new.duration }
            let s0 = max(.zero, start)
            // The clip's new length is whole frames, without running past the take.
            let length = snap(end - s0)
            src = .init(start: s0, duration: s0 + length > new.duration ? snapDown(end - s0) : length)
        }
        guard src.isValid else { throw bad("\(new.name) is too short to use here.") }
        let offset = (src.start - c.sourceRange.start).seconds
        func moved(_ k: [Keyframe]) -> [Keyframe] { k.map { Keyframe(t: $0.t + offset, v: $0.v, ease: $0.ease) } }
        var n = c
        n.assetID = new.id; n.name = new.name; n.sourceRange = src
        n.effects = c.effects?.map { e in var e = e; e.keys = e.keys?.mapValues(moved); return e }
        n.gainKeys = c.gainKeys.map(moved); n.duckKeys = c.duckKeys.map(moved)
        n.audioOverrides = c.audioOverrides.filter { k, _ in new.audio.contains { String($0.id) == k } }
        s.clips[i] = n
        var out = Outcome(summary: "Used \(label(n))’s reading for \(label(c))", warnings: warnings)
        let delta = n.end - c.end
        if (op.ripple ?? true) && abs(delta.seconds) > 1e-9 {
            if delta > .zero { if let sp = shift(from: c.end, by: delta, except: n.id, track: c.layer == 0 ? nil : track(of: c)) { out.splices = [sp] } }
            else if c.layer == 0 { out.splices = [removeRange(.init(start: n.end, duration: .zero - delta), except: n.id)] }
            else { _ = shift(from: c.end, by: delta, except: n.id, track: track(of: c)) }
        }
        out.changes = [.init(before: (c.start.seconds, c.end.seconds), after: (n.start.seconds, n.end.seconds), tracks: hasSound(n) && n.kind == .video && n.layer == 0 ? ["A1", "V1"] : [n.trackName])]
        return out
    }

    mutating func removeWords(_ op: EditOperation) throws -> Outcome {
        guard let ids = op.wordIDs, !ids.isEmpty else { throw bad("wordIDs lists the words to cut, from direction_transcript.") }
        let words = TranscriptEditing.words(in: s, transcripts: transcripts)
        guard !words.isEmpty else { throw DirectionError("no_words", "This cut has no transcript yet. Transcribe its takes first.") }
        let ranges = try TranscriptEditing.deletionRanges(wordIDs: Set(ids), words: words).map { MediaRange(start: snapDown($0.start), duration: snapUp($0.end) - snapDown($0.start)) }
        var merged: [MediaRange] = []
        for r in ranges.sorted(by: { $0.start > $1.start }) { if let last = merged.last, r.end >= last.start { merged[merged.count - 1] = .init(start: r.start, duration: max(last.end, r.end) - r.start) } else { merged.append(r) } }
        var out = Outcome(summary: "Cut \(ids.count) \(ids.count == 1 ? "word" : "words")")
        for r in merged {
            out.changes.append(.init(before: (r.start.seconds, r.end.seconds), after: nil, tracks: tracksTouching(r.start.seconds, r.end.seconds)))
            out.splices.append(removeRange(r, ripple: true)!)
        }
        return out
    }

    mutating func tightenPauses(_ op: EditOperation) throws -> Outcome {
        guard let raw = op.range else { throw bad("range is required: where to look for pauses.") }
        guard let longer = op.longerThan, longer > 0, longer < 60 else { throw bad("longerThan is the shortest pause to tighten, in seconds.") }
        guard let keep = op.to?.double, keep >= 0, keep < longer else { throw bad("to is how long each pause becomes, in seconds, less than longerThan.") }
        let r = snap(raw)
        let words = TranscriptEditing.words(in: s, transcripts: transcripts).filter { $0.range.end > r.start && $0.range.start < r.end }
        guard words.count >= 1 else { throw DirectionError("no_words", "There are no words between \(tc(r.start)) and \(tc(r.end)) to find pauses from. Transcribe the take first.") }
        var cuts: [MediaRange] = []
        for (a, b) in zip(words, words.dropFirst()) {
            let gapStart = a.range.end.seconds, gapEnd = b.range.start.seconds, gap = gapEnd - gapStart
            guard gap > longer + 1e-6, gapStart >= r.start.seconds - 1e-9, gapEnd <= r.end.seconds + 1e-9 else { continue }
            var lo = gapStart + keep / 2, hi = gapEnd - keep / 2
            // With measured sound, only the quiet part of a pause goes, so a breath or a laugh stays.
            if let quiet = op.resolved?.quiet {
                let pieces = quiet.compactMap { q -> (Double, Double)? in let x = max(q.start.seconds, gapStart), y = min(q.end.seconds, gapEnd); return y > x ? (x, y) : nil }
                guard let best = pieces.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }) else { continue }
                let want = min(gap - keep, best.1 - best.0), mid = (best.0 + best.1) / 2
                lo = mid - want / 2; hi = mid + want / 2
            }
            // Inward to whole frames, so a cut never reaches into a word.
            let a0 = snapUp(MediaTime(seconds: max(lo, gapStart))), b0 = snapDown(MediaTime(seconds: min(hi, gapEnd)))
            if b0 > a0 { cuts.append(.init(start: a0, duration: b0 - a0)) }
        }
        let total = cuts.reduce(0) { $0 + $1.duration.seconds }
        var out = Outcome(summary: cuts.isEmpty ? "Found no pauses longer than \(longer) s" : "Tightened \(cuts.count) \(cuts.count == 1 ? "pause" : "pauses"), \(deltaText(-total))")
        for c in cuts.reversed() {
            out.changes.append(.init(before: (c.start.seconds, c.end.seconds), after: nil, tracks: tracksTouching(c.start.seconds, c.end.seconds)))
            out.splices.append(removeRange(c, ripple: true)!)
        }
        return out
    }

    mutating func speed(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard c.hold == nil else { throw bad("A freeze has no speed.") }
        if let g = song(of: c) { throw bad("\(g) plays at its own speed, so its parts stay in time.") }
        guard let rate = op.rate ?? op.speed, rate.isFinite, (0.1...8).contains(rate) else { throw bad("rate is 0.1 to 8; 2 plays twice as fast.") }
        s.clips[i].speed = rate
        if !op.legacy, let a = assetOf(c) {
            // Whole frames in the cut, without running past the take.
            let n = max(1, (c.sourceRange.duration.seconds / rate / frame).rounded())
            var d = MediaTime(seconds: n * frame * rate)
            if !a.isImage && c.sourceRange.start + d > a.duration { d = MediaTime(seconds: ((a.duration - c.sourceRange.start).seconds / rate / frame).rounded(.down) * frame * rate) }
            s.clips[i].sourceRange.duration = d
        }
        let delta = s.clips[i].end - c.end
        var out = Outcome(summary: "Set \(label(c)) to \(String(format: "%g", rate))× speed")
        if op.ripple ?? true {
            for k in s.clips.indices where k != i && s.clips[k].start.seconds >= c.end.seconds - 1e-9 && (op.legacy || c.layer == 0 || on(s.clips[k], track(of: c))) { s.clips[k].start = s.clips[k].start + delta }
            if op.legacy || c.layer == 0 { let sp = Splice(at: c.start.seconds, removed: c.duration.seconds, inserted: s.clips[i].duration.seconds); spliceTrackKeys(sp); out.splices = [sp] }
        }
        out.changes = [.init(before: (c.start.seconds, c.end.seconds), after: (c.start.seconds, s.clips[i].end.seconds), tracks: [c.trackName])]
        return out
    }

    mutating func freeze(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard c.kind != .audio, c.hold == nil else { throw bad("Freeze holds a frame of picture.") }
        guard let raw = op.at else { throw bad("at is the cut time of the frame to hold.") }
        guard let seconds = op.seconds, seconds > 0, seconds <= 600 else { throw bad("seconds is how long to hold, up to 600.") }
        let at = snap(raw)
        guard at >= c.start, at < c.end else { throw bad("at must be inside \(label(c)), \(tc(c.start))–\(tc(c.end)).") }
        let held = frames(max(1, Int((seconds / frame).rounded())))
        var hold = c
        // A lineage of its own: it shows the same source frame as the clip after it, and notes there would match both.
        hold.id = newID("clip"); hold.lineageID = hold.id; hold.effects = EditReducer.reIDed(c.effects)
        hold.start = at; hold.sourceRange = .init(start: c.sourceTime(at: at), duration: frames(1).scaled(by: c.speed)); hold.hold = held
        // Keys on a held frame play over the hold, so the frame keeps the values it had: a follow stays put.
        let frozen = hold.sourceRange.start.seconds
        hold.effects = hold.effects?.map { e in
            guard e.name != "stabilize", let keys = e.keys, !keys.isEmpty else { return e }
            var e = e
            for k in keys.keys { e.params[k] = .number(e.number(k, at: frozen, default: 0)) }
            e.keys = nil
            return e
        }
        hold.transition = nil; hold.soundLead = nil; hold.soundTail = nil; hold.fadeIn = nil; hold.fadeOut = nil
        let sp = insertGap(at: at, held)
        s.clips.append(hold)
        return .init(summary: "Held \(label(c))’s frame at \(tc(at)) for \(String(format: "%.1f", held.seconds)) s", changes: [.init(before: (at.seconds, at.seconds), after: (at.seconds, at.seconds + held.seconds), tracks: tracksTouching(at.seconds, at.seconds + held.seconds))], splices: [sp], clipIDs: [hold.id])
    }

    // MARK: Picture

    /// Keys from the editor, in cut seconds, into a clip's source seconds.
    func sourceKeys(_ keys: [String: [Keyframe]], _ c: Clip?) -> [String: [Keyframe]] {
        guard let c else { return keys.mapValues { $0.sorted { $0.t < $1.t } } }
        return keys.mapValues { k in k.map { Keyframe(t: c.sourceRange.start.seconds + ($0.t - c.start.seconds) * c.speed, v: $0.v, ease: $0.ease) }.sorted { $0.t < $1.t } }
    }

    mutating func reframe(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard c.kind != .audio else { throw bad("reframe works on picture.") }
        guard let scale = op.scale, (0.1...8).contains(scale) else { throw bad("scale is 0.1 to 8.") }
        for (k, v) in [("x", op.x), ("y", op.y)] { if let v { guard (-1...1).contains(v) else { throw bad("\(k) is −1 to 1, a fraction of the frame.") } } }
        if let keep = op.keepIn { guard keep == "thirds" || keep == "center" else { throw bad("keepIn is thirds or center.") } }
        var params: [String: JSONValue] = ["scale": .number(scale)]
        if let x = op.x { params["x"] = .number(x) }; if let y = op.y { params["y"] = .number(y) }
        var keys: [String: [Keyframe]] = [:]
        if let f = op.follow {
            guard f == "face" || f == "subject" else { throw bad("follow is face or subject.") }
            guard let found = op.resolved?.keys, found["x"] != nil else { throw bad("follow: \(f) is tracked by Direction's tools; send it through direction_edit.") }
            keys.merge(found) { _, b in b }
        }
        if let k = op.keys { keys.merge(try checkedKeys("transform", k, c)) { _, b in b } }
        var fx = c.effects?.first { $0.name == "transform" } ?? ClipEffect(name: "transform")
        fx.params.merge(params) { _, b in b }
        var all = fx.keys ?? [:]
        if op.follow == nil { if op.x != nil { all["x"] = nil }; if op.y != nil { all["y"] = nil } }
        all.merge(keys) { _, b in b }
        fx.keys = all.isEmpty ? nil : all
        setEffect(fx, on: i)
        var out = change("Reframed \(label(c)) to \(String(format: "%g", scale))×" + (op.follow.map { " following the \($0)" } ?? ""), c)
        out.effectID = fx.id
        return out
    }
    mutating func setEffect(_ fx: ClipEffect, on i: Int) {
        var effects = s.clips[i].effects ?? []
        if let k = effects.firstIndex(where: { $0.id == fx.id }) { effects[k] = fx } else if fx.name == "transform" { effects.insert(fx, at: 0) } else { effects.append(fx) }
        s.clips[i].effects = effects
    }

    mutating func balance(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard c.kind != .audio else { throw bad("Balance works on picture.") }
        var g = c.grade, summary = "Balanced \(label(c))"
        switch op.type {
        case "color": guard let full = op.grade else { throw bad("color takes a full grade.") }; g = full
        case "matchBalance":
            let target = try clipIndex(op.toClipID, "toClipID")
            guard let measured = op.resolved?.grade else { throw bad("matchBalance is measured by Direction's tools; send it through direction_edit.") }
            g = measured; summary = "Matched \(label(c))’s balance to \(label(s.clips[target]))"
        default:
            guard [op.exposure, op.contrast, op.saturation, op.temperature, op.tint].contains(where: { $0 != nil }) else { throw bad("balance takes exposure, contrast, saturation, temperature or tint.") }
            if let v = op.exposure { g.exposure = v }; if let v = op.contrast { g.contrast = v }; if let v = op.saturation { g.saturation = v }
            if let v = op.temperature { g.temperature = v }; if let v = op.tint { g.tint = v }
        }
        guard (-5...5).contains(g.exposure), (0...4).contains(g.contrast), (0...3).contains(g.saturation), (-3_000...3_000).contains(g.temperature), (-100...100).contains(g.tint) else { throw bad("Balance ranges: exposure −5–5, contrast 0–4, saturation 0–3, temperature −3000–3000, tint −100–100.") }
        s.clips[i].grade = g
        return change(summary, c)
    }

    mutating func cameraLUT(_ op: EditOperation) throws -> Outcome {
        let a = try asset(op.assetID)
        guard let lut = op.lut, !lut.isEmpty else { throw bad("lut is auto, none or a .cube file.") }
        var value = lut
        if lut != "auto" && lut != "none" {
            guard lut.lowercased().hasSuffix(".cube") else { throw bad("A camera LUT is a .cube file.") }
            let candidates = lut.hasPrefix("/") ? [URL(fileURLWithPath: lut)] : [context?.filmURL?.appendingPathComponent("Looks/Camera").appendingPathComponent(lut), context?.filmURL?.appendingPathComponent(lut)].compactMap { $0 }
            guard let found = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else { throw DirectionError("missing_media", "Can't find the LUT \(lut).") }
            value = found.standardizedFileURL.path
        }
        guard let k = project.assets.firstIndex(where: { $0.id == a.id }) else { throw DirectionError("missing_media", "There's no footage \(a.id).") }
        project.assets[k].cameraLUT = value
        let uses = s.clips.filter { $0.assetID == a.id }
        return .init(summary: lut == "none" ? "Took the camera LUT off \(a.name)" : "Set \(a.name)’s camera LUT to \(lut == "auto" ? "automatic" : URL(fileURLWithPath: value).lastPathComponent)", changes: uses.map { .init(before: ($0.start.seconds, $0.end.seconds), after: ($0.start.seconds, $0.end.seconds), tracks: [$0.trackName]) })
    }

    /// Checks parameters against the catalog (or a shader's own header) and merges them over `old`.
    func checkedParams(_ effect: String, _ params: [String: JSONValue], over old: [String: JSONValue] = [:], source: String? = nil) throws -> [String: JSONValue] {
        let specs: [EditCatalog.Param]
        if effect == "shader" { specs = [.init(name: "file", kind: "text")] + (try ShaderHeader.params(source ?? "")).map(\.catalogParam) }
        else { guard let e = EditCatalog.effect(effect) else { throw bad("There's no effect \(effect). direction_edit_catalog lists them.") }; specs = e.params }
        var out = old
        for (k, v) in params {
            guard let p = specs.first(where: { $0.name == k }) else { throw bad("\(effect) has no parameter \(k). It takes \(specs.map(\.name).joined(separator: ", ")).") }
            switch p.kind {
            case "number": guard let n = v.double, n.isFinite, n >= (p.min ?? -.infinity), n <= (p.max ?? .infinity) else { throw bad("\(effect).\(k) is \(p.rangeText).") }
            case "bool": guard v.bool != nil else { throw bad("\(effect).\(k) is true or false.") }
            case "choice": guard let c = v.string, p.choices?.contains(c) ?? false else { throw bad("\(effect).\(k) is one of \(p.choices?.joined(separator: ", ") ?? "").") }
            case "crop": guard case .object(let parts) = v, parts.allSatisfy({ ["l", "r", "t", "b"].contains($0.key) && ($0.value.double.map { (0...0.5).contains($0) } ?? false) }) else { throw bad("\(effect).crop is {l, r, t, b}, each 0–0.5.") }
            case "color": guard let c = v.string, ShaderHeader.rgb(c) != nil else { throw bad("\(effect).\(k) is a color like #F2A33A.") }
            default: guard v.string != nil else { throw bad("\(effect).\(k) is text.") }
            }
            out[k] = v
        }
        return out
    }
    /// Checks keys and moves them from cut seconds to the clip's source seconds.
    func checkedKeys(_ effect: String, _ keys: [String: [Keyframe]], _ c: Clip?, source: String? = nil) throws -> [String: [Keyframe]] {
        let specs: [EditCatalog.Param]
        if effect == "shader" { specs = (try ShaderHeader.params(source ?? "")).map(\.catalogParam) }
        else { guard let e = EditCatalog.effect(effect), e.keys else { throw bad("\(effect) can't be keyed.") }; specs = e.params }
        for (k, list) in keys {
            let base = k.split(separator: ".").first.map(String.init) ?? k
            guard let p = specs.first(where: { $0.name == k && $0.kind == "number" }) ?? specs.first(where: { $0.name == base && ($0.kind == "number" || $0.kind == "crop") }), p.keyable else { throw bad("\(effect) can't key \(k).") }
            if p.kind == "crop" { guard k.split(separator: ".").count == 2, ["l", "r", "t", "b"].contains(String(k.split(separator: ".")[1])) else { throw bad("Key the crop as crop.l, crop.r, crop.t or crop.b.") } }
            guard !list.isEmpty, list.count <= 10_000 else { throw bad("\(k) needs 1–10,000 keys.") }
            for key in list { guard key.t.isFinite, key.v.isFinite, key.v >= (p.kind == "crop" ? 0 : p.min ?? -.infinity), key.v <= (p.kind == "crop" ? 0.5 : p.max ?? .infinity) else { throw bad("Keys for \(k) are \(p.kind == "crop" ? "0–0.5" : p.rangeText), at times in cut seconds.") }; if let e = key.ease { guard ["linear", "hold", "smooth"].contains(e) else { throw bad("ease is linear, hold or smooth.") } } }
        }
        return sourceKeys(keys, c)
    }

    /// The clip or track an effect goes on.
    enum EffectTarget { case clip(Int), track(String) }
    func effectTarget(_ value: String?) throws -> EffectTarget {
        guard let value, !value.isEmpty else { throw bad("target is a clip id or a track (V2).") }
        if let i = s.clips.firstIndex(where: { $0.id == value }) { return .clip(i) }
        if let t = try? parseTrack(value) { guard !t.audio else { throw bad("Sound tracks take gain and duck, not picture effects.") }; return .track(name(t)) }
        throw bad("There's no clip or track \(value). Read direction_timeline for ids.")
    }

    mutating func addEffect(_ op: EditOperation) throws -> Outcome {
        guard let effect = op.effect, !effect.isEmpty else { throw bad("effect names the effect: transform, blend, mask, blur, sharpen, stabilize, filter.<kind> or shader.") }
        if effect == "look" || effect == "lut" { throw DirectionError("look_is_yours", "The look is the director's. Propose one instead.") }
        let target = try effectTarget(op.target ?? op.clipID)
        if effect == "blend" {
            guard case .clip(let i) = target else { throw bad("blend goes on a clip on V2 or above.") }
            guard s.clips[i].layer > 0, s.clips[i].kind != .audio else { throw bad("Only clips on V2 and above blend into what's under them.") }
            let mode = try checkedParams("blend", op.params ?? [:])["mode"]?.string ?? "normal"
            s.clips[i].blend = mode
            var out = change("Blended \(label(s.clips[i])) with \(mode)", s.clips[i]); out.effectID = s.clips[i].id + ":blend"; return out
        }
        if effect == "shader" { guard op.resolved?.source != nil else { throw bad("A shader is compiled and checked by Direction's tools; send it through direction_edit.") } }
        if effect == "stabilize" { guard case .clip(_) = target, op.resolved?.keys != nil else { throw bad("stabilize is measured per clip by Direction's tools; send it through direction_edit.") } }
        if effect == "pixelGrid" { guard case .clip(_) = target, op.resolved?.data != nil else { throw bad("pixelGrid finds the subject square by square with Direction's tools; send it through direction_edit.") } }
        if effect == "backdrop" { guard case .clip(let i) = target, s.clips[i].layer == 0, s.clips[i].kind == .video else { throw bad("backdrop goes on a shot on V1, behind it.") } }
        guard effect == "shader" || EditCatalog.effect(effect) != nil else { throw bad("There's no effect \(effect). direction_edit_catalog lists them.") }
        let source = op.resolved?.source
        var fx = ClipEffect(name: effect, params: try checkedParams(effect, op.params ?? [:], source: source), source: source)
        switch target {
        case .clip(let i):
            let c = s.clips[i]
            if effect == "transform", c.effects?.contains(where: { $0.name == "transform" }) == true { throw bad("\(c.id) already has a transform; change it with setEffect or reframe.") }
            if let k = op.keys { fx.keys = try checkedKeys(effect, k, c, source: source) }
            if effect == "stabilize" { fx.keys = op.resolved?.keys }
            if effect == "pixelGrid" { fx.data = op.resolved?.data }
            setEffect(fx, on: i)
            var out = change("Added \(effect) to \(label(c))", c); out.effectID = fx.id; return out
        case .track(let name):
            guard ["blur", "sharpen", "shader", "mask"].contains(effect) || effect.hasPrefix("filter.") else { throw bad("Tracks take blur, sharpen, mask, filter.<kind> and shader.") }
            if let k = op.keys { fx.keys = try checkedKeys(effect, k, nil, source: source) }
            var t = s.track(name); t.effects = (t.effects ?? []) + [fx]; s.tracks = (s.tracks ?? [:]).merging([name: t]) { _, b in b }
            return .init(summary: "Added \(effect) to \(name)", changes: [.init(before: (0, s.duration.seconds), after: (0, s.duration.seconds), tracks: [name])], effectID: fx.id)
        }
    }

    func findEffect(_ id: String?) throws -> (clip: Int?, track: String?, index: Int) {
        guard let id, !id.isEmpty else { throw bad("effectID is required.") }
        for (i, c) in s.clips.enumerated() { if let k = c.effects?.firstIndex(where: { $0.id == id }) { return (i, nil, k) } }
        for (name, t) in s.tracks ?? [:] { if let k = t.effects?.firstIndex(where: { $0.id == id }) { return (nil, name, k) } }
        throw bad("There's no effect \(id). Read direction_timeline for effect ids.")
    }

    mutating func setEffect(_ op: EditOperation) throws -> Outcome {
        if let id = op.effectID, id.hasSuffix(":blend"), let i = s.clips.firstIndex(where: { $0.id + ":blend" == id }) {
            s.clips[i].blend = try checkedParams("blend", op.params ?? [:])["mode"]?.string ?? s.clips[i].blend
            var out = change("Changed \(label(s.clips[i]))’s blend", s.clips[i]); out.effectID = id; return out
        }
        let (ci, tn, k) = try findEffect(op.effectID)
        var fx = ci.map { s.clips[$0].effects![k] } ?? s.tracks![tn!]!.effects![k]
        if fx.name == "shader", op.params?["file"] != nil || op.resolved?.source != nil {
            guard let source = op.resolved?.source else { throw bad("A changed shader is compiled and checked by Direction's tools; send it through direction_edit.") }
            fx.source = source
        }
        if let p = op.params { fx.params = try checkedParams(fx.name, p, over: fx.params, source: fx.source) }
        if fx.name == "stabilize", let found = op.resolved?.keys { fx.keys = found }
        if fx.name == "pixelGrid", let found = op.resolved?.data { fx.data = found }
        if let keys = op.keys { var all = fx.keys ?? [:]; all.merge(try checkedKeys(fx.name, keys, ci.map { s.clips[$0] }, source: fx.source)) { _, b in b }; fx.keys = all }
        if let ci { s.clips[ci].effects![k] = fx; var out = change("Changed \(fx.name) on \(label(s.clips[ci]))", s.clips[ci]); out.effectID = fx.id; return out }
        s.tracks![tn!]!.effects![k] = fx
        return .init(summary: "Changed \(fx.name) on \(tn!)", changes: [.init(before: (0, s.duration.seconds), after: (0, s.duration.seconds), tracks: [tn!])], effectID: fx.id)
    }

    mutating func removeEffect(_ op: EditOperation) throws -> Outcome {
        if let id = op.effectID, id.hasSuffix(":blend"), let i = s.clips.firstIndex(where: { $0.id + ":blend" == id }) {
            s.clips[i].blend = nil; return change("Took the blend off \(label(s.clips[i]))", s.clips[i])
        }
        let (ci, tn, k) = try findEffect(op.effectID)
        if let ci { let name = s.clips[ci].effects!.remove(at: k).name; if s.clips[ci].effects!.isEmpty { s.clips[ci].effects = nil }; return change("Took \(name) off \(label(s.clips[ci]))", s.clips[ci]) }
        let name = s.tracks![tn!]!.effects!.remove(at: k).name
        return .init(summary: "Took \(name) off \(tn!)", changes: [.init(before: (0, s.duration.seconds), after: (0, s.duration.seconds), tracks: [tn!])])
    }

    mutating func transition(_ op: EditOperation) throws -> Outcome {
        let (li, ri) = try editPoint(op.editPoint, needsLeft: false)
        if op.transitionType == nil, let name = op.transitionName { throw bad("\(name) is one of the style's transitions, found by Direction's tools; send it through direction_edit.") }
        guard let type = op.transitionType, EditCatalog.transitions.contains(type) else { throw bad("type is \(EditCatalog.transitions.joined(separator: ", ")), or name is one of the style's transitions.") }
        guard let n = op.frames, (1...600).contains(n) else { throw bad("frames is the transition's length, 1–600.") }
        let R = s.clips[ri]
        guard R.kind != .audio else { throw bad("Transitions are for picture; fade sound with fade.") }
        var t = ClipTransition(type: type, frames: n, before: 0, after: 0)
        if !t.isDip, li == nil { throw bad("A \(type == "shader" ? "transition" : type) needs a clip on each side. Use dipToBlack to fade in.") }
        // Everything but the dips is drawn from both shots: a Metal function Direction checked first.
        if !t.isDip && type != "dissolve" {
            guard let source = op.resolved?.source else { throw bad("\(type) is drawn and checked by Direction's tools; send it through direction_edit.") }
            var params = op.params ?? [:]
            if type == "shader" { t.file = params["file"]?.string; params["file"] = nil; params = try checkedParams("shader", params, source: source) }
            else {
                let specs = EditCatalog.builtInTransition(type)!.params
                for (k, v) in params {
                    guard let p = specs.first(where: { $0.name == k }) else { throw bad("\(type) has no parameter \(k). It takes \(specs.map(\.name).joined(separator: ", ")).") }
                    guard let x = v.double, x.isFinite, x >= (p.min ?? -.infinity), x <= (p.max ?? .infinity) else { throw bad("\(type).\(k) is \(p.rangeText).") }
                }
            }
            t.source = source; t.params = params.isEmpty ? nil : params
        }
        let beforeFrames = li == nil ? 0 : n / 2, afterFrames = n - beforeFrames
        t.before = secs(beforeFrames); t.after = secs(afterFrames)
        let name = type == "shader" ? (t.file.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "transition") : type
        if !t.isDip, let li {
            let L = s.clips[li]
            guard handleAfter(L) + 1e-6 >= t.after else { throw bad("\(label(L)) has only \(framesText(handleAfter(L))) after its out point; a \(n)-frame \(name) needs \(afterFrames).") }
            guard handleBefore(R) + 1e-6 >= t.before else { throw bad("\(label(R)) has only \(framesText(handleBefore(R))) before its in point; a \(n)-frame \(name) needs \(beforeFrames).") }
        }
        guard t.after <= R.duration.seconds + 1e-6, li.map({ t.before <= s.clips[$0].duration.seconds + 1e-6 }) ?? true else { throw bad("The transition is longer than the clips beside it.") }
        s.clips[ri].transition = t
        let cut = R.start.seconds
        let words = ["dissolve": "Dissolved", "dipToBlack": "Dipped to black", "dipToWhite": "Dipped to white", "push": "Pushed", "slide": "Slid", "whip": "Whipped", "zoom": "Zoomed", "wipe": "Wiped", "iris": "Irised"][type] ?? "Used \(name)"
        var tracks = [R.trackName], summary = "\(words) into \(label(R)) over \(n) frames"
        if let named = op.transitionName { summary = "\(named): " + summary.prefix(1).lowercased() + summary.dropFirst() }
        // A style's transition brings its sound, centered on the cut on a free sound track over the music.
        if let sound = op.resolved?.sound {
            if !project.assets.contains(where: { $0.path == sound.path }) { project.assets.append(sound) }
            let a = project.assets.first { $0.path == sound.path }!
            let length = a.duration.seconds, start = max(0, snap(MediaTime(seconds: cut - length / 2)).seconds)
            var layer = 2
            while s.clips.contains(where: { $0.kind == .audio && $0.layer == layer && $0.start.seconds < start + length && $0.end.seconds > start }) { layer += 1 }
            var clip = Clip(assetID: a.id, name: a.name, kind: .audio, layer: layer, start: MediaTime(seconds: start), sourceRange: .init(start: .zero, duration: a.duration))
            clip.gainDB = op.resolved?.soundDB
            s.clips.append(clip)
            tracks.append(clip.trackName)
            summary += ", \(URL(fileURLWithPath: a.path).deletingPathExtension().lastPathComponent) under it"
        }
        return .init(summary: summary, changes: [.init(before: (cut - t.before, cut + t.after), after: (cut - t.before, cut + t.after), tracks: tracks)])
    }

    // MARK: Layers

    mutating func cutaway(_ op: EditOperation) throws -> Outcome {
        let a = try asset(op.assetID)
        guard !a.video.isEmpty else { throw bad("\(a.name) has no picture to cut away to.") }
        // Without a source range, the same moment plays from a take in sync with the story.
        let synced = op.sourceRange == nil && op.range == nil
        if synced, (op.seconds ?? 0) <= 0 { throw bad("Without sourceRange, seconds says how long the cutaway runs; it plays the same moment from a take in sync with V1.") }
        let length = synced ? snap(MediaTime(seconds: op.seconds!)) : try sourceRange(op.sourceRange ?? op.range, of: a).duration
        var at: MediaTime
        if let cover = op.cover {
            let cut: MediaTime
            if cover.contains("|") { cut = s.clips[try editPoint(cover, needsLeft: false).right].start } else { cut = s.clips[try clipIndex(cover, "cover")].start }
            at = snap(cut - length.scaled(by: 0.5)); if at < .zero { at = .zero }
        } else { guard let t = op.at else { throw bad("at, or cover with an edit point, says where the cutaway goes.") }; at = snap(t) }
        let src = synced ? try syncedSource(a, at: at, length: length) : try sourceRange(op.sourceRange ?? op.range, of: a)
        let r = MediaRange(start: at, duration: src.duration)
        let layer = firstFree(audio: false, from: 1, r)
        var clip = Clip(assetID: a.id, name: a.name, kind: .video, layer: layer, start: at, sourceRange: src)
        if synced { clip.synced = true }
        // The sound under it keeps playing.
        for stream in a.audio { var m = stream.settings; m.muted = true; clip.audioOverrides[String(stream.id)] = m }
        s.clips.append(clip)
        return .init(summary: "Cut away to \(label(clip)) at \(tc(at))" + (op.cover != nil ? ", over the jump cut" : ""), changes: [.init(before: (at.seconds, clip.end.seconds), after: (at.seconds, clip.end.seconds), tracks: [clip.trackName])], clipIDs: [clip.id])
    }

    /// Four corners as pin's parameters: tl, tr, br, bl, each .x and .y.
    static func pinParams(_ corners: [[Double]]) -> [String: JSONValue] {
        var p: [String: JSONValue] = [:]
        for (name, c) in zip(EditCatalog.pinCorners, corners) { p[name + ".x"] = .number(c[0]); p[name + ".y"] = .number(c[1]) }
        return p
    }
    func checkedCorners(_ corners: [[Double]]?) throws -> [[Double]]? {
        guard let corners else { return nil }
        guard corners.count == 4, corners.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite && (-1...2).contains($0) } }) else { throw bad("corners is four [x, y] points, fractions of the frame from its top left: top left, top right, bottom right, bottom left.") }
        return corners
    }

    /// A clip on V2 or above, in perspective inside a screen, window or sign of the shot under it.
    mutating func pin(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard c.kind == .video, c.layer > 0 else { throw bad("pin puts a clip on V2 or above into the shot under it.") }
        if let f = op.follow, f != "screen" { throw bad("follow is screen.") }
        let corners = try checkedCorners(op.corners)
        var fx = c.effects?.first { $0.name == "pin" } ?? ClipEffect(name: "pin", params: [:])
        if let keys = op.resolved?.keys {
            fx.params = [:]; fx.keys = try checkedKeys("pin", keys, c)
        } else if let corners, op.follow == nil {
            fx.params = try checkedParams("pin", Self.pinParams(corners)); fx.keys = nil
        } else { throw bad("Without corners, pin finds and follows the screen with Direction's tools; send it through direction_edit.") }
        setEffect(fx, on: i)
        var out = change("Pinned \(label(c)) into the shot under it" + (fx.keys != nil ? ", following it" : ""), s.clips[i]); out.effectID = fx.id
        out.warnings = op.resolved?.warnings ?? []
        return out
    }

    /// Pushes into a screen in the left shot until it fills the frame at the cut, with the right shot's
    /// first frame pinned in it, so the cut lands inside the screen (agent-timeline.md › Zoom through).
    mutating func zoomThrough(_ op: EditOperation) throws -> Outcome {
        let (li, ri) = try editPoint(op.editPoint)
        guard let li else { throw bad("zoomThrough needs a shot on each side of the cut.") }
        let A = s.clips[li], B = s.clips[ri]
        guard A.layer == 0, B.layer == 0, A.kind == .video, B.kind == .video, B.assetID != nil else { throw bad("zoomThrough works at a cut on V1.") }
        guard let keys = op.resolved?.keys, keys["scale"] != nil, keys["tl.x"] != nil else { throw bad("zoomThrough finds the screen and works out the push with Direction's tools; send it through direction_edit.") }
        let seconds = op.seconds ?? 1
        guard (0.2...5).contains(seconds), seconds <= A.duration.seconds + 1e-6 else { throw bad("seconds is how long the push takes, 0.2–5, and no longer than \(label(A)).") }
        if A.effects?.contains(where: { $0.name == "transform" }) == true { throw bad("\(label(A)) already has a transform. Take it off with removeEffect, then zoom through.") }
        let start = snap(A.end - MediaTime(seconds: seconds)), length = A.end - start
        // The left shot pushes in: scale, x and y, in its own source seconds.
        var push = ClipEffect(name: "transform", params: [:])
        push.keys = try checkedKeys("transform", keys.filter { ["scale", "x", "y"].contains($0.key) }, A)
        setEffect(push, on: li)
        // The right shot's first frame, held over the push and pinned into the screen.
        var held = Clip(assetID: B.assetID, name: B.name, kind: .video, layer: firstFree(audio: false, from: 1, .init(start: start, duration: length)), start: start, sourceRange: .init(start: B.sourceRange.start, duration: frames(1).scaled(by: B.speed)))
        held.hold = length; held.grade = B.grade
        if let crop = B.effects?.first(where: { $0.name == "transform" })?.params["crop"] { held.effects = [ClipEffect(name: "transform", params: ["crop": crop])] }
        if let a = assetOf(B) { for stream in a.audio { var m = stream.settings; m.muted = true; held.audioOverrides[String(stream.id)] = m } }
        var pin = ClipEffect(name: "pin", params: [:])
        pin.keys = try checkedKeys("pin", keys.filter { $0.key.contains(".") }, held)
        held.effects = (held.effects ?? []) + [pin]
        s.clips.append(held)
        var out = Outcome(summary: "Pushed into the screen in \(label(A)) and through to \(label(B)) over \(String(format: "%.1f", length.seconds)) s", changes: [.init(before: (start.seconds, A.end.seconds), after: (start.seconds, A.end.seconds), tracks: ["V1", held.trackName])], clipIDs: [held.id])
        out.warnings = op.resolved?.warnings ?? []
        return out
    }

    /// The part of `a` that recorded the same moment as V1 at `at` (footage-index.md › Sync).
    func syncedSource(_ a: MediaAsset, at: MediaTime, length: MediaTime) throws -> MediaRange {
        guard let base = s.clips.first(where: { $0.kind == .video && $0.layer == 0 && $0.assetID != nil && $0.start <= at && at < $0.end }), let baseID = base.assetID else { throw bad("There's no story clip on V1 at \(tc(at)) to line \(a.name) up with.") }
        let here = base.sourceRange.start.seconds + (at - base.start).seconds * base.speed
        let dailies = context?.dailies ?? Dailies()
        guard let start = dailies.syncedTime(here, from: baseID, to: a.id) else { throw DirectionError("not_in_sync", "\(a.name) isn't in sync with \(label(base)). Give sourceRange, or see direction_dailies › syncGroups.") }
        guard start >= -frame / 2, start + length.seconds <= a.duration.seconds + frame else { throw bad("\(a.name) wasn't recording for all of \(tc(at))–\(tc(at + length)).") }
        return try sourceRange(MediaRange(start: MediaTime(seconds: max(0, start)), duration: length), of: a)
    }

    /// Another take in sync plays its sound under a story clip, lined up, in place of the clip's own:
    /// the group's sound take by default (a recorder, or the better mic), or `assetID`. Naming the
    /// clip's own take puts its own sound back (footage-index.md › Sync).
    mutating func syncSound(_ op: EditOperation) throws -> Outcome {
        let c = s.clips[try clipIndex(op.clipID)]
        guard c.kind == .video, c.layer == 0, c.hold == nil, let baseID = c.assetID, let own = assetOf(c) else { throw bad("syncSound plays sound in sync under a story clip on V1.") }
        guard let group = (context?.dailies ?? Dailies()).syncGroup(for: baseID) else { throw DirectionError("not_in_sync", "\(label(c)) isn't in sync with another take. See direction_dailies › syncGroups.") }
        let soundID = op.assetID ?? group.soundAssetID
        guard group.takes.contains(where: { $0.assetID == soundID }) else { throw DirectionError("not_in_sync", "That take isn't in sync with \(label(c)).") }
        // Sound already laid in sync under this clip makes way, under this clip only: after a split, the
        // other half keeps its sound.
        let under = { (x: Clip) in x.synced == true && x.kind == .audio && x.start < c.end && x.end > c.start }
        let had = s.clips.contains(where: under)
        let laid = s.clips.filter(under)
        s.clips.removeAll(where: under)
        s.clips += EditReducer.removing(c.range, from: laid, ripple: false)
        // Found again: the clips moved.
        let i = try clipIndex(op.clipID)
        if soundID == baseID {
            guard had else { throw bad("\(label(c)) already plays its own sound.") }
            for stream in own.audio { var m = c.audioOverrides[String(stream.id)] ?? stream.settings; m.muted = false; s.clips[i].audioOverrides[String(stream.id)] = m }
            return .init(summary: "\(label(c)) plays its own sound again", changes: [.init(before: (c.start.seconds, c.end.seconds), after: (c.start.seconds, c.end.seconds), tracks: ["A1"])])
        }
        let a = try asset(soundID)
        guard !a.audio.isEmpty else { throw bad("\(a.name) has no sound.") }
        guard c.speed == 1 else { throw bad("\(label(c)) plays at \(String(format: "%g", c.speed))×; sound in sync needs it at normal speed.") }
        let src = try syncedSource(a, at: c.start, length: c.duration)
        var clip = Clip(assetID: a.id, name: a.name, kind: .audio, layer: firstFree(audio: true, from: 1, c.range), start: c.start, sourceRange: src)
        clip.synced = true
        s.clips.append(clip)
        for stream in own.audio { var m = c.audioOverrides[String(stream.id)] ?? stream.settings; m.muted = true; s.clips[i].audioOverrides[String(stream.id)] = m }
        return .init(summary: "\(label(c)) plays \(label(clip))\u{2019}s sound, in sync", changes: [.init(before: (c.start.seconds, c.end.seconds), after: (c.start.seconds, c.end.seconds), tracks: ["A1", clip.trackName])], clipIDs: [clip.id])
    }

    /// The story clip on V1 at a time.
    func story(at t: MediaTime) -> Clip? {
        s.clips.first { $0.kind == .video && $0.layer == 0 && $0.assetID != nil && $0.start.seconds <= t.seconds + 1e-9 && t.seconds < $0.end.seconds - 1e-9 }
    }

    /// Synced clips follow the story under them: after every operation each is lined up again with
    /// the V1 clip under its start, and split where the story jumps to footage that doesn't carry
    /// on from it, so each part follows its own. One that can't follow (the story under it isn't in
    /// sync with it, plays at another speed, or the take wasn't recording then) keeps what it plays
    /// and stops being synced, with a warning. Returns what changed and the warnings.
    mutating func relineSynced() -> (changes: [LocalChange], warnings: [String]) {
        guard let dailies = context?.dailies else { return ([], []) }
        var changes: [LocalChange] = [], warnings: [String] = []
        func expected(_ c: Clip, _ a: MediaAsset, under base: Clip, at t: MediaTime) -> Double? {
            guard base.hold == nil, base.speed == c.speed, let id = base.assetID else { return nil }
            // Where the take is at the clip's start, if the story's take carried on back to it.
            let here = base.sourceTime(at: t).seconds - (t - c.start).seconds * c.speed
            return dailies.syncedTime(here, from: id, to: a.id)
        }
        var i = 0
        while i < s.clips.count {
            defer { i += 1 }
            guard s.clips[i].synced == true else { continue }
            let c = s.clips[i]
            guard let a = assetOf(c), c.hold == nil else { s.clips[i].synced = nil; continue }
            func unsync(_ why: String) {
                s.clips[i].synced = nil
                warnings.append("\(label(c)) at \(tc(c.start)) \(why); it plays what it did and isn't kept in sync any more. Cut away again without sourceRange to line it up.")
            }
            guard let base = story(at: c.start), let start = expected(c, a, under: base, at: c.start) else { unsync("isn't over a take it's in sync with"); continue }
            // Where the story jumps under the clip to footage that doesn't carry on from it, the clip
            // splits, and the part after follows the story there.
            let next = s.clips.filter { $0.kind == .video && $0.layer == 0 && $0.assetID != nil && $0.start.seconds > c.start.seconds + frame / 2 && $0.start.seconds < c.end.seconds - frame / 2 }.min { $0.start < $1.start }
            if let next, expected(c, a, under: next, at: c.start).map({ abs($0 - start) >= frame / 2 }) ?? true {
                let (l, r) = EditReducer.split(c, at: next.start)
                s.clips[i] = l; s.clips.insert(r, at: i + 1)
            }
            let piece = s.clips[i]
            guard start >= -frame / 2, start + piece.sourceRange.duration.seconds <= a.duration.seconds + frame else { unsync("needs \(a.name) from before it started or after it stopped recording"); continue }
            let moved = start - piece.sourceRange.start.seconds
            guard abs(moved) > frame / 4 else { continue }
            s.clips[i].sourceRange.start = MediaTime(seconds: max(0, start))
            changes.append(.init(before: (piece.start.seconds, piece.end.seconds), after: (piece.start.seconds, piece.end.seconds), tracks: [piece.trackName]))
        }
        return (changes, warnings)
    }

    mutating func placeGraphic(_ op: EditOperation) throws -> Outcome {
        guard let graphic = op.graphic, !graphic.isEmpty else { throw bad("graphic names a checked graphic.") }
        let id = op.resolved?.assetID ?? project.assets.last(where: { $0.graphic == graphic })?.id
        guard let id, let a = project.assets.first(where: { $0.id == id }) else { throw DirectionError("missing_media", "There's no checked graphic “\(graphic)”. Run direction_graphic on it first.") }
        guard let raw = op.at else { throw bad("at is where the graphic starts, in cut seconds.") }
        let at = snap(raw)
        let length = op.seconds.map { MediaTime(seconds: $0) } ?? a.duration
        guard length.seconds > 0, a.isImage || length.seconds <= a.duration.seconds + frame else { throw bad("“\(graphic)” is rendered for \(String(format: "%.2f", a.duration.seconds)) s.") }
        let d = a.isImage ? snap(length) : min(snap(length), snapDown(a.duration))
        let r = MediaRange(start: at, duration: d)
        var clip = Clip(assetID: a.id, name: graphic, kind: .video, layer: firstFree(audio: false, from: 1, r), start: at, sourceRange: .init(start: .zero, duration: d))
        clip.aboveLook = op.aboveLook ?? true
        for stream in a.audio { var m = stream.settings; m.muted = true; clip.audioOverrides[String(stream.id)] = m }
        s.clips.append(clip)
        return .init(summary: "Placed the graphic “\(graphic)” at \(tc(at))–\(tc(clip.end))", changes: [.init(before: (at.seconds, clip.end.seconds), after: (at.seconds, clip.end.seconds), tracks: [clip.trackName])], clipIDs: [clip.id])
    }

    mutating func placeMade(_ op: EditOperation) throws -> Outcome {
        let a = try asset(op.madeID ?? op.assetID, "madeID")
        guard let tn = op.track else { throw bad("track is where the made clip goes: V2, A2…") }
        let t = try parseTrack(tn)
        if t.audio { guard !a.audio.isEmpty else { throw bad("\(a.name) has no sound.") } } else { guard !a.video.isEmpty else { throw bad("\(a.name) has no picture.") } }
        guard let raw = op.at else { throw bad("at is where it starts, in cut seconds.") }
        let src = try sourceRange(op.sourceRange, of: a), at = snap(raw)
        let clip = Clip(assetID: a.id, name: a.name, kind: t.audio ? .audio : .video, layer: t.layer, start: at, sourceRange: src)
        guard free(t, clip.range) else { throw DirectionError("overlap", "\(tn) already has a clip at \(tc(at))–\(tc(clip.end)).") }
        s.clips.append(clip)
        return .init(summary: "Placed \(a.name) (made) on \(tn) at \(tc(at))", changes: [.init(before: (at.seconds, clip.end.seconds), after: (at.seconds, clip.end.seconds), tracks: [tn])], clipIDs: [clip.id])
    }

    // MARK: Sound

    mutating func gain(_ op: EditOperation) throws -> Outcome {
        guard let target = op.target ?? op.clipID else { throw bad("target is a clip id or a sound track (A2).") }
        guard let dB = op.dB, (-96...24).contains(dB) else { throw bad("dB is −96 to 24.") }
        let given = op.keys?["dB"] ?? op.keys?["gain"]
        if let given { guard given.allSatisfy({ $0.t.isFinite && (-96...24).contains($0.v) }) else { throw bad("Gain keys are {t, v}: t in cut seconds, v in dB from −96 to 24.") } }
        if let i = s.clips.firstIndex(where: { $0.id == target }) {
            let c = s.clips[i]
            guard hasSound(c) else { throw bad("\(c.id) has no sound.") }
            // A song's part is set wherever it's heard in that stretch of the song; its keys are in the song's time.
            let pieces = withSong(i).filter { s.clips[$0].assetID == c.assetID }
            let keys = given.flatMap { sourceKeys(["dB": $0], c)["dB"] }
            for k in pieces { s.clips[k].gainDB = dB == 0 ? nil : dB; if let keys { s.clips[k].gainKeys = keys } }
            let what = pieces.count > 1 || song(of: c) != nil ? "\(song(of: c) ?? label(c))\u{2019}s \(partName(c))" : "\(label(c))’s sound"
            return .init(summary: "Set \(what) to \(dbText(dB))", changes: pieces.map { k in .init(before: (s.clips[k].start.seconds, s.clips[k].end.seconds), after: (s.clips[k].start.seconds, s.clips[k].end.seconds), tracks: [c.kind == .audio ? s.clips[k].trackName : "A1"]) })
        }
        let t = try parseTrack(target)
        guard t.audio else { throw bad("Gain goes on a clip with sound or an A track.") }
        var settings = s.track(name(t)); settings.gainDB = dB == 0 ? nil : dB
        if let given { settings.gainKeys = given.sorted { $0.t < $1.t } }
        s.tracks = (s.tracks ?? [:]).merging([name(t): settings]) { _, b in b }
        return .init(summary: "Set \(name(t)) to \(dbText(dB))", changes: [.init(before: (0, s.duration.seconds), after: (0, s.duration.seconds), tracks: [name(t)])])
    }

    mutating func fade(_ op: EditOperation) throws -> Outcome {
        let i = try clipIndex(op.clipID); let c = s.clips[i]
        guard hasSound(c) else { throw bad("\(c.id) has no sound to fade.") }
        guard op.fadeIn != nil || op.fadeOut != nil else { throw bad("fade takes in and/or out, in frames.") }
        // A song fades as one: every part that starts (for in) or ends (for out) where this one does.
        let together = withSong(i)
        let ins = op.fadeIn == nil ? [] : together.filter { abs(s.clips[$0].start.seconds - c.start.seconds) < frame / 2 }
        let outs = op.fadeOut == nil ? [] : together.filter { abs(s.clips[$0].end.seconds - c.end.seconds) < frame / 2 }
        for k in Set(ins + outs) {
            let total = Int((s.clips[k].duration.seconds / frame).rounded())
            for v in [op.fadeIn, op.fadeOut].compactMap({ $0 }) { guard v >= 0, v <= total else { throw bad("Fades are 0 to \(total) frames for \(k == i ? "this clip" : label(s.clips[k])).") } }
        }
        if let v = op.fadeIn { for k in ins { s.clips[k].fadeIn = v == 0 ? nil : secs(v) } }
        if let v = op.fadeOut { for k in outs { s.clips[k].fadeOut = v == 0 ? nil : secs(v) } }
        let words = (op.fadeIn.map { " in over \($0) frames" } ?? "") + (op.fadeOut.map { (op.fadeIn != nil ? " and" : "") + " out over \($0) frames" } ?? "")
        if Set(ins + outs).count > 1 { return change("Faded \(song(of: c)!)" + words, c) }
        return change("Faded \(label(c))’s sound" + words, c)
    }

    /// Words on a sound track: A1 is what's heard of V1 plus any sound-only clips on A1.
    func trackWords(_ t: Track) -> [TimelineWord] {
        let clips = t.audio && t.layer == 0 ? TranscriptEditing.spoken(s) : s.clips.filter { on($0, t) }
        return TranscriptEditing.words(on: clips, transcripts: transcripts)
    }

    mutating func duck(_ op: EditOperation) throws -> Outcome {
        let t = try parseTrack(op.track ?? "")
        let under = try parseTrack(op.under ?? "A1")
        guard t.audio, under.audio, name(t) != name(under) else { throw bad("track is the sound to duck (usually A2) and under is the dialogue (usually A1).") }
        guard let dB = op.dB, dB.isFinite, abs(dB) <= 60, dB != 0 else { throw bad("dB is how far down to go, like −6.") }
        let depth = -abs(dB), attack = op.attack ?? 0.25, release = op.release ?? 0.5
        guard (0...10).contains(attack), (0...10).contains(release) else { throw bad("attack and release are 0–10 seconds.") }
        let words = trackWords(under)
        guard !words.isEmpty else { throw DirectionError("no_words", "\(name(under)) has no transcript to find the dialogue in. Transcribe it first.") }
        // Lines are words less than 0.6 s apart.
        var lines: [(Double, Double)] = []
        for w in words { let a = w.range.start.seconds, b = w.range.end.seconds; if let last = lines.last, a - last.1 < 0.6 { lines[lines.count - 1].1 = max(last.1, b) } else { lines.append((a, b)) } }
        // Ducked windows with their ramps; windows whose ramps meet stay down between them.
        var windows: [(Double, Double)] = []
        for l in lines { if let last = windows.last, l.0 - attack <= last.1 + release { windows[windows.count - 1].1 = max(last.1, l.1) } else { windows.append(l) } }
        // A song's parts on other tracks duck with the one on this track.
        let onTrack = s.clips.indices.filter { on(s.clips[$0], t) && hasSound(s.clips[$0]) }
        let targets = Array(Set(onTrack.flatMap(withSong))).sorted()
        guard !targets.isEmpty else { throw bad("\(name(t)) has no sound to duck.") }
        var count = 0
        for i in targets {
            let c = s.clips[i], r = c.soundRange
            var keys: [Keyframe] = []
            for w in windows where w.1 + release > r.start.seconds && w.0 - attack < r.end.seconds {
                count += 1
                keys += [.init(t: w.0 - attack, v: 0), .init(t: w.0, v: depth), .init(t: w.1, v: depth), .init(t: w.1 + release, v: 0)]
            }
            s.clips[i].duckKeys = keys.isEmpty ? nil : sourceKeys(["d": keys], c)["d"]
        }
        let ducked = Set(targets.map { s.clips[$0].trackName }).union([name(t)]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for tn in ducked {
            var settings = s.track(tn); settings.ducked = DuckSettings(under: name(under), dB: depth, attack: attack, release: release)
            s.tracks = (s.tracks ?? [:]).merging([tn: settings]) { _, b in b }
        }
        let a = targets.map { s.clips[$0].start.seconds }.min() ?? 0, b = targets.map { s.clips[$0].end.seconds }.max() ?? 0
        return .init(summary: "Ducked \(ducked.joined(separator: ", ")) \(dbText(depth)) under \(name(under)) for \(lines.count) \(lines.count == 1 ? "line" : "lines")", changes: [.init(before: (a, b), after: (a, b), tracks: ducked)], warnings: count == 0 ? ["No dialogue falls under \(name(t))."] : [])
    }

    mutating func placeMusic(_ op: EditOperation) throws -> Outcome {
        let a = try asset(op.madeID ?? op.assetID, "madeID")
        guard !a.audio.isEmpty else { throw bad("\(a.name) has no sound.") }
        guard let raw = op.at else { throw bad("at is where the music may start, in cut seconds.") }
        let at = snap(raw)
        guard let endOn = op.endOn else { throw bad("endOn is {cut: \"<left>|<right>\"}, {word: id} or a time in seconds.") }
        var end: MediaTime, what: String
        if let t = endOn.double ?? endOn["time"].double { end = snap(MediaTime(seconds: t)); what = tc(end) }
        else if let p = endOn["cut"].string ?? (endOn.string?.contains("|") == true ? endOn.string : nil) { end = s.clips[try editPoint(p, needsLeft: false).right].start; what = "the cut at \(tc(end))" }
        else if let id = endOn["word"].string ?? endOn.string {
            guard let word = TranscriptEditing.words(on: s.clips, transcripts: transcripts).first(where: { $0.id == id }) else { throw bad("There's no word \(id) in this cut. Read direction_transcript for word ids.") }
            end = snap(word.range.start); what = "“\(word.text)” at \(tc(end))"
        } else { throw bad("endOn is {cut: \"<left>|<right>\"}, {word: id} or a time in seconds.") }
        guard end > at else { throw bad("The music has to end after it starts.") }
        // A library song's parts, by name; each plays the same moment of the song.
        var playing = [a]
        if let names = op.parts {
            guard let g = a.song, !g.isEmpty else { throw bad("\(a.name) isn\u{2019}t a song in parts; leave parts out.") }
            guard !names.isEmpty else { throw bad("parts names at least one of \(g)\u{2019}s parts: \(parts(of: g).compactMap(\.part).joined(separator: ", ")).") }
            playing = []
            for n in names { let p = try part(n, of: g); if !playing.contains(where: { $0.id == p.id }) { playing.append(p) } }
        }
        let songLength = playing.map(\.duration).min()!, title = playing.count > 1 ? "\(a.song!) (\(playing.compactMap(\.part).joined(separator: ", ")))" : playing[0].name
        var start = at, warnings: [String] = [], src: MediaTime
        if let from = op.from {
            // From a moment of the song: it plays on from there and stops at the mark.
            guard from.isFinite, from >= 0 else { throw bad("from is the moment of the song that plays at at, in the song's seconds.") }
            src = snap(MediaTime(seconds: from))
            let left = songLength - src
            guard left > .zero else { throw bad("\(title) is only \(String(format: "%.1f", songLength.seconds)) s long.") }
            if end - start > left { throw bad("From \(String(format: "%.1f", from)) s, \(title) has \(String(format: "%.1f", left.seconds)) s left, so it can play until \(tc(at + snapDown(left))) at most.") }
        } else {
            let available = snapDown(songLength)
            if end - start > available { start = end - available; warnings.append("\(title) is \(String(format: "%.1f", songLength.seconds)) s, so it starts at \(tc(start)) to end on time.") }
            // Trimmed from the head, so the music's own ending lands on the mark.
            src = songLength - (end - start)
        }
        let length = end - start, r = MediaRange(start: start, duration: length)
        // Each part on a sound track of its own, the first on track when it's given.
        var ids: [String] = [], tracks: [String] = []
        for (k, p) in playing.enumerated() {
            var t: Track = (true, firstFree(audio: true, from: 1, r))
            if k == 0, let given = op.track { t = try parseTrack(given) }
            guard t.audio else { throw bad("Music goes on an A track.") }
            guard free(t, r) else { throw DirectionError("overlap", "\(name(t)) already has sound at \(tc(start))–\(tc(end)).") }
            let clip = Clip(assetID: p.id, name: p.name, kind: .audio, layer: t.layer, start: start, sourceRange: .init(start: src, duration: length))
            s.clips.append(clip); ids.append(clip.id); tracks.append(name(t))
        }
        let on = tracks.count == 1 ? tracks[0] : tracks.joined(separator: ", ")
        let summary = op.from == nil ? "Placed \(title) on \(on) to end on \(what)" : "Placed \(title) on \(on) from \(tc(src)) in the song to \(what)"
        return .init(summary: summary, changes: [.init(before: (start.seconds, end.seconds), after: (start.seconds, end.seconds), tracks: tracks)], clipIDs: ids, warnings: warnings)
    }

    mutating func audio(_ op: EditOperation) throws -> Outcome {
        guard let track = op.audioTrackID, let settings = op.audio else { throw bad("audio takes audioTrackID and full audio settings.") }
        if let id = op.clipID {
            let i = try clipIndex(id)
            let a = try asset(s.clips[i].assetID ?? "")
            guard a.audio.contains(where: { $0.id == track }) else { throw bad("The clip does not have that audio track.") }
            s.clips[i].audioOverrides[String(track)] = settings
            return change("Changed \(label(s.clips[i]))’s sound", s.clips[i])
        }
        guard let ai = project.assets.firstIndex(where: { $0.id == op.assetID }), let ti = project.assets[ai].audio.firstIndex(where: { $0.id == track }) else { throw bad("Audio track not found.") }
        project.assets[ai].audio[ti].settings = settings
        let uses = s.clips.filter { $0.assetID == op.assetID }
        return .init(summary: "Changed \(project.assets[ai].audio[ti].label) in \(project.assets[ai].name)", changes: uses.map { .init(before: ($0.start.seconds, $0.end.seconds), after: ($0.start.seconds, $0.end.seconds), tracks: [$0.kind == .audio ? $0.trackName : "A1"]) })
    }
}

// MARK: - Transcripts

public enum TranscriptEditing {
    /// The transcript chosen for each source: the most recently selected track.
    static func selected(_ transcripts: [SourceTranscript]) -> [String: SourceTranscript] {
        Dictionary(grouping: transcripts, by: \.assetID).compactMapValues { alternatives in alternatives.max { ($0.selectedAt ?? 0) < ($1.selectedAt ?? 0) } }
    }

    /// The words heard on the story track, in cut time: a narration on A1 and a talking head on V1 alike.
    public static func words(in sequence: Sequence, transcripts: [SourceTranscript]) -> [TimelineWord] {
        words(on: spoken(sequence), transcripts: transcripts)
    }

    /// The story track's clips that are heard: sound on its own on A1, and V1's pictures that play their
    /// own sound or have sound in sync under them. B-roll laid on V1 with its sound off says nothing.
    public static func spoken(_ sequence: Sequence) -> [Clip] {
        sequence.clips.filter { c in
            guard c.layer == 0, c.hold == nil else { return false }
            if c.kind == .audio { return true }
            guard c.kind == .video else { return false }
            let silent = !c.audioOverrides.isEmpty && c.audioOverrides.values.allSatisfy(\.muted)
            return !silent || sequence.clips.contains { $0.synced == true && $0.kind == .audio && $0.start < c.end && $0.end > c.start }
        }
    }

    /// Timed words for these clips, in cut time. A freeze has none.
    public static func words(on clips: [Clip], transcripts: [SourceTranscript]) -> [TimelineWord] {
        let chosen = selected(transcripts)
        return clips.filter { $0.hold == nil }.flatMap { clip -> [TimelineWord] in
            guard let assetID = clip.assetID, let t = chosen[assetID] else { return [] }
            return t.words.compactMap { w in
                guard let r = w.range.intersection(clip.sourceRange) else { return nil }
                return TimelineWord(id: clip.id + ":" + w.id, sourceWordID: w.id, clipID: clip.id, assetID: assetID, text: w.text, range: .init(start: clip.sequenceTime(at: r.start), duration: r.duration.scaled(by: 1 / clip.speed)))
            }
        }.sorted { $0.range.start < $1.range.start }
    }

    /// A take's own words, in source time.
    public static func sourceWords(_ assetID: String, _ transcripts: [SourceTranscript]) -> [TranscriptWord] {
        (selected(transcripts)[assetID]?.words ?? []).sorted { $0.range.start < $1.range.start }
    }

    static func normalized(_ text: String) -> String { text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) }

    /// Finds a line in another reading: a local alignment (matches +2, misses −1) of `line` inside `take`.
    /// Returns the matched word pairs, in order.
    public static func align(_ line: [String], _ take: [String]) -> [(Int, Int)] {
        let a = Array(line.prefix(400)).map(normalized), b = take.map(normalized)
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let w = b.count + 1
        var h = [Int32](repeating: 0, count: (a.count + 1) * w)
        var best = (0, 0, Int32(0))
        for i in 1...a.count { for j in 1...b.count {
            let diag = h[(i - 1) * w + j - 1] + (a[i - 1] == b[j - 1] ? 2 : -1)
            let v = max(0, diag, h[(i - 1) * w + j] - 1, h[i * w + j - 1] - 1)
            h[i * w + j] = v
            if v > best.2 { best = (i, j, v) }
        } }
        var i = best.0, j = best.1, pairs: [(Int, Int)] = []
        while i > 0 && j > 0 && h[i * w + j] > 0 {
            let v = h[i * w + j]
            if a[i - 1] == b[j - 1] && v == h[(i - 1) * w + j - 1] + 2 { pairs.append((i - 1, j - 1)); i -= 1; j -= 1 }
            else if v == h[(i - 1) * w + j - 1] - 1 { i -= 1; j -= 1 }
            else if v == h[(i - 1) * w + j] - 1 { i -= 1 }
            else { j -= 1 }
        }
        return pairs.reversed()
    }

    public static func deletionRanges(wordIDs: Set<String>, words: [TimelineWord]) throws -> [MediaRange] {
        guard !wordIDs.isEmpty, wordIDs.isSubset(of: Set(words.map(\.id))) else { throw DirectionError("stale_transcript", "Selected words no longer match this edit. Refresh the transcript.") }
        let ranges = words.filter { wordIDs.contains($0.id) }.map(\.range).sorted { $0.start < $1.start }
        var merged: [MediaRange] = []
        for r in ranges {
            if let last = merged.last, r.start <= last.end { merged[merged.count - 1].duration = max(last.end, r.end) - last.start }
            else { merged.append(r) }
        }
        return merged.reversed()
    }

    public static func deletedIDs(original: [TimelineWord], editedText: String) throws -> Set<String> {
        let target = editedText.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }.filter { !$0.isEmpty }
        let source = original.map { normalized($0.text) }
        guard target.count <= source.count else { throw DirectionError("transcript_insert_not_supported", "Text edits remove footage. New or rewritten speech cannot be created from the source recording.") }
        if target == source { return [] }
        var earliest: [Int] = [], next = 0
        for word in target { while next < source.count && source[next] != word { next += 1 }; guard next < source.count else { throw DirectionError("transcript_insert_not_supported", "Only deletion of existing words changes footage. Use word selection for precise cuts.") }; earliest.append(next); next += 1 }
        var latest: [Int] = [], previous = source.count - 1
        for word in target.reversed() { while previous >= 0 && source[previous] != word { previous -= 1 }; guard previous >= 0 else { throw DirectionError("invalid_transcript_edit", "Unable to align edited text.") }; latest.append(previous); previous -= 1 }
        guard earliest == latest.reversed() else { throw DirectionError("ambiguous_transcript_edit", "This deletion matches repeated words. Select the exact words in the transcript instead.") }
        let kept = Set(earliest)
        return Set(original.indices.filter { !kept.contains($0) }.map { original[$0].id })
    }
}

public enum ReviewAnchoring {
    public static func anchors(project: Project, sequence: Sequence, range: MediaRange?, time: MediaTime?) -> [SourceAnchor] {
        sequence.clips.compactMap { c in
            let overlap: MediaRange?
            if let range { overlap = c.range.intersection(range) }
            else if let time { overlap = c.range.contains(time) ? MediaRange(start: time, duration: min(MediaTime(seconds: 1 / sequence.frameRate.value), c.end - time)) : nil }
            else { overlap = c.range }
            guard let overlap else { return nil }
            let asset = c.assetID.flatMap { id in project.assets.first { $0.id == id } }
            return SourceAnchor(clipID: c.id, lineageID: c.lineageID, assetID: c.assetID, kind: c.kind, sourceRange: .init(start: c.sourceTime(at: overlap.start), duration: overlap.duration.scaled(by: c.speed)), sequenceRange: overlap, audioTrackIDs: asset?.audio.map(\.id) ?? [])
        }
    }

    public static func project(_ anchor: SourceAnchor, onto sequence: Sequence) -> AnchorProjection {
        let candidates = sequence.clips.filter { $0.lineageID == anchor.lineageID && $0.assetID == anchor.assetID }
        let matches = candidates.compactMap { c -> (String, MediaRange, MediaRange)? in
            guard let source = c.sourceRange.intersection(anchor.sourceRange) else { return nil }
            return (c.id, .init(start: c.sequenceTime(at: source.start), duration: source.duration.scaled(by: 1 / c.speed)), source)
        }
        let ambiguous = matches.indices.contains { i in matches.indices.contains { j in i < j && matches[i].2.intersection(matches[j].2) != nil } }
        return .init(status: matches.isEmpty ? "removed" : ambiguous ? "ambiguous" : matches.count > 1 ? "split" : "exact", clipIDs: matches.map(\.0), ranges: matches.map(\.1))
    }
}

extension ReviewAnchoring {
    /// Position a comment on the displayed edit without pretending removed or ambiguous
    /// source material still has a precise location. Opening a marker reviews its original revision.
    public static func markerTime(_ comment: ReviewComment, in sequence: Sequence, revision: Int) -> Double? {
        guard comment.sequenceID == sequence.id else { return nil }
        if comment.editRevision == revision { return comment.range?.start.seconds ?? comment.time?.seconds }
        guard comment.scope != "cut" else { return nil }
        let projections = comment.anchors.map { project($0, onto: sequence) }
        guard !projections.contains(where: { $0.status == "ambiguous" }) else { return nil }
        return projections.flatMap(\.ranges).map { $0.start.seconds }.min()
    }
}
