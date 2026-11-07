import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
@testable import DirectionMedia

/// Where a song's beats and bars fall (library.md › Beats and bars), checked on music made here: clicks and a band
/// at a known tempo, in parts, with sections that change at known bars; a pad with no beat; a tempo that changes.
struct SongBeatsTests {
    static let rate = MusicListening.rate
    /// A beat is heard within this of where it is: under a frame at 30 a second.
    static let withinAFrame = 1.0 / 30

    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// A click on every beat from `start`, the first of every `accent` louder and lower; `beats` says where each is.
    static func clicks(bpm: Double, seconds: Double, start: Double = 0.3, accent: Int = 4) -> (samples: [Float], beats: [Double]) {
        let beat = 60 / bpm
        var x = (0..<Int(seconds * rate)).map { i in Float(0.03 * sin(2 * .pi * 110 * Double(i) / rate)) }
        var beats: [Double] = [], t = start, k = 0
        while t < seconds - 0.1 {
            let down = k % accent == 0, f = down ? 600.0 : 1_200, a = down ? 0.9 : 0.5
            for j in 0..<Int(0.04 * rate) where Int(t * rate) + j < x.count { let s = Double(j) / rate; x[Int(t * rate) + j] += Float(a * exp(-s * 90) * sin(2 * .pi * f * s)) }
            beats.append(t); t += beat; k += 1
        }
        return (x, beats)
    }

    /// A band in four parts at a known tempo: drums (kick on 1 and 3, snare on 2 and 4, hats on the eighths), bass on
    /// each beat, and keys holding a chord a bar. Each section of 8 bars has its own chords and sound, so the song moves
    /// on at bars 9, 17…
    struct Band {
        var drums: [Float], bass: [Float], keys: [Float], beats: [Double], downbeats: [Double]
        var mix: [Float] { (0..<drums.count).map { drums[$0] + bass[$0] + keys[$0] } }
    }
    static func band(bpm: Double, sections: Int = 3, start: Double = 0.4, tail: Double = 3, drumsFrom bar: Int = 1) -> Band {
        let beat = 60 / bpm, bars = sections * 8, total = start + Double(bars * 4) * beat + tail
        let n = Int(total * rate)
        var drums = [Float](repeating: 0, count: n), bass = drums, keys = drums
        // A minor, then E flat major, then E major: no chord shared between sections.
        let progressions = [[[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]], [[51, 55, 58], [56, 60, 63], [58, 62, 65], [60, 63, 67]], [[52, 56, 59], [57, 61, 64], [59, 63, 66], [61, 64, 68]]]
        var beats: [Double] = [], downs: [Double] = []
        var noise = SystemRandomNumberGenerator()
        func add(_ into: inout [Float], at t: Double, seconds: Double, _ f: (Double) -> Double) {
            let a = Int(t * rate)
            // Each sound ends over 20 ms, as an instrument's does, rather than being cut off.
            for j in 0..<Int(seconds * rate) where a + j < n { let s = Double(j) / rate; into[a + j] += Float(f(s) * min(1, (seconds - s) / 0.02)) }
        }
        for b in 0..<bars {
            let section = b / 8, chord = progressions[section % 3][b % 4], bright = 1 + Double(section % 3)
            let barStart = start + Double(b * 4) * beat
            downs.append(barStart)
            // Keys: the bar's chord, brighter in each later section.
            add(&keys, at: barStart, seconds: 4 * beat) { s in
                let env = min(1, s * 40) * exp(-s * 0.4)
                return 0.06 * env * chord.reduce(0) { acc, m in acc + (1...4).reduce(0) { $0 + pow(0.35 * bright, Double($1 - 1)) / Double($1) * sin(2 * .pi * hz(m) * Double($1) * s) } }
            }
            for k in 0..<4 {
                let t = barStart + Double(k) * beat
                beats.append(t)
                add(&bass, at: t, seconds: beat * 0.9) { s in 0.25 * min(1, s * 200) * exp(-s * 3) * sin(2 * .pi * hz(chord[0] - 24) * s) }
                guard b + 1 >= bar else { continue }
                if k % 2 == 0 { add(&drums, at: t, seconds: 0.25) { s in 0.9 * exp(-s * 18) * sin(2 * .pi * (55 + 90 * exp(-s * 30)) * s) } }
                else { add(&drums, at: t, seconds: 0.15) { s in 0.4 * exp(-s * 30) * (Double.random(in: -1...1, using: &noise) + 0.5 * sin(2 * .pi * 190 * s)) } }
                for h in 0..<2 { add(&drums, at: t + Double(h) * beat / 2, seconds: 0.03) { s in 0.08 * exp(-s * 150) * Double.random(in: -1...1, using: &noise) } }
            }
        }
        return Band(drums: drums, bass: bass, keys: keys, beats: beats, downbeats: downs)
    }

