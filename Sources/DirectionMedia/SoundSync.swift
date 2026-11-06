import Foundation
@preconcurrency import AVFoundation
import Accelerate
import DirectionCore

/// Finds takes that recorded the same moment by their sound (footage-index.md › Sync): two cameras,
/// a camera and a screen recording, a camera and a sound recorder. Each take becomes a loudness curve
/// (one value every 10 ms), and curves are matched by cross-correlation. All of it runs on this Mac.
public enum SoundSync {
    /// Curve samples per second: 10 ms, a third of a frame at 30 fps.
    public static let rate = 100.0
    /// The weakest match that counts as the same moment (a correlation of the two curves where they overlap).
    public static let minimumMatch = 0.6
    /// The shortest overlap that counts.
    public static let minimumOverlap = 10.0

    /// A take's sound as a loudness curve, from its loudest unmuted track, z-scored. `level` is the
    /// 90th-percentile loudness before scaling, to tell a close mic from a far one.
    public struct Curve: Codable, Sendable {
        public var values: [Float]
        public var level: Float
        public var trackID: Int32
        public init(values: [Float], level: Float, trackID: Int32) { self.values = values; self.level = level; self.trackID = trackID }
    }

    public static func curve(asset: MediaAsset) async throws -> Curve? {
        // Muting is the mix's choice: a take with every track muted (the cut's sound comes from
        // somewhere else) still recorded the moment, so it's heard on all of them.
        let unmuted = asset.audio.filter { !$0.settings.muted }, tracks = unmuted.isEmpty ? asset.audio : unmuted
        guard !tracks.isEmpty else { return nil }
        let access = try MediaAccess(assets: [asset]); defer { withExtendedLifetime(access) {} }
        let source = AVURLAsset(url: try MediaInspector.checkedURL(asset))
        var best: Curve?
        for stream in tracks {
            try Task.checkCancellation()
            guard let track = try await source.loadTracks(withMediaType: .audio).first(where: { $0.trackID == stream.id }) else { continue }
            let raw = try envelope(source, track: track)
            let level = percentile(raw, 0.9)
            // A silent track (desktop audio nobody played) can't be matched.
            guard level > 1e-4, level > (best?.level ?? 0) else { continue }
            best = Curve(values: standardized(raw), level: level, trackID: stream.id)
        }
        return best
    }

