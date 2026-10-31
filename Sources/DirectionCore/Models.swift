import Foundation

public struct VideoStream: Codable, Hashable, Sendable, Identifiable {
    public var id: Int32
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var colorPrimaries: String?
    public var transferFunction: String?
    public init(id: Int32, width: Int, height: Int, frameRate: Double, colorPrimaries: String? = nil, transferFunction: String? = nil) { self.id = id; self.width = width; self.height = height; self.frameRate = frameRate; self.colorPrimaries = colorPrimaries; self.transferFunction = transferFunction }
}

public struct AudioEffects: Codable, Hashable, Sendable {
    public var highPassHz: Double = 0
    public var bassDB: Double = 0
    public var trebleDB: Double = 0
    public var compressor: Bool = false
    public var thresholdDB: Double = -20
    public var limiter: Bool = false
    public init() {}
    public var isActive: Bool { highPassHz > 0 || bassDB != 0 || trebleDB != 0 || compressor || limiter }
}

public struct AudioSettings: Codable, Hashable, Sendable {
    public var muted: Bool = false
    public var gainDB: Double = 0
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    public var effects: AudioEffects = .init()
    public init(muted: Bool = false, gainDB: Double = 0) { self.muted = muted; self.gainDB = gainDB }
}

public struct AudioStream: Codable, Hashable, Sendable, Identifiable {
    public var id: Int32
    public var index: Int
    public var label: String
    public var channels: Int
    public var sampleRate: Double
    public var language: String?
    public var settings: AudioSettings
    public init(id: Int32, index: Int, label: String, channels: Int, sampleRate: Double, language: String? = nil, settings: AudioSettings = .init()) { self.id = id; self.index = index; self.label = label; self.channels = channels; self.sampleRate = sampleRate; self.language = language; self.settings = settings }
}

public struct MediaAsset: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var duration: MediaTime
    public var video: [VideoStream]
    public var audio: [AudioStream]
    public var fileSize: Int64
    public var modifiedAt: Double
    public var bookmark: Data?
    public var thumbnailPath: String?
    public var isImage: Bool = false
    /// A camera LUT for this take (looks.md › Camera LUT): "auto", "none" or a .cube path. nil is "auto".
    public var cameraLUT: String? = nil
    /// A made clip (made-media.md): the made record it came from. The asset's own id also works as a madeID.
    public var madeID: String? = nil
    /// A checked graphic's name (graphics.md): its ProRes 4444 render, with alpha.
    public var graphic: String? = nil
    public init(id: String = newID("asset"), name: String, path: String, duration: MediaTime, video: [VideoStream] = [], audio: [AudioStream] = [], fileSize: Int64 = 0, modifiedAt: Double = 0, bookmark: Data? = nil, thumbnailPath: String? = nil) {
        self.id = id; self.name = name; self.path = path; self.duration = duration; self.video = video; self.audio = audio; self.fileSize = fileSize; self.modifiedAt = modifiedAt; self.bookmark = bookmark; self.thumbnailPath = thumbnailPath
    }

    /// Footage: what the director brought in, which Direction looks at, listens to, syncs and logs as
    /// takes. Not a graphic's render, and not a file the editor wrote into the film's folder or took
    /// from a style (a delivery's mixed sound, a whoosh). Made clips are footage.
    public func isFootage(film: URL, styles: URL = SharedSettings.stylesFolder) -> Bool {
        guard graphic == nil else { return false }
        let path = URL(fileURLWithPath: self.path).standardizedFileURL.path
        let inside = { (folder: URL) in path.hasPrefix(folder.standardizedFileURL.path + "/") }
        if madeID != nil || inside(film.appendingPathComponent("Made")) { return true }
        return !inside(film) && !inside(styles)
    }
}

extension Project {
    /// The takes: footage the director brought in (`MediaAsset.isFootage`).
    public func footage(film: URL) -> [MediaAsset] { assets.filter { $0.isFootage(film: film) } }
}