    /// Each heard beat near a true one, and the true ones all heard, but for a beat at either end.
    static func matches(_ heard: [Double], _ truth: [Double], _ label: String) {
        let off = heard.map { h in truth.map { abs($0 - h) }.min() ?? 1 }
        #expect(off.allSatisfy { $0 < withinAFrame }, "\(label): worst beat \(off.max() ?? 0) s off")
        #expect(heard.count >= truth.count - 2 && heard.count <= truth.count, "\(label): \(heard.count) beats for \(truth.count)")
    }

    @Test func clicksAreHeardOnTheBeatWithBarsOnTheFirst() async throws {
        for bpm in [120.0, 96, 140] {
            let (x, truth) = Self.clicks(bpm: bpm, seconds: 24)
            let heard = try await SongBeats.offPool { SongBeats.hear(samples: x) }
            let grid = try #require(heard.grid, "\(bpm): no grid")
            #expect(heard.steady == true)
            #expect(abs(grid.tempo - bpm) < 0.5, "\(bpm) heard as \(grid.tempo)")
            Self.matches(grid.beats, truth, "\(bpm) BPM")
            #expect(grid.beatsPerBar == 4)
            // Bar 1 starts on the first beat, the loud one.
            #expect(abs((grid.barStart(1) ?? 0) - truth[0]) < Self.withinAFrame, "\(bpm): bar 1 at \(grid.barStart(1) ?? -1)")
        }
    }

    @Test func aBandsBarsAndSectionsAreHeard() async throws {
        let b = Self.band(bpm: 112)
        let grid = try #require(try await SongBeats.offPool { SongBeats.hear(samples: b.mix) }.grid)
        #expect(abs(grid.tempo - 112) < 0.5, "\(grid.tempo)")
        Self.matches(grid.beats, b.beats, "band")
        #expect(grid.beatsPerBar == 4)
        let starts = grid.barStarts
        #expect(starts.allSatisfy { s in b.downbeats.contains { abs($0 - s) < Self.withinAFrame } }, "bars \(starts.prefix(4)) against \(b.downbeats.prefix(4))")
        #expect(grid.changes.contains(9) && grid.changes.contains(17), "changes \(grid.changes)")
        #expect(grid.changes.count <= 4, "changes \(grid.changes)")
    }

    @Test func aPadWithNoBeatAndATempoThatChangesHaveNoSteadyBeat() async throws {
        // A pad that swells, with no knock in it.
        let pad = (0..<Int(30 * Self.rate)).map { i -> Float in
            let t = Double(i) / Self.rate
            return Float(0.1 * [220.0, 261.6, 329.6].reduce(0) { $0 + sin(2 * .pi * $1 * t) } * (0.6 + 0.4 * sin(2 * .pi * 0.07 * t)) + Double.random(in: -0.02...0.02))
        }
        let ambient = try await SongBeats.offPool { SongBeats.hear(samples: pad) }
        #expect(ambient.grid == nil && ambient.steady == false)
        // 100 beats a minute, then 132.
        let slow = Self.clicks(bpm: 100, seconds: 30).samples, fast = Self.clicks(bpm: 132, seconds: 30).samples
        let changing = try await SongBeats.offPool { SongBeats.hear(samples: slow + fast) }
        #expect(changing.grid == nil && changing.steady == false, "\(changing.grid?.tempo ?? 0)")
        // Too short to tell either way.
        let short = try await SongBeats.offPool { SongBeats.hear(samples: Self.clicks(bpm: 120, seconds: 5).samples) }
        #expect(short.grid == nil && short.steady == nil)
    }

