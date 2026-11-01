import Foundation
import Accelerate
@preconcurrency import AVFoundation
import DirectionCore

/// The music in a video someone else made, heard in the whole mix (styles.md › From a video › Music): macOS
/// can't take the music apart from the voice, so the beat is read where the words leave room, the key from the
/// notes that sound most, and the music's level in the pauses between words. Everything here is an estimate a
/// director would check by ear; the study says so.
enum MusicListening {
    /// Onsets are read on a log scale this steep: enough for a soft beat, not so much that the flutter of a held
    /// note counts.
    static let onsetGain: Float = 10
    /// Read at 12 kHz in one channel: notes up to 2 kHz and the beat, and nothing a style needs above that.
    static let rate = 12_000.0
    /// Onsets from 512-sample frames every 128 (94 a second); notes from 4096 every 2048 (about 6 a second);
    /// level every 50 ms.
    static let onsetSize = 512, onsetHop = 128, noteSize = 4096, noteHop = 2048, levelSize = 600
    static let onsetRate = rate / Double(onsetHop), noteRate = rate / Double(noteHop), levelRate = rate / Double(levelSize)
    /// Notes are read from G2 to C7: below that one bin is wider than a semitone.
    static let lowestNote = 98.0, highestNote = 2_100.0

    struct Features: Sendable {
        /// How much new sound starts in each frame (spectral flux), `onsetRate` a second.
        var onsets: [Float] = []
        /// How strongly each of the 12 pitch classes sounds (C first), `noteRate` a second.
        var notes: [[Float]] = []
        /// Level in dB, `levelRate` a second.
        var levels: [Float] = []
    }

    // MARK: Reading

