import Foundation

public struct EditOperation: Codable, Hashable, Sendable {
    public var type: String
    public var assetID: String?
    public var clipID: String?
    public var at: MediaTime?
    public var range: MediaRange?
    public var layer: Int?
    public var speed: Double?
    public var ripple: Bool?
    public var grade: ColorGrade?
    public var framing: Framing?
    public var audioTrackID: Int32?
    public var audio: AudioSettings?
    public var text: String?
    public var width: Int?
    public var height: Int?
    public var frameRate: FrameRate?
    public init(_ type: String) { self.type = type }
}

public struct EditBatch: Codable, Hashable, Sendable {
    public var baseEditRevision: Int
    public var sequenceID: String?
    public var idempotencyKey: String
    public var summary: String
    public var operations: [EditOperation]
    public init(baseEditRevision: Int, sequenceID: String? = nil, idempotencyKey: String = UUID().uuidString, summary: String = "Edited sequence", operations: [EditOperation]) { self.baseEditRevision = baseEditRevision; self.sequenceID = sequenceID; self.idempotencyKey = idempotencyKey; self.summary = summary; self.operations = operations }
}

public enum EditReducer {
    public static func apply(_ batch: EditBatch, to original: Project) throws -> Project {
        guard !batch.operations.isEmpty && batch.operations.count <= 1_000 else { throw DirectionError("invalid_batch", "Submit between 1 and 1,000 operations.") }
        var project = original
        guard let index = project.sequences.firstIndex(where: { batch.sequenceID == nil || $0.id == batch.sequenceID }) else { throw DirectionError("sequence_not_found", "Sequence not found.") }
        for op in batch.operations {
            var s = project.sequences[index]
            let ci = op.clipID.flatMap { id in s.clips.firstIndex { $0.id == id } }
            switch op.type {
            case "insert":
                let asset = try project.asset(try required(op.assetID, "assetID"))
                let r = op.range ?? MediaRange(start: .zero, duration: asset.duration)
                let kind: ClipKind = asset.video.isEmpty ? .audio : .video
                let clip = Clip(assetID: asset.id, name: asset.name, kind: kind, layer: op.layer ?? 0, start: op.at ?? s.duration, sourceRange: r, speed: op.speed ?? 1)
                s.clips.append(clip)
            case "title":
                guard let text = op.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2_000 else { throw DirectionError("invalid_title", "Provide 1–2,000 title characters.") }
                var clip = Clip(assetID: nil, name: text, kind: .title, layer: op.layer ?? 100, start: op.at ?? .zero, sourceRange: op.range ?? .init(start: 0, end: 3))
                clip.title = text; s.clips.append(clip)
            case "removeRange":
                guard let r = op.range, r.isValid, r.end <= s.duration else { throw DirectionError("invalid_range", "Removal range must fall inside the sequence.") }
                s.clips = removing(r, from: s.clips, ripple: op.ripple ?? true)
            case "remove":
                guard let ci else { throw DirectionError("clip_not_found", "Clip not found.") }
                let r = s.clips[ci].range
                if op.ripple == true { s.clips = removing(r, from: s.clips, ripple: true) } else { s.clips.remove(at: ci) }
            case "split":
                guard let ci, let t = op.at, t > s.clips[ci].start && t < s.clips[ci].end else { throw DirectionError("invalid_split", "Split inside an existing clip.") }
                let clip = s.clips[ci], sourceTime = clip.sourceTime(at: t)
                var left = clip, right = clip
                left.sourceRange.duration = sourceTime - clip.sourceRange.start
                right.id = newID("clip"); right.start = t; right.sourceRange = .init(start: sourceTime, duration: clip.sourceRange.end - sourceTime)
                s.clips.replaceSubrange(ci...ci, with: [left, right])
            case "trim":
                guard let ci, let r = op.range else { throw DirectionError("invalid_trim", "Provide clipID and a source range.") }
                let oldEnd = s.clips[ci].end
                s.clips[ci].sourceRange = r
                if op.ripple == true { let delta = s.clips[ci].end - oldEnd; for i in s.clips.indices where i != ci && s.clips[i].start >= oldEnd { s.clips[i].start = s.clips[i].start + delta } }
            case "move":
                guard let ci, let t = op.at else { throw DirectionError("invalid_move", "Provide clipID and at.") }
                s.clips[ci].start = t
                if let layer = op.layer { s.clips[ci].layer = layer }
            case "speed":
                guard let ci, let speed = op.speed, speed.isFinite && (0.1...8).contains(speed) else { throw DirectionError("invalid_speed", "Speed must be between 0.1 and 8.") }
                let oldEnd = s.clips[ci].end
                s.clips[ci].speed = speed
                if op.ripple ?? true { let delta = s.clips[ci].end - oldEnd; for i in s.clips.indices where i != ci && s.clips[i].start >= oldEnd { s.clips[i].start = s.clips[i].start + delta } }
            case "color":
                guard let ci, let grade = op.grade else { throw DirectionError("invalid_color", "Provide clipID and grade.") }; s.clips[ci].grade = grade
            case "frame":
                guard let ci, let framing = op.framing else { throw DirectionError("invalid_frame", "Provide clipID and framing.") }; s.clips[ci].framing = framing
            case "audio":
                guard let track = op.audioTrackID, let settings = op.audio else { throw DirectionError("invalid_audio", "Provide audioTrackID and audio settings.") }
                if let ci {
                    let asset = try project.asset(s.clips[ci].assetID ?? "")
                    guard asset.audio.contains(where: { $0.id == track }) else { throw DirectionError("audio_track_not_found", "The clip does not have that audio track.") }
                    s.clips[ci].audioOverrides[String(track)] = settings
                } else {
                    guard let ai = project.assets.firstIndex(where: { $0.id == op.assetID }), let ti = project.assets[ai].audio.firstIndex(where: { $0.id == track }) else { throw DirectionError("audio_track_not_found", "Audio track not found.") }
                    project.assets[ai].audio[ti].settings = settings
                }
            case "format":
                if let width = op.width { s.width = width }; if let height = op.height { s.height = height }; if let rate = op.frameRate { s.frameRate = rate }
            case "rename": if let name = op.text, !name.isEmpty { s.name = name }
            case "duplicateSequence":
                var copy = s; copy.id = newID("sequence"); copy.name = op.text ?? s.name + " copy"; if let w = op.width { copy.width = w }; if let h = op.height { copy.height = h }; project.sequences.append(copy)
            default: throw DirectionError("unknown_operation", "Unknown edit operation: \(op.type).")
            }
            project.sequences[index] = s
        }
        try validate(project)
        return project
    }

