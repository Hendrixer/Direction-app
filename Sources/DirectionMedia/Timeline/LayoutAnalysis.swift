import Foundation
@preconcurrency import AVFoundation
import Vision
import DirectionCore

/// What a layout needs from the footage (layouts.md): which takes in sync are cameras and which are
/// screen recordings, and where the face is in each camera. Faces are found with Apple's Vision on this
/// Mac, once per take, and kept in the film's cache.
public enum LayoutAnalysis {
    /// The takes in sync with the story over `range`, sorted into cameras (best face first) and screens,
    /// with each camera's face track.
    public static func measure(project: Project, sequence: DirectionCore.Sequence, dailies: Dailies, range: MediaRange?, cacheDirectory: URL) async throws -> LayoutMeasure {
        let stories = sequence.clips.filter { c in c.kind == .video && c.layer == 0 && c.assetID != nil && (range.map { r in c.start < r.end && c.end > r.start } ?? true) }
        var groups: [SyncGroup] = []
        for c in stories { if let g = dailies.syncGroup(for: c.assetID), !groups.contains(where: { $0.id == g.id }) { groups.append(g) } }
        var cameras: [(id: String, score: Double)] = [], screens: [String] = [], faces: [String: FaceTrack] = [:]
        for g in groups {
            let takes = g.takes.compactMap { t in project.assets.first { $0.id == t.assetID && !$0.video.isEmpty && !$0.isImage } }
            guard takes.count > 1 else { continue }
            let (camera, screen) = try await sort(takes, cacheDirectory: cacheDirectory)
            cameras += camera; screens += screen
            for c in camera { faces[c.id] = try await faceTrack(project.assets.first { $0.id == c.id }!, cacheDirectory: cacheDirectory) }
        }
        return LayoutMeasure(cameras: cameras.sorted { $0.score > $1.score }.map(\.id), screens: screens, faces: faces)
    }

    /// A take named for a camera is one. Otherwise the camera is the take with the biggest face, and
    /// another only if its face is nearly as big and it doesn't look like a screen recording: a screen often
    /// shows the person too (a preview of the camera, a video of them). With no face anywhere, a name or
    /// shape that looks like a screen recording decides. At least one take is always the screen.
    static func sort(_ takes: [MediaAsset], cacheDirectory: URL) async throws -> (cameras: [(id: String, score: Double)], screens: [String]) {
        var scores: [(asset: MediaAsset, score: Double)] = []
        for a in takes { scores.append((a, try await faceScore(a, cacheDirectory: cacheDirectory))) }
        let ranked = scores.sorted { $0.score > $1.score }, best = ranked.first?.score ?? 0
        var cameras: [(id: String, score: Double)]
        let named = ranked.filter { looksLikeCamera($0.asset) }
        if !named.isEmpty && named.count < takes.count {
            cameras = named.map { ($0.asset.id, $0.score) }
        } else if best >= 0.05 {
            cameras = [(ranked[0].asset.id, best)] + ranked.dropFirst().filter { $0.score >= best * 0.8 && !looksLikeScreen($0.asset) }.map { ($0.asset.id, $0.score) }
            if cameras.count == takes.count { cameras.removeLast() }
        } else if let guess = takes.first(where: { !looksLikeScreen($0) }) {
            cameras = [(guess.id, 0)]
        } else { cameras = [] }
        let screens = takes.filter { a in !cameras.contains { $0.id == a.id } }.map(\.id)
        guard !cameras.isEmpty, !screens.isEmpty else { return ([], []) }
        return (cameras, screens)
    }

    static func looksLikeCamera(_ a: MediaAsset) -> Bool {
        let name = a.name.lowercased()
        return ["camera", "webcam", "facecam", "cam-", "cam_", "a-cam", "a cam"].contains(where: name.contains) && !looksLikeScreen(a)
    }