public struct ColorGrade: Codable, Hashable, Sendable {
    public var exposure: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var temperature: Double = 0
    public var tint: Double = 0
    public init() {}
}

public struct Framing: Codable, Hashable, Sendable {
    public var fit: Bool = true
    public var scale: Double = 1
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var opacity: Double = 1
    public init() {}
}

public enum ClipKind: String, Codable, Sendable { case video, audio, title }

public struct Clip: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var lineageID: String
    public var assetID: String?
    public var name: String
    public var kind: ClipKind
    public var layer: Int
    public var start: MediaTime
    public var sourceRange: MediaRange
    public var speed: Double
    public var grade: ColorGrade
    public var framing: Framing
    public var audioOverrides: [String: AudioSettings]
    public var title: String?
    // The editor's timeline (agent-timeline.md). Every field is optional so older films decode unchanged.
    /// The clip's effects, in render order (transform, mask, blur, sharpen, stabilize, filter.<kind>, shader).
    public var effects: [ClipEffect]? = nil
    /// normal, screen, multiply, overlay or add. Only V2 and above blend.
    public var blend: String? = nil
    /// Composited after the director's look. Graphics are above it by default.
    public var aboveLook: Bool? = nil
    /// The transition into this clip from the one before it on its track.
    public var transition: ClipTransition? = nil
    /// Sound: the clip's own gain over each stream's setting, and gain keys (dB, source seconds).
    public var gainDB: Double? = nil
    public var gainKeys: [Keyframe]? = nil
    /// Written by `duck` (dB below the clip's level, source seconds), so ducking can be redone without touching gain.
    public var duckKeys: [Keyframe]? = nil
    /// Sound fades in seconds, over any stream fade.
    public var fadeIn: Double? = nil
    public var fadeOut: Double? = nil
    /// J- and L-cuts, in cut seconds: the sound starts this much before the picture (negative: after),
    /// and ends this much after it (negative: before).
    public var soundLead: Double? = nil
    public var soundTail: Double? = nil
    /// A freeze: shows the frame at sourceRange.start for this long, without sound.
    public var hold: MediaTime? = nil
    /// Plays the same moment as the story clip under it, from a take in sync with it (a cutaway
    /// without a source range, or `syncSound`). Direction lines it up again after every edit.
    public var synced: Bool? = nil
    public init(id: String = newID("clip"), assetID: String?, name: String, kind: ClipKind = .video, layer: Int = 0, start: MediaTime = .zero, sourceRange: MediaRange, speed: Double = 1) {
        self.id = id; self.lineageID = id; self.assetID = assetID; self.name = name; self.kind = kind; self.layer = layer; self.start = start; self.sourceRange = sourceRange; self.speed = speed; self.grade = .init(); self.framing = .init(); self.audioOverrides = [:]
    }
    public var duration: MediaTime { hold ?? sourceRange.duration.scaled(by: 1 / speed) }
    public var end: MediaTime { start + duration }
    public var range: MediaRange { .init(start: start, duration: duration) }
    public func sourceTime(at sequenceTime: MediaTime) -> MediaTime { hold != nil ? sourceRange.start : sourceRange.start + (sequenceTime - start).scaled(by: speed) }
    public func sequenceTime(at sourceTime: MediaTime) -> MediaTime { hold != nil ? start : start + (sourceTime - sourceRange.start).scaled(by: 1 / speed) }
    /// V1, V2… for picture and titles (layer + 1); A1, A2… for sound-only clips. A1 also carries V1's own sound.
    public var trackName: String { (kind == .audio ? "A" : "V") + String(layer + 1) }
    /// Where the clip's sound plays in the cut, with any J- or L-cut.
    public var soundRange: MediaRange { let s = start - MediaTime(seconds: soundLead ?? 0); return .init(start: s, duration: end + MediaTime(seconds: soundTail ?? 0) - s) }
    public func effect(_ id: String) -> ClipEffect? { effects?.first { $0.id == id } }
}

