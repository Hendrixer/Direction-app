import Foundation
@preconcurrency import AVFoundation
@preconcurrency import SoundAnalysis
import DirectionCore

/// Step 5: sounds. Apple's built-in classifier in 1 s windows; runs of the same kind merge, and the
/// top label maps to the seven kinds in `Sound`. Loudness per second is kept for the strip.
public enum SoundIndexer {
    /// SoundAnalysis labels → kinds. Labels not listed here say nothing a director would search for.
    public static func kind(for label: String) -> SoundKind? {
        let l = label.lowercased()
        if ["silence"].contains(l) { return .silence }
        if l.contains("laugh") || l == "giggling" || l == "chuckle_chortle" || l == "snicker" { return .laughter }
        if ["speech", "conversation", "narration_monologue", "shout", "yell", "whispering", "babbling", "battle_cry", "children_shouting", "screaming", "crowd"].contains(l) { return .speech }
        if l.contains("applause") || l == "clapping" || l == "cheering" || l == "finger_snapping" { return .applause }
        if l.contains("wind") || l == "rustling_leaves" { return .wind }
        if l.contains("traffic") || l.contains("car") || l.contains("vehicle") || l.contains("truck") || l.contains("bus") || l.contains("motorcycle") || l.contains("engine") || l.contains("siren") || l == "horn" || l.contains("train") { return .traffic }
        if l.contains("music") || l.contains("guitar") || l.contains("piano") || l.contains("drum") || l.contains("violin") || l.contains("cello") || l.contains("orchestra") || l.contains("singing") || l.contains("choir") || l.contains("synthesizer") || l.contains("bass") || l.contains("trumpet") || l.contains("saxophone") || l.contains("flute") || l.contains("organ") || l.contains("harp") || l.contains("ukulele") || l.contains("banjo") || l.contains("rapping") || l.contains("humming") || l == "hip_hop_music" { return .music }
        return nil
    }

    /// One classified second, before merging.
    public struct Window: Sendable, Equatable {
        public var start: Double; public var end: Double; public var label: String; public var confidence: Double
        public init(start: Double, end: Double, label: String, confidence: Double) { self.start = start; self.end = end; self.label = label; self.confidence = confidence }
    }

    /// Pure: windows → runs. Quiet seconds become silence; neighbors of the same kind merge.
    public static func merge(_ windows: [Window], loudness: [Float], assetID: String) -> [IndexSound] {
        var out: [IndexSound] = []
        for w in windows.sorted(by: { $0.start < $1.start }) {
            let second = Int(w.start)
            let quiet = second < loudness.count && loudness[second] < -50
            guard let kind = quiet ? .silence : kind(for: w.label) else { continue }
            if var last = out.last, last.kind == kind, w.start - last.end < 0.75 {
                last.end = max(last.end, w.end); last.confidence = max(last.confidence, w.confidence)
                out[out.count - 1] = last
            } else {
                out.append(IndexSound(assetID: assetID, start: w.start, end: w.end, kind: kind, label: quiet ? "silence" : w.label, confidence: quiet ? 1 : w.confidence))
            }
        }
        return out
    }

    /// Classifies a take's first unmuted track. Returns its runs and loudness per second.
    public static func analyze(_ asset: MediaAsset, cacheDirectory: URL) async throws -> (sounds: [IndexSound], loudness: [Float]) {
        guard let track = asset.audio.first(where: { !$0.settings.muted }) ?? asset.audio.first else { return ([], []) }
        let file = try await AudioProcessor.extract(asset: asset, trackID: track.id, directory: cacheDirectory)
        let loudness = try loudness(file)
        let windows = try await classify(file)
        return (merge(windows, loudness: loudness, assetID: asset.id), loudness)
    }

    /// dBFS per second from the PCM itself.
    public static func loudness(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate, channels = Int(file.processingFormat.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(rate)) else { return [] }
        var out: [Float] = []
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(rate))
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            var sum: Float = 0
            for c in 0..<channels { for i in 0..<n { let v = data[c][i]; sum += v * v } }
            let rms = (sum / Float(max(1, n * channels))).squareRoot()
            out.append(rms > 0 ? max(-90, 20 * log10(rms)) : -90)
        }
        return out
    }

    public static func classify(_ url: URL) async throws -> [Window] {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1, preferredTimescale: 48_000)
        request.overlapFactor = 0
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let observer = Observer()
        try analyzer.add(request, withObserver: observer)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<[Window], Error>) in
                observer.finish = { result in done.resume(with: result) }
                analyzer.analyze { _ in }
            }
        } onCancel: { analyzer.cancelAnalysis() }
    }

    private final class Observer: NSObject, SNResultsObserving, @unchecked Sendable {
        var windows: [Window] = []
        var finish: ((Result<[Window], Error>) -> Void)?
        private var finished = false
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult, let top = r.classifications.first else { return }
            windows.append(Window(start: r.timeRange.start.seconds, end: r.timeRange.end.seconds, label: top.identifier, confidence: top.confidence))
        }
        func request(_ request: SNRequest, didFailWithError error: Error) { done(.failure(error)) }
        func requestDidComplete(_ request: SNRequest) { done(.success(windows)) }
        private func done(_ result: Result<[Window], Error>) { guard !finished else { return }; finished = true; finish?(result) }
    }
}