    @Test func aSongInPartsKeepsOneGridHeardOnItsDrums() async throws {
        // Drums come in at bar 5: the grid still starts with the song.
        let b = Self.band(bpm: 104, drumsFrom: 5)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("beats-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ x: [Float], _ name: String) throws -> URL {
            let url = dir.appendingPathComponent(name)
            let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(x.count))!
            buffer.frameLength = AVAudioFrameCount(x.count)
            for i in x.indices { buffer.floatChannelData![0][i] = x[i] }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        let drums = try write(b.drums, "Song (Drums).wav"), bass = try write(b.bass, "Song (Bass).wav"), keys = try write(b.keys, "Song (Keys).wav"), mix = try write(b.mix, "Song.wav")
        let parts = try await SongBeats.offPool { try SongBeats.hear(mix: mix, parts: [mix, drums, bass, keys], drums: drums) }
        let grid = try #require(parts.grid)
        #expect(grid.heardOn == "Drums")
        Self.matches(grid.beats, b.beats, "in parts")
        #expect(abs((grid.barStart(1) ?? 0) - b.downbeats[0]) < Self.withinAFrame, "bar 1 at \(grid.barStart(1) ?? -1)")
        // Without a full mix, every part together; the same beats as the full mix alone.
        let summed = try #require(try await SongBeats.offPool { try SongBeats.hear(mix: nil, parts: [drums, bass, keys], drums: drums) }.grid)
        let whole = try #require(try await SongBeats.offPool { try SongBeats.hear(mix) }.grid)
        #expect(summed.beats.count == grid.beats.count && zip(summed.beats, grid.beats).allSatisfy { abs($0 - $1) < 0.005 })
        #expect(grid.beats.filter { g in whole.beats.contains { abs($0 - g) < Self.withinAFrame } }.count >= grid.beats.count - 2, "full mix alone: \(whole.beats.count) beats against \(grid.beats.count)")
    }

    /// Off-beat accents (a skank and hats louder than the kick, between the beats): the beat is where the kick is.
    @Test func theBeatIsOnTheKickWhenTheOffBeatsAreLouder() async throws {
        let bpm = 96.0, beat = 60 / bpm, start = 0.35, seconds = 30.0
        var x = [Float](repeating: 0, count: Int(seconds * Self.rate)), kicks: [Double] = []
        var noise = SystemRandomNumberGenerator()
        func add(at t: Double, seconds d: Double, _ f: (Double) -> Double) {
            let a = Int(t * Self.rate)
            for j in 0..<Int(d * Self.rate) where a + j < x.count { let s = Double(j) / Self.rate; x[a + j] += Float(f(s) * min(1, (d - s) / 0.01)) }
        }
        var t = start
        while t < seconds - 1 {
            kicks.append(t)
            add(at: t, seconds: 0.25) { s in 0.35 * exp(-s * 16) * sin(2 * .pi * (50 + 70 * exp(-s * 30)) * s) }
            let off = t + beat / 2
            add(at: off, seconds: 0.12) { s in 0.5 * exp(-s * 25) * [523.3, 659.3, 784.0].reduce(0) { $0 + sin(2 * .pi * $1 * s) + 0.5 * sin(4 * .pi * $1 * s) } / 3 }
            add(at: off, seconds: 0.05) { s in 0.45 * exp(-s * 60) * Double.random(in: -1...1, using: &noise) }
            t += beat
        }
        let samples = x
        let grid = try #require(try await SongBeats.offPool { SongBeats.hear(samples: samples) }.grid)
        let off = grid.beats.map { b in kicks.map { abs($0 - b) }.min() ?? 1 }
        #expect(off.filter { $0 < Self.withinAFrame }.count >= grid.beats.count - 2, "beats \(grid.beats.prefix(6)) against kicks \(kicks.prefix(6))")
    }

    @Test func musicalTimesNameTheSongsBarsAndBeats() throws {
        let grid = BeatGrid(beats: (0..<16).map { 0.5 + Double($0) * 0.5 }, bars: [1, 5, 9, 13], beatsPerBar: 4, changes: [3])
        #expect(try grid.seconds(.object(["bar": .number(2)]), song: "S") == 3.0)
        #expect(try grid.seconds(.object(["bar": .number(2), "beat": .number(3)]), song: "S") == 4.0)
        #expect(try grid.seconds(.object(["beat": .number(1)]), song: "S") == 0.5)
        #expect(try grid.seconds(.number(4), song: "S") == nil)
        #expect(throws: DirectionError.self) { try grid.seconds(.object(["bar": .number(9)]), song: "S") }
        #expect(throws: DirectionError.self) { try grid.seconds(.object(["bar": .number(1), "beat": .number(5)]), song: "S") }
        #expect(grid.bar(at: 3.2) == 2 && grid.bar(at: 0.6) == nil)
        #expect(grid.line.contains("4 beats a bar") && grid.line.contains("bar 3 (0:05.0)"), "\(grid.line)")
    }