    public static func looksLikeScreen(_ a: MediaAsset) -> Bool {
        let name = a.name.lowercased()
        if ["screen", "recording", "capture", "display", "cleanshot"].contains(where: name.contains) { return true }
        guard let v = a.video.first, v.height > 0 else { return false }
        let ratio = Double(v.width) / Double(v.height)
        return abs(ratio - 16.0 / 9) > 0.05 && abs(ratio - 9.0 / 16) > 0.05
    }

    /// How big the main face usually is in a take: the median, over five frames, of the largest face's height.
    static func faceScore(_ a: MediaAsset, cacheDirectory: URL) async throws -> Double {
        let file = cache(a, "score", cacheDirectory)
        if let data = try? Data(contentsOf: file), let v = try? JSONDecoder().decode(Double.self, from: data) { return v }
        let d = a.duration.seconds
        let times = [0.1, 0.3, 0.5, 0.7, 0.9].map { $0 * d }
        let images = try await frames(a, at: times)
        let heights = try await VisionWork.run { images.map { largestFace(in: $0.image.image)?.h ?? 0 } }.sorted()
        let score = heights.isEmpty ? 0 : heights[heights.count / 2]
        save(score, to: file)
        return score
    }

    /// The face about once a second through the whole take, nearest the last one when there are several.
    /// Read in short runs so a long take never holds more than a few frames.
    public static func faceTrack(_ a: MediaAsset, cacheDirectory: URL) async throws -> FaceTrack {
        let file = cache(a, "faces", cacheDirectory)
        if let data = try? Data(contentsOf: file), let track = try? JSONDecoder().decode(FaceTrack.self, from: data) { return track }
        let d = a.duration.seconds, step = max(1, d / 3_600)
        var samples: [FaceTrack.Sample] = [], t = 0.0
        while t < d {
            try Task.checkCancellation()
            var times: [Double] = []
            while t < d && times.count < 24 { times.append(t); t += step }
            let images = try await frames(a, at: times, tolerance: step / 2)
            let previous = samples.last
            let found = try await VisionWork.run {
                var out: [FaceTrack.Sample] = [], last = previous
                for (time, frame) in images {
                    guard let f = largestFace(in: frame.image, near: last) else { continue }
                    let s = FaceTrack.Sample(t: time, x: f.x, y: f.y, h: f.h)
                    out.append(s); last = s
                }
                return out
            }
            samples += found
        }
        let track = FaceTrack(samples: samples)
        save(track, to: file)
        return track
    }

    /// The face nearest `near`, or the largest, as its middle (y down) and height, fractions of the picture.
    static func largestFace(in image: CGImage, near: FaceTrack.Sample? = nil) -> (x: Double, y: Double, h: Double)? {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let faces = (request.results ?? []).map(\.boundingBox).filter { $0.height > 0.02 }
        let pick = near.map { p in faces.min { hypot($0.midX - p.x, 1 - $0.midY - p.y) < hypot($1.midX - p.x, 1 - $1.midY - p.y) } } ?? faces.max { $0.height < $1.height }
        return pick.map { (Double($0.midX), Double(1 - $0.midY), Double($0.height)) }
    }

    static func frames(_ a: MediaAsset, at times: [Double], tolerance: Double = 0.25) async throws -> [(t: Double, image: VisionImage)] {
        let url = try MediaInspector.checkedURL(a)
        let access = try MediaAccess(assets: [a]); defer { withExtendedLifetime(access) {} }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600); generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)
        var out: [(t: Double, image: VisionImage)] = []
        for t in times { if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image { out.append((t, VisionImage(image: image))) } }
        return out
    }

    static func cache(_ a: MediaAsset, _ kind: String, _ directory: URL) -> URL {
        let key = AudioProcessor.digest(Data("\(a.path):\(a.fileSize):\(a.modifiedAt):\(kind)-v1".utf8))
        return directory.appendingPathComponent("Faces").appendingPathComponent(key + ".json")
    }
    static func save<T: Encodable>(_ value: T, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.direction.encode(value).write(to: file, options: .atomic)
    }
}