/// A value at a time. Clip keys are kept in source seconds so they ride along with trims, splits and ripples;
/// the editor reads and writes them in cut seconds. Track keys are in cut seconds.
public struct Keyframe: Codable, Hashable, Sendable {
    public var t: Double
    public var v: Double
    /// linear (default), hold or smooth, toward the next key.
    public var ease: String?
    public init(t: Double, v: Double, ease: String? = nil) { self.t = t; self.v = v; self.ease = ease }

    /// The value at `t`: held before the first and after the last key.
    public static func value(_ keys: [Keyframe], at t: Double) -> Double? {
        guard let first = keys.first else { return nil }
        if keys.count == 1 || t <= first.t { return first.v }
        guard let i = keys.firstIndex(where: { $0.t > t }) else { return keys[keys.count - 1].v }
        let a = keys[i - 1], b = keys[i], span = b.t - a.t
        guard span > 0 else { return b.v }
        var p = (t - a.t) / span
        switch a.ease { case "hold": p = 0; case "smooth": p = p * p * (3 - 2 * p); default: break }
        return a.v + (b.v - a.v) * p
    }
}

/// One effect on a clip or a track (agent-timeline.md › Effects catalog). Parameters are numbers,
/// text or small objects (crop `{l,r,t,b}`); keys are numbers by parameter name ("opacity", "crop.l").
public struct ClipEffect: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var params: [String: JSONValue]
    public var keys: [String: [Keyframe]]?
    /// A shader's Metal source, kept with the effect so every revision renders the same.
    public var source: String?
    public init(id: String = newID("fx"), name: String, params: [String: JSONValue] = [:], keys: [String: [Keyframe]]? = nil, source: String? = nil) { self.id = id; self.name = name; self.params = params; self.keys = keys; self.source = source }

    /// A numeric parameter at a time (source seconds for clips), keyed or not.
    public func number(_ param: String, at t: Double?, default value: Double) -> Double {
        if let t, let k = keys?[param], let v = Keyframe.value(k, at: t) { return v }
        if let v = params[param]?.double { return v }
        // crop.l is the l of the crop object; pin's tl.x is a name of its own.
        let parts = param.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2, case .object = params[parts[0]] { return params[parts[0]]?[parts[1]].double ?? value }
        return (params[param]?.bool.map { $0 ? 1 : 0 }) ?? value
    }
}

/// A transition at the cut before a clip: `before` seconds of it play before the cut and `after` after it
/// (OTIO's in_offset and out_offset). A dissolve uses handles on both sides; dips don't need any.
public struct ClipTransition: Codable, Hashable, Sendable {
    /// dissolve, dipToBlack, dipToWhite, one of Direction's own (push, slide, whip, zoom, wipe, iris),
    /// or shader: the editor's own, from Transitions/<name>.metal.
    public var type: String
    public var frames: Int
    public var before: Double
    public var after: Double
    /// The Metal function that draws it, kept with the cut so it renders the same later (shader
    /// transitions, Direction's own included); its parameters; and the editor's file for its own.
    public var source: String? = nil
    public var params: [String: JSONValue]? = nil
    public var file: String? = nil
    public init(type: String, frames: Int, before: Double, after: Double) { self.type = type; self.frames = frames; self.before = before; self.after = after }
    /// Dips play over one clip; every other transition shows both, so it needs handle on both sides.
    public var isDip: Bool { type == "dipToBlack" || type == "dipToWhite" }
}

