import Foundation

/// Loudness to ITU-R BS.1770-4, the meter EBU R128 and the streaming targets use: each channel is
/// K-weighted (a high shelf, then a high-pass), its mean square taken over 400 ms blocks every 100 ms
/// and summed across channels by their weights, and the blocks gated at −70 LUFS, then at 10 LU under
/// the loudness of what's left. Peaks are the sample peak and the true peak, read from the signal
/// oversampled 4×. Samples come in as they're mixed; only one number per 100 ms is kept.
public struct LoudnessMeter: Sendable {
    public let sampleRate: Double
    public let channels: Int
    /// BS.1770's weights: 1 for left, right and centre, 1.41 for the surrounds; the LFE isn't counted.
    let weights: [Double]
    var shelf: [Biquad], highPass: [Biquad]
    /// The weighted mean square of each whole 100 ms, in order.
    var steps: [Double] = []
    /// The true peak of each whole 100 ms, as a linear level.
    var stepPeaks: [Double] = []
    var energy = 0.0, count = 0, stepPeak = 0.0
    let stepLength: Int
    var peak = 0.0, between = 0.0
    /// Each channel's last 12 samples, kept twice over so they're always in a row.
    var recent: [Double], cursor = 0

    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate; self.channels = channels
        weights = channels == 6 ? [1, 1, 1, 0, 1.41, 1.41] : Array(repeating: 1, count: channels)
        // The pre-filter and the RLB high-pass, for any rate (BS.1770-4 lists them at 48 kHz).
        var k = tan(.pi * 1681.974450955533 / sampleRate)
        let vh = pow(10, 3.999843853973347 / 20), vb = pow(vh, 0.4996667741545416), q1 = 0.7071752369554196
        var a0 = 1 + k / q1 + k * k
        let s = Biquad(b0: (vh + vb * k / q1 + k * k) / a0, b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q1 + k * k) / a0, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q1 + k * k) / a0)
        k = tan(.pi * 38.13547087602444 / sampleRate)
        let q2 = 0.5003270373238773
        a0 = 1 + k / q2 + k * k
        let h = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q2 + k * k) / a0)
        shelf = Array(repeating: s, count: channels); highPass = Array(repeating: h, count: channels)
        stepLength = max(1, Int((sampleRate / 10).rounded()))
        recent = Array(repeating: 0, count: channels * 2 * Oversampling.taps)
    }

    /// Interleaved samples, as many whole frames as there are.
    public mutating func add(_ samples: UnsafeBufferPointer<Float>) {
        let taps = Oversampling.taps, h = Oversampling.phases
        var ring = recent, shelf = shelf, highPass = highPass
        var peak = peak, between = between, energy = energy, count = count, cursor = cursor, stepPeak = stepPeak
        for frame in 0..<(samples.count / channels) {
            var e = 0.0
            for c in 0..<channels {
                let x = Double(samples[frame * channels + c])
                peak = max(peak, abs(x)); stepPeak = max(stepPeak, abs(x))
                let newest = c * 2 * taps + cursor + taps
                ring[newest - taps] = x; ring[newest] = x
                for p in 0..<3 {
                    var y = 0.0
                    for j in 0..<taps { y += ring[newest - j] * h[p * taps + j] }
                    between = max(between, abs(y)); stepPeak = max(stepPeak, abs(y))
                }
                let w = highPass[c].filter(shelf[c].filter(x))
                e += weights[c] * w * w
            }
            cursor = (cursor + 1) % taps
            energy += e; count += 1
            if count == stepLength { steps.append(energy / Double(stepLength)); stepPeaks.append(stepPeak); energy = 0; count = 0; stepPeak = 0 }
        }
        recent = ring; self.shelf = shelf; self.highPass = highPass
        self.peak = peak; self.between = between; self.energy = energy; self.count = count; self.cursor = cursor; self.stepPeak = stepPeak
    }

    static func lufs(_ z: Double) -> Double { -0.691 + 10 * log10(z) }

    /// Integrated loudness in LUFS, or nil when nothing is left after gating (silence, or under 400 ms).
    public var integrated: Double? {
        guard steps.count >= 4 else { return nil }
        let blocks = (0...(steps.count - 4)).map { j in (steps[j] + steps[j + 1] + steps[j + 2] + steps[j + 3]) / 4 }
        let audible = blocks.filter { $0 > 0 && Self.lufs($0) > -70 }
        guard !audible.isEmpty else { return nil }
        let relative = Self.lufs(audible.reduce(0, +) / Double(audible.count)) - 10
        let gated = audible.filter { Self.lufs($0) > relative }
        return gated.isEmpty ? nil : Self.lufs(gated.reduce(0, +) / Double(gated.count))
    }
    /// Short-term loudness (EBU R128: the last 3 s) every `every` seconds, from the first whole 3 s; nil where
    /// it's silent (under −70 LUFS). Each value is the 3 s that end at its time.
    public func shortTerm(every: Double) -> [(end: Double, lufs: Double?)] {
        let stride = max(1, Int((every * 10).rounded())), window = 30
        guard steps.count >= window else { return steps.count >= 4 ? [(Double(steps.count) / 10, Self.level(steps))] : [] }
        return Swift.stride(from: window, through: steps.count, by: stride).map { end in (Double(end) / 10, Self.level(steps[(end - window)..<end])) }
    }
    /// The true peak in each `every` seconds, in dBTP, by its start.
    public func peaks(every: Double) -> [(start: Double, dBTP: Double)] {
        let stride = max(1, Int((every * 10).rounded()))
        return Swift.stride(from: 0, to: stepPeaks.count, by: stride).map { i in (Double(i) / 10, 20 * log10(max(stepPeaks[i..<min(stepPeaks.count, i + stride)].max() ?? 0, 1e-12))) }
    }
    static func level<C: Collection>(_ z: C) -> Double? where C.Element == Double {
        let mean = z.reduce(0, +) / Double(max(1, z.count)); return mean > 0 && lufs(mean) > -70 ? lufs(mean) : nil
    }
    public var samplePeakDBFS: Double { 20 * log10(max(peak, 1e-12)) }
    public var truePeakDBTP: Double { 20 * log10(max(peak, between, 1e-12)) }
    /// Seconds measured so far.
    public var seconds: Double { Double(steps.count * stepLength + count) / sampleRate }
}

struct Biquad: Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) { self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2 }
    mutating func filter(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// The three samples between each pair, for the true peak: a Hann-windowed sinc over 12 samples, six
/// samples behind, each phase scaled so a steady level passes unchanged. Phases one after another.
enum Oversampling {
    static let taps = 12
    static let phases: [Double] = (1..<4).flatMap { p -> [Double] in
        let h = (0..<taps).map { j -> Double in
            let a = Double(j) - 6 + Double(p) / 4
            return sin(.pi * a) / (.pi * a) * (0.5 + 0.5 * cos(.pi * a / 6))
        }
        let sum = h.reduce(0, +)
        return h.map { $0 / sum }
    }
}
