import Foundation

// Fitting a song to a length (agent-timeline.md › Music › fit): play it from its start to its own ending, and make
// it the length asked for by jumping, once or twice, from the start of one bar to the start of another that sounds
// alike, the way a music editor cuts a needle drop to picture. Direction measures the bars (MusicMaterial); the
// search here is plain arithmetic, so it's the same every time the batch runs.

/// What Direction measured of a song for fitting it: its grid, its length, and each bar's sound.
public struct MusicMaterial: Codable, Hashable, Sendable {
    public var grid: BeatGrid
    /// The song's length in seconds (its shortest part, for a song in parts).
    public var seconds: Double
    /// Each bar's sound as a point to compare (its notes, timbre and level, each unit length), bar 1 first.
    public var bars: [[Float]]
    /// Each bar's level in dB.
    public var levels: [Float]
    /// Where the last thing played starts to ring out (seconds): the ending can be faded from a little after it.
    public var lastHit: Double
    public init(grid: BeatGrid, seconds: Double, bars: [[Float]], levels: [Float], lastHit: Double) { self.grid = grid; self.seconds = seconds; self.bars = bars; self.levels = levels; self.lastHit = lastHit }
}

/// A song as fitted: the pieces of it played in turn, in its own seconds, and how they join.
public struct MusicPlan: Codable, Hashable, Sendable {
    /// Each piece ends, and the next starts, just before a downbeat.
    public var pieces: [SecondsRange]
    /// Seconds each join crosses over, ending at the join.
    public var crossfade: Double
    /// A fade at the start (the music starts inside its intro) or the end (its ring is cut short), in seconds.
    public var fadeIn: Double?
    public var fadeOut: Double?
    /// "bars 1–12, then 29–48", and each join's bars and how alike they are.
    public var said: String
    public var joins: [String]
    public var warnings: [String]
    public var length: Double { pieces.reduce(0) { $0 + $1.end - $1.start } }
}

public enum MusicFitting {
    /// Each join crosses over this long, ending this long before the downbeat, so the new bar's first hit plays whole.
    public static let crossfade = 0.010, early = 0.002
    /// The ending may be faded from this long after the last thing played.
    static let ring = 1.5
    /// A join costing more than this isn't between alike bars.
    static let poor = 0.35

    struct Join { var x: Int; var y: Int; var cost: Double }
    struct Candidate { var start: Double; var startBar: Int?; var joins: [Join]; var tail: Double; var cost: Double; var warnings: [String] }

