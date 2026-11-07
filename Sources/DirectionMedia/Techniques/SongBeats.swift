import Foundation
import Accelerate
import CryptoKit
import DirectionCore

/// Where a song's beats and bars fall and where it moves on (library.md › Beats and bars), heard once when it's
/// measured. The beat is followed by dynamic programming over how much new sound starts in each moment (Ellis's
/// beat tracker): the best chain of beats that land on onsets and keep close to the song's tempo, at the tempo whose
/// beats and halves meet the most of what's played. Music made to a click (most library music) then gets the one
/// steady pace its hits lie on, so a sparse stretch can't knock a beat off it. The bars start on the beats where the
/// harmony changes and the low end hits, and where the song moves on; the song moves on where the bars either side of
/// a moment sound most unlike each other (Foote's novelty). A song kept in parts is heard once for all of them: its
/// beats where the drums are clearest, its bars and changes in the whole mix. No steady beat (ambient, a tempo that
/// changes) is said, not guessed.
public enum SongBeats {
    /// What listening found: a grid; or that there's no steady beat to cut on (`steady` false); or, for a sound too
    /// short to tell, neither.
    public struct Heard: Codable, Sendable, Equatable {
        public var grid: BeatGrid?
        public var steady: Bool?
        public init(grid: BeatGrid?, steady: Bool?) { self.grid = grid; self.steady = steady }
    }

    static let rate = MusicListening.rate, onsetRate = MusicListening.onsetRate
    /// Seconds from the start of the onset frame a hit peaks in to the hit itself: a hit is heard most as it enters
    /// the frame, three quarters of the way along it (measured on clicks and drum hits).
    static let onsetDelay = 448 / MusicListening.rate
    /// The shortest sound with a beat worth keeping.
    static let shortest = 8.0
    /// How closely the beats keep to the tempo (Ellis's tightness).
    static let tightness = 100.0
    /// The local tempo (eight beats at a time) may drift this far either way before the beat isn't steady.
    static let drift = 0.08

    // MARK: Hearing

    /// One sound on its own.
    public static func hear(_ url: URL) throws -> Heard { hear(samples: try MusicListening.samples(url)) }

    /// A song in parts: the beat where the drums are clearest, the bars and changes in the whole mix (its full mix,
    /// or every part played together).
    public static func hear(mix: URL?, parts: [URL], drums: URL?) throws -> Heard {
        var whole: [Float] = []
        if let mix { whole = try MusicListening.samples(mix) } else {
            for p in parts {
                let x = try MusicListening.samples(p)
                if whole.isEmpty { whole = x } else { let n = min(whole.count, x.count); whole = vDSP.add(whole[0..<n], x[0..<n]) }
            }
        }
        var heard = hear(samples: whole, beatsFrom: try drums.map { try MusicListening.samples($0) })
        if drums != nil { heard.grid?.heardOn = "Drums" }
        return heard
    }

    /// The grid of some samples at `rate`; with a drums part, its hits lead the beat.
    static func hear(samples: [Float], beatsFrom drums: [Float]? = nil) -> Heard {
        guard Double(samples.count) / rate >= shortest else { return Heard(grid: nil, steady: nil) }
        let f = MusicListening.features(samples: samples)
        var onsets = unit(f.onsets)
        if let drums {
            let d = unit(MusicListening.features(samples: drums).onsets)
            onsets = (0..<min(onsets.count, d.count)).map { d[$0] + 0.5 * onsets[$0] }
        }
        // Each stretch's tempo is checked against the one heard in the whole song, which has the same doubts about
        // threes and twos the stretches have, and the one followed.
        guard let (frames, heardTempo) = follow(onsets, heard: unit(f.onsets)), steadyTempo(onsets, [heardTempo, onsetRate * 60 / pace(frames)]), onTheBeat(onsets, frames) else { return Heard(grid: nil, steady: false) }
        let followed = frames.map { (refine(onsets, at: $0) * Double(MusicListening.onsetHop) / rate + onsetDelay) }
        // Music made to a click keeps one pace from start to end: where most beats lie on one, it's the grid, and a
        // beat followed a little early or late, or lost in a sparse stretch, is put back on it. Music played without
        // a click keeps the beats as followed, if they keep close to their tempo.
        let beats = clicked(onsets, followed: followed, pace: pace(frames) * Double(MusicListening.onsetHop) / rate) ?? followed
        guard steadyBeats(beats) else { return Heard(grid: nil, steady: false) }
        let per = perBeat(samples, beats: beats)
        let (count, phase) = meter(per)
        let bars = Array(stride(from: phase, to: beats.count, by: count))
        let changes = moves(barFeatures(per, bars: bars, beats: beats.count))
        return Heard(grid: BeatGrid(beats: beats.map { ($0 * 1000).rounded() / 1000 }, bars: bars, beatsPerBar: count, changes: changes), steady: true)
    }

