import Foundation
@preconcurrency import AVFoundation
import CoreImage
import Vision
import DirectionCore

/// Screens, windows and signs in a shot (agent-timeline.md › Pin and Zoom through): Vision finds the
/// rectangles, follows one as the camera moves, and Direction works out the keys that pin a picture
/// into it or push the camera through it. Corners are fractions of the cut's frame from its top left,
/// in the order top left, top right, bottom right, bottom left.
extension TimelineAnalysis {
    typealias Quad = [CGPoint]

    /// Rectangles in a frame, biggest first, as fractions of the picture (y down).
    static func quads(in image: CGImage) throws -> [Quad] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.2; request.maximumAspectRatio = 1; request.minimumSize = 0.08
        request.maximumObservations = 8; request.minimumConfidence = 0.4; request.quadratureTolerance = 30
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).map(quad).sorted { area($0) > area($1) }
    }
    static func quad(_ o: VNRectangleObservation) -> Quad { [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) } }
    static func area(_ q: Quad) -> Double {
        var a = 0.0
        for i in 0..<4 { let p = q[i], n = q[(i + 1) % 4]; a += Double(p.x * n.y - n.x * p.y) }
        return abs(a) / 2
    }

    /// One quad through frames: Vision follows it from the first; where it loses it, the last place holds.
    static func follow(_ first: Quad, through frames: [CGImage]) -> (quads: [Quad], lost: Int) {
        var out: [Quad] = [first], lost = 0
        guard frames.count > 1 else { return (out, 0) }
        let handler = VNSequenceRequestHandler()
        let v = first.map { CGPoint(x: $0.x, y: 1 - $0.y) }
        var last = VNRectangleObservation(requestRevision: VNDetectRectanglesRequestRevision1, topLeft: v[0], topRight: v[1], bottomRight: v[2], bottomLeft: v[3])
        for image in frames.dropFirst() {
            let request = VNTrackRectangleRequest(rectangleObservation: last)
            request.trackingLevel = VNRequestTrackingLevel.accurate
            let ran = (try? handler.perform([request], on: image)) != nil
            if ran, let found = request.results?.first as? VNRectangleObservation, found.confidence > 0.3 {
                last = found; out.append(quad(found))
            } else { lost += 1; out.append(out.last!) }
        }
        return (out, lost)
    }

    /// Where a point of a clip's picture lands in the cut's frame, and back, with its framing and a
    /// transform at that moment (crop and rotation aside), as fractions of the frame.
    struct Placement {
        var x: (a: Double, b: Double), y: (a: Double, b: Double)
        func show(_ p: CGPoint) -> CGPoint { CGPoint(x: x.a + Double(p.x) * x.b, y: y.a + Double(p.y) * y.b) }
        func source(_ p: CGPoint) -> CGPoint { CGPoint(x: (Double(p.x) - x.a) / x.b, y: (Double(p.y) - y.a) / y.b) }
    }
    static func placement(_ c: Clip, picture: CGSize, frame: CGSize, at sourceSeconds: Double?) -> Placement {
        let f = c.framing, tr = c.effects?.first { $0.name == "transform" }
        let ts = tr?.number("scale", at: sourceSeconds, default: 1) ?? 1, tx = tr?.number("x", at: sourceSeconds, default: 0) ?? 0, ty = tr?.number("y", at: sourceSeconds, default: 0) ?? 0
        let w = Double(picture.width), h = Double(picture.height), W = Double(frame.width), H = Double(frame.height)
        let ratio = (f.fit ? min(W / w, H / h) : max(W / w, H / h)) * f.scale * ts
        let cx = w * ratio / W, cy = h * ratio / H
        return Placement(x: (0.5 - cx / 2 + f.offsetX + tx, cx), y: (0.5 - cy / 2 + f.offsetY + ty, cy))
    }

    /// Frames of a clip between two cut times, about `fps` a second, with the cut time of each.
    static func cutFrames(_ asset: MediaAsset, _ c: Clip, from a: Double, to b: Double, fps: Double, cap: Int) async throws -> [(t: Double, image: CGImage)] {
        let s0 = c.sourceTime(at: MediaTime(seconds: a)).seconds, s1 = max(s0 + 1e-3, c.sourceTime(at: MediaTime(seconds: b)).seconds)
        let samples = try await frames(asset, MediaRange(start: MediaTime(seconds: s0), duration: MediaTime(seconds: s1 - s0)), fps: fps * c.speed, maxSize: 640, cap: cap)
        return samples.map { (c.start.seconds + ($0.t - c.sourceRange.start.seconds) / c.speed, $0.image) }
    }

    /// The quad to follow in the first frame: near the corners given (in the frame), or the biggest one.
    static func start(_ image: CGImage, near corners: [[Double]]?, placement: Placement) throws -> Quad? {
        guard let corners else { return try quads(in: image).first }
        return corners.map { placement.source(CGPoint(x: $0[0], y: $0[1])) }
    }

    /// Keys at each time, linear between, in cut seconds.
    static func keys(_ times: [Double], _ values: [String: [Double]]) -> [String: [Keyframe]] {
        values.mapValues { v in zip(times, v).map { Keyframe(t: ($0 * 1_000_000).rounded() / 1_000_000, v: ($1 * 10_000).rounded() / 10_000) } }
    }

    static func noScreen(_ c: Clip) -> DirectionError {
        DirectionError("no_screen", "I couldn't find a screen, window or sign in \(c.name) to use. Give corners: four [x, y] points, fractions of the frame from its top left (top left, top right, bottom right, bottom left).")
    }

    /// `pin`: corner keys (cut seconds) that keep `clip` inside the screen in `story`, the shot under it.
    public static func pin(clip: Clip, story: Clip, asset: MediaAsset, corners: [[Double]]?, frame: CGSize, fps: Double) async throws -> ResolvedValues {
        let a = max(clip.start.seconds, story.start.seconds), b = min(clip.end.seconds, story.end.seconds)
        guard b > a else { throw DirectionError("bad_argument", "\(clip.name) isn't over \(story.name).") }
        let samples = try await cutFrames(asset, story, from: a, to: b, fps: min(fps, 15), cap: 600)
        let size = CGSize(width: samples[0].image.width, height: samples[0].image.height)
        func place(_ t: Double) -> Placement { placement(story, picture: size, frame: frame, at: story.sourceTime(at: MediaTime(seconds: t)).seconds) }
        guard let first = try start(samples[0].image, near: corners, placement: place(samples[0].t)) else { throw noScreen(story) }
        let (found, lost) = follow(first, through: samples.map(\.image))
        var values: [String: [Double]] = [:]
        for (i, s) in samples.enumerated() {
            let shown = found[i].map(place(s.t).show)
            for (name, p) in zip(EditCatalog.pinCorners, shown) { values[name + ".x", default: []].append(Double(p.x)); values[name + ".y", default: []].append(Double(p.y)) }
        }
        let warnings = lost * 4 > samples.count ? ["I lost the screen in \(lost * 100 / samples.count)% of \(story.name); the pin holds its last place there."] : []
        return ResolvedValues(keys: keys(samples.map(\.t), values), warnings: warnings.isEmpty ? nil : warnings)
    }

    /// `zoomThrough`: transform keys for the left shot that push into its screen until it fills the frame
    /// at the cut, and corner keys for the right shot's first frame, pinned in the screen and opening out
    /// to the whole frame by the cut. All in cut seconds, one key a frame.
    public static func zoomThrough(left: Clip, asset: MediaAsset, seconds: Double, corners: [[Double]]?, frame: CGSize, fps: Double) async throws -> ResolvedValues {
        let n = max(2, min(Int((seconds * fps).rounded()), 300)), end = left.end.seconds, begin = end - Double(n) / fps
        guard begin >= left.start.seconds - 1e-6 else { throw DirectionError("bad_argument", "\(left.name) is shorter than the push.") }
        let samples = try await cutFrames(asset, left, from: begin, to: end, fps: min(fps, 30), cap: 300)
        let size = CGSize(width: samples[0].image.width, height: samples[0].image.height)
        let place = placement(left, picture: size, frame: frame, at: nil)
        var first = try start(samples[0].image, near: corners, placement: place)
        // Nothing at the start of the push: the screen may only come into view later in it.
        if first == nil, corners == nil { first = try quads(in: samples[samples.count / 2].image).first ?? quads(in: samples[samples.count - 1].image).first }
        guard let first else { throw noScreen(left) }
        let (found, lost) = follow(first, through: samples.map(\.image))
        // The screen as the frame shows it, one per frame of the push, between the samples.
        let times = (0...n).map { begin + Double($0) / fps }
        func shown(at t: Double) -> Quad {
            let j = samples.lastIndex { $0.t <= t + 1e-9 } ?? 0, k = min(j + 1, samples.count - 1)
            let span = samples[k].t - samples[j].t, f = span > 0 ? min(1, max(0, (t - samples[j].t) / span)) : 0
            return (0..<4).map { i in place.show(CGPoint(x: found[j][i].x + (found[k][i].x - found[j][i].x) * f, y: found[j][i].y + (found[k][i].y - found[j][i].y) * f)) }
        }
        let last = shown(at: end)
        let w = Double(last.map(\.x).max()! - last.map(\.x).min()!), h = Double(last.map(\.y).max()! - last.map(\.y).min()!)
        guard w > 0.01, h > 0.01 else { throw noScreen(left) }
        let zoom = max(1 / w, 1 / h)
        guard zoom <= 8 else { throw DirectionError("bad_argument", "The screen in \(left.name) is only \(Int((w * h * 100).rounded()))% of the frame; filling the frame with it would take \(String(format: "%.1f", zoom))×, and 8× is the most a transform does. Use a closer shot, or a shorter push from a closer frame.") }
        var values: [String: [Double]] = [:]
        for t in times {
            let u = min(1, max(0, (t - begin) / (end - begin))), e = u * u * (3 - 2 * u)
            let q = shown(at: t)
            let cx = Double(q.map(\.x).min()! + q.map(\.x).max()!) / 2, cy = Double(q.map(\.y).min()! + q.map(\.y).max()!) / 2
            // Scale grows evenly in the eye; the screen's middle travels to the frame's middle.
            let k = pow(zoom, e)
            let tx = (cx + (0.5 - cx) * e) - 0.5 - (cx - 0.5) * k, ty = (cy + (0.5 - cy) * e) - 0.5 - (cy - 0.5) * k
            values["scale", default: []].append(k); values["x", default: []].append(tx); values["y", default: []].append(ty)
            // The right shot sits in the screen, then opens out to the whole frame by the cut.
            let open = u <= 0.6 ? 0 : { let v = (u - 0.6) / 0.4; return v * v * (3 - 2 * v) }()
            for (i, name) in EditCatalog.pinCorners.enumerated() {
                let px = 0.5 + (Double(q[i].x) - 0.5) * k + tx, py = 0.5 + (Double(q[i].y) - 0.5) * k + ty
                let fx = [0.0, 1, 1, 0][i], fy = [0.0, 0, 1, 1][i]
                values[name + ".x", default: []].append(min(2, max(-1, px + (fx - px) * open))); values[name + ".y", default: []].append(min(2, max(-1, py + (fy - py) * open)))
            }
        }
        let warnings = lost * 4 > samples.count ? ["I lost the screen in \(lost * 100 / samples.count)% of the push; it holds its last place there."] : []
        return ResolvedValues(keys: keys(times, values), warnings: warnings.isEmpty ? nil : warnings)
    }
}
