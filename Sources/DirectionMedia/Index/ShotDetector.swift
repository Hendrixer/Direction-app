import Foundation
import CoreGraphics
import Vision
import DirectionCore

/// Step 2: shots. Vision feature prints on frames sampled 4 times a second. A boundary is a local
/// peak in the distance between neighbors above 0.35, or a fade (mean luminance crossing 4% black).
/// Shots are at least 0.5 s. Each boundary is then placed on the exact frame.
public enum ShotDetector {
    public static let rate = 4.0, threshold: Float = 0.35, black = 0.04, minimumShot = 0.5, sampleSize = 512

    public struct Sample: Sendable { public var time: Double; public var print: [Float]; public var luma: Double }

    public struct Result: Sendable {
        public var ranges: [ClosedRange<Double>]
        public var samples: [Sample]
    }

    /// Feature print of one frame, as Vision's normalized float vector.
    public static func featurePrint(_ image: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let o = request.results?.first else { throw DirectionError("feature_print_failed", "Vision couldn't read a frame.") }
        return o.data.withUnsafeBytes { raw in
            switch o.elementType {
            case .float: Array(raw.bindMemory(to: Float.self).prefix(o.elementCount))
            case .double: raw.bindMemory(to: Double.self).prefix(o.elementCount).map(Float.init)
            default: []
            }
        }
    }

    /// Several frames' prints, on Vision's own threads (`VisionWork`): Vision blocks while it works.
    static func featurePrints(_ images: [CGImage]) async throws -> [[Float]] {
        let frames = images.map(VisionImage.init)
        return try await VisionWork.run { try frames.map { try featurePrint($0.image) } }
    }

    public static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return .infinity }
        var d: Float = 0
        for i in a.indices { let x = a[i] - b[i]; d += x * x }
        return d.squareRoot()
    }

    /// Pure: the sample indices where a new shot starts. `distances[i]` is between samples i−1 and i
    /// (distances[0] is unused). Fades win over picture changes when both are near.
    public static func boundaries(times: [Double], distances: [Float], luma: [Double], duration: Double) -> [Int] {
        let n = times.count
        guard n > 1 else { return [] }
        var candidates: [(index: Int, strength: Float)] = []
        for i in 1..<n {
            let d = distances[i]
            let peak = d > threshold && d >= distances[i - 1] && (i + 1 >= n || d >= distances[i + 1])
            let fade = (luma[i - 1] >= black) != (luma[i] >= black)
            if fade { candidates.append((i, .infinity)) } else if peak { candidates.append((i, d)) }
        }
        // Keep shots at least 0.5 s long: of two boundaries too close together keep the stronger.
        var kept: [(index: Int, strength: Float)] = []
        for c in candidates {
            guard times[c.index] >= minimumShot, duration - times[c.index] >= minimumShot else { continue }
            if let last = kept.last, times[c.index] - times[last.index] < minimumShot {
                if c.strength > last.strength { kept[kept.count - 1] = c }
                continue
            }
            kept.append(c)
        }
        return kept.map(\.index)
    }

    /// Samples the take at 4 fps, finds boundaries and refines each to the exact frame.
    public static func detect(_ asset: MediaAsset, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Result {
        let duration = asset.duration.seconds
        guard !asset.video.isEmpty, !asset.isImage, duration > 0 else { return Result(ranges: duration > 0 ? [0...duration] : [], samples: []) }
        var times: [Double] = []
        var t = 0.0
        while t < duration { times.append(t); t += 1 / rate }
        var samples: [Sample] = []
        samples.reserveCapacity(times.count)
        // Decode in batches so a long take doesn't hold every frame in memory at once.
        for chunk in stride(from: 0, to: times.count, by: 48).map({ Array(times[$0..<min(times.count, $0 + 48)]) }) {
            let images = try await SourceFrames.images(asset, at: chunk, maxDimension: sampleSize, tolerance: 0.5 / rate)
            let prints = try await featurePrints(images)
            for ((time, image), print) in zip(zip(chunk, images), prints) { samples.append(Sample(time: time, print: print, luma: SourceFrames.luminance(image))) }
            progress?(Double(samples.count) / Double(times.count))
        }
        var distances: [Float] = [0]
        for i in samples.indices.dropFirst() { distances.append(distance(samples[i - 1].print, samples[i].print)) }
        let found = boundaries(times: samples.map(\.time), distances: distances, luma: samples.map(\.luma), duration: duration)
        var cuts: [Double] = []
        for i in found {
            let fade = (samples[i - 1].luma >= black) != (samples[i].luma >= black)
            let exact = (try? await refine(asset, from: samples[i - 1], to: samples[i], fade: fade)) ?? samples[i].time
            if let last = cuts.last, exact - last < minimumShot { continue }
            if exact >= minimumShot && duration - exact >= minimumShot { cuts.append(exact) }
        }
        let edges = [0] + cuts + [duration]
        return Result(ranges: zip(edges, edges.dropFirst()).map { $0...$1 }, samples: samples)
    }

    /// The first frame of the new shot between two samples: the frame after the biggest jump,
    /// or after the luminance crosses black for a fade.
    static func refine(_ asset: MediaAsset, from a: Sample, to b: Sample, fade: Bool) async throws -> Double {
        let fps = max(1, asset.video.first?.frameRate ?? 24)
        // Whole frames after the earlier sample up to the later one, asked for at their middles
        // so the decoder never lands on the frame before.
        let first = Int((a.time * fps + 1e-6).rounded(.down)) + 1, last = Int((b.time * fps).rounded())
        guard last >= first else { return b.time }
        let frames = Array(first...last)
        let images = try await SourceFrames.images(asset, at: frames.map { (Double($0) + 0.5) / fps }, maxDimension: sampleSize)
        if fade {
            let above = a.luma >= black
            for (n, image) in zip(frames, images) where (SourceFrames.luminance(image) >= black) != above { return Double(n) / fps }
            return b.time
        }
        var previous = a.print, best = (frame: last, d: Float(0))
        for (n, p) in zip(frames, try await featurePrints(images)) {
            let d = distance(previous, p)
            if d > best.d { best = (n, d) }
            previous = p
        }
        return Double(best.frame) / fps
    }
}