    /// Onsets over their spread, so a quiet song and a loud one are followed alike.
    static func unit(_ x: [Float]) -> [Float] {
        guard x.count > 1 else { return x }
        var mean: Float = 0, sd: Float = 0
        vDSP_normalize(x, 1, nil, 1, &mean, &sd, vDSP_Length(x.count))
        return sd > 0 ? vDSP.divide(x, sd) : x
    }

    // MARK: Steady

    /// How much of what's played lands on the beats and halfway between them, against how much would by chance: what
    /// starts within two frames of them, over the share of the song's frames that are.
    static func explained(_ onsets: [Float], _ frames: [Int]) -> Double {
        guard frames.count >= 8, let lo = frames.first, let hi = frames.last, hi > lo else { return 0 }
        var near = [Bool](repeating: false, count: onsets.count)
        for (a, b) in zip(frames, frames.dropFirst()) { for g in [a, (a + b) / 2] { for k in max(0, g - 2)...min(onsets.count - 1, g + 2) { near[k] = true } } }
        let span = onsets[lo...hi], median = span.sorted()[span.count / 2]
        var on: Double = 0, all: Double = 0, marked = 0
        for i in lo...hi { let v = Double(max(0, onsets[i] - median)); all += v; if near[i] { on += v; marked += 1 } }
        guard all > 0, marked > 0 else { return 0 }
        return (on / all) / (Double(marked) / Double(hi - lo + 1))
    }

    /// The tempo heard in each sixteen seconds agrees with one of the song's in three in four of the stretches with a
    /// beat, give or take an octave, or half again (a groove heard in threes there): a song whose tempo changes has
    /// no one beat to cut on.
    static func steadyTempo(_ onsets: [Float], _ tempos: [Double]) -> Bool {
        let window = Int(16 * onsetRate), step = Int(8 * onsetRate)
        guard onsets.count >= window + step else { return true }
        var heard = 0, off = 0
        for a in stride(from: 0, through: onsets.count - window, by: step) {
            guard let t = MusicListening.tempo(onsets[a..<(a + window)]) else { continue }
            heard += 1
            if !tempos.contains(where: { tempo in [1.0, 2, 0.5, 1.5, 2.0 / 3].contains { abs(log(t / tempo / $0)) < log(1.04) } }) { off += 1 }
        }
        return heard < 3 || Double(off) / Double(heard) < 0.25
    }

    /// The beats keep landing on what's played: in every sixteen seconds with much played, they and the halves between
    /// them meet at least 60% as much of it as they do where they meet it best (the best quarter of the song). Beats
    /// held at one pace through a change of tempo drift off it.
    static func onTheBeat(_ onsets: [Float], _ frames: [Int]) -> Bool {
        let window = Int(16 * onsetRate), step = Int(8 * onsetRate)
        guard let first = frames.first, let last = frames.last, last - first >= window + step else { return true }
        var stretches: [(energy: Float, fit: Double)] = []
        for a in stride(from: first, through: last - window, by: step) {
            let inside = frames.filter { $0 >= a && $0 < a + window }
            stretches.append((onsets[a..<(a + window)].reduce(0, +), explained(onsets, inside)))
        }
        let usual = stretches.map(\.energy).sorted()[stretches.count / 2], fits = stretches.map(\.fit).sorted(), best = fits[fits.count * 3 / 4]
        return stretches.allSatisfy { $0.energy < 0.5 * usual || $0.fit >= 0.6 * best }
    }

