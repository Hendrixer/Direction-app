import Foundation
import CoreGraphics
import Vision
import DirectionCore

/// Text on screen (footage-index.md › Text on screen). Apple's text recognition reads the middle
/// frame of every shot; a shot with real text in it (a screen recording, slides, a whiteboard) is
/// read every 2 s, skipping frames that haven't changed since the last one read, and what it says
/// is kept in stretches with their times. All of it runs on this Mac.
public enum ScreenReader {
    /// Bumped when reading changes, so takes read by an older reader are read again.
    public static let version = 1
    /// Seconds between frames read in a shot with text.
    public static let interval = 2.0
    /// 4K screen text reads as well at 1920 as at full size, in the same time (measured).
    public static let frameSize = 1920
    /// The fewest words a shot's middle frame needs for the whole shot to be read.
    public static let wordsToRead = 12
    /// Lines Vision is less sure of are left out: at 0.3 and 0.5 they're mostly noise.
    public static let minimumConfidence: Float = 0.8
    /// A frame is read again once this share of its pixels changed since the last frame read.
    public static let changed = 0.001
    /// Frames read at once: four in flight is about twice as fast as one at a time (measured).
    static let concurrency = 4

    public struct Sample: Sendable, Equatable {
        public var time: Double
        public var lines: [String]
        public init(time: Double, lines: [String]) { self.time = time; self.lines = lines }
    }

    /// Every shot of a take with picture, in shot order.
    public static func read(_ asset: MediaAsset, shots: [Shot]) async throws -> [ScreenText] {
        guard !asset.video.isEmpty, !shots.isEmpty else { return [] }
        let middles = try await lines(asset, at: shots.map(\.middle), skipUnchanged: false)
        var out: [ScreenText] = []
        for (shot, middle) in zip(shots, middles) where !middle.isEmpty {
            try Task.checkCancellation()
            let words = middle.reduce(0) { $0 + $1.split(separator: " ").count }
            // A little text (a sign, a mug, a caption) or a short shot: its middle stands for it.
            guard words >= wordsToRead, shot.duration >= 2 * interval else {
                out.append(ScreenText(assetID: asset.id, shotID: shot.id, start: shot.start, end: shot.end, lines: middle)); continue
            }
            let times = Array(stride(from: shot.start + interval / 2, to: shot.end, by: interval))
            let read = try await lines(asset, at: times, skipUnchanged: true)
            out += stretches(zip(times, read).map { Sample(time: $0, lines: $1) }, shot: shot)
        }
        return out
    }

    // MARK: Stretches

    /// A shot's samples as stretches (pure). Lines in at least 80% of the samples stayed on screen
    /// the whole shot and make one stretch from its start to its end. The rest go in stretches for
    /// as long as each frame shares half its lines with the one before and a quarter with the
    /// stretch's first; each stretch runs from halfway after the sample before it to halfway
    /// before the sample after it.
    public static func stretches(_ samples: [Sample], shot: Shot) -> [ScreenText] {
        let samples = samples.sorted { $0.time < $1.time }
        guard !samples.isEmpty else { return [] }
        func make(_ start: Double, _ end: Double, _ lines: [String]) -> ScreenText { ScreenText(assetID: shot.assetID, shotID: shot.id, start: start, end: end, lines: lines) }
        let keyed = samples.map { s -> [(key: String, line: String)] in
            var seen = Set<String>()
            return s.lines.compactMap { l in let k = key(l); return !k.isEmpty && seen.insert(k).inserted ? (k, l) : nil }
        }
        guard samples.count >= 3 else {
            let all = ordered(keyed.flatMap { $0 })
            return all.isEmpty ? [] : [make(shot.start, shot.end, all)]
        }
        var counts: [String: Int] = [:]
        for s in keyed { for k in Set(s.map(\.key)) { counts[k, default: 0] += 1 } }
        let steady = Set(counts.filter { Double($0.value) >= 0.8 * Double(samples.count) }.keys)
        var out: [ScreenText] = []
        let steadyLines = ordered(keyed.flatMap { $0 }.filter { steady.contains($0.key) })
        if !steadyLines.isEmpty { out.append(make(shot.start, shot.end, steadyLines)) }

        struct Group { var first: Int; var last: Int; var firstKeys: Set<String>; var lastKeys: Set<String>; var lines: [(key: String, line: String)] }
        var groups: [Group] = []
        for (i, s) in keyed.enumerated() {
            let changing = s.filter { !steady.contains($0.key) }
            let keys = Set(changing.map(\.key))
            guard !keys.isEmpty else { continue }
            if var g = groups.last, g.last == i - 1, jaccard(g.lastKeys, keys) >= 0.5, jaccard(g.firstKeys, keys) >= 0.25 {
                g.last = i; g.lastKeys = keys; g.lines += changing
                groups[groups.count - 1] = g
            } else {
                groups.append(Group(first: i, last: i, firstKeys: keys, lastKeys: keys, lines: changing))
            }
        }
        for g in groups {
            let start = g.first == 0 ? shot.start : (samples[g.first - 1].time + samples[g.first].time) / 2
            let end = g.last == samples.count - 1 ? shot.end : (samples[g.last].time + samples[g.last + 1].time) / 2
            out.append(make(start, end, ordered(g.lines)))
        }
        return out
    }

