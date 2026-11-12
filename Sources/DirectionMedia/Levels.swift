import Foundation
import AVFoundation
import DirectionCore

/// The sound's level every frame (or every so many seconds) over a stretch: each window's sample peak and RMS in
/// dBFS. Where speech starts and stops is in the signal; a transcript's word times only approximate it (the editor
/// once measured a narration 217 calls at a time to find its edges, 2026-11-11).
public struct Levels: Sendable, Equatable {
    public var start: Double
    public var every: Double
    public var peakDBFS: [Double]
    public var rmsDBFS: [Double]

    public static let most = 6_000
    /// A window's level with nothing in it.
    public static let floor: Double = -120

    public var json: JSONValue {
        .object(["start": .number(start), "every": .number((every * 1_000_000).rounded() / 1_000_000), "count": .number(Double(peakDBFS.count)),
                 "peakDBFS": .array(peakDBFS.map { .number($0.rounded()) }), "rmsDBFS": .array(rmsDBFS.map { .number($0.rounded()) })])
    }
}

/// Windows of `window` sample frames, any number of channels, fed buffer by buffer.
struct LevelMeter {
    let window: Int
    private var peak: Float = 0, squares: Double = 0, filled = 0, values = 0
    private(set) var peaks: [Double] = [], rms: [Double] = []
    init(window: Int) { self.window = max(1, window) }

    mutating func add(_ value: Float) { peak = max(peak, abs(value)); squares += Double(value) * Double(value); values += 1 }
    mutating func endFrame() {
        filled += 1
        if filled == window { flush() }
    }
    mutating func flush() {
        guard filled > 0 else { return }
        peaks.append(peak > 0 ? max(Levels.floor, 20 * log10(Double(peak))) : Levels.floor)
        let mean = squares / Double(max(1, values))
        rms.append(mean > 0 ? max(Levels.floor, 10 * log10(mean)) : Levels.floor)
        peak = 0; squares = 0; filled = 0; values = 0
    }
}

extension AudioProcessor {
    /// A take's track, start to end in its own seconds.
    public static func levels(asset: MediaAsset, trackID: Int32, start: Double, end: Double, every: Double, directory: URL) async throws -> Levels {
        let path = try await extract(asset: asset, trackID: trackID, directory: directory)
        let file = try AVAudioFile(forReading: path)
        let rate = file.processingFormat.sampleRate, channels = Int(file.processingFormat.channelCount)
        let first = AVAudioFramePosition((start * rate).rounded()), last = min(file.length, AVAudioFramePosition((end * rate).rounded()))
        guard first < last else { throw DirectionError("invalid_range", "Measure a stretch inside the take: it\u{2019}s \(String(format: "%.2f", Double(file.length) / rate)) s long.") }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192) else { throw DirectionError("audio_buffer_failed", "Cannot allocate a buffer to measure.") }
        file.framePosition = first
        var meter = LevelMeter(window: Int((every * rate).rounded())), left = last - first
        while left > 0 {
            try Task.checkCancellation()
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(buffer.frameCapacity), left)))
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            for i in 0..<n {
                for c in 0..<channels { meter.add(data[c][i]) }
                meter.endFrame()
            }
            left -= Int64(n)
        }
        meter.flush()
        return Levels(start: start, every: every, peakDBFS: meter.peaks, rmsDBFS: meter.rms)
    }
}

extension SequenceRenderer {
    /// The cut's mix as it plays and delivers, over a stretch in cut seconds.
    public static func levels(_ compiled: CompiledSequence, range: MediaRange, every: Double) async throws -> Levels {
        guard range.isValid, range.duration > .zero, range.end <= compiled.sequence.duration else { throw DirectionError("invalid_range", "Measure a stretch inside the cut.") }
        let tracks = try await compiled.composition.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw DirectionError("no_audio", "The cut has no enabled audio.") }
        let reader = try AVAssetReader(asset: compiled.composition)
        reader.timeRange = range.cmRange
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings); mix.audioMix = compiled.audioMix
        reader.add(mix)
        guard reader.startReading() else { throw reader.error ?? DirectionError("measure_failed", "Cannot read the cut\u{2019}s sound.") }
        var meter = LevelMeter(window: Int((every * 48_000).rounded())), samples: [Float] = []
        do {
            while let sample = await mix.nextSample(of: reader) {
                try Task.checkCancellation()
                guard let data = CMSampleBufferGetDataBuffer(sample) else { continue }
                let frames = CMSampleBufferGetNumSamples(sample), n = frames * 2
                if samples.count != n { samples = [Float](repeating: 0, count: n) }
                guard samples.withUnsafeMutableBytes({ CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }) == kCMBlockBufferNoErr else { throw DirectionError("measure_failed", "The cut\u{2019}s sound came back unreadable.") }
                for i in 0..<frames { meter.add(samples[2 * i]); meter.add(samples[2 * i + 1]); meter.endFrame() }
            }
            try ReadStall.check(reader, "the cut\u{2019}s sound")
            guard reader.status == .completed else { throw reader.error ?? DirectionError("measure_failed", "Measuring the cut\u{2019}s sound stopped.") }
        } catch { ReadStall.cancel(reader); throw error }
        meter.flush()
        return Levels(start: range.start.seconds, every: every, peakDBFS: meter.peaks, rmsDBFS: meter.rms)
    }
}
