import Foundation

/// Captions from the cut's words (finish.md › Captions), worked out the same way every time: a caption ends at
/// the end of a sentence, at a pause, or when it holds as many words or letters as fit, and stays up until the
/// next one starts. The finishing step lays them as caption graphics; delivery writes the same lines as SRT.
public enum Captions {
    public struct Line: Codable, Hashable, Sendable {
        public var text: String
        /// Cut seconds.
        public var start: Double
        public var end: Double
        public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
    }

    /// A pause this long starts a new caption.
    static let pause = 0.4
    /// A caption stays up at least this long, unless the next one starts first, and at most this long past its last word.
    static let shortest = 0.8, linger = 0.6

    /// How many words and letters fit at once in a cut this shape: a wide frame takes a longer line.
    public static func fit(width: Int, height: Int, wordsAtATime: Int? = nil) -> (words: Int, characters: Int) {
        let wide = Double(width) / Double(max(1, height)) >= 1.3
        return (max(1, wordsAtATime ?? (wide ? 7 : 4)), wide ? 42 : 24)
    }

    public static func lines(_ words: [TimelineWord], wordsAtATime: Int, maxCharacters: Int) -> [Line] {
        var out: [Line] = [], current: [TimelineWord] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            out.append(.init(text: current.map(\.text).joined(separator: " "), start: first.range.start.seconds, end: last.range.end.seconds))
            current = []
        }
        for w in words.sorted(by: { $0.range.start < $1.range.start }) where !w.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let last = current.last {
                let gap = w.range.start.seconds - last.range.end.seconds
                let length = current.map(\.text.count).reduce(0, +) + current.count + w.text.count
                if gap >= pause || current.count >= wordsAtATime || length > maxCharacters || ends(last.text) { close() }
            }
            current.append(w)
        }
        close()
        // Up until the next starts, a little past the last word, and never a flash.
        for i in out.indices {
            let next = i + 1 < out.count ? out[i + 1].start : .infinity
            out[i].end = min(next, max(out[i].end + linger, out[i].start + shortest))
            out[i].start = (out[i].start * 100).rounded() / 100; out[i].end = (out[i].end * 100).rounded() / 100
        }
        return out
    }

    static func ends(_ word: String) -> Bool { [".", "?", "!", "\u{2026}"].contains { word.hasSuffix($0) } }

    /// The captions in stretches of at most `limit` seconds (a graphic's longest), each broken at the longest
    /// pause before the limit, so a stretch never starts mid-sentence when it can help it.
    public static func stretches(_ lines: [Line], limit: Double = 110) -> [[Line]] {
        var out: [[Line]] = [], rest = lines[...]
        while let first = rest.first {
            guard let lastFit = rest.lastIndex(where: { $0.end - first.start <= limit }) else { out.append([first]); rest = rest.dropFirst(); continue }
            if lastFit == rest.indices.last { out.append(Array(rest)); break }
            // The longest gap between captions inside the limit, from the second half on.
            let candidates = rest.indices.filter { $0 < lastFit && $0 >= rest.startIndex + (lastFit - rest.startIndex) / 2 }
            let cut = candidates.max { a, b in rest[a + 1].start - rest[a].end < rest[b + 1].start - rest[b].end } ?? lastFit
            out.append(Array(rest[...cut])); rest = rest[(cut + 1)...]
        }
        return out
    }

    /// SubRip, the caption file every player and site takes.
    public static func srt(_ lines: [Line]) -> String {
        func stamp(_ t: Double) -> String {
            let ms = Int((max(0, t) * 1000).rounded()), h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60
            return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms % 1000)
        }
        return lines.enumerated().map { i, l in "\(i + 1)\n\(stamp(l.start)) --> \(stamp(l.end))\n\(l.text)\n" }.joined(separator: "\n")
    }
}