/// A track's own settings: effects over every clip on it, the above-look flag, gain and keys (cut seconds).
public struct TrackSettings: Codable, Hashable, Sendable {
    public var effects: [ClipEffect]?
    public var aboveLook: Bool?
    public var gainDB: Double?
    public var gainKeys: [Keyframe]?
    /// What `duck` did, for the outline: "ducked −6 dB under A1".
    public var ducked: DuckSettings?
    public init(effects: [ClipEffect]? = nil, aboveLook: Bool? = nil, gainDB: Double? = nil, gainKeys: [Keyframe]? = nil, ducked: DuckSettings? = nil) { self.effects = effects; self.aboveLook = aboveLook; self.gainDB = gainDB; self.gainKeys = gainKeys; self.ducked = ducked }
    public var isEmpty: Bool { (effects ?? []).isEmpty && aboveLook == nil && gainDB == nil && (gainKeys ?? []).isEmpty && ducked == nil }
}

public struct DuckSettings: Codable, Hashable, Sendable {
    public var under: String
    public var dB: Double
    public var attack: Double
    public var release: Double
    public init(under: String, dB: Double, attack: Double, release: Double) { self.under = under; self.dB = dB; self.attack = attack; self.release = release }
}

public struct Sequence: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    public var clips: [Clip]
    /// Per-track settings by name ("V2", "A2"). nil until the editor sets one.
    public var tracks: [String: TrackSettings]? = nil
    public init(id: String = newID("sequence"), name: String = "Main edit", width: Int = 1920, height: Int = 1080, frameRate: FrameRate = .init(), clips: [Clip] = []) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.frameRate = frameRate; self.clips = clips
    }
    public var duration: MediaTime { clips.map(\.end).max() ?? .zero }
    public func track(_ name: String) -> TrackSettings { tracks?[name] ?? TrackSettings() }
}

public struct Project: Codable, Hashable, Sendable, Identifiable {
    public var schemaVersion: Int = 1
    public var id: String
    public var name: String
    public var editRevision: Int
    public var assets: [MediaAsset]
    public var sequences: [Sequence]
    public var createdAt: Double
    public init(name: String) { id = newID("project"); self.name = name; editRevision = 0; assets = []; sequences = [.init()]; createdAt = Date().timeIntervalSince1970 }
    public func sequence(_ id: String?) throws -> Sequence { guard let s = id.flatMap({ value in sequences.first { $0.id == value } }) ?? (id == nil ? sequences.first : nil) else { throw DirectionError("sequence_not_found", "Sequence not found.") }; return s }
    public func asset(_ id: String) throws -> MediaAsset { guard let a = assets.first(where: { $0.id == id }) else { throw DirectionError("asset_not_found", "Asset \(id) not found.") }; return a }
}

public struct TranscriptWord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var range: MediaRange
    public init(id: String = newID("word"), text: String, range: MediaRange) { self.id = id; self.text = text; self.range = range }
}

public struct SourceTranscript: Codable, Hashable, Sendable {
    public var assetID: String
    public var audioTrackID: Int32
    public var language: String
    public var provider: String
    public var words: [TranscriptWord]
    /// The most recently chosen track is used for this source's text edits.
    public var selectedAt: Double?
    public init(assetID: String, audioTrackID: Int32, language: String = "en-US", provider: String = "imported", words: [TranscriptWord]) { self.assetID = assetID; self.audioTrackID = audioTrackID; self.language = language; self.provider = provider; self.words = words }

    /// Whisper stuck in a loop ("I'm going to go into too much detail on this, but I'm going…" to the
    /// end of the take): somewhere a run of 60 words uses fewer than 18 different ones. Real speech,
    /// retakes included, stays above 35.
    public var looksLooped: Bool {
        let w = words.map { $0.text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" } }
        let span = 60
        guard w.count >= span else { return false }
        return stride(from: 0, through: w.count - span, by: 10).contains { Set(w[$0..<$0 + span]).count < 18 }
    }
}

public struct TimelineWord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourceWordID: String
    public var clipID: String
    public var assetID: String
    public var text: String
    public var range: MediaRange
}

public struct ReviewCut: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var editRevision: Int
    public var sequenceID: String
    public var createdAt: Double
    public init(id: String, name: String, editRevision: Int, sequenceID: String, createdAt: Double) { self.id = id; self.name = name; self.editRevision = editRevision; self.sequenceID = sequenceID; self.createdAt = createdAt }
}