    /// Lines compared without case, spacing or punctuation.
    static func key(_ line: String) -> String { line.lowercased().filter { $0.isLetter || $0.isNumber } }
    /// The first spelling of each line, in the order lines were first seen.
    private static func ordered(_ lines: [(key: String, line: String)]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { seen.insert($0.key).inserted ? $0.line : nil }
    }
    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        return union == 0 ? 1 : Double(a.intersection(b).count) / Double(union)
    }

    // MARK: Reading frames

    /// The lines in frames at `times`, decoded a dozen at a time. With `skipUnchanged`, a frame
    /// that looks like the last one read keeps that one's lines instead of being read again.
    static func lines(_ asset: MediaAsset, at times: [Double], skipUnchanged: Bool) async throws -> [[String]] {
        var out: [[String]] = [], lastThumb: [UInt8]?, lastLines: [String] = []
        for chunk in stride(from: 0, to: times.count, by: 12).map({ Array(times[$0..<min(times.count, $0 + 12)]) }) {
            try Task.checkCancellation()
            let images = try await SourceFrames.images(asset, at: chunk, maxDimension: frameSize, tolerance: interval / 4)
            var plan: [Int?] = [], toRead: [Frame] = []
            for image in images {
                if skipUnchanged {
                    let thumb = thumbnail(image)
                    if let last = lastThumb, changedShare(last, thumb) < changed { plan.append(nil); continue }
                    lastThumb = thumb
                }
                plan.append(toRead.count); toRead.append(Frame(image: image))
            }
            let read = try await lines(toRead)
            for p in plan {
                if let i = p { lastLines = read[i] }
                out.append(lastLines)
            }
        }
        return out
    }

    private struct Frame: @unchecked Sendable { var image: CGImage }

    /// Several frames read at once, in order.
    private static func lines(_ frames: [Frame]) async throws -> [[String]] {
        var out = [[String]](repeating: [], count: frames.count)
        try await withThrowingTaskGroup(of: (Int, [String]).self) { group in
            var next = 0
            func add() { guard next < frames.count else { return }; let i = next, f = frames[i]; next += 1; group.addTask { (i, try await lines(f.image)) } }
            for _ in 0..<concurrency { add() }
            while let (i, l) = try await group.next() { out[i] = l; add() }
        }
        return out
    }

    /// One frame's confident lines, cleaned, the largest text first (titles and headings, then
    /// body text, then menus and labels), and text of one size top to bottom, left to right. Rows
    /// across a screen run through every column, so size says more than position. Language
    /// correction is off: it halves the time and changes nothing Vision is sure of.
    ///
    /// Vision's older request, not the Swift `RecognizeTextRequest`: several of those at once in one
    /// process crash inside Apple's text recognition (a 17-minute screen recording took the app
    /// down; about 1 run in 10 of 8 at once crashed, against none in 360 of these).
    public static func lines(_ image: CGImage) async throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let read = (request.results ?? []).compactMap { o -> Read? in
            guard let c = o.topCandidates(1).first, c.confidence >= minimumConfidence, let text = clean(c.string) else { return nil }
            return Read(text: text, rect: o.boundingBox)
        }
        return ordered(read, frameHeight: Double(image.height))
    }

    struct Read { var text: String; var rect: CGRect }

    /// Pure: sizes in steps of 3 px of the frame read, largest first; rows from the top (Vision's
    /// origin is bottom left), a line joining the row when its center is within half its height of
    /// the row's first; each row left to right.
    static func ordered(_ read: [Read], frameHeight: Double) -> [String] {
        var rows: [[Read]] = []
        for r in read.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let first = rows.last?.first, abs(first.rect.midY - r.rect.midY) < max(0.003, r.rect.height / 2) { rows[rows.count - 1].append(r) }
            else { rows.append([r]) }
        }
        let placed = rows.enumerated().flatMap { row, items in items.sorted { $0.rect.minX < $1.rect.minX }.enumerated().map { (row: row, column: $0.offset, read: $0.element) } }
        func size(_ r: Read) -> Int { Int((Double(r.rect.height) * frameHeight / 3).rounded()) }
        return placed.sorted { (size($1.read), $0.row, $0.column) < (size($0.read), $1.row, $1.column) }.map(\.read.text)
    }

    /// Icons read as stray symbols in front of a label ("• All videos", "© Customize") are dropped,
    /// spaces collapse, and a line needs three letters or digits to count. In the system font a
    /// capital I and a small l are drawn alike, and Vision reads "AI" as "Al"; the word alone is
    /// put back, so searching "AI" finds it.
    public static func clean(_ raw: String) -> String? {
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, !first.contains(where: { $0.isLetter || $0.isNumber }) { words.removeFirst() }
        while let last = words.last, !last.contains(where: { $0.isLetter || $0.isNumber }) { words.removeLast() }
        words = words.map { w in
            let core = w.trimmingCharacters(in: .punctuationCharacters)
            return core == "Al" || core == "Als" || core == "Al's" ? w.replacingOccurrences(of: "Al", with: "AI") : w
        }
        let line = words.joined(separator: " ")
        return line.filter({ $0.isLetter || $0.isNumber }).count >= 3 ? line : nil
    }

    /// A small grey copy of a frame for telling whether anything on it changed.
    static func thumbnail(_ image: CGImage) -> [UInt8] {
        let w = 480, h = max(1, Int((480 * Double(image.height) / Double(max(1, image.width))).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return pixels
    }

    /// The share of pixels that moved by more than a tenth of the range: a line of text appearing
    /// shows, a blinking caret or sensor noise doesn't.
    static func changedShare(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var n = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > 24 { n += 1 }
        return Double(n) / Double(a.count)
    }
}