    /// The one pace a song made to a click keeps, as every beat from the first followed to the last on it, when six in
    /// ten of its strongest hits (the loudest quarter) lie within 25 ms of the sixteenths of it, and half in each third
    /// of the song (a band that drifts is off it somewhere). The pace is the one near what was followed (`pace` seconds
    /// a beat) at which what's played piles up most at one place in the beat; the beat is the sixteenth of it with the
    /// most played on it; then both are fitted to the hits on the beats.
    static func clicked(_ onsets: [Float], followed: [Double], pace: Double) -> [Double]? {
        guard let from = followed.first, let to = followed.last else { return nil }
        let n = onsets.count, median = onsets.sorted()[n / 2], hop = Double(MusicListening.onsetHop)
        var peaks: [(t: Double, w: Double)] = []
        for i in 1..<max(1, n - 1) where onsets[i] > median && onsets[i] >= onsets[i - 1] && onsets[i] > onsets[i + 1] {
            peaks.append((refine(onsets, at: i) * hop / rate + onsetDelay, Double(onsets[i] - median)))
        }
        guard peaks.count >= 32, pace > 0 else { return nil }
        let bins = 64
        func folded(_ p: Double) -> [Double] {
            var h = [Double](repeating: 0, count: bins)
            for x in peaks { let ph = (x.t / p).truncatingRemainder(dividingBy: 1); h[min(bins - 1, Int(ph * Double(bins)))] += x.w }
            return (0..<bins).map { b in 0.5 * h[(b + bins - 1) % bins] + h[b] + 0.5 * h[(b + 1) % bins] }
        }
        var best = (p: pace, score: 0.0)
        for k in -500...500 {
            let p = pace * (1 + Double(k) * 2e-5)
            if let top = folded(p).max(), top > best.score { best = (p, top) }
        }
        var p = best.p
        let h = folded(p), top = h.indices.max { h[$0] < h[$1] }!
        // The beat: of the four sixteenths, the one with the most played on it and on the eighth after it. (On a song
        // made at 80 to a click from 0:00, its sections then start on round bars: 2:00.0, not half a beat after.)
        let quarter = (0..<4).map { (top + $0 * bins / 4) % bins }.max { a, b in h[a] + 0.5 * h[(a + bins / 2) % bins] < h[b] + 0.5 * h[(b + bins / 2) % bins] }!
        var t0 = (Double(quarter) + 0.5) / Double(bins) * p
        for _ in 0..<3 {
            let on = peaks.compactMap { x -> (k: Double, t: Double, w: Double)? in let k = ((x.t - t0) / p).rounded(); return abs(x.t - t0 - k * p) < 0.025 ? (k, x.t, x.w) : nil }
            let w = on.reduce(0) { $0 + $1.w }
            guard on.count >= 8, w > 0 else { return nil }
            let mk = on.reduce(0) { $0 + $1.w * $1.k } / w, mt = on.reduce(0) { $0 + $1.w * $1.t } / w
            let sxx = on.reduce(0) { $0 + $1.w * ($1.k - mk) * ($1.k - mk) }
            guard sxx > 0 else { return nil }
            p = on.reduce(0) { $0 + $1.w * ($1.k - mk) * ($1.t - mt) } / sxx; t0 = mt - p * mk
        }
        let strongest = peaks.sorted { $0.w > $1.w }.prefix(max(16, peaks.count / 4))
        func onGrid(_ x: (t: Double, w: Double)) -> Bool { let q = p / 4; return abs(x.t - t0 - ((x.t - t0) / q).rounded() * q) < 0.025 }
        guard Double(strongest.filter(onGrid).count) >= 0.6 * Double(strongest.count) else { return nil }
        for third in 0..<3 {
            let a = from + (to - from) * Double(third) / 3, b = from + (to - from) * Double(third + 1) / 3
            let inside = strongest.filter { $0.t >= a && $0.t < b }
            guard inside.count < 8 || Double(inside.filter(onGrid).count) >= 0.5 * Double(inside.count) else { return nil }
        }
        let first = ((from - t0) / p - 0.75).rounded(.up), last = ((to - t0) / p + 0.75).rounded(.down)
        guard last > first else { return nil }
        return stride(from: first, through: last, by: 1).map { t0 + $0 * p }.filter { $0 >= 0 }
    }

    /// Eight beats at a time keep within `drift` of the song's tempo.
    static func steadyBeats(_ beats: [Double]) -> Bool {
        let gaps = zip(beats, beats.dropFirst()).map { $1 - $0 }
        guard gaps.count >= 16 else { return true }
        let middle = gaps.sorted()[gaps.count / 2]
        var local: [Double] = []
        for a in stride(from: 0, through: gaps.count - 8, by: 4) { let g = gaps[a..<(a + 8)].sorted(); local.append((g[3] + g[4]) / 2) }
        return local.allSatisfy { abs($0 / middle - 1) <= drift }
    }

