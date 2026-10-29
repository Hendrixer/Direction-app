import Foundation
import DirectionCore

/// Whisper on this Mac through the `mlx_whisper` command (pip install mlx-whisper). Slower than
/// Apple's engine, with word times from Whisper itself rather than spread across a phrase.
public enum WhisperTranscriber {
    /// GUI apps don't get the shell's PATH, so look where pip, pipx and Homebrew put scripts.
    public static func executable() -> URL? {
        let home = NSHomeDirectory()
        var candidates = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let pythons = (try? FileManager.default.contentsOfDirectory(atPath: "\(home)/Library/Python")) ?? []
        candidates += pythons.sorted(by: >).map { "\(home)/Library/Python/\($0)/bin" }
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return candidates.lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("mlx_whisper") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// mlx_whisper decodes audio with ffmpeg.
    public static func ffmpeg() -> URL? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].lazy.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// True when the model's weights are already in the Hugging Face cache.
    public static func isDownloaded(_ model: String) -> Bool {
        let folder = "models--" + model.replacingOccurrences(of: "/", with: "--")
        let hub = ProcessInfo.processInfo.environment["HF_HUB_CACHE"] ?? NSHomeDirectory() + "/.cache/huggingface/hub"
        return FileManager.default.fileExists(atPath: hub + "/" + folder + "/snapshots")
    }

    public static func availability(model: String = SharedSettings.whisperModel) -> JSONValue {
        .object([
            "available": .bool(executable() != nil && ffmpeg() != nil),
            "executable": executable().map { .string($0.path) } ?? .null,
            "ffmpeg": .bool(ffmpeg() != nil),
            "model": .string(model),
            "downloaded": .bool(isDownloaded(model)),
            "provider": .string("Whisper through mlx-whisper; on-device"),
        ])
    }

    public static func transcribe(asset: MediaAsset, trackID: Int32, language: String, model: String, directory: URL) async throws -> SourceTranscript {
        guard let tool = executable() else { throw DirectionError("whisper_unavailable", "mlx_whisper isn't installed. Install it with `pip install mlx-whisper`, or choose Apple in Settings › Footage.") }
        guard let ffmpeg = ffmpeg() else { throw DirectionError("whisper_unavailable", "Whisper needs ffmpeg to read audio. Install it with `brew install ffmpeg`.") }
        let audio = try await AudioProcessor.extract(asset: asset, trackID: trackID, directory: directory)
        let output = directory.appendingPathComponent("Whisper").appendingPathComponent(newID("whisper"))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }

        // "en-US" → "en"; Whisper names languages by their two-letter code.
        let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
        let process = Process()
        process.executableURL = tool
        process.arguments = [audio.path, "--model", model, "--language", code, "--word-timestamps", "True", "--output-format", "json", "--output-dir", output.path, "--output-name", "words", "--verbose", "False"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ffmpeg.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in done.resume() }
                do { try process.run() } catch { process.terminationHandler = nil; done.resume(throwing: error) }
            }
        } onCancel: { process.terminate() }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.split(separator: "\n").last.map(String.init) ?? ""
            throw DirectionError("whisper_failed", "Whisper stopped before finishing. \(message)".trimmingCharacters(in: .whitespaces))
        }
        let data = try Data(contentsOf: output.appendingPathComponent("words.json"))
        let words = try words(fromWhisperJSON: data, duration: asset.duration)
        guard !words.isEmpty else { throw DirectionError("no_speech", "No timed speech was recognized on this audio track.") }
        return .init(assetID: asset.id, audioTrackID: trackID, language: language, provider: "mlx-whisper:" + (model.split(separator: "/").last.map(String.init) ?? model), words: words)
    }

    private struct Output: Decodable {
        struct Segment: Decodable { var words: [Word]? }
        struct Word: Decodable { var word: String; var start: Double; var end: Double }
        var segments: [Segment]
    }

    /// Whisper's JSON: segments[].words[] with seconds. Words start with a space; overlaps are trimmed.
    public static func words(fromWhisperJSON data: Data, duration: MediaTime) throws -> [TranscriptWord] {
        let output = try JSONDecoder().decode(Output.self, from: data)
        var words: [TranscriptWord] = []
        for word in output.segments.flatMap({ $0.words ?? [] }) {
            let text = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = MediaTime(seconds: max(0, word.start)), end = min(duration, MediaTime(seconds: word.end))
            guard !text.isEmpty, end > start else { continue }
            words.append(.init(text: text, range: .init(start: start, duration: end - start)))
        }
        words.sort { $0.range.start < $1.range.start }
        for i in words.indices.dropLast() where words[i].range.end > words[i + 1].range.start { words[i].range.duration = words[i + 1].range.start - words[i].range.start }
        words.removeAll { $0.range.duration <= .zero }
        return words
    }
}
