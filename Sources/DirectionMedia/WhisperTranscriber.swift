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

    /// The Python that runs the `mlx_whisper` script, read from its first line, so Direction can call
    /// Whisper's own `transcribe` with the settings its command line can't pass.
    public static func interpreter(for tool: URL) -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: tool.resolvingSymlinksInPath()), let head = try? handle.read(upToCount: 512) else { return nil }
        try? handle.close()
        guard let line = String(decoding: head, as: UTF8.self).split(separator: "\n").first, line.hasPrefix("#!") else { return nil }
        let path = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        // `#!/usr/bin/env python3` names the program rather than a path; the command line serves then.
        guard !path.contains(" "), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Whisper's command line decodes at one temperature, so when a window starts repeating itself
    /// nothing catches it, and with each window primed by the last the loop runs on to the end of the
    /// take. This asks for the library's fallback temperatures (a window that compresses too well is
    /// decoded again), starts each window fresh, and skips silences where it would make words up.
    public static let script = """
    import json, sys, mlx_whisper
    audio, model, language, out = sys.argv[1:5]
    result = mlx_whisper.transcribe(audio, path_or_hf_repo=model, language=language, word_timestamps=True,
        condition_on_previous_text=False, hallucination_silence_threshold=2.0, verbose=None)
    with open(out, "w") as f:
        json.dump({"segments": [{"words": [{"word": w["word"], "start": float(w["start"]), "end": float(w["end"])} for w in s.get("words", [])]} for s in result["segments"]]}, f)
    """

    public static func transcribe(asset: MediaAsset, trackID: Int32, language: String, model: String, directory: URL) async throws -> SourceTranscript {
        guard let tool = executable() else { throw DirectionError("whisper_unavailable", "mlx_whisper isn't installed. Install it with `pip install mlx-whisper`, or choose Apple in Settings › Engines.") }
        guard let ffmpeg = ffmpeg() else { throw DirectionError("whisper_unavailable", "Whisper needs ffmpeg to read audio. Install it with `brew install ffmpeg`.") }
        let audio = try await AudioProcessor.extract(asset: asset, trackID: trackID, directory: directory)
        let output = directory.appendingPathComponent("Whisper").appendingPathComponent(newID("whisper"))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let words = output.appendingPathComponent("words.json")

        // "en-US" → "en"; Whisper names languages by their two-letter code.
        let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
        let process = Process()
        if let python = interpreter(for: tool) {
            process.executableURL = python
            process.arguments = ["-I", "-c", script, audio.path, model, code, words.path]
        } else {
            process.executableURL = tool
            process.arguments = [audio.path, "--model", model, "--language", code, "--word-timestamps", "True", "--condition-on-previous-text", "False", "--hallucination-silence-threshold", "2", "--output-format", "json", "--output-dir", output.path, "--output-name", "words", "--verbose", "False"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ffmpeg.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        // Once the model is here, don't ask the Hugging Face hub about it again: that can hang offline.
        if isDownloaded(model) { environment["HF_HUB_OFFLINE"] = "1" }
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        process.environment = environment
        // Keep reading what it says so a chatty run can't fill the pipe and stall.
        let errors = Pipe(), tail = ErrorTail()
        errors.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if d.isEmpty { h.readabilityHandler = nil } else { tail.append(d) } }
        defer { errors.fileHandleForReading.readabilityHandler = nil }
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { p in ChildProcesses.ended(p); done.resume() }
                do { try process.run(); ChildProcesses.started(process) } catch { process.terminationHandler = nil; done.resume(throwing: error) }
            }
        } onCancel: { process.terminate() }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw DirectionError("whisper_failed", "Whisper stopped before finishing. \(tail.last)".trimmingCharacters(in: .whitespaces))
        }
        let timed = try self.words(fromWhisperJSON: try Data(contentsOf: words), duration: asset.duration)
        guard !timed.isEmpty else { throw DirectionError("no_speech", "No timed speech was recognized on this audio track.") }
        return .init(assetID: asset.id, audioTrackID: trackID, language: language, provider: "mlx-whisper:" + (model.split(separator: "/").last.map(String.init) ?? model), words: timed)
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
