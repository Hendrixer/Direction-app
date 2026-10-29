import Foundation

// What Direction finds when it looks at footage (product-model.md › Shot, Sound, Index;
// specs/footage-index.md). Times are source seconds inside the take.

/// Where a take's index is. A take that's `looking` with no live index job is really `waiting`.
public enum IndexState: String, Codable, Sendable, CaseIterable { case waiting, looking, done, failed }

/// The fixed shape a description fills. Both engines decode into it greedily.
public struct ShotLook: Codable, Hashable, Sendable {
    public var description: String
    /// wide | medium | close | insert
    public var size: String?
    /// static | pan | tilt | push | pull | handheld
    public var movement: String?
    /// What's visible, never names: "woman, dark hair". The editor maps these to names when it logs.
    public var people: [String]
    public var setting: String?
    /// soft | shaky | overexposed | underexposed
    public var flags: [String]
    public init(description: String, size: String? = nil, movement: String? = nil, people: [String] = [], setting: String? = nil, flags: [String] = []) {
        self.description = description; self.size = size; self.movement = movement; self.people = people; self.setting = setting; self.flags = flags
    }

    public static let sizes = ["wide", "medium", "close", "insert"]
    public static let movements = ["static", "pan", "tilt", "push", "pull", "handheld"]
    public static let flagValues = ["soft", "shaky", "overexposed", "underexposed"]
    public static let maxWords = 18

    /// Checks a reply against the shape and tidies what's close enough (case, synonyms, length).
    /// Returns nil when there's no usable description at all.
    public static func validated(_ raw: ShotLook) -> ShotLook? {
        var words = raw.description.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        if words.count > maxWords {
            // Too long: end at the last whole sentence that fits, else cut and close it.
            if let end = words.prefix(maxWords).lastIndex(where: { ".!?".contains($0.last ?? " ") }), end >= 2 { words = Array(words.prefix(end + 1)) }
            else { words = Array(words.prefix(maxWords)); words[words.count - 1] = words[words.count - 1].trimmingCharacters(in: .punctuationCharacters) + "." }
        }
        func pick(_ value: String?, _ allowed: [String], _ synonyms: [String: String]) -> String? {
            guard let v = value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            if allowed.contains(v) { return v }
            if let s = synonyms[v] { return s }
            return allowed.first { v.contains($0) }
        }
        let size = pick(raw.size, sizes, ["close-up": "close", "closeup": "close", "close up": "close", "extreme close-up": "close", "ecu": "close", "cu": "close", "mcu": "medium", "medium close-up": "medium", "mid": "medium", "long": "wide", "establishing": "wide", "full": "wide", "detail": "insert"])
        let movement = pick(raw.movement, movements, ["still": "static", "locked": "static", "locked-off": "static", "none": "static", "dolly in": "push", "push in": "push", "zoom in": "push", "dolly out": "pull", "pull out": "pull", "zoom out": "pull", "hand-held": "handheld", "tracking": "handheld"])
        let flags = raw.flags.compactMap { pick($0, flagValues, ["blurry": "soft", "out of focus": "soft", "blur": "soft", "shake": "shaky", "bright": "overexposed", "blown out": "overexposed", "dark": "underexposed"]) }
        let people = raw.people.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(6)
        let setting = raw.setting?.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return ShotLook(description: words.joined(separator: " "), size: size, movement: movement, people: Array(people), setting: setting?.isEmpty == false ? setting : nil, flags: flags.filter { seen.insert($0).inserted })
    }

    /// The JSON schema OpenRouter enforces with `response_format`.
    public static var jsonSchema: JSONValue {
        let s = JSONValue.object(["type": .string("string")])
        func e(_ v: [String]) -> JSONValue { .object(["type": .string("string"), "enum": .array(v.map(JSONValue.string))]) }
        return .object(["type": .string("object"), "additionalProperties": .bool(false),
                        "required": .array(["description", "size", "movement", "people", "setting", "flags"].map(JSONValue.string)),
                        "properties": .object(["description": s, "size": e(sizes), "movement": e(movements),
                                               "people": .object(["type": .string("array"), "items": s]), "setting": s,
                                               "flags": .object(["type": .string("array"), "items": e(flagValues)])])])
    }
}

/// One continuous stretch of picture inside a take.
public struct Shot: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var assetID: String
    /// 1-based, in take order.
    public var number: Int
    public var start: Double
    public var end: Double
    /// Small JPEGs at 10%, 50% and 90% of the shot, in the film's `Index/Keyframes` folder.
    public var keyframes: [String]
    public var look: ShotLook?
    /// Which engine and version wrote the look: "mlx-vlm · mlx-community/Qwen3-VL-8B-Instruct-4bit".
    public var engine: String?
    public init(id: String = newID("shot"), assetID: String, number: Int, start: Double, end: Double, keyframes: [String] = [], look: ShotLook? = nil, engine: String? = nil) {
        self.id = id; self.assetID = assetID; self.number = number; self.start = start; self.end = end; self.keyframes = keyframes; self.look = look; self.engine = engine
    }
    public var duration: Double { end - start }
    public var middle: Double { (start + end) / 2 }
}

