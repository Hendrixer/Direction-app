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
    public init(id: String = newID("asset"), name: String, path: String, duration: MediaTime, video: [VideoStream] = [], audio: [AudioStream] = [], fileSize: Int64 = 0, modifiedAt: Double = 0, bookmark: Data? = nil, thumbnailPath: String? = nil) {
        self.id = id; self.name = name; self.path = path; self.duration = duration; self.video = video; self.audio = audio; self.fileSize = fileSize; self.modifiedAt = modifiedAt; self.bookmark = bookmark; self.thumbnailPath = thumbnailPath
    }
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
    public init(id: String = newID("clip"), assetID: String?, name: String, kind: ClipKind = .video, layer: Int = 0, start: MediaTime = .zero, sourceRange: MediaRange, speed: Double = 1) {
        self.id = id; self.lineageID = id; self.assetID = assetID; self.name = name; self.kind = kind; self.layer = layer; self.start = start; self.sourceRange = sourceRange; self.speed = speed; self.grade = .init(); self.framing = .init(); self.audioOverrides = [:]
    }
    public var duration: MediaTime { sourceRange.duration.scaled(by: 1 / speed) }
    public var end: MediaTime { start + duration }
    public var range: MediaRange { .init(start: start, duration: duration) }
    public func sourceTime(at sequenceTime: MediaTime) -> MediaTime { sourceRange.start + (sequenceTime - start).scaled(by: speed) }
    public func sequenceTime(at sourceTime: MediaTime) -> MediaTime { start + (sourceTime - sourceRange.start).scaled(by: 1 / speed) }
}

public struct Sequence: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    public var clips: [Clip]
    public init(id: String = newID("sequence"), name: String = "Main edit", width: Int = 1920, height: Int = 1080, frameRate: FrameRate = .init(), clips: [Clip] = []) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.frameRate = frameRate; self.clips = clips
    }
    public var duration: MediaTime { clips.map(\.end).max() ?? .zero }
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
    public init(id: String, kind: String, revision: Int, ownerPID: Int32, status: String, phase: String, progress: Double?, result: JSONValue?, error: String?, createdAt: Double, updatedAt: Double) { self.id = id; self.kind = kind; self.revision = revision; self.ownerPID = ownerPID; self.status = status; self.phase = phase; self.progress = progress; self.result = result; self.error = error; self.createdAt = createdAt; self.updatedAt = updatedAt }
    public var isTerminal: Bool { ["completed", "failed", "cancelled", "interrupted"].contains(status) }
}