    // MARK: Following the beat

    /// The beats (frame numbers) and their tempo. A groove of threes against twos (kicks 3 + 3 + 2 sixteenths apart)
    /// repeats well every three sixteenths, so the tempo can be heard a half or a third off: the beat is the one, in
    /// about the octave heard, whose beats and the halves between them land on the most of what's played, followed
    /// again at the pace it settled on.
    static func follow(_ onsets: [Float], heard: [Float]) -> (frames: [Int], heardTempo: Double)? {
        guard let heardTempo = MusicListening.tempo(onsets[...]) else { return nil }
        var frames = track(onsets, period: onsetRate * 60 / heardTempo, heard: heard), fit = explained(onsets, frames), period = onsetRate * 60 / heardTempo
        for ratio in [1.5, 2.0 / 3, 0.75, 4.0 / 3] {
            var other = heardTempo * ratio
            while other / heardTempo > 1.42 { other /= 2 }
            while heardTempo / other > 1.42 { other *= 2 }
            guard (50...200).contains(other) else { continue }
            let f = track(onsets, period: onsetRate * 60 / other, heard: heard), e = explained(onsets, f)
            if e > fit * 1.1 { frames = f; fit = e; period = onsetRate * 60 / other }
        }
        guard frames.count >= 8 else { return nil }
        let settled = pace(frames)
        if abs(settled / period - 1) > 0.03 { frames = track(onsets, period: settled, heard: heard) }
        guard frames.count >= 8 else { return nil }
        return (frames, heardTempo)
    }

    /// Frames a beat, on average, over the beats within a tenth of the usual gap.
    static func pace(_ frames: [Int]) -> Double {
        guard frames.count >= 2 else { return 1 }
        let gaps = zip(frames, frames.dropFirst()).map { Double($1 - $0) }, middle = gaps.sorted()[gaps.count / 2]
        let usual = gaps.filter { abs($0 / middle - 1) <= 0.1 }
        return usual.reduce(0, +) / Double(max(1, usual.count))
    }

    /// The best chain of beats through the onsets (frame numbers): each lands on an onset and follows the one
    /// before by about `period` frames (Ellis 2007, as librosa has it). Beats at either end with next to nothing
    /// `heard` on them (a fade, the silence before the song) are left off; a quiet intro keeps its beats.
    static func track(_ onsets: [Float], period: Double, heard: [Float]) -> [Int] {
        let n = onsets.count
        // Onsets spread over a few frames either side, so the chain can land between frames.
        let w = Int(period.rounded())
        let kernel = (-w...w).map { k in Float(exp(-0.5 * pow(Double(k) * 32 / period, 2))) }
        var local = [Float](repeating: 0, count: n)
        for i in 0..<n { var s: Float = 0; for (j, k) in kernel.enumerated() { let x = i + j - w; if x >= 0 && x < n { s += k * onsets[x] } }; local[i] = s }
        let lo = Int((period / 2).rounded()), hi = Int((2 * period).rounded())
        let cost = (0...hi).map { d in d < lo ? -Double.infinity : -tightness * pow(log(Double(d) / period), 2) }
        var score = [Double](repeating: 0, count: n), back = [Int](repeating: -1, count: n)
        for i in 0..<n {
            var best = -Double.infinity, from = -1
            for d in lo...hi where i - d >= 0 { let s = score[i - d] + cost[d]; if s > best { best = s; from = i - d } }
            // A chain starts afresh where nothing before leads to it in time: the first beat of the song is on its
            // own onset, not pulled toward the silence before it.
            if from >= 0 && best > 0 { score[i] = Double(local[i]) + best; back[i] = from } else { score[i] = Double(local[i]) }
        }
        // The last beat: the last top of the score that's at least half the usual top.
        var tops: [Int] = []
        for i in 1..<max(1, n - 1) where score[i] > score[i - 1] && score[i] >= score[i + 1] { tops.append(i) }
        guard !tops.isEmpty else { return [] }
        let usual = tops.map { score[$0] }.sorted()[tops.count / 2]
        var i = tops.last { score[$0] >= 0.5 * usual } ?? tops.last!
        var beats: [Int] = []
        while i >= 0 { beats.append(i); i = back[i] }
        beats.reverse()
        // Beats at either end with nothing there (the silence before the song, a chord ringing out, a fade) aren't
        // the song's. A beat is there when something starts on it that stands out from the second around it, and
        // from silence; a quiet intro's beats are kept.
        guard !beats.isEmpty else { return [] }
        let hit = beats.map { b in (max(0, b - 2)...min(heard.count - 1, b + 2)).map { heard[$0] }.max() ?? 0 }
        let typical = hit.sorted()[hit.count / 2], second = Int(onsetRate / 2)
        func there(_ k: Int) -> Bool {
            let around = heard[max(0, beats[k] - second)...min(heard.count - 1, beats[k] + second)].sorted()
            return hit[k] >= 0.15 * typical && hit[k] >= 2 * around[around.count / 2]
        }
        guard let a = beats.indices.first(where: there), let b = beats.indices.last(where: there), a <= b else { return [] }
        return Array(beats[a...b])
    }