public struct FrameRegion: Codable, Hashable, Sendable {
    public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var isValid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.00001 && y + height <= 1.00001 }
}

public struct SourceAnchor: Codable, Hashable, Sendable {
    public var clipID: String
    public var lineageID: String
    public var assetID: String?
    public var kind: ClipKind
    public var sourceRange: MediaRange
    public var sequenceRange: MediaRange
    public var audioTrackIDs: [Int32]
}

public struct FeedbackReply: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var author: String
    public var text: String
    public var revision: Int?
    public var createdAt: Double
    public init(id: String, author: String, text: String, revision: Int?, createdAt: Double) { self.id = id; self.author = author; self.text = text; self.revision = revision; self.createdAt = createdAt }
}

public struct ReviewComment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var cutID: String?
    public var editRevision: Int
    public var sequenceID: String
    public var scope: String
    public var range: MediaRange?
    public var time: MediaTime?
    public var region: FrameRegion?
    public var text: String
    public var author: String
    public var status: String
    public var anchors: [SourceAnchor]
    public var transcriptContext: [TimelineWord]
    public var replies: [FeedbackReply]
    public var createdAt: Double
    public var cursor: Int64
    /// Project-wide, permanent and never reused, so "note 4" means the same thing in every cut.
    public var number: Int? = nil
    public var kind: NoteKind? = nil
    public var noteState: NoteState? = nil
    /// nil or "director"; "outside" for people on a share link; "editor" for unasked changes.
    public var authorRole: String? = nil
    public var person: Person? = nil
    /// inbox, accepted or declined, for outside notes.
    public var outsideState: String? = nil
    public var scriptAction: ScriptAction? = nil
    public var sceneID: String? = nil
    public var turnoverID: String? = nil
    public var answers: [NoteAnswer]? = nil
    public var updatedAt: Double? = nil
    public init(id: String, cutID: String?, editRevision: Int, sequenceID: String, scope: String, range: MediaRange?, time: MediaTime?, region: FrameRegion?, text: String, author: String, status: String, anchors: [SourceAnchor], transcriptContext: [TimelineWord], replies: [FeedbackReply], createdAt: Double, cursor: Int64) {
        self.id = id; self.cutID = cutID; self.editRevision = editRevision; self.sequenceID = sequenceID; self.scope = scope; self.range = range; self.time = time; self.region = region; self.text = text; self.author = author; self.status = status; self.anchors = anchors; self.transcriptContext = transcriptContext; self.replies = replies; self.createdAt = createdAt; self.cursor = cursor
    }
}

public struct AnchorProjection: Codable, Hashable, Sendable {
    public var status: String
    public var clipIDs: [String]
    public var ranges: [MediaRange]
}

public struct ProjectEvent: Codable, Sendable, Identifiable {
    public var id: Int64
    public var kind: String
    public var revision: Int
    public var summary: String
    public var createdAt: Double
}

public struct JobRecord: Codable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var revision: Int
    public var ownerPID: Int32
    public var status: String
    public var phase: String
    public var progress: Double?
    public var result: JSONValue?
    public var error: String?
    public var createdAt: Double
    public var updatedAt: Double
    /// The take a job works on, when it works on one (transcription), so a job that died can be found
    /// and started again.
    public var assetID: String?
    public init(id: String, kind: String, revision: Int, ownerPID: Int32, status: String, phase: String, progress: Double?, result: JSONValue?, error: String?, createdAt: Double, updatedAt: Double, assetID: String? = nil) { self.id = id; self.kind = kind; self.revision = revision; self.ownerPID = ownerPID; self.status = status; self.phase = phase; self.progress = progress; self.result = result; self.error = error; self.createdAt = createdAt; self.updatedAt = updatedAt; self.assetID = assetID }
    public var isTerminal: Bool { ["completed", "failed", "cancelled", "interrupted"].contains(status) }
}
