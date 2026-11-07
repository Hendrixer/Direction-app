import Foundation

/// Where a song's beats fall (library.md › Beats and bars): each beat, which beats start a bar, and the bars where
/// the song moves on (the intro ends, a build, a drop). Heard once, when the song is measured, so the editor can cut
/// on the beat and say "bar 9" instead of guessing a time. Times are the song's own seconds, to the millisecond.
public struct BeatGrid: Codable, Hashable, Sendable {
    /// Every beat, in order.
    public var beats: [Double]
    /// The beats that start a bar, as indices into `beats`: bar 1 starts at `beats[bars[0]]`. Beats before it are a
    /// pickup into the first bar.
    public var bars: [Int]
    /// Beats in a bar: 4, or 3.
    public var beatsPerBar: Int
    /// The bars where the song moves on, by number (bar 1 is the first).
    public var changes: [Int]
    /// A song in parts keeps one grid for every part, heard on the part with the cleanest beat ("Drums"), or nil
    /// when the sound was heard on its own.
    public var heardOn: String?

    public init(beats: [Double], bars: [Int], beatsPerBar: Int, changes: [Int] = [], heardOn: String? = nil) {
        self.beats = beats; self.bars = bars; self.beatsPerBar = beatsPerBar; self.changes = changes; self.heardOn = heardOn
    }

    /// Beats a minute, from the middle beat length.
    public var tempo: Double {
        let gaps = zip(beats, beats.dropFirst()).map { $1 - $0 }.sorted()
        guard !gaps.isEmpty, gaps[gaps.count / 2] > 0 else { return 0 }
        return 60 / gaps[gaps.count / 2]
    }
    /// How long a bar lasts, from the middle beat length.
    public var barSeconds: Double { tempo > 0 ? 60 / tempo * Double(beatsPerBar) : 0 }
    public var barCount: Int { bars.count }
    /// Where each bar starts, bar 1 first.
    public var barStarts: [Double] { bars.map { beats[$0] } }

    /// Where bar `n` starts (1 is the first), or nil past the song's bars.
    public func barStart(_ n: Int) -> Double? { n >= 1 && n <= bars.count ? beats[bars[n - 1]] : nil }
    /// Where beat `n` falls (1 is the first beat heard, pickup included).
    public func beat(_ n: Int) -> Double? { n >= 1 && n <= beats.count ? beats[n - 1] : nil }
    /// The bar playing at a moment of the song: its number, or nil before the first.
    public func bar(at seconds: Double) -> Int? {
        let starts = barStarts
        guard let first = starts.first, seconds >= first - 1e-6 else { return nil }
        return (starts.lastIndex { $0 <= seconds + 1e-6 } ?? 0) + 1
    }

    /// The moment of the song a musical time names: {bar: 9}, {beat: 33}, either with `beats` more after it
    /// ({bar: 9, beat: 3} is the third beat of bar 9). Nil when it isn't one; throws when it's past the song.
    public func seconds(_ v: JSONValue, song: String) throws -> Double? {
        guard case .object(let o) = v, o["bar"] != nil || o["beat"] != nil else { return nil }
        func whole(_ k: String) throws -> Int? {
            guard let x = o[k], x != .null else { return nil }
            guard let n = x.double, n.rounded() == n, n >= 1, n < 1e6 else { throw DirectionError("bad_argument", "\(k) is a whole number from 1.") }
            return Int(n)
        }
        let bar = try whole("bar"), beat = try whole("beat")
        if let bar {
            guard let start = barStart(bar) else { throw DirectionError("bad_argument", "\(song) has \(bars.count) bars; there\u{2019}s no bar \(bar).") }
            guard let beat else { return start }
            guard beat <= beatsPerBar else { throw DirectionError("bad_argument", "A bar of \(song) has \(beatsPerBar) beats; beat \(beat) of a bar isn\u{2019}t one.") }
            let i = bars[bar - 1] + beat - 1
            guard i < beats.count else { throw DirectionError("bad_argument", "\(song) ends before beat \(beat) of bar \(bar).") }
            return beats[i]
        }
        guard let beat, let t = self.beat(beat) else { throw DirectionError("bad_argument", "\(song) has \(beats.count) beats; there\u{2019}s no beat \(beat ?? 0).") }
        return t
    }

    /// One sentence for the editor: "4 beats a bar, a bar every 2.24 s from 0.42 s (64 bars); it moves on at
    /// bar 9 (0:18.3), bar 17 (0:36.2)."
    public var line: String {
        var out = "\(beatsPerBar) beats a bar, a bar about every \(String(format: "%.2f", barSeconds)) s from \(String(format: "%.2f", barStarts.first ?? 0)) s (\(bars.count) bars)"
        if !changes.isEmpty { out += "; it moves on at " + changes.compactMap { n in barStart(n).map { "bar \(n) (\(Self.clock($0)))" } }.joined(separator: ", ") }
        return out + "."
    }
    /// 1:02.5
    public static func clock(_ t: Double) -> String { let r = (max(0, t) * 10).rounded() / 10; return String(format: "%d:%04.1f", Int(r) / 60, r.truncatingRemainder(dividingBy: 60)) }

    /// What the editor reads in direction_library: tempo, the bars' starts and the changes in full; every beat only
    /// when asked for.
    public func compact(beats every: Bool = false) -> JSONValue {
        func ms(_ t: Double) -> JSONValue { .number((t * 1000).rounded() / 1000) }
        var o: [String: JSONValue] = ["tempo": .number((tempo * 10).rounded() / 10), "beatsPerBar": .number(Double(beatsPerBar)),
                                      "firstBeat": beats.first.map(ms) ?? .null, "bars": .array(barStarts.map(ms)),
                                      "changes": .array(changes.compactMap { n in barStart(n).map { .object(["bar": .number(Double(n)), "at": ms($0)]) } })]
        if every { o["beats"] = .array(beats.map(ms)) }
        if let h = heardOn { o["heardOn"] = .string(h) }
        return .object(o)
    }
}