    /// A beat's frame, moved onto the onset it lands on (within two frames), between frames.
    static func refine(_ onsets: [Float], at i: Int) -> Double {
        let lo = max(1, i - 2), hi = min(onsets.count - 2, i + 2)
        guard lo <= hi, let top = (lo...hi).max(by: { onsets[$0] < onsets[$1] }), onsets[top] > 0.5 else { return Double(i) }
        let (a, b, c) = (onsets[top - 1], onsets[top], onsets[top + 1])
        let d = a - 2 * b + c
        return Double(top) + (d == 0 ? 0 : Double(max(-0.5, min(0.5, 0.5 * (a - c) / d))))
    }

    // MARK: What each beat sounds like

    /// What one beat sounds like: its notes (12, C first), timbre (the shape of its spectrum), low end and level over
    /// the beat; and how loud it hits (dB over its first 70 ms) and how much low end hits with it (a kick).
    struct Beat { var notes: [Float]; var timbre: [Float]; var low: Float; var level: Float; var hit: Float; var lowHit: Float = 0 }

    /// A sixth of a second a frame, so a fast beat holds two or three that don't reach into the next.
    static let frameSize = 2048, frameHop = 512
    /// Spectrum bands for timbre: 24 from 60 Hz to 6 kHz.
    static let bandEdges: [Double] = (0...24).map { 60 * pow(100, Double($0) / 24) }