    /// Features of a sound file, read in one pass.
    static func features(_ url: URL) throws -> Features {
        let file = try AVAudioFile(forReading: url)
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: mono) else { throw DirectionError("audio_unreadable", "\(url.lastPathComponent) can't be read.") }
        converter.downmix = true
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate)
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
              let output = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(rate) + 4096) else { throw DirectionError("audio_unreadable", "\(url.lastPathComponent) can't be read.") }
        final class Feed: @unchecked Sendable { var ended = false }
        let feed = Feed()
        var reader = Reader()
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if !feed.ended {
                    do { try file.read(into: input, frameCount: chunk) } catch { input.frameLength = 0 }
                    if input.frameLength == 0 { feed.ended = true }
                }
                if feed.ended { state.pointee = .endOfStream; return nil }
                state.pointee = .haveData
                return input
            }
            if status == .error { throw error ?? DirectionError("audio_unreadable", "\(url.lastPathComponent) can't be read.") }
            if output.frameLength > 0, let data = output.floatChannelData { reader.add(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength))) }
            if status == .endOfStream || (feed.ended && output.frameLength == 0) { break }
        }
        return reader.features
    }

    /// Features of samples already at `rate`, for tests and short sounds.
    static func features(samples: [Float]) -> Features {
        var reader = Reader()
        samples.withUnsafeBufferPointer { reader.add($0) }
        return reader.features
    }

    /// Takes samples as they come and keeps the three frame sizes going.
    struct Reader {
        var features = Features()
        private var pending: [Float] = []
        /// Where `pending` starts, and where each kind of frame reads next, in samples from the start.
        private var base = 0, onsetAt = 0, noteAt = 0, levelAt = 0
        private let onsetSpectrum = Spectrum(size: onsetSize), noteSpectrum = Spectrum(size: noteSize)
        private var lastOnset: [Float]?
        private let pitchClass: [(bin: Int, pc: Int, weight: Float)]
        /// Each onset bin's band: 24 from 60 Hz to 6 kHz, a third of an octave or so each. A held note's
        /// energy stays in its band frame to frame even as single bins flutter.
        private let band: [Int?]

        init() {
            band = (0..<(onsetSize / 2)).map { k in
                let f = Double(k) * rate / Double(onsetSize)
                guard f >= 60 else { return nil }
                return min(23, Int(log2(f / 60) / log2(100) * 24))
            }
            pitchClass = (1..<(noteSize / 2)).compactMap { k in
                let f = Double(k) * rate / Double(noteSize)
                guard f >= lowestNote, f <= highestNote else { return nil }
                let pitch = 69 + 12 * log2(f / 440), nearest = pitch.rounded()
                // A bin between two semitones says little about either.
                let w = cos(Double.pi * (pitch - nearest)); return (k, (Int(nearest) % 12 + 12) % 12, Float(w * w))
            }
        }

        mutating func add(_ samples: UnsafeBufferPointer<Float>) {
            pending.append(contentsOf: samples)
            let end = base + pending.count, buffer = pending
            buffer.withUnsafeBufferPointer { p in
                while onsetAt + onsetSize <= end {
                    var bands = [Float](repeating: 0, count: 24)
                    for (k, m) in onsetSpectrum.magnitudes(p, from: onsetAt - base).enumerated() { if let b = band[k] { bands[b] += m } }
                    let mags = bands.map { log1pf(onsetGain * $0) }
                    features.onsets.append(lastOnset.map { last in zip(mags, last).reduce(0) { $0 + max(0, $1.0 - $1.1) } } ?? 0)
                    lastOnset = mags; onsetAt += onsetHop
                }
                while noteAt + noteSize <= end {
                    let mags = noteSpectrum.magnitudes(p, from: noteAt - base)
                    var chroma = [Float](repeating: 0, count: 12)
                    for b in pitchClass { chroma[b.pc] += b.weight * mags[b.bin] }
                    features.notes.append(chroma); noteAt += noteHop
                }
                while levelAt + levelSize <= end {
                    var rms: Float = 0
                    vDSP_rmsqv(p.baseAddress! + (levelAt - base), 1, &rms, vDSP_Length(levelSize))
                    features.levels.append(20 * log10f(rms + 1e-7)); levelAt += levelSize
                }
            }
            let used = min(onsetAt, noteAt, levelAt) - base
            if used > 0 { pending.removeFirst(used); base += used }
        }
    }

    /// Magnitudes of a Hann-windowed frame.
    final class Spectrum: @unchecked Sendable {
        let size: Int
        private let fft: vDSP.FFT<DSPSplitComplex>
        private let window: [Float]
        init(size: Int) {
            self.size = size
            fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(size))), radix: .radix2, ofType: DSPSplitComplex.self)!
            window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        }
        func magnitudes(_ samples: UnsafeBufferPointer<Float>, from start: Int) -> [Float] {
            let frame = vDSP.multiply(UnsafeBufferPointer(rebasing: samples[start..<(start + size)]), window)
            var real = [Float](repeating: 0, count: size / 2), imag = [Float](repeating: 0, count: size / 2), out = [Float](repeating: 0, count: size / 2)
            real.withUnsafeMutableBufferPointer { r in
                imag.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    frame.withUnsafeBufferPointer { f in f.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2)) } }
                    let input = split
                    fft.forward(input: input, output: &split)
                    out.withUnsafeMutableBufferPointer { vDSP_zvabs(&split, 1, $0.baseAddress!, 1, vDSP_Length(size / 2)) }
                }
            }
            return out
        }
    }

    // MARK: Beat

    /// The beat in some onsets: the lag that repeats best between 50 and 200 beats a minute, leaning toward
    /// 120 the way listeners do, so a beat isn't read at half or double. `quiet` frames (words) count as
    /// nothing. Nil without at least eight seconds to hear or a beat that repeats.
    static func tempo(_ onsets: ArraySlice<Float>, quiet: [Bool]? = nil) -> Double? {
        guard onsets.count >= Int(8 * onsetRate) else { return nil }
        var x = Array(onsets)
        // A beat is a knock now and then, far above the usual; a held note's flutter or vibrato repeats too, but
        // never stands out like that.
        let sorted = x.sorted()
        guard sorted[Int(Double(sorted.count - 1) * 0.99)] >= beatPeak * max(sorted[sorted.count / 2], 1e-4) else { return nil }
        // Take away the running mean (a second), so loud stretches don't look like beats.
        let span = Int(onsetRate), sums = x.reduce(into: [Float(0)]) { $0.append($0.last! + $1) }
        x = x.indices.map { i in let a = max(0, i - span / 2), b = min(x.count, i + span / 2 + 1); return max(0, x[i] - (sums[b] - sums[a]) / Float(b - a)) }
        if let quiet { for i in x.indices where i < quiet.count && quiet[i] { x[i] = 0 } }
        // Spread each onset over a few frames, so a beat that falls between frames repeats as well as one on them.
        let kernel: [Float] = [1, 4, 6, 4, 1].map { $0 / 16 }
        x = x.indices.map { i in (-2...2).reduce(Float(0)) { s, k in let j = i + k; return j >= 0 && j < x.count ? s + kernel[k + 2] * x[j] : s } }
        // Around zero, so only what repeats counts, not that there's always some sound.
        x = vDSP.add(-vDSP.mean(x), x)
        let energy = vDSP.dot(x, x)
        guard energy > 0 else { return nil }
        let lags = Int((60 / 200) * onsetRate)...Int((60 / 50) * onsetRate)
        func ac(_ lag: Int) -> Float {
            guard lag < x.count else { return 0 }
            return x.withUnsafeBufferPointer { p in var d: Float = 0; vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &d, vDSP_Length(x.count - lag)); return d } / energy * Float(x.count) / Float(x.count - lag)
        }
        let scores = lags.map { lag -> (Int, Float, Float) in
            let bpm = 60 * onsetRate / Double(lag), r = ac(lag)
            return (lag, r, r * Float(exp(-0.5 * pow(log2(bpm / 120), 2))))
        }
        guard let best = scores.max(by: { $0.2 < $1.2 }), best.1 >= beatStrength else { return nil }
        // Between frames: the top of a parabola through the best lag and its neighbors.
        let (a, b, c) = (ac(best.0 - 1), best.1, ac(best.0 + 1))
        let shift = a - 2 * b + c == 0 ? 0 : Double(0.5 * (a - c) / (a - 2 * b + c))
        return 60 * onsetRate / (Double(best.0) + max(-0.5, min(0.5, shift)))
    }
    /// How well the beat repeats, against the onsets' own energy, before it counts as a beat.
    static let beatStrength: Float = 0.25
    /// How far above the median onset the loudest one in a hundred must be for there to be beats at all.
    static let beatPeak: Float = 8

    // MARK: Key

    /// Krumhansl and Kessler's major and minor profiles: how well each note fits a key, tonic first.
    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    static let noteNames = ["C", "C\u{266F}", "D", "E\u{266D}", "E", "F", "F\u{266F}", "G", "A\u{266D}", "A", "B\u{266D}", "B"]
    /// How closely the notes must follow a key's profile, and how far ahead of the next key, to name it. Music
    /// under a voice fits less closely than music alone; in a real film its key read 0.45–0.6 where the score's
    /// own key was the best fit.
    static let keyFit: Float = 0.45, keyLead: Float = 0.05

    /// The key some notes are in, by the profile they follow best: "A minor".
    static func key(_ chroma: [Float]) -> String? {
        guard chroma.count == 12, chroma.contains(where: { $0 > 0 }) else { return nil }
        func r(_ x: [Float], _ y: [Float]) -> Float {
            let mx = vDSP.mean(x), my = vDSP.mean(y)
            let dx = vDSP.add(-mx, x), dy = vDSP.add(-my, y)
            let d = (vDSP.dot(dx, dx) * vDSP.dot(dy, dy)).squareRoot()
            return d == 0 ? 0 : vDSP.dot(dx, dy) / d
        }
        var fits: [(String, Float)] = []
        for tonic in 0..<12 {
            let rotated = (0..<12).map { chroma[($0 + tonic) % 12] }
            fits.append(("\(noteNames[tonic]) major", r(rotated, majorProfile)))
            fits.append(("\(noteNames[tonic]) minor", r(rotated, minorProfile)))
        }
        let ranked = fits.sorted { $0.1 > $1.1 }
        guard ranked[0].1 >= keyFit, ranked[0].1 - ranked[1].1 >= keyLead else { return nil }
        return ranked[0].0
    }

    /// Which frames of a kind (`size` samples every `hop`) have their middles in some stretches.
    static func mask(_ stretches: [ClosedRange<Double>], count: Int, size: Int, hop: Int) -> [Bool] {
        var out = [Bool](repeating: false, count: count)
        for s in stretches {
            let a = max(0, Int(((s.lowerBound * rate - Double(size) / 2) / Double(hop)).rounded(.up))), b = min(count - 1, Int(((s.upperBound * rate - Double(size) / 2) / Double(hop)).rounded(.down)))
            if a <= b { for i in a...b { out[i] = true } }
        }
        return out
    }
    static func onsetMask(_ s: [ClosedRange<Double>], _ f: Features) -> [Bool] { mask(s, count: f.onsets.count, size: onsetSize, hop: onsetHop) }
    static func noteMask(_ s: [ClosedRange<Double>], _ f: Features) -> [Bool] { mask(s, count: f.notes.count, size: noteSize, hop: noteHop) }
    static func levelMask(_ s: [ClosedRange<Double>], _ f: Features) -> [Bool] { mask(s, count: f.levels.count, size: levelSize, hop: levelSize) }

    /// The notes of a stretch, each frame counting as much as it's heard without words (`quiet`) over it.
    static func notes(_ f: Features, from start: Double, to end: Double, quiet: [Bool]) -> [Float] {
        let a = max(0, Int(start * noteRate)), b = min(f.notes.count, Int(end * noteRate))
        var sum = [Float](repeating: 0, count: 12)
        guard a < b else { return sum }
        for i in a..<b { sum = vDSP.add(sum, vDSP.multiply(i < quiet.count && quiet[i] ? 0.25 : 1, f.notes[i])) }
        return sum
    }

    /// Where the chords change inside one long stretch of music: the seconds where the notes of the eight
    /// seconds before and the eight after differ most, kept twelve seconds apart.
    static func changes(_ f: Features, from start: Double, to end: Double, quiet: [Bool]) -> [Double] {
        let side = 8.0, apart = 12.0
        guard end - start >= 2 * apart else { return [] }
        func unit(_ v: [Float]) -> [Float] { let n = vDSP.dot(v, v).squareRoot(); return n == 0 ? v : vDSP.divide(v, n) }
        var novelty: [(Double, Float)] = []
        var t = start + apart
        while t <= end - apart {
            let before = unit(notes(f, from: t - side, to: t, quiet: quiet)), after = unit(notes(f, from: t, to: t + side, quiet: quiet))
            novelty.append((t, 1 - vDSP.dot(before, after)))
            t += 1
        }
        var out: [Double] = []
        for (i, n) in novelty.enumerated() where n.1 >= chordChange {
            let window = novelty[max(0, i - 6)...min(novelty.count - 1, i + 6)]
            guard window.allSatisfy({ $0.1 <= n.1 }), out.last.map({ n.0 - $0 >= apart }) ?? true else { continue }
            out.append(n.0)
        }
        return out
    }
    /// How different the notes either side must be (1 − their cosine) to be a new cue.
    static let chordChange: Float = 0.12

    // MARK: Level

    /// The median level of the 50 ms frames whose middles fall in some stretches.
    static func level(_ f: Features, in stretches: [ClosedRange<Double>]) -> Double? {
        let values = zip(f.levels, levelMask(stretches, f)).compactMap { $1 ? $0 : nil }.sorted()
        guard values.count >= 4 else { return nil }
        return Double(values[values.count / 2])
    }

    /// A hit on a cut: an onset in the tenth of a second around it at least four times what's usual in the
    /// three seconds about it, and a real knock (`hitOnset`), not the flutter of something held.
    static func hit(_ f: Features, at cut: Double) -> Bool {
        let at = Int(cut * onsetRate), near = Int(0.1 * onsetRate), around = Int(1.5 * onsetRate)
        guard at - around >= 0, at + around < f.onsets.count else { return false }
        let peak = f.onsets[(at - near)...(at + near)].max() ?? 0
        let usual = Array(f.onsets[(at - around)..<(at - near)] + f.onsets[(at + near + 1)...(at + around)]).sorted()
        let median = usual[usual.count / 2]
        return peak > max(4 * median, hitOnset)
    }
    /// Onset strength of a sound that starts at once in a few bands: about 6 dB up across a handful of them.
    static let hitOnset: Float = 1

    /// A riser into a cut: the level climbs steadily through the two seconds before it, by 6 dB or more.
    static func riser(_ f: Features, into cut: Double) -> Bool {
        let b = Int(cut * levelRate) - 1, a = b - Int(2 * levelRate)
        guard a >= 0, b < f.levels.count else { return false }
        let y = f.levels[a...b].map(Double.init), x = y.indices.map { Double($0) / levelRate }
        let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
        let sxy = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }, sxx = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }, syy = y.reduce(0) { $0 + ($1 - my) * ($1 - my) }
        guard sxx > 0, syy > 0 else { return false }
        let slope = sxy / sxx, fit = sxy * sxy / (sxx * syy)
        return slope * 2 >= 6 && fit >= 0.6
    }
}
