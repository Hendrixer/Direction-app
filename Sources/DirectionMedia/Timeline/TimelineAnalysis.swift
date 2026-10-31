import Foundation
@preconcurrency import AVFoundation
import CoreImage
import Vision
import DirectionCore

/// Measurements the edit functions need from the footage itself (agent-timeline.md): Direction measures,
/// then hands concrete values to the operation, so the cut never depends on a guess.
public enum TimelineAnalysis {
    /// Frames across a source range, about `fps` a second, at most `cap`.
    static func frames(_ asset: MediaAsset, _ range: MediaRange, fps: Double, maxSize: CGFloat, cap: Int) async throws -> [(t: Double, image: CGImage)] {
        let url = try MediaInspector.checkedURL(asset)
        let access = try MediaAccess(assets: [asset]); defer { withExtendedLifetime(access) {} }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = .init(width: maxSize, height: maxSize)
        let step = max(1 / fps, range.duration.seconds / Double(cap))
        generator.requestedTimeToleranceBefore = CMTime(seconds: step / 2, preferredTimescale: 600); generator.requestedTimeToleranceAfter = CMTime(seconds: step / 2, preferredTimescale: 600)
        var out: [(Double, CGImage)] = []
        var t = range.start.seconds
        while t < range.end.seconds - 1e-6 && out.count < cap {
            try Task.checkCancellation()
            if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600_000)).image { out.append((t, image)) }
            t += step
        }
        guard !out.isEmpty else { throw DirectionError("bad_argument", "Can't read frames from \(asset.name).") }
        return out
    }

    static func smooth(_ v: [Double], _ radius: Int) -> [Double] { v.indices.map { i in let a = max(0, i - radius), b = min(v.count - 1, i + radius); return v[a...b].reduce(0, +) / Double(b - a + 1) } }

    /// `reframe` with `follow`: x and y keys (source seconds) that keep the face or subject where it belongs at `scale`.
    /// keepIn center or thirds places it; without keepIn it stays where it first appears.
    public static func follow(asset: MediaAsset, clip: Clip, subject: String, scale: Double, keepIn: String?, frame: CGSize) async throws -> ResolvedValues {
        let samples = try await frames(asset, clip.sourceRange, fps: 5, maxSize: 640, cap: 240)
        // On Vision's own threads (`VisionWork`): it blocks while it works.
        let frames = samples.map { VisionImage(image: $0.image) }
        let points: [CGPoint?] = try await VisionWork.run {
            var points: [CGPoint?] = []
            for frame in frames {
                let handler = VNImageRequestHandler(cgImage: frame.image)
                var box: CGRect?
                if subject == "face" {
                    let request = VNDetectFaceRectanglesRequest(); try handler.perform([request])
                    let faces = (request.results ?? []).map(\.boundingBox)
                    let previous = points.last.flatMap { $0 }
                    box = previous.map { p in faces.min { hypot($0.midX - p.x, 1 - $0.midY - p.y) < hypot($1.midX - p.x, 1 - $1.midY - p.y) } } ?? faces.max { $0.width * $0.height < $1.width * $1.height }
                } else {
                    let request = VNGenerateAttentionBasedSaliencyImageRequest(); try handler.perform([request])
                    box = (request.results?.first?.salientObjects ?? []).map(\.boundingBox).max { $0.width * $0.height < $1.width * $1.height }
                }
                // Vision's origin is bottom left; ours is top left.
                points.append(box.map { CGPoint(x: $0.midX, y: 1 - $0.midY) })
            }
            return points
        }
        guard let firstSeen = points.firstIndex(where: { $0 != nil }) else { throw DirectionError("bad_argument", "I couldn't find a \(subject) in \(clip.name). Reframe it without follow.") }
        // Fill the frames where it wasn't found from its neighbors.
        var filled = points
        var last = points[firstSeen]!
        for i in filled.indices { if let p = filled[i] { last = p } else { filled[i] = last } }
        let xs = smooth(filled.map { Double($0!.x) }, 2), ys = smooth(filled.map { Double($0!.y) }, 2)
        // Where a point of the picture lands at this scale with x = y = 0, as fractions of the output frame.
        let size = CGSize(width: samples[0].image.width, height: samples[0].image.height)
        let fit = min(frame.width / size.width, frame.height / size.height)
        let coverX = Double(size.width * fit / frame.width) * scale, coverY = Double(size.height * fit / frame.height) * scale
        let target: (Double, Double)
        switch keepIn {
        case "center": target = (0.5, 0.5)
        case "thirds": target = (xs[firstSeen] < 0.5 ? 1.0 / 3 : 2.0 / 3, subject == "face" ? 0.38 : 0.5)
        default: target = (0.5 + (xs[firstSeen] - 0.5) * coverX, 0.5 + (ys[firstSeen] - 0.5) * coverY)
        }
        func clamp(_ v: Double, _ cover: Double) -> Double { let m = max(0, (cover - 1) / 2); return min(1, max(-1, min(m, max(-m, v)))) }
        var kx: [Keyframe] = [], ky: [Keyframe] = []
        for (i, s) in samples.enumerated() {
            kx.append(.init(t: s.t, v: (clamp(target.0 - 0.5 - (xs[i] - 0.5) * coverX, coverX) * 10_000).rounded() / 10_000))
            ky.append(.init(t: s.t, v: (clamp(target.1 - 0.5 - (ys[i] - 0.5) * coverY, coverY) * 10_000).rounded() / 10_000))
        }
        let missed = points.filter { $0 == nil }.count
        return .init(keys: ["x": kx, "y": ky], warnings: missed * 4 > points.count ? ["The \(subject) was out of sight in \(missed * 100 / points.count)% of \(clip.name); I held its last place there."] : nil)
    }

    /// `stabilize`: Vision homographic registration between neighboring frames, smoothed, as correction keys
    /// dx and dy (fractions of the frame, y down) and rotation (degrees). Cached per take and range.
    public static func stabilize(asset: MediaAsset, clip: Clip, cacheDirectory: URL) async throws -> [String: [Keyframe]] {
        let key = AudioProcessor.digest(Data("\(asset.path):\(asset.fileSize):\(asset.modifiedAt):\(clip.sourceRange.start.seconds):\(clip.sourceRange.duration.seconds):stabilize-v1".utf8))
        let cache = cacheDirectory.appendingPathComponent("Stabilize").appendingPathComponent(key + ".json")
        if let data = try? Data(contentsOf: cache), let keys = try? JSONDecoder().decode([String: [Keyframe]].self, from: data) { return keys }
        let fps = min(15, max(4, asset.video.first?.frameRate ?? 15))
        let samples = try await frames(asset, clip.sourceRange, fps: fps, maxSize: 480, cap: 600)
        guard samples.count > 1 else { return ["dx": [.init(t: samples[0].t, v: 0)], "dy": [.init(t: samples[0].t, v: 0)], "rotation": [.init(t: samples[0].t, v: 0)]] }
        let w = Double(samples[0].image.width), h = Double(samples[0].image.height)
        // On Vision's own threads (`VisionWork`): it blocks while it works.
        let frames = samples.map { VisionImage(image: $0.image) }
        let (x, y, r) = try await VisionWork.run {
            var x = [0.0], y = [0.0], r = [0.0]
            for (a, b) in zip(frames, frames.dropFirst()) {
                let request = VNHomographicImageRegistrationRequest(targetedCGImage: b.image)
                try VNImageRequestHandler(cgImage: a.image).perform([request])
                // The warp maps the next frame onto this one: how far the picture moved, in pixels and radians.
                let m = request.results?.first?.warpTransform
                let tx = Double(m?.columns.2.x ?? 0), ty = Double(m?.columns.2.y ?? 0), rot = atan2(Double(m?.columns.0.y ?? 0), Double(m?.columns.0.x ?? 1))
                x.append(x.last! + tx); y.append(y.last! + ty); r.append(r.last! + rot)
            }
            return (x, y, r)
        }
        let radius = max(3, Int(fps))
        let sx = smooth(x, radius), sy = smooth(y, radius), sr = smooth(r, radius)
        func keys(_ path: [Double], _ smoothPath: [Double], _ scale: Double) -> [Keyframe] { samples.indices.map { Keyframe(t: samples[$0].t, v: ((smoothPath[$0] - path[$0]) * scale * 10_000).rounded() / 10_000) } }
        let result = ["dx": keys(x, sx, 1 / w), "dy": keys(y, sy, -1 / h), "rotation": keys(r, sr, 180 / .pi)]
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.direction.encode(result).write(to: cache, options: .atomic)
        return result
    }

    /// `matchBalance`: measures the middle frame of both shots and finds the balance that makes `clip`
    /// read like `reference` as it's balanced now: exposure, then temperature, tint, saturation and contrast.
    public static func matchBalance(asset: MediaAsset, clip: Clip, referenceAsset: MediaAsset, reference: Clip) async throws -> ColorGrade {
        func middle(_ a: MediaAsset, _ c: Clip) async throws -> CIImage {
            if a.isImage, let image = CIImage(contentsOf: try MediaInspector.checkedURL(a)) { return image }
            let mid = MediaRange(start: c.sourceRange.start + c.sourceRange.duration.scaled(by: 0.5), duration: MediaTime(seconds: 0.05))
            return CIImage(cgImage: try await frames(a, mid, fps: 20, maxSize: 160, cap: 1)[0].image)
        }
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        func graded(_ image: CIImage, _ g: ColorGrade) -> CIImage {
            var i = image
            if g.exposure != 0 { i = i.applyingFilter("CIExposureAdjust", parameters: ["inputEV": g.exposure]) }
            if g.temperature != 0 || g.tint != 0 { i = i.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + g.temperature, y: g.tint)]) }
            if g.contrast != 1 || g.saturation != 1 { i = i.applyingFilter("CIColorControls", parameters: ["inputContrast": g.contrast, "inputSaturation": g.saturation]) }
            return i
        }
        struct Stats { var r = 0.0, g = 0.0, b = 0.0, luma = 0.0, spread = 0.0, chroma = 0.0 }
        func stats(_ image: CIImage) -> Stats {
            let small = image.transformed(by: .init(scaleX: 64 / max(1, image.extent.width), y: 36 / max(1, image.extent.height)))
            var px = [Float](repeating: 0, count: 64 * 36 * 4)
            context.render(small, toBitmap: &px, rowBytes: 64 * 16, bounds: CGRect(x: small.extent.minX, y: small.extent.minY, width: 64, height: 36), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
            var s = Stats(), lumas: [Double] = []
            for i in stride(from: 0, to: px.count, by: 4) {
                let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2]), y = 0.2126 * r + 0.7152 * g + 0.0722 * b
                s.r += r; s.g += g; s.b += b; lumas.append(y); s.chroma += max(r, g, b) - min(r, g, b)
            }
            let n = Double(lumas.count)
            s.r /= n; s.g /= n; s.b /= n; s.chroma /= n; s.luma = lumas.reduce(0, +) / n
            s.spread = sqrt(lumas.map { ($0 - s.luma) * ($0 - s.luma) }.reduce(0, +) / n)
            return s
        }
        let want = stats(graded(try await middle(referenceAsset, reference), reference.grade))
        let raw = try await middle(asset, clip)
        // Each control in turn: bisect until the measure matches the reference.
        func solve(_ lo: Double, _ hi: Double, _ apply: (Double) -> ColorGrade, _ measure: (Stats) -> Double, _ target: Double) -> Double {
            var a = lo, b = hi
            let rising = measure(stats(graded(raw, apply(hi)))) >= measure(stats(graded(raw, apply(lo))))
            for _ in 0..<14 { let m = (a + b) / 2; if (measure(stats(graded(raw, apply(m)))) < target) == rising { a = m } else { b = m } }
            return (a + b) / 2
        }
        var g = clip.grade
        for _ in 0..<2 {
            g.exposure = solve(-5, 5, { var x = g; x.exposure = $0; return x }, \.luma, want.luma)
            g.temperature = solve(-3_000, 3_000, { var x = g; x.temperature = $0; return x }, { $0.r / max(1e-6, $0.b) }, want.r / max(1e-6, want.b))
            g.tint = solve(-100, 100, { var x = g; x.tint = $0; return x }, { $0.g / max(1e-6, ($0.r + $0.b) / 2) }, want.g / max(1e-6, (want.r + want.b) / 2))
            g.saturation = solve(0, 3, { var x = g; x.saturation = $0; return x }, { $0.chroma / max(1e-6, $0.luma) }, want.chroma / max(1e-6, want.luma))
            g.contrast = solve(0.5, 2, { var x = g; x.contrast = $0; return x }, { $0.spread / max(1e-6, $0.luma) }, want.spread / max(1e-6, want.luma))
        }
        func round(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
        g.exposure = round(g.exposure, 0.01); g.temperature = round(g.temperature, 1); g.tint = round(g.tint, 0.1); g.saturation = round(g.saturation, 0.01); g.contrast = round(g.contrast, 0.01)
        return g
    }

    /// `tightenPauses`: stretches of the story's sound quieter than its own floor, in cut time. A breath,
    /// a laugh or a door stays because it isn't quiet.
    public static func quietRanges(project: Project, sequence: Sequence, range: MediaRange, cacheDirectory: URL) async throws -> [MediaRange] {
        var quiet: [MediaRange] = []
        for clip in sequence.clips where clip.layer == 0 && clip.hold == nil && clip.range.intersection(range) != nil {
            guard let asset = clip.assetID.flatMap({ id in project.assets.first { $0.id == id } }), let stream = asset.audio.first(where: { !(clip.audioOverrides[String($0.id)] ?? $0.settings).muted }) else { continue }
            let file = try AVAudioFile(forReading: try await AudioProcessor.extract(asset: asset, trackID: stream.id, directory: cacheDirectory.appendingPathComponent("Audio")))
            let overlap = clip.range.intersection(range)!
            let rate = file.processingFormat.sampleRate, window = Int(rate * 0.02)
            let from = AVAudioFramePosition(clip.sourceTime(at: overlap.start).seconds * rate), count = AVAudioFrameCount(min(Double(file.length - from), overlap.duration.seconds * clip.speed * rate))
            guard from >= 0, from < file.length, count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { continue }
            file.framePosition = from; try file.read(into: buffer, frameCount: count)
            guard let data = buffer.floatChannelData else { continue }
            let channels = Int(buffer.format.channelCount), n = Int(buffer.frameLength) / window
            guard n > 0 else { continue }
            let levels: [Double] = (0..<n).map { k in
                var sum = 0.0
                for c in 0..<channels { for i in (k * window)..<((k + 1) * window) { let v = Double(data[c][i]); sum += v * v } }
                return 10 * log10(max(1e-12, sum / Double(window * channels)))
            }
            let floor = levels.sorted()[levels.count / 10]
            let threshold = min(-30, max(-60, floor + 8))
            var k = 0
            while k < n {
                guard levels[k] < threshold else { k += 1; continue }
                let a = k; while k < n && levels[k] < threshold { k += 1 }
                let sourceStart = Double(from) / rate + Double(a * window) / rate, sourceEnd = Double(from) / rate + Double(k * window) / rate
                let cutStart = clip.start.seconds + (sourceStart - clip.sourceRange.start.seconds) / clip.speed, cutEnd = clip.start.seconds + (sourceEnd - clip.sourceRange.start.seconds) / clip.speed
                if cutEnd - cutStart >= 0.06 { quiet.append(MediaRange(start: cutStart, end: cutEnd)) }
            }
        }
        return quiet
    }
}