    /// Each beat's sound, from the frames that lie within it, so the next beat's hit isn't heard in this one.
    static func perBeat(_ samples: [Float], beats: [Double]) -> [Beat] {
        let spectrum = MusicListening.Spectrum(size: frameSize)
        let bin = rate / Double(frameSize)
        let pitch: [(bin: Int, pc: Int, weight: Float)] = (1..<(frameSize / 2)).compactMap { k in
            let f = Double(k) * bin
            guard f >= MusicListening.lowestNote, f <= MusicListening.highestNote else { return nil }
            let p = 69 + 12 * log2(f / 440), nearest = p.rounded(), w = cos(Double.pi * (p - nearest))
            return (k, (Int(nearest) % 12 + 12) % 12, Float(w * w))
        }
        let band: [Int?] = (0..<(frameSize / 2)).map { k in let f = Double(k) * bin; return f < 60 || f >= 6_000 ? nil : bandEdges.lastIndex { $0 <= f } }
        let lowBins = (1..<(frameSize / 2)).filter { Double($0) * bin >= 40 && Double($0) * bin < 150 }
        var frames: [(t: Double, notes: [Float], bands: [Float], low: Float, level: Float)] = []
        samples.withUnsafeBufferPointer { p in
            var at = 0
            while at + frameSize <= samples.count {
                let m = spectrum.magnitudes(p, from: at)
                var notes = [Float](repeating: 0, count: 12), bands = [Float](repeating: 0, count: 24)
                for x in pitch { notes[x.pc] += x.weight * m[x.bin] }
                for (k, v) in m.enumerated() { if let b = band[k] { bands[b] += v * v } }
                let low = lowBins.reduce(Float(0)) { $0 + m[$1] * m[$1] }
                var rms: Float = 0
                vDSP_rmsqv(p.baseAddress! + at, 1, &rms, vDSP_Length(frameSize))
                frames.append((Double(at + frameSize / 2) / rate, notes, bands.map { log10f($0 + 1e-6) }, log10f(low + 1e-6), 20 * log10f(rms + 1e-7)))
                at += frameHop
            }
        }
        let ends = beats.dropFirst() + [beats.last! + (beats.count > 1 ? beats.last! - beats[beats.count - 2] : 0.5)]
        let half = Double(frameSize / 2) / rate, slack = 0.01
        var k = 0
        return zip(beats, ends).map { a, b in
            while k < frames.count && frames[k].t - half < a - slack { k += 1 }
            var j = k, notes = [Float](repeating: 0, count: 12), bands = [Float](repeating: 0, count: 24), low: Float = 0, level: Float = 0, n: Float = 0
            while j < frames.count && frames[j].t + half <= b + slack { notes = vDSP.add(notes, frames[j].notes); bands = vDSP.add(bands, frames[j].bands); low += frames[j].low; level += frames[j].level; n += 1; j += 1 }
            if n == 0, let near = frames.indices.min(by: { abs(frames[$0].t - a) < abs(frames[$1].t - a) }) { notes = frames[near].notes; bands = frames[near].bands; low = frames[near].low; level = frames[near].level; n = 1 }
            // The hit: the level of its first 70 ms, and the low end in a frame about it.
            let s0 = max(0, Int(a * rate)), s1 = min(samples.count, s0 + Int(0.07 * rate))
            var rms: Float = 0
            if s1 > s0 { samples.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + s0, 1, &rms, vDSP_Length(s1 - s0)) } }
            var lowHit: Float = -6
            let f0 = Int((a + 0.04) * rate) - frameSize / 2
            if f0 >= 0, f0 + frameSize <= samples.count {
                let m = samples.withUnsafeBufferPointer { spectrum.magnitudes($0, from: f0) }
                lowHit = log10f(lowBins.reduce(Float(0)) { $0 + m[$1] * m[$1] } + 1e-6)
            }
            return Beat(notes: n > 0 ? vDSP.divide(notes, n) : notes, timbre: dct(n > 0 ? vDSP.divide(bands, n) : bands), low: n > 0 ? low / n : 0, level: n > 0 ? level / n : -140, hit: 20 * log10f(rms + 1e-7), lowHit: lowHit)
        }
    }

    /// The shape of a spectrum: the first twelve cosine coefficients of its log bands after the overall level.
    static func dct(_ x: [Float]) -> [Float] {
        let n = Float(x.count)
        return (1...12).map { k in x.enumerated().reduce(Float(0)) { $0 + $1.element * cos(Float.pi * Float(k) * (Float($1.offset) + 0.5) / n) } }
    }

    // MARK: Bars

    /// Beats in a bar and which beat starts the first: the beats where the harmony changes, the low end hits and the
    /// song moves on come round every 4 (or 3) beats. Four unless three is clearly heard; the first beat when
    /// nothing tells them apart.
    static func meter(_ per: [Beat]) -> (count: Int, phase: Int) {
        guard per.count >= 8 else { return (4, 0) }
        func z(_ x: [Float]) -> [Float] {
            var mean: Float = 0, sd: Float = 0, out = [Float](repeating: 0, count: x.count)
            vDSP_normalize(x, 1, &out, 1, &mean, &sd, vDSP_Length(x.count))
            return sd > 1e-6 ? out : [Float](repeating: 0, count: x.count)
        }
        let change = per.indices.map { i in i == 0 ? 0 : 1 - cosine(per[i - 1].notes, per[i].notes) }
        let accent = vDSP.add(vDSP.add(z(change), vDSP.multiply(0.6, z(per.map(\.lowHit)))), vDSP.multiply(0.6, z(per.map(\.hit))))
        // Where the song moves on, beat by beat: a downbeat almost always.
        let novelty = foote(per.map { feature($0) }, half: 8)
        let n = Float(novelty.count), mean = novelty.reduce(0, +) / n, sd = (novelty.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n).squareRoot()
        var sections = [Float](repeating: 0, count: per.count)
        for i in novelty.indices where sd > 0 && novelty[i] > mean + 2.5 * sd && i > 0 && i < novelty.count - 1 && novelty[i] >= novelty[i - 1] && novelty[i] >= novelty[i + 1] { sections[i] = 1 }
        let evidence = vDSP.add(accent, sections)
        func scores(_ count: Int) -> [Float] { (0..<count).map { k in let xs = stride(from: k, to: evidence.count, by: count).map { evidence[$0] }; return xs.reduce(0, +) / Float(max(1, xs.count)) } }
        func lead(_ s: [Float]) -> (phase: Int, by: Float) {
            let best = s.indices.max { s[$0] < s[$1] }!
            let rest = s.enumerated().filter { $0.offset != best }.map(\.element)
            return (best, s[best] - rest.reduce(0, +) / Float(rest.count))
        }
        let four = lead(scores(4)), three = lead(scores(3))
        if three.by > 1.3 * four.by && three.by > 0.5 { return (3, three.phase) }
        return four.by > 0.15 ? (4, four.phase) : (4, 0)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let d = (vDSP.dot(a, a) * vDSP.dot(b, b)).squareRoot()
        return d > 0 ? vDSP.dot(a, b) / d : 1
    }

    /// One beat or bar as a point to compare: its notes, its timbre and its level, each about as loud as the others.
    static func feature(_ b: Beat) -> [Float] {
        let notes = b.notes, nn = vDSP.dot(notes, notes).squareRoot()
        let t = b.timbre, tn = vDSP.dot(t, t).squareRoot()
        return (nn > 0 ? vDSP.divide(notes, nn) : notes) + (tn > 0 ? vDSP.divide(t, tn) : t) + [b.level / 20]
    }

    /// Each bar's sound: the beats in it put together.
    static func barFeatures(_ per: [Beat], bars: [Int], beats: Int) -> [[Float]] {
        bars.enumerated().map { k, start in
            let end = k + 1 < bars.count ? bars[k + 1] : min(beats, start + (bars.count > 1 ? bars[1] - bars[0] : 4))
            var notes = [Float](repeating: 0, count: 12), timbre = [Float](repeating: 0, count: 12), level: Float = 0, low: Float = 0
            for i in start..<max(start + 1, end) where i < per.count { notes = vDSP.add(notes, per[i].notes); timbre = vDSP.add(timbre, per[i].timbre); level += per[i].level; low += per[i].low }
            let n = Float(max(1, min(end, per.count) - start))
            return feature(Beat(notes: notes, timbre: vDSP.divide(timbre, n), low: low / n, level: level / n, hit: 0))
        }
    }

    /// How new each point is against the ones around it (Foote's checkerboard over how alike each pair is),
    /// `half` points either side.
    static func foote(_ x: [[Float]], half: Int) -> [Float] {
        let n = x.count
        guard n > 2 * half else { return [Float](repeating: 0, count: n) }
        let unit = x.map { v -> [Float] in let d = vDSP.dot(v, v).squareRoot(); return d > 0 ? vDSP.divide(v, d) : v }
        var out = [Float](repeating: 0, count: n)
        for i in half..<(n - half + 1) {
            var s: Float = 0
            for a in (i - half)..<(i + half) {
                for b in (i - half)..<(i + half) {
                    let g = Float(exp(-0.5 * pow((Double(a - i) + 0.5) / Double(half), 2) - 0.5 * pow((Double(b - i) + 0.5) / Double(half), 2)))
                    let sign: Float = (a < i) == (b < i) ? 1 : -1
                    s += sign * g * vDSP.dot(unit[a], unit[b])
                }
            }
            out[i] = s
        }
        return out
    }

    /// The bars where the song moves on (bar numbers, from 2): tops of the novelty over four bars either side that
    /// stand out from the song's usual and are a real change (the bars either side 2% less alike across than within,
    /// at least), at least four bars apart, the strongest kept first.
    static func moves(_ bars: [[Float]]) -> [Int] {
        let half = 4
        guard bars.count >= 12 else { return [] }
        let novelty = foote(bars, half: half)
        let inner = Array(novelty[half..<(novelty.count - half + 1)]), n = Float(inner.count)
        let mean = inner.reduce(0, +) / n, sd = (inner.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n).squareRoot()
        guard sd > 0 else { return [] }
        // The kernel's whole weight: novelty is about half of it times how much less alike the two sides are.
        let weight = (0..<(2 * half)).reduce(Float(0)) { s, a in s + (0..<(2 * half)).reduce(Float(0)) { t, b in t + Float(exp(-0.5 * pow((Double(a - half) + 0.5) / Double(half), 2) - 0.5 * pow((Double(b - half) + 0.5) / Double(half), 2))) } }
        let floor = 0.02 * weight / 2
        let tops = (half..<(novelty.count - half + 1)).filter { i in novelty[i] > max(floor, mean + 0.5 * sd) && (max(half, i - 3)...min(novelty.count - half, i + 3)).allSatisfy { novelty[$0] <= novelty[i] } }
        var kept: [Int] = []
        for i in tops.sorted(by: { novelty[$0] > novelty[$1] }) where kept.allSatisfy({ abs($0 - i) >= 4 }) { kept.append(i) }
        return kept.sorted().map { $0 + 1 }
    }

    // MARK: Songs, kept

    /// What listening keeps between runs, so a song is heard once.
    static let cacheVersion = 1

    /// The grid of a sound, or of a song in parts (each file with the part it is): heard once for all its parts, its
    /// beat where the drums are clearest. Kept in the cache by the files it was heard from.
    public static func heard(_ files: [(url: URL, part: String?)], cacheDirectory: URL) async throws -> Heard {
        guard !files.isEmpty else { return Heard(grid: nil, steady: nil) }
        var key = "v\(cacheVersion).\(ShelfItem.Measured.currentVersion)"
        for f in files.sorted(by: { $0.url.path < $1.url.path }) {
            let v = try? f.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            key += "|\(f.url.path)|\(f.part ?? "")|\(v?.fileSize ?? 0)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        let file = cacheDirectory.appendingPathComponent("Beats", isDirectory: true).appendingPathComponent("\(name).json")
        if let data = try? Data(contentsOf: file), let h = try? JSONDecoder().decode(Heard.self, from: data) { return h }
        let h: Heard = try await Task.detached(priority: .userInitiated) {
            guard files.count > 1 else { return try hear(files[0].url) }
            let drums = files.first { $0.part == "Drums" }?.url, mix = files.first { $0.part == Stems.fullMix }?.url
            var h = try hear(mix: mix, parts: files.map(\.url), drums: drums)
            if drums == nil { h.grid?.heardOn = mix != nil ? Stems.fullMix : "every part" }
            return h
        }.value
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(h).write(to: file, options: .atomic)
        return h
    }

    /// The grid of a sound in a film: a song in parts is heard once for all the film's copies of its parts.
    public static func heard(_ asset: MediaAsset, in project: Project, cacheDirectory: URL) async throws -> Heard {
        try await heard(parts(asset, in: project).map { (URL(fileURLWithPath: $0.path), $0.part) }, cacheDirectory: cacheDirectory)
    }

    /// A sound's parts in a film: a song in parts's every part, or the sound itself.
    static func parts(_ asset: MediaAsset, in project: Project) -> [MediaAsset] {
        (asset.song ?? "").isEmpty ? [asset] : project.assets.filter { $0.song == asset.song && !$0.audio.isEmpty }
    }

    /// What fitting a song needs (MusicFitting): its grid, length, and each bar's sound and level, heard in the whole
    /// mix (a song in parts's full mix, or every part together).
    public static func material(_ asset: MediaAsset, in project: Project, grid: BeatGrid) async throws -> MusicMaterial {
        let parts = parts(asset, in: project)
        let seconds = parts.map(\.duration.seconds).min() ?? asset.duration.seconds
        return try await Task.detached(priority: .userInitiated) {
            var whole: [Float] = []
            if let mix = parts.first(where: { $0.part == Stems.fullMix }) ?? (parts.count == 1 ? parts.first : nil) { whole = try MusicListening.samples(URL(fileURLWithPath: mix.path)) }
            else {
                for p in parts {
                    let x = try MusicListening.samples(URL(fileURLWithPath: p.path))
                    if whole.isEmpty { whole = x } else { let n = min(whole.count, x.count); whole = vDSP.add(whole[0..<n], x[0..<n]) }
                }
            }
            guard !whole.isEmpty, !grid.beats.isEmpty else { throw DirectionError("no_beat", "\(asset.song ?? asset.name) can\u{2019}t be heard.") }
            let per = perBeat(whole, beats: grid.beats)
            let bars = barFeatures(per, bars: grid.bars, beats: grid.beats.count)
            let levels = grid.bars.enumerated().map { k, start -> Float in
                let end = k + 1 < grid.bars.count ? grid.bars[k + 1] : min(per.count, start + grid.beatsPerBar)
                let xs = per[start..<max(start + 1, min(end, per.count))].map(\.level)
                return xs.reduce(0, +) / Float(max(1, xs.count))
            }
            return MusicMaterial(grid: grid, seconds: seconds, bars: bars.map { $0.map { ($0 * 1000).rounded() / 1000 } }, levels: levels.map { ($0 * 10).rounded() / 10 }, lastHit: grid.beats.last ?? 0)
        }.value
    }
}