    /// How real music was checked: the files in DIRECTION_BEATS_PROBE (separated by |), and a song in parts in
    /// DIRECTION_BEATS_PARTS (mix|drums|other parts), its grid measured against its own drum hits. Nothing runs without them.
    @Test func probe() throws {
        guard let list = ProcessInfo.processInfo.environment["DIRECTION_BEATS_PROBE"] else { return }
        for path in list.split(separator: "|").map(String.init) {
            let started = Date()
            let h = try SongBeats.hear(URL(fileURLWithPath: path))
            let g = h.grid
            print("PROBE \(URL(fileURLWithPath: path).lastPathComponent): steady \(String(describing: h.steady)) tempo \(g?.tempo ?? 0) beats \(g?.beats.count ?? 0) bars \(g?.bars.count ?? 0) per \(g?.beatsPerBar ?? 0) first \(g?.beats.first ?? -1) bar1 \(g?.barStart(1) ?? -1) changes \(g?.changes ?? []) in \(Date().timeIntervalSince(started)) s")
            if let g { print("PROBE line: \(g.line)") }
        }
        // A song in parts: mix|drums|other parts…
        if let list = ProcessInfo.processInfo.environment["DIRECTION_BEATS_PARTS"] {
            let urls = list.split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            let started = Date()
            let h = try SongBeats.hear(mix: urls[0], parts: urls, drums: urls[1])
            let g = h.grid
            print("PROBE parts: steady \(String(describing: h.steady)) tempo \(g?.tempo ?? 0) beats \(g?.beats.count ?? 0) bars \(g?.bars.count ?? 0) first \(g?.beats.first ?? -1) bar1 \(g?.barStart(1) ?? -1) changes \(g?.changes ?? []) heardOn \(g?.heardOn ?? "") in \(Date().timeIntervalSince(started)) s")
            if let g { print("PROBE parts line: \(g.line)") }
            // Against the drum hits themselves: how far each beat is from the nearest strong hit within 100 ms.
            let d = SongBeats.unit(MusicListening.features(samples: try MusicListening.samples(urls[1])).onsets), r = SongBeats.onsetRate
            let hits = (1..<(d.count - 1)).filter { d[$0] > 3 && d[$0] >= d[$0 - 1] && d[$0] > d[$0 + 1] }.map { SongBeats.refine(d, at: $0) / r + SongBeats.onsetDelay }
            if let g {
                let near = g.beats.compactMap { b in hits.map { $0 - b }.min { abs($0) < abs($1) }.flatMap { abs($0) < 0.1 ? $0 : nil } }
                let sorted = near.map(abs).sorted()
                let byTime = stride(from: 0.0, to: g.beats.last ?? 0, by: 30).map { a -> String in
                    let inside = g.beats.filter { $0 >= a && $0 < a + 30 }.compactMap { b in hits.map { $0 - b }.min { abs($0) < abs($1) }.flatMap { abs($0) < 0.1 ? $0 : nil } }.sorted()
                    return inside.isEmpty ? "\(Int(a)):-" : "\(Int(a)):\(String(format: "%+.0f", inside[inside.count / 2] * 1000))ms/\(inside.count)"
                }
                print("PROBE parts drift: \(byTime)")
                print("PROBE parts against \(hits.count) drum hits: \(near.count)/\(g.beats.count) beats have one within 100 ms; median \(String(format: "%.1f", sorted[sorted.count / 2] * 1000)) ms, 90th \(String(format: "%.1f", sorted[sorted.count * 9 / 10] * 1000)) ms, mean signed \(String(format: "%+.1f", near.reduce(0, +) / Double(near.count) * 1000)) ms, within 20 ms \(sorted.filter { $0 <= 0.02 }.count)")
            }
            let drumsAlone = try SongBeats.hear(urls[1]).grid, mixAlone = try SongBeats.hear(urls[0]).grid
            for (label, other) in [("drums alone", drumsAlone), ("full mix alone", mixAlone)] {
                guard let g, let o = other else { print("PROBE \(label): none"); continue }
                let near = g.beats.map { b in o.beats.map { abs($0 - b) }.min() ?? 9 }
                let bars = g.barStarts.filter { b in o.barStarts.contains { abs($0 - b) < 0.03 } }.count
                let againstHits = o.beats.compactMap { b in hits.map { $0 - b }.min { abs($0) < abs($1) }.flatMap { abs($0) < 0.1 ? abs($0) : nil } }.sorted()
                if !againstHits.isEmpty { print("PROBE \(label) against drum hits: \(againstHits.count) near one, median \(String(format: "%.1f", againstHits[againstHits.count / 2] * 1000)) ms, 90th \(String(format: "%.1f", againstHits[againstHits.count * 9 / 10] * 1000)) ms") }
                print("PROBE \(label): \(o.beats.count) beats, \(near.filter { $0 < 0.02 }.count) within 20 ms, median off \(near.sorted()[near.count / 2]), bars agreeing \(bars)/\(g.bars.count), tempo \(o.tempo), changes \(o.changes)")
            }
        }
    }
}
