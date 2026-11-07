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
        /// The shot the crop is on, for a face the crop loses or cuts through.
        public var clipID: String?
    }
    public struct Result: Codable, Sendable {
        public var problems: [Problem]
        public var frames: Int
    }

    /// The most frames looked at, so a long film still checks in about a minute.
    static let most = 72

    /// Faces are judged on the picture alone (the shots as framed, without graphics or titles over them), so
    /// words over a face are said as words over a face, not as a crop that lost it; words are read from the
    /// frame as it delivers.
    public static func run(project: Project, sequence s: Sequence, compiled: CompiledSequence, looks: LookContext? = nil, cacheDirectory: URL, label: @Sendable (Clip) -> String) async throws -> Result {
        let graphics = Set(project.assets.filter { $0.graphic != nil }.map(\.id))
        func isGraphic(_ c: Clip) -> Bool { c.kind == .title || (c.assetID.map(graphics.contains) ?? false) }
        let story = s.storyLayer
        let shots = s.clips.filter { c in c.kind == .video && c.layer == story && c.hold == nil && !isGraphic(c) && (c.assetID.flatMap { id in project.assets.first { $0.id == id } }?.video.isEmpty == false) }
        // Picture over the story (a cutaway, a made shot) is what's seen there: the shot's crop isn't.
        let over = s.clips.filter { c in c.kind == .video && c.layer > story && !isGraphic(c) }
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
        let folder = cacheDirectory.appendingPathComponent("Checks-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // The takes' own frames, a take at a time, for whether a face is there to lose. A shot in a layout, or
        // under other picture at that moment, isn't judged on its crop.
        var source: [Double: (face: Bool, clip: Clip)] = [:]
        let judged = times.compactMap { t in shots.first { $0.start.seconds <= t && t < $0.end.seconds }.map { (t, $0) } }
            .filter { t, _ in !over.contains { $0.start.seconds <= t && t < $0.end.seconds } }
        for (assetID, group) in Dictionary(grouping: judged, by: { $0.1.assetID ?? "" }) {
            guard let asset = project.assets.first(where: { $0.id == assetID }) else { continue }
            let group = group.filter { !Self.showsWhole($0.1, asset, s) }
            guard !group.isEmpty else { continue }
            let images = try await SourceFrames.images(asset, at: group.map { $0.1.sourceTime(at: MediaTime(seconds: $0.0)).seconds }, maxDimension: 480, tolerance: 0.1)
            for ((t, c), image) in zip(group, images) {
                let faces = try await VisionWork.run { [i = VisionImage(image: image)] in try faceBoxes(i.image) }
                source[t] = (faces.contains { $0.height >= 0.1 }, c)
            }
        }

        // The picture without its graphics, when there are any.
        var picture = compiled
        if s.clips.contains(where: isGraphic), let i = project.sequences.firstIndex(where: { $0.id == s.id }) {
            var bare = project
            bare.sequences[i].clips.removeAll(where: isGraphic)
            picture = try await SequenceRenderer.compile(project: bare, sequenceID: s.id, cacheDirectory: cacheDirectory, looks: looks)
        }

        var problems: [Problem] = []
        for t in times {
            try Task.checkCancellation()
            let png = folder.appendingPathComponent("\(Int(t * 1000)).png")
            _ = try await SequenceRenderer.frame(compiled, at: MediaTime(seconds: t), to: png, maxDimension: 640)
            guard let image = GraphicChecks.loadImage(png) else { continue }
            var faces: [CGRect]
            let words: [ScreenReader.Read]
            if picture === compiled {
                (faces, words) = try await VisionWork.run { [i = VisionImage(image: image)] in (try faceBoxes(i.image), try VideoStudying.text(i.image)) }
            } else {
                let bareFile = folder.appendingPathComponent("\(Int(t * 1000))-picture.png")
                _ = try await SequenceRenderer.frame(picture, at: MediaTime(seconds: t), to: bareFile, maxDimension: 640)
                guard let shot = GraphicChecks.loadImage(bareFile) else { continue }
                faces = try await VisionWork.run { [i = VisionImage(image: shot)] in try faceBoxes(i.image) }
                words = try await VisionWork.run { [i = VisionImage(image: image)] in try VideoStudying.text(i.image) }
            }
            let when = PlainTime.text(t)
            if let s = source[t] {
                if s.face && !faces.contains(where: { $0.height >= 0.06 }) { problems.append(.init(kind: "faceLost", at: t, says: "At \(when) the frame loses the face in \(label(s.clip)): the crop leaves it out.", clipID: s.clip.id)) }
                else if faces.contains(where: { $0.height >= 0.12 && ($0.minX <= 0.005 || $0.maxX >= 0.995 || $0.minY <= 0.005) }) { problems.append(.init(kind: "faceCut", at: t, says: "At \(when) the frame\u{2019}s edge cuts through the face in \(label(s.clip)).", clipID: s.clip.id)) }
            }
            // Vision's boxes start at the bottom left.
            if tall, let w = words.first(where: { $0.rect.minY < 0.2 || $0.rect.maxX > 0.875 }) {
                problems.append(.init(kind: "wordsCovered", at: t, says: "At \(when) \u{201C}\(w.text)\u{201D} sits where the phone apps put their buttons and captions (the bottom fifth and right eighth of a tall frame)."))
            }
            if let w = words.first(where: { word in faces.contains { f in f.height >= 0.08 && f.intersection(word.rect).area > f.area * 0.25 } }) {
                problems.append(.init(kind: "wordsOverFace", at: t, says: "At \(when) \u{201C}\(w.text)\u{201D} covers a face."))
            }
        }
        // One line for a run of the same problem: on one shot, or seen again within a few seconds of the last time.
        var merged: [Problem] = [], seen: [String: (at: Double, clipID: String?)] = [:]
        for p in problems {
            defer { seen[p.kind] = (p.at, p.clipID) }
            if let last = seen[p.kind], p.clipID != nil ? p.clipID == last.clipID : p.at - last.at <= 4.5 { continue }
            merged.append(p)
        }
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