    private static func required(_ value: String?, _ name: String) throws -> String { guard let value else { throw DirectionError("invalid_arguments", "\(name) is required.") }; return value }

    public static func removing(_ range: MediaRange, from clips: [Clip], ripple: Bool) -> [Clip] {
        var result: [Clip] = []
        for clip in clips {
            guard let overlap = clip.range.intersection(range) else {
                var c = clip
                if ripple && c.start >= range.end { c.start = c.start - range.duration }
                result.append(c); continue
            }
            if clip.start < overlap.start {
                var left = clip
                left.sourceRange.duration = (overlap.start - clip.start).scaled(by: clip.speed)
                result.append(left)
            }
            if clip.end > overlap.end {
                var right = clip
                right.id = clip.start < overlap.start ? newID("clip") : clip.id
                let sourceStart = clip.sourceTime(at: overlap.end)
                right.sourceRange = .init(start: sourceStart, duration: clip.sourceRange.end - sourceStart)
                right.start = ripple ? overlap.end - range.duration : overlap.end
                result.append(right)
            }
        }
        return result
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
                if let id = c.assetID { let a = try p.asset(id); guard a.isImage || c.sourceRange.end <= a.duration else { throw DirectionError("source_out_of_bounds", "\(c.name) extends past the source duration.") } }
                else if c.kind != .title { throw DirectionError("missing_asset", "A media clip must reference an asset.") }
                let g = c.grade
                guard g.exposure.isFinite && (-5...5).contains(g.exposure), g.contrast.isFinite && (0...4).contains(g.contrast), g.saturation.isFinite && (0...3).contains(g.saturation), g.temperature.isFinite && (-3_000...3_000).contains(g.temperature), g.tint.isFinite && (-100...100).contains(g.tint) else { throw DirectionError("invalid_grade", "Color values are outside supported ranges.") }
                let f = c.framing
                guard f.scale.isFinite && (0.05...10).contains(f.scale), f.offsetX.isFinite && (-2...2).contains(f.offsetX), f.offsetY.isFinite && (-2...2).contains(f.offsetY), f.opacity.isFinite && (0...1).contains(f.opacity) else { throw DirectionError("invalid_framing", "Framing values are outside supported ranges.") }
                for audio in c.audioOverrides.values { try validateAudio(audio) }
            }
            let groups = Dictionary(grouping: s.clips, by: { "\($0.kind.rawValue):\($0.layer)" })
            for group in groups.values { let ordered = group.sorted { $0.start < $1.start }; for i in ordered.indices.dropFirst() where ordered[i].start < ordered[i - 1].end { throw DirectionError("overlapping_clips", "Clips on the same layer overlap. Put an overlay on another layer.") } }
        }
    }

    public static func validateAudio(_ a: AudioSettings) throws {
        let e = a.effects
        guard a.gainDB.isFinite && (-96...24).contains(a.gainDB), a.fadeIn.isFinite && (0...120).contains(a.fadeIn), a.fadeOut.isFinite && (0...120).contains(a.fadeOut), e.highPassHz.isFinite && (0...5_000).contains(e.highPassHz), e.bassDB.isFinite && (-24...24).contains(e.bassDB), e.trebleDB.isFinite && (-24...24).contains(e.trebleDB), e.thresholdDB.isFinite && (-60...0).contains(e.thresholdDB) else { throw DirectionError("invalid_audio", "Audio settings are outside supported ranges.") }
    }
}

public enum TranscriptEditing {
    public static func words(in sequence: Sequence, transcripts: [SourceTranscript]) -> [TimelineWord] {
        let selected = Dictionary(grouping: transcripts, by: \.assetID).compactMapValues { alternatives in alternatives.max { ($0.selectedAt ?? 0) < ($1.selectedAt ?? 0) } }
        let narrative = sequence.clips.filter { $0.kind == .video && $0.layer == 0 && $0.assetID.flatMap { selected[$0] } != nil }
        let clips = narrative.isEmpty ? sequence.clips.filter { $0.kind == .audio && $0.layer == 0 } : narrative
        return clips.flatMap { clip -> [TimelineWord] in
            guard let assetID = clip.assetID, let t = selected[assetID] else { return [] }
            return t.words.compactMap { w in
                guard let r = w.range.intersection(clip.sourceRange) else { return nil }
                return TimelineWord(id: clip.id + ":" + w.id, sourceWordID: w.id, clipID: clip.id, assetID: assetID, text: w.text, range: .init(start: clip.sequenceTime(at: r.start), duration: r.duration.scaled(by: 1 / clip.speed)))
            }
        }.sorted { $0.range.start < $1.range.start }
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
        func normalized(_ text: String) -> String { text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) }
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
