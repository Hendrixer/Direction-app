import Foundation
import AVFoundation
import CoreGraphics
import Vision
import DirectionCore

/// What changes on a screen recording, for screen zooms (agent-timeline.md › Moves): the take looked at four
/// times a second, small and grey, each look against the one before. The cursor, a click landing and
/// typing show as small changes in one place; a new page as a big one. Kept per take in 10-second pieces,
/// so the same stretch is only ever looked at once.
public enum ScreenActivity {
    public static let fps = 4.0
    static let width = 480
    static let chunk = 10.0
    /// A pixel this much brighter or darker than before counts as changed (compression noise stays under it).
    static let threshold = 22

    /// What changed between `from` and `to`, in the take's seconds.
    public static func measure(_ a: MediaAsset, from: Double, to: Double, cacheDirectory: URL) async throws -> [ActivitySample] {
        guard !a.video.isEmpty, !a.isImage, to > from else { return [] }
        var out: [ActivitySample] = []
        let first = Int((max(0, from) / chunk).rounded(.down)), last = Int((min(a.duration.seconds, to) / chunk).rounded(.down))
        for k in first...max(first, last) {
            out += try await piece(a, k, cacheDirectory: cacheDirectory)
        }
        return out.filter { $0.t >= from - 0.5 && $0.t <= to + 0.5 }
    }

    /// One 10-second piece, measured or read back.
    static func piece(_ a: MediaAsset, _ k: Int, cacheDirectory: URL) async throws -> [ActivitySample] {
        let file = LayoutAnalysis.cache(a, "activity-\(k)", cacheDirectory)
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ActivitySample].self, from: data) { return saved }
        let start = Double(k) * chunk, end = min(a.duration.seconds - 0.05, start + chunk)
        guard end > start else { return [] }
        // One look before the piece, so its first sample has something to compare with.
        let times = stride(from: max(0, start - 1 / fps), to: end, by: 1 / fps).map { ($0 * 1000).rounded() / 1000 }
        let frames = try await grey(a, at: times)
        var out: [ActivitySample] = []
        // Only neighbors are compared: a look that didn't decode would make two a half second apart look busy.
        for (previous, current) in zip(frames, frames.dropFirst()) where current.t >= start - 1e-6 && current.t - previous.t <= 1.5 / fps {
            out.append(compare(previous.pixels, current.pixels, w: current.w, h: current.h, t: current.t))
        }
        // A piece missing a look is used now but not kept, so it's looked at again when the Mac is less busy.
        if frames.count == times.count { LayoutAnalysis.save(out, to: file) }
        return out
    }

    /// Where two looks differ: how much of the picture, its middle and the box around it. The middle is the
    /// median of the changed pixels and the box runs from their 5th to 95th percentile each way, so the
    /// odd pixel flickering at the far side (compression around text) doesn't stretch it across the screen.
    static func compare(_ a: [UInt8], _ b: [UInt8], w: Int, h: Int, t: Double) -> ActivitySample {
        guard a.count == b.count, a.count == w * h else { return ActivitySample(t: t, amount: 0) }
        var n = 0, columns = [Int](repeating: 0, count: w), rows = [Int](repeating: 0, count: h)
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                for y in 0..<h {
                    let row = y * w
                    for x in 0..<w where abs(Int(pa[row + x]) - Int(pb[row + x])) > threshold { n += 1; columns[x] += 1; rows[y] += 1 }
                }
            }
        }
        // A few stray pixels are noise, not something happening.
        guard n >= 4 else { return ActivitySample(t: t, amount: 0) }
        /// The position below which `share` of the changed pixels lie.
        func at(_ counts: [Int], _ share: Double) -> Int {
            let target = Double(n) * share
            var sum = 0
            for (i, c) in counts.enumerated() { sum += c; if Double(sum) >= target { return i } }
            return counts.count - 1
        }
        let W = Double(w), H = Double(h)
        let x0 = at(columns, 0.05), x1 = at(columns, 0.95), y0 = at(rows, 0.05), y1 = at(rows, 0.95)
        func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
        return ActivitySample(t: t, amount: r(Double(n) / (W * H)), cx: r((Double(at(columns, 0.5)) + 0.5) / W), cy: r((Double(at(rows, 0.5)) + 0.5) / H),
                              x: r(Double(x0) / W), y: r(Double(y0) / H), w: r(Double(x1 - x0 + 1) / W), h: r(Double(y1 - y0 + 1) / H))
    }

    /// The take at each time, small and grey.
    static func grey(_ a: MediaAsset, at times: [Double]) async throws -> [(t: Double, pixels: [UInt8], w: Int, h: Int)] {
        let url = try MediaInspector.checkedURL(a)
        let access = try MediaAccess(assets: [a]); defer { withExtendedLifetime(access) {} }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: width)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance; generator.requestedTimeToleranceAfter = tolerance
        var out: [(t: Double, pixels: [UInt8], w: Int, h: Int)] = []
        for t in times {
            // A busy Mac sometimes drops a frame; a few more tries, each after a longer moment, before leaving that look out.
            let at = CMTime(seconds: t, preferredTimescale: 600)
            var got: CGImage?
            for wait in [0, 0, 50, 150, 400] where got == nil {
                if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
                got = try? await generator.image(at: at).image
            }
            guard let image = got else { continue }
            let w = width, h = max(2, Int((Double(width) * Double(image.height) / Double(max(1, image.width))).rounded()))
            var pixels = [UInt8](repeating: 0, count: w * h)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.interpolationQuality = .low
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            // A bitmap context keeps its top row first, so y goes down like everything else.
            if drawn { out.append((t, pixels, w, h)) }
        }
        return out
    }

    /// Where words are on screen at one moment: the box (fractions of the picture, y down) of the best line
    /// holding them, or nil.
    public static func find(_ words: String, in a: MediaAsset, at t: Double) async throws -> [Double]? {
        let url = try MediaInspector.checkedURL(a)
        let access = try MediaAccess(assets: [a]); defer { withExtendedLifetime(access) {} }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: ScreenReader.frameSize, height: ScreenReader.frameSize)
        guard let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image else { return nil }
        let frame = VisionImage(image: image), wanted = words.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return try await VisionWork.run {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: frame.image, options: [:]).perform([request])
            // The shortest line with the words in it: a button over a paragraph that mentions it.
            let hits = (request.results ?? []).compactMap { o -> (String, CGRect)? in
                guard let c = o.topCandidates(1).first, let found = c.string.range(of: wanted, options: .caseInsensitive) else { return nil }
                // Just the words, where Vision can say; else the whole line.
                return (c.string, (try? c.boundingBox(for: found))??.boundingBox ?? o.boundingBox)
            }.sorted { $0.0.count < $1.0.count }
            guard let box = hits.first?.1 else { return nil }
            func r(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
            return [r(box.minX), r(1 - box.maxY), r(box.width), r(box.height)]
        }
    }
}
