import Foundation
import Vision
import CoreGraphics
import DirectionCore

/// Before delivery (finish.md › Checks): the cut as it delivers, frame by frame where it matters, against what
/// a viewer loses. A crop that loses a face the take has, or cuts down through it; words in a tall or feed frame
/// where the phone apps put their buttons and captions (the bottom fifth, the right eighth); words over a face.
/// Each is said with its time. They're for a person to judge, so they never stop a delivery on their own.
public enum FramingCheck {
    public struct Problem: Codable, Hashable, Sendable {
        /// faceLost, faceCut, wordsCovered, wordsOverFace.
        public var kind: String
        /// Cut seconds.
        public var at: Double
        public var says: String
    }
    public struct Result: Codable, Sendable {
        public var problems: [Problem]
        public var frames: Int
    }

    /// The most frames looked at, so a long film still checks in about a minute.
    static let most = 72

    public static func run(project: Project, sequence s: Sequence, compiled: CompiledSequence, cacheDirectory: URL, label: @Sendable (Clip) -> String) async throws -> Result {
        let graphics = Set(project.assets.filter { $0.graphic != nil }.map(\.id))
        let story = s.storyLayer
        let shots = s.clips.filter { c in c.kind == .video && c.layer == story && c.hold == nil && !(c.assetID.map(graphics.contains) ?? true) && (c.assetID.flatMap { id in project.assets.first { $0.id == id } }?.video.isEmpty == false) }
        // The middle of each shot, and every 4 s through a long one; then each stretch of captions.
        var times: [Double] = []
        for c in shots {
            let a = c.start.seconds, b = c.end.seconds
            times.append((a + b) / 2)
            if b - a > 8 { times += Swift.stride(from: a + 2, to: b - 1, by: 4).map { $0 } }
        }
        for c in s.clips where c.layer > 0 && (c.assetID.flatMap { id in project.assets.first { $0.id == id }?.graphic }?.hasPrefix("captions-") ?? false) {
            times += Swift.stride(from: c.start.seconds + 0.5, to: c.end.seconds, by: max(3, c.duration.seconds / 6)).map { $0 }
        }
        times = Array(Set(times.map { ($0 * 4).rounded() / 4 })).filter { $0 < s.duration.seconds }.sorted()
        if times.count > most { let step = Double(times.count) / Double(most); times = (0..<most).map { times[Int(Double($0) * step)] } }

        let tall = Double(s.height) > Double(s.width) * 1.05
        let folder = cacheDirectory.appendingPathComponent("Checks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // The takes' own frames, a take at a time, for whether a face is there to lose.
        var source: [Double: (face: Bool, clip: Clip)] = [:]
        for (assetID, group) in Dictionary(grouping: times.compactMap { t in shots.first { $0.start.seconds <= t && t < $0.end.seconds }.map { (t, $0) } }, by: { $0.1.assetID ?? "" }) {
            guard let asset = project.assets.first(where: { $0.id == assetID }), !Self.showsWhole(group[0].1, asset, s) else { continue }
            let images = try await SourceFrames.images(asset, at: group.map { $0.1.sourceTime(at: MediaTime(seconds: $0.0)).seconds }, maxDimension: 480, tolerance: 0.1)
            for ((t, c), image) in zip(group, images) {
                let faces = try await VisionWork.run { [i = VisionImage(image: image)] in try faceBoxes(i.image) }
                source[t] = (faces.contains { $0.height >= 0.1 }, c)
            }
        }

        var problems: [Problem] = []
        for t in times {
            try Task.checkCancellation()
            let png = folder.appendingPathComponent("\(Int(t * 1000)).png")
            _ = try await SequenceRenderer.frame(compiled, at: MediaTime(seconds: t), to: png, maxDimension: 640)
            guard let image = GraphicChecks.loadImage(png) else { continue }
            let (faces, words) = try await VisionWork.run { [i = VisionImage(image: image)] in (try faceBoxes(i.image), try VideoStudying.text(i.image)) }
            let when = PlainTime.text(t)
            if let s = source[t] {
                if s.face && !faces.contains(where: { $0.height >= 0.06 }) { problems.append(.init(kind: "faceLost", at: t, says: "At \(when) the frame loses the face in \(label(s.clip)): the crop leaves it out.")) }
                else if faces.contains(where: { $0.height >= 0.12 && ($0.minX <= 0.005 || $0.maxX >= 0.995 || $0.minY <= 0.005) }) { problems.append(.init(kind: "faceCut", at: t, says: "At \(when) the frame\u{2019}s edge cuts through the face in \(label(s.clip)).")) }
            }
            // Vision's boxes start at the bottom left.
            if tall, let w = words.first(where: { $0.rect.minY < 0.2 || $0.rect.maxX > 0.875 }) {
                problems.append(.init(kind: "wordsCovered", at: t, says: "At \(when) \u{201C}\(w.text)\u{201D} sits where the phone apps put their buttons and captions (the bottom fifth and right eighth of a tall frame)."))
            }
            if let w = words.first(where: { word in faces.contains { f in f.height >= 0.08 && f.intersection(word.rect).area > f.area * 0.25 } }) {
                problems.append(.init(kind: "wordsOverFace", at: t, says: "At \(when) \u{201C}\(w.text)\u{201D} covers a face."))
            }
        }
        // One line for a run of the same problem.
        var merged: [Problem] = []
        for p in problems { if let last = merged.last(where: { $0.kind == p.kind }), p.at - last.at <= 4.5 { continue }; merged.append(p) }
        return Result(problems: Array(merged.prefix(20)), frames: times.count)
    }

    /// The take's whole picture is in the frame, as it was shot: nothing a crop could lose.
    static func showsWhole(_ c: Clip, _ a: MediaAsset, _ s: Sequence) -> Bool {
        let moved = c.effects?.contains { ["transform", "pin", "crop"].contains($0.name) } ?? false
        return c.framing.fit && c.framing.scale <= 1.001 && !moved && c.layout == nil
    }

    static func faceBoxes(_ image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).map(\.boundingBox)
    }
}

extension CGRect {
    var area: Double { isNull ? 0 : Double(width * height) }
}
