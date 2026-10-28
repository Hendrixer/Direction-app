import Foundation
@preconcurrency import AVFoundation
import Speech
import DirectionCore

public enum LocalTranscriber {
    public static func availability(language: String = "en-US") async -> JSONValue {
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
        let installed = await SpeechTranscriber.installedLocales
        return .object(["available": .bool(SpeechTranscriber.isAvailable && supported != nil), "language": .string(language), "installedLocales": .array(installed.map { .string($0.identifier) }), "provider": .string("Apple SpeechAnalyzer; on-device recognition")])
    }

    public static func transcribe(asset: MediaAsset, trackID: Int32, language: String, directory: URL) async throws -> SourceTranscript {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { throw DirectionError("transcription_unavailable", "Local transcription is unavailable for \(language) on this Mac. A timed transcript can also be imported.") }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
        try Task.checkCancellation()
        let path = try await AudioProcessor.extract(asset: asset, trackID: trackID, directory: directory)
        let file = try AVAudioFile(forReading: path)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task { () throws -> [TranscriptWord] in
            var words: [TranscriptWord] = []
            for try await result in transcriber.results {
                let text = result.text
                for run in text.runs {
                    let value = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, let time = run.audioTimeRange, time.duration.seconds > 0 else { continue }
                    let tokens = value.split(whereSeparator: \.isWhitespace).map(String.init)
                    for (i, token) in tokens.enumerated() {
                        let duration = CMTimeMultiplyByFloat64(time.duration, multiplier: 1 / Double(tokens.count))
                        let start = CMTimeAdd(time.start, CMTimeMultiplyByFloat64(duration, multiplier: Double(i)))
                        let end = min(asset.duration, MediaTime(CMTimeAdd(start, duration)))
                        if end > MediaTime(start) { words.append(.init(text: token, range: .init(start: .init(start), duration: end - MediaTime(start)))) }
                    }
                }
            }
            return words
        }
        do {
            try await withTaskCancellationHandler {
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
            var words = try await results.value.sorted { $0.range.start < $1.range.start }
            for i in words.indices.dropLast() where words[i].range.end > words[i + 1].range.start { words[i].range.duration = words[i + 1].range.start - words[i].range.start }
            words.removeAll { $0.range.duration <= .zero }
            guard !words.isEmpty else { throw DirectionError("no_speech", "No timed speech was recognized on this audio track.") }
            return .init(assetID: asset.id, audioTrackID: trackID, language: locale.identifier, provider: "apple-speech-analyzer", words: words)
        } catch { await analyzer.cancelAndFinishNow(); results.cancel(); throw error }
    }
}