/// The seven kinds a SoundAnalysis label maps to.
public enum SoundKind: String, Codable, Sendable, CaseIterable { case speech, laughter, music, applause, wind, traffic, silence }

public struct IndexSound: Codable, Hashable, Sendable {
    public var assetID: String
    public var start: Double
    public var end: Double
    public var kind: SoundKind
    /// SoundAnalysis's own top label for the run ("laughter", "speech", "wind_noise_microphone").
    public var label: String
    public var confidence: Double
    public init(assetID: String, start: Double, end: Double, kind: SoundKind, label: String, confidence: Double) { self.assetID = assetID; self.start = start; self.end = end; self.kind = kind; self.label = label; self.confidence = confidence }
}

/// One take's index: where it is, its contact sheet, loudness for the strip, and what was skipped.
public struct TakeIndex: Codable, Hashable, Sendable {
    public var assetID: String
    public var state: IndexState
    /// What's running now: shots, sheet, sounds, search, describing.
    public var step: String?
    /// Path, size and modification time of the file this index was made from.
    public var fingerprint: String
    public var shotCount = 0
    public var described = 0
    public var contactSheet: String?
    public var sheetTimes: [Double] = []
    /// dBFS per second of the first audio track, for the sounds lane.
    public var loudness: [Float] = []
    public var engine: String?
    /// Why descriptions didn't run ("mlx-vlm isn't installed"). Shots, sounds and words still did.
    public var describeSkipped: String?
    public var error: String?
    /// Dollars OpenRouter charged to describe this take's shots.
    public var spend: Double?
    /// The transcript the search rows were made from; a newer transcript remakes them.
    public var wordsFingerprint: String?
    /// Shots, keyframes, sheet, sounds and words are in; only descriptions may be left.
    public var firstPassDone = false
    /// The engine that last went through this take's shots, so shots it couldn't describe
    /// aren't retried with it again and again.
    public var triedEngine: String?
    public var updatedAt: Double
    public init(assetID: String, state: IndexState, fingerprint: String, updatedAt: Double = Date().timeIntervalSince1970) { self.assetID = assetID; self.state = state; self.fingerprint = fingerprint; self.updatedAt = updatedAt }

    public static func fingerprint(_ asset: MediaAsset) -> String { "\(asset.path)|\(asset.fileSize)|\(asset.modifiedAt)" }
    public static func wordsFingerprint(_ transcripts: [SourceTranscript]) -> String {
        guard let t = transcripts.max(by: { ($0.selectedAt ?? 0, $0.words.count) < ($1.selectedAt ?? 0, $1.words.count) }) else { return "" }
        return "\(t.audioTrackID)|\(t.provider)|\(t.words.count)|\(t.selectedAt ?? 0)"
    }
    /// Done, but some shots still have no line and `engine` hasn't tried them.
    public func needsDescriptions(by engine: String?) -> Bool { state == .done && described < shotCount && engine != nil && triedEngine != engine }
}

/// A search row: a shot's description or one line of dialogue inside it.
public struct IndexSearchRow: Sendable {
    public enum Kind: String, Sendable { case picture, words }
    public var shotID: String
    public var assetID: String
    public var kind: Kind
    public var text: String
    public var start: Double
    public var vector: [Float]?
    public init(shotID: String, assetID: String, kind: Kind, text: String, start: Double, vector: [Float]?) { self.shotID = shotID; self.assetID = assetID; self.kind = kind; self.text = text; self.start = start; self.vector = vector }
}

/// A passage of the cut the editor watched with `direction_watch` (cut seconds at a revision).
public struct WatchedRange: Codable, Hashable, Sendable {
    public var revision: Int
    public var start: Double
    public var end: Double
    public var at: Double
}

/// "MM:SS:FF" source timecode for contact sheets and tool replies (product-model.md › Formats).
public enum SourceTimecode {
    public static func format(_ seconds: Double, fps: Double = 24) -> String {
        guard seconds.isFinite, seconds < 360_000 else { return "--:--:--" }
        let s = max(0, seconds), rate = fps.isFinite && fps > 0 ? fps.rounded() : 24
        let total = Int(s), frames = min(Int(rate) - 1, Int(((s - Double(total)) * rate + 1e-6).rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d:%02d", h, m, sec, frames) : String(format: "%02d:%02d:%02d", m, sec, frames)
    }
    public static func range(_ a: Double, _ b: Double, fps: Double = 24) -> String { "\(format(a, fps: fps))\u{2013}\(format(b, fps: fps))" }
}