    /// Mean absolute level every 10 ms, decoded at 8 kHz mono. Samples land at their own timestamps,
    /// so a track that starts after the picture keeps its place.
    static func envelope(_ source: AVURLAsset, track: AVAssetTrack) throws -> [Float] {
        let sampleRate = 8_000.0, hop = Int(sampleRate / rate)
        let reader = try AVAssetReader(asset: source)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? DirectionError("audio_decode_failed", "Cannot decode audio.") }
        var sums: [Float] = [], counts: [Int] = []
        while let sample = output.nextSample(of: reader) {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let n = CMSampleBufferGetNumSamples(sample)
            let stamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let first = stamp.isFinite && stamp >= 0 ? Int((stamp * sampleRate).rounded()) : (sums.count * hop)
            var length = 0, pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr, let pointer else { continue }
            let samples = min(n, length / MemoryLayout<Float>.size)
            pointer.withMemoryRebound(to: Float.self, capacity: samples) { p in
                let lastBin = (first + samples - 1) / hop
                if lastBin >= sums.count { sums += Array(repeating: 0, count: lastBin + 1 - sums.count); counts += Array(repeating: 0, count: lastBin + 1 - counts.count) }
                for i in 0..<samples { let bin = (first + i) / hop; sums[bin] += abs(p[i]); counts[bin] += 1 }
            }
        }
        try ReadStall.check(reader, source.url.lastPathComponent)
        if reader.status == .failed { throw reader.error ?? DirectionError("audio_decode_failed", "Cannot decode audio.") }
        return zip(sums, counts).map { $1 > 0 ? $0 / Float($1) : 0 }
    }

    // MARK: Matching

    public struct Match: Equatable, Sendable {
        /// Seconds: `a`'s time = `b`'s time + offset.
        public var offset: Double
        /// The curves' correlation where they overlap, 0–1.
        public var match: Double
        /// Seconds the two takes share.
        public var overlap: Double
        public var isSameMoment: Bool { match >= SoundSync.minimumMatch && overlap >= SoundSync.minimumOverlap }
        public init(offset: Double, match: Double, overlap: Double) { self.offset = offset; self.match = match; self.overlap = overlap }
    }

    /// Where `b` sits on `a`'s clock. The lag is picked by match weighted toward longer overlaps, so a
    /// short burst that happens to line up doesn't beat the whole take; the match reported is the plain
    /// correlation at that lag, refined between samples.
    public static func match(_ a: [Float], _ b: [Float]) -> Match? {
        let minOverlap = Int(minimumOverlap * rate)
        guard a.count >= minOverlap, b.count >= minOverlap else { return nil }
        let c = correlate(a, b)
        // c[i] pairs a[k + j] with b[j] for lag k = i − (b.count − 1).
        func overlap(_ i: Int) -> Int { let k = i - (b.count - 1); return min(a.count, b.count + k) - max(0, k) }
        var bestIndex = -1, bestScore = -Double.infinity
        for i in c.indices {
            let o = overlap(i)
            guard o >= minOverlap else { continue }
            let score = Double(c[i]) / Double(o).squareRoot()
            if score > bestScore { bestScore = score; bestIndex = i }
        }
        guard bestIndex >= 0 else { return nil }
        func r(_ i: Int) -> Double { c.indices.contains(i) && overlap(i) > 0 ? Double(c[i]) / Double(overlap(i)) : 0 }
        // A parabola through the peak and its neighbours places it between samples.
        let (l, m, h) = (r(bestIndex - 1), r(bestIndex), r(bestIndex + 1))
        let denominator = l - 2 * m + h
        let shift = denominator < 0 ? max(-0.5, min(0.5, 0.5 * (l - h) / denominator)) : 0
        let lag = Double(bestIndex - (b.count - 1)) + shift
        return Match(offset: lag / rate, match: max(0, min(1, m)), overlap: Double(overlap(bestIndex)) / rate)
    }

    /// Full cross-correlation, every lag from −(b.count − 1) to a.count − 1, through the FFT.
    static func correlate(_ a: [Float], _ b: [Float]) -> [Float] {
        let total = a.count + b.count - 1
        var n = 1; while n < total { n <<= 1 }
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD), let inverse = vDSP_DFT_zop_CreateSetup(forward, vDSP_Length(n), .INVERSE) else { return [] }
        defer { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(inverse) }
        func transform(_ x: [Float]) -> ([Float], [Float]) {
            let real = x + Array(repeating: 0, count: n - x.count), imag = [Float](repeating: 0, count: n)
            var outReal = [Float](repeating: 0, count: n), outImag = [Float](repeating: 0, count: n)
            vDSP_DFT_Execute(forward, real, imag, &outReal, &outImag)
            return (outReal, outImag)
        }
        let (ar, ai) = transform(a), (br, bi) = transform(b)
        // A · conj(B)
        var pr = [Float](repeating: 0, count: n), pi = [Float](repeating: 0, count: n)
        for i in 0..<n { pr[i] = ar[i] * br[i] + ai[i] * bi[i]; pi[i] = ai[i] * br[i] - ar[i] * bi[i] }
        var cr = [Float](repeating: 0, count: n), ci = [Float](repeating: 0, count: n)
        vDSP_DFT_Execute(inverse, pr, pi, &cr, &ci)
        let scale = 1 / Float(n)
        // Circular lags: negative ones wrap to the end.
        return (0..<total).map { i in let k = i - (b.count - 1); return cr[k >= 0 ? k : n + k] * scale }
    }

    // MARK: Groups

    /// Takes linked by matches into groups. The sound take, whose sound the cut uses, is a sound-only
    /// take if there is one (a recorder beats a camera mic), otherwise the loudest; offsets are on its clock.
    public static func groups(_ matches: [(a: String, b: String, match: Match)], curves: [String: Curve], audioOnly: Set<String>, now: Double = Date().timeIntervalSince1970) -> [SyncGroup] {
        // Every take gets a place on one clock: clock time = take time + place. A match says
        // a = b + offset, so place(b) = place(a) + offset.
        var edges: [String: [(other: String, delta: Double, match: Double)]] = [:]
        for m in matches where m.match.isSameMoment {
            edges[m.a, default: []].append((m.b, m.match.offset, m.match.match))
            edges[m.b, default: []].append((m.a, -m.match.offset, m.match.match))
        }
        var seen = Set<String>(), out: [SyncGroup] = []
        for start in edges.keys.sorted() where !seen.contains(start) {
            var place: [String: (at: Double, match: Double)] = [start: (0, 1)], queue = [start]
            seen.insert(start)
            while !queue.isEmpty {
                let id = queue.removeFirst()
                for e in edges[id] ?? [] where place[e.other] == nil {
                    place[e.other] = (place[id]!.at + e.delta, min(e.match, place[id]!.match)); seen.insert(e.other); queue.append(e.other)
                }
            }
            guard place.count > 1 else { continue }
            let sound = place.keys.max { a, b in
                (audioOnly.contains(a) ? 1 : 0, curves[a]?.level ?? 0, a) < (audioOnly.contains(b) ? 1 : 0, curves[b]?.level ?? 0, b)
            }!
            // On the sound take's clock: sound time = take time + offset.
            let origin = place[sound]!.at
            let takes = place.map { id, p in SyncedTake(assetID: id, offset: ((p.at - origin) * 1000).rounded() / 1000, match: id == sound ? 1 : (p.match * 100).rounded() / 100) }
                .sorted { ($0.assetID != sound ? 1 : 0, $0.assetID) < ($1.assetID != sound ? 1 : 0, $1.assetID) }
            out.append(SyncGroup(id: newID("sync"), soundAssetID: sound, takes: takes, method: "sound", createdAt: now))
        }
        return out
    }

    // MARK: Helpers

    static func standardized(_ x: [Float]) -> [Float] {
        guard !x.isEmpty else { return x }
        let mean = vDSP.mean(x), centered = vDSP.add(-mean, x)
        let sd = (vDSP.sumOfSquares(centered) / Float(x.count)).squareRoot()
        return sd > 0 ? vDSP.divide(centered, sd) : centered
    }
    static func percentile(_ x: [Float], _ p: Double) -> Float {
        guard !x.isEmpty else { return 0 }
        let sorted = x.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }
}