    /// The plan that makes the song `length` seconds: from its start to its own ending, with one or two joins between
    /// bars that sound alike, keeping the intro and the ending when there's room for them. What's left over (less than
    /// a bar) comes off the ring at the end or the moment before bar 1; failing that, the music starts on a later bar
    /// or ends faded early, and says so.
    public static func plan(_ m: MusicMaterial, length: Double, song: String) throws -> MusicPlan {
        let g = m.grid, starts = g.barStarts, n = starts.count
        guard length > 0 else { throw DirectionError("bad_argument", "fit needs a length.") }
        guard n >= 4, m.bars.count == n, m.levels.count == n else { throw DirectionError("no_beat", "\(song) is too short to fit by its bars.") }
        let barSeconds = g.barSeconds
        // Bar k (0-based) runs from starts[k] to starts[k + 1]; the last to the song's end.
        func unit(_ v: [Float]) -> [Float] { let d = v.reduce(0) { $0 + $1 * $1 }.squareRoot(); return d > 0 ? v.map { $0 / d } : v }
        let f = m.bars.map(unit)
        func alike(_ a: Int, _ b: Int) -> Double { Double(zip(f[a], f[b]).reduce(Float(0)) { $0 + $1.0 * $1.1 }) }
        // Joining from the start of bar x to the start of bar y: what's just been heard (bar x-1) should be like what
        // came before y (bar y-1), and what comes next (bar y) like what would have (bar x), at about the same level,
        // and a whole number of phrases (4 bars, best 8) away.
        func cost(_ x: Int, _ y: Int) -> Double {
            let d = abs(y - x)
            let phrase = d % 8 == 0 ? 0 : d % 4 == 0 ? 0.03 : d % 2 == 0 ? 0.12 : 0.2
            let level = Double(abs(m.levels[x - 1] - m.levels[y - 1]) + abs(m.levels[x] - m.levels[y])) / 2 / 3 * 0.1
            return 1 - (alike(x - 1, y - 1) + alike(x, y)) / 2 + phrase + level
        }
        // The intro ends where the song first moves on; the ending starts where it last does.
        let changes = g.changes.map { $0 - 1 }.filter { $0 > 0 && $0 < n }
        let intro = changes.first ?? 0, outro = changes.last ?? n - 1
        let head = max(0, starts[0] - 0.005), tailRoom = max(0, m.seconds - max(m.lastHit, starts[n - 1]) - ring)
        var joins: [Join] = []
        for x in 1..<n { for y in 1..<n where abs(y - x) >= 2 { joins.append(Join(x: x, y: y, cost: cost(x, y))) } }
        func keepsShape(_ j: Join) -> Bool { j.y > j.x ? j.x >= intro && j.y <= outro : j.y >= intro && j.x <= outro }
        let shift = { (j: Join) in starts[j.y] - starts[j.x] }

        // What's left over once the joins are made comes off the ring, then the moment before bar 1; a little more
        // (up to a bar) can come off the end faded early, or the start; anything else isn't this plan.
        func settle(_ start: Double, _ startBar: Int?, _ js: [Join], _ base: Double, _ notes: [String]) -> Candidate? {
            var left = m.seconds - start - js.reduce(0) { $0 + shift($1) } - length
            guard left >= -1e-9 else { return nil }
            var tail = min(left, tailRoom); left -= tail
            var begin = start, warnings = notes, cost = base + js.reduce(0) { max($0, $1.cost) } + Double(js.count) * 0.02
            if startBar == nil { let h = min(left, head); begin += h; left -= h }
            if left > 1e-9 {
                guard left <= barSeconds else { return nil }
                tail += left; left = 0; cost += 0.15
                warnings.append("\(song) ends faded \(String(format: "%.1f", tail)) s before its own end.")
            }
            return Candidate(start: begin, startBar: startBar, joins: js, tail: tail, cost: cost, warnings: warnings)
        }

        var best: Candidate?
        func consider(_ c: Candidate?) { if let c, c.cost < (best?.cost ?? .infinity) { best = c } }
        let roomForShape = length >= starts[intro] - starts[0] + (m.seconds - starts[outro]) + 2 * barSeconds
        for shaped in roomForShape ? [true, false] : [false] {
            let usable = joins.filter { !shaped || keepsShape($0) }
            consider(settle(0, nil, [], 0, []))
            for j in usable { consider(settle(0, nil, [j], 0, [])) }
            // Two joins, from the hundred and fifty best, in order, with at least two bars between.
            let top = usable.sorted { $0.cost < $1.cost }.prefix(150)
            for a in top { for b in top where b.x >= a.y + 2 { consider(settle(0, nil, [a, b], 0.02, [])) } }
            if best != nil { break }
        }
        if best == nil || best!.cost > poor || best!.joins.contains(where: { abs($0.y - $0.x) % 4 != 0 }) {
            // Starting on a later bar, skipping the intro: best where the song moves on or a phrase starts, and only as
            // a last resort when the song is made longer, since there's room for its start then.
            for s in 1..<n {
                let note = "\(song) starts at bar \(s + 1), leaving out what comes before."
                let base = 0.1 + (changes.contains(s) ? 0 : s % 4 == 0 ? 0.03 : 0.08) + (length > m.seconds ? 0.3 : 0)
                consider(settle(starts[s], s, [], base, [note]))
                for j in joins where j.x > s && j.y > s { consider(settle(starts[s], s, [j], base, [note])) }
            }
        }
        guard var c = best else {
            let most = m.seconds * 2
            throw DirectionError("bad_argument", length > m.seconds ? "\(song) can be fitted to about \(Int(most)) s at most with two joins; place it twice for longer." : "\(song) can\u{2019}t be fitted to \(String(format: "%.1f", length)) s by its bars.")
        }
        // A join that had to be made between bars that aren't alike, or out of step with the phrases, is said, with
        // lengths near this one that join cleanly: no join, or one between alike bars, with what's left over off the
        // ring or before bar 1.
        let weak = c.joins.filter { $0.cost > poor || abs($0.y - $0.x) % 4 != 0 }
        if !weak.isEmpty {
            let slack = head + tailRoom
            let spans = [(m.seconds - slack, m.seconds)] + joins.filter { $0.cost < 0.15 }.map { j in (m.seconds - shift(j) - slack, m.seconds - shift(j)) }
            let below = spans.filter { $0.1 < length - 0.05 }.map(\.1).max(), above = spans.filter { $0.0 > length + 0.05 }.map(\.0).min()
            let near = [below, above].compactMap { $0 }.map { String(format: "%.1f s", $0) }
            c.warnings.append("The join from bar \(weak.map { "\($0.x) into bar \($0.y + 1)" }.joined(separator: " and from bar ")) isn\u{2019}t between alike bars; listen to it\(near.isEmpty ? "" : ", or fit to " + near.joined(separator: " or ") + ", which join cleanly").")
        }
        // The pieces, each ending and the next starting just before a downbeat.
        var pieces: [SecondsRange] = [], from = c.start, first = (c.startBar ?? 0) + 1, words: [String] = [], said: [String] = []
        for j in c.joins {
            pieces.append(.init(start: from, end: starts[j.x] - early)); said.append("bars \(first)\u{2013}\(j.x)")
            words.append("bar \(j.x) into bar \(j.y + 1) (\(Int((100 * max(0, 1 - j.cost)).rounded()))% alike)")
            from = starts[j.y] - early; first = j.y + 1
        }
        pieces.append(.init(start: from, end: m.seconds - c.tail))
        said.append(c.tail > 0 ? "bars \(first)\u{2013}\(n) to its end, faded" : "bars \(first)\u{2013}\(n) to its end")
        let fadeOut = c.tail > 1e-6 ? min(1.0, max(0.3, m.seconds - c.tail - max(m.lastHit, starts[n - 1]))) : nil
        let fadeIn = c.start > 0.005 && c.startBar == nil ? 0.01 : nil
        return MusicPlan(pieces: pieces, crossfade: crossfade, fadeIn: fadeIn, fadeOut: fadeOut, said: said.joined(separator: ", then "), joins: words, warnings: c.warnings)
    }
}
