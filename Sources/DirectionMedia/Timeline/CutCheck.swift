import Foundation
import Vision
import CoreGraphics
import DirectionCore

/// direction_check's look at the cuts (agent-timeline.md › Cut points): jump cuts, where the story cuts between two
/// moments of one take, or two takes framed alike, and the picture visibly jumps; and sound that starts or stops
/// partway through a word. Each is said with its time, how much it jumps, and what could fix it. For the editor,
/// so they're advice; nothing is stopped by them.
public enum CutCheck {
    public struct Problem: Codable, Hashable, Sendable {
        /// jumpCut or midWord.
        public var kind: String
        /// Cut seconds.
        public var at: Double
        public var says: String
        public var clipIDs: [String]
        /// jumpCut: how much it jumps, 0–1.
        public var amount: Double?
        public var fix: String
    }
    public struct Result: Codable, Sendable {
        public var problems: [Problem]
        /// Cuts on the story looked at.
        public var cuts: Int
    }

    /// The most cuts whose frames are rendered and compared, so a long cut still checks in about a minute.
    static let most = 40

    public static func run(project: Project, sequence s: Sequence, dailies: Dailies, transcripts: [SourceTranscript], looks: LookContext? = nil, cacheDirectory: URL, label: @Sendable (Clip) -> String) async throws -> Result {
        let frame = 1 / s.frameRate.value
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in project.assets.first { $0.id == id } } }
        func isGraphic(_ c: Clip) -> Bool { c.kind == .title || asset(c)?.graphic != nil }
        let story = s.storyLayer
        let shots = s.clips.filter { c in c.kind == .video && c.layer == story && c.hold == nil && !isGraphic(c) && c.layout == nil && asset(c).map { !$0.video.isEmpty && !$0.isImage } == true }.sorted { $0.start < $1.start }
        // Picture over the story at a cut (a cutaway, a made shot) hides it.
        let over = s.clips.filter { c in c.kind == .video && c.layer > story && !isGraphic(c) }
        let cuts = zip(shots, shots.dropFirst()).filter { l, r in abs(l.end.seconds - r.start.seconds) < frame / 2 }
        var problems: [Problem] = []

        // Jump cuts: the same take on both sides, or takes of one setup (not angles of one moment, which cut as a
        // multicam does), or other takes whose frames look alike.
        var candidates: [(Clip, Clip)] = []
        for (l, r) in cuts {
            let at = r.start.seconds
            guard r.transition == nil, !over.contains(where: { $0.start.seconds <= at - frame && $0.end.seconds >= at + frame }) else { continue }
            if l.assetID == r.assetID {
                // A split that plays on where it left off isn't a jump.
                if abs(r.sourceRange.start.seconds - l.sourceRange.end.seconds) < frame * l.speed / 2, l.speed == r.speed { continue }
                candidates.append((l, r)); continue
            }
            if let g = dailies.syncGroup(for: l.assetID), g.take(r.assetID ?? "") != nil { continue }
            let a = l.assetID.flatMap { dailies.takes[$0]?.setupCode }, b = r.assetID.flatMap { dailies.takes[$0]?.setupCode }
            if let a, a == b { candidates.append((l, r)); continue }
            // Other takes: only when their own frames at the cut look alike.
            guard let la = asset(l), let ra = asset(r),
                  let x = try? await SourceFrames.image(la, at: max(0, l.sourceRange.end.seconds - frame * l.speed), maxDimension: 320),
                  let y = try? await SourceFrames.image(ra, at: r.sourceRange.start.seconds, maxDimension: 320) else { continue }
            let prints = try await ShotDetector.featurePrints([x, y])
            if ShotDetector.distance(prints[0], prints[1]) < 0.4 { candidates.append((l, r)) }
        }
        if !candidates.isEmpty {
            // The picture as it plays at each cut, without graphics over it: a title doesn't hide a jump.
            var bare = project
            if let i = bare.sequences.firstIndex(where: { $0.id == s.id }) { bare.sequences[i].clips.removeAll(where: isGraphic) }
            let compiled = try await SequenceRenderer.compile(project: bare, sequenceID: s.id, cacheDirectory: cacheDirectory, looks: looks)
            let folder = cacheDirectory.appendingPathComponent("Checks-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            for (l, r) in candidates.prefix(most) {
                try Task.checkCancellation()
                let at = r.start.seconds
                let before = folder.appendingPathComponent("\(Int(at * 1000))-a.png"), after = folder.appendingPathComponent("\(Int(at * 1000))-b.png")
                _ = try await SequenceRenderer.frame(compiled, at: MediaTime(seconds: at - frame / 2), to: before, maxDimension: 480)
                _ = try await SequenceRenderer.frame(compiled, at: MediaTime(seconds: at + frame / 2), to: after, maxDimension: 480)
                guard let x = GraphicChecks.loadImage(before), let y = GraphicChecks.loadImage(after) else { continue }
                let (prints, faces) = try await VisionWork.run { [x = VisionImage(image: x), y = VisionImage(image: y)] in
                    (try [x, y].map { try ShotDetector.featurePrint($0.image) }, [x, y].map { largestFace($0.image) })
                }
                guard let jump = judge(distance: Double(ShotDetector.distance(prints[0], prints[1])), before: faces[0], after: faces[1]) else { continue }
                let same = l.assetID == r.assetID
                problems.append(.init(kind: "jumpCut", at: at, says: "At \(PlainTime.text(at)) the cut from \(label(l)) to \(same ? "later in it" : label(r)) jumps: \(jump.words).", clipIDs: [l.id, r.id], amount: jump.amount,
                                      fix: "Cover it with a cutaway (cutaway with cover \"\(l.id)|\(r.id)\"), change the framing on one side (punchIn over the cut), or roll the cut to where the two frames match."))
            }
        }

        // Sound that starts or stops inside a word: the clip's own words, at its sound's ends (J and L cuts included),
        // for the story's shots and sound on its own (a narration on A1).
        for c in shots + s.clips.filter({ $0.kind == .audio }) {
            guard let a = asset(c), a.audio.contains(where: { !(c.audioOverrides[String($0.id)] ?? $0.settings).muted }) else { continue }
            let words = TranscriptEditing.sourceWords(a.id, transcripts)
            guard !words.isEmpty else { continue }
            let starts = c.sourceRange.start.seconds - (c.soundLead ?? 0) * c.speed, ends = c.sourceRange.end.seconds + (c.soundTail ?? 0) * c.speed
            func inside(_ t: Double) -> TranscriptWord? { words.first { $0.range.start.seconds + 0.06 < t && t < $0.range.end.seconds - 0.06 } }
            if let w = inside(ends) {
                let at = c.soundRange.end.seconds
                problems.append(.init(kind: "midWord", at: at, says: "At \(PlainTime.text(at)) the sound of \(label(c)) stops partway through \u{201C}\(w.text.trimmingCharacters(in: .punctuationCharacters))\u{201D}.", clipIDs: [c.id],
                                      fix: "Trim its tail with snap \"pause\", or roll the cut with snap \"pause\"."))
            }
            if let w = inside(starts) {
                let at = c.soundRange.start.seconds
                problems.append(.init(kind: "midWord", at: at, says: "At \(PlainTime.text(at)) the sound of \(label(c)) starts partway through \u{201C}\(w.text.trimmingCharacters(in: .punctuationCharacters))\u{201D}.", clipIDs: [c.id],
                                      fix: "Trim its head with snap \"pause\", or roll the cut with snap \"pause\"."))
            }
        }
        return Result(problems: Array(problems.sorted { $0.at < $1.at }.prefix(30)), cuts: cuts.count)
    }

    /// Whether two frames either side of a cut jump, and how much: framed alike (the face no more than 15% bigger
    /// or smaller, or without faces, pictures of the same shot) yet visibly different (the face moved 1% of the
    /// frame or changed size 3%, or the picture changed).
    static func judge(distance d: Double, before: CGRect?, after: CGRect?) -> (amount: Double, words: String)? {
        if let a = before, let b = after {
            let ratio = Double(b.height / max(a.height, 1e-6)), moved = Double(hypot(b.midX - a.midX, b.midY - a.midY))
            guard abs(ratio - 1) < 0.15, d < 0.6 else { return nil }
            guard moved >= 0.01 || abs(ratio - 1) >= 0.03 || d >= 0.12 else { return nil }
            var words = "the two shots are framed alike"
            if moved >= 0.01 { words += " and the face moves \(Int((moved * 100).rounded()))% of the frame" }
            if abs(ratio - 1) >= 0.03 { words += (moved >= 0.01 ? " and gets " : " and the face gets ") + "\(Int((abs(ratio - 1) * 100).rounded()))% \(ratio > 1 ? "bigger" : "smaller")" }
            if moved < 0.01 && abs(ratio - 1) < 0.03 { words += " but the picture changes around the face" }
            return (min(1, max(moved / 0.04, abs(ratio - 1) / 0.1, (d - 0.12) / 0.3)), words)
        }
        guard d >= 0.12, d < 0.45 else { return nil }
        return (min(1, (d - 0.12) / 0.3), "the two shots are framed alike but the picture changes")
    }

    static func largestFace(_ image: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results?.map(\.boundingBox).filter { $0.height >= 0.06 }.max { $0.height < $1.height }
    }
}
