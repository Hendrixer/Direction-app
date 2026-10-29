import Testing
import Foundation
import DirectionCore
import DirectionMedia

struct WhisperTests {
    @Test func whisperWordsBecomeTimedWordsWithoutOverlaps() throws {
        let json = """
        {"text": " Not yet. Look up.", "language": "en", "segments": [
          {"id": 0, "start": 0.0, "end": 1.2, "text": " Not yet.", "words": [
            {"word": " Not", "start": 0.12, "end": 0.40, "probability": 0.98},
            {"word": " yet.", "start": 0.36, "end": 0.90, "probability": 0.95}]},
          {"id": 1, "start": 1.2, "end": 3.0, "text": " Look up.", "words": [
            {"word": " Look", "start": 1.30, "end": 1.62, "probability": 0.97},
            {"word": " ", "start": 1.62, "end": 1.70, "probability": 0.10},
            {"word": " up.", "start": 1.70, "end": 9.00, "probability": 0.96}]},
          {"id": 2, "start": 3.0, "end": 3.5, "text": ""}
        ]}
        """
        let words = try WhisperTranscriber.words(fromWhisperJSON: Data(json.utf8), duration: MediaTime(seconds: 2.5))
        #expect(words.map(\.text) == ["Not", "yet.", "Look", "up."])
        // "Not" ran into "yet.", so it ends where "yet." starts.
        #expect(abs(words[0].range.end.seconds - 0.36) < 0.001)
        // The last word is clipped to the footage.
        #expect(abs(words[3].range.end.seconds - 2.5) < 0.001)
    }

    @Test func sharedSettingsDefaultToApple() {
        let real = SharedSettings.defaults, suite = "dev.direction.tests.\(UUID().uuidString)"
        SharedSettings.defaults = UserDefaults(suiteName: suite)!
        defer { SharedSettings.defaults.removePersistentDomain(forName: suite); SharedSettings.defaults = real }
        #expect(SharedSettings.transcriptionEngine == .apple)
        #expect(SharedSettings.whisperModel == "mlx-community/whisper-large-v3-turbo")
    }

    @Test func whisperRunsThroughThePythonBehindItsCommand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("mlx_whisper"), link = dir.appendingPathComponent("linked")
        try "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: script)
        #expect(WhisperTranscriber.interpreter(for: link)?.path == "/bin/sh")
        // `#!/usr/bin/env python3` names a program, not a path: the command line serves then.
        try "#!/usr/bin/env python3\n".write(to: script, atomically: true, encoding: .utf8)
        #expect(WhisperTranscriber.interpreter(for: script) == nil)
    }

    @Test func theWhisperScriptIsValidPythonAndAsksForTheLoopSafeSettings() throws {
        #expect(WhisperTranscriber.script.contains("condition_on_previous_text=False"))
        #expect(WhisperTranscriber.script.contains("hallucination_silence_threshold=2.0"))
        // The command line's single temperature is what let loops run on; the library's default list must stay.
        #expect(!WhisperTranscriber.script.contains("temperature"))
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", "import ast, sys; ast.parse(sys.argv[1])", WhisperTranscriber.script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    @Test func aTranscriptStuckInALoopIsCaughtAndRealSpeechIsNot() {
        func transcript(_ text: String) -> SourceTranscript {
            let words = text.split(separator: " ").enumerated().map { i, w in TranscriptWord(text: String(w), range: .init(start: MediaTime(seconds: Double(i) * 0.3), duration: MediaTime(seconds: 0.25))) }
            return SourceTranscript(assetID: "a", audioTrackID: 1, words: words)
        }
        let speech = "Imagine being a scientist and the system you work with comes back with a discovery nobody was looking for. You gave it one problem. While it worked on that it found something else, figured out how to test it, and now it is explaining the result. I think a change that large could happen in less than thirty years. I think a change that large could happen in less than thirty years. If the systems doing research get good at improving themselves, the pace could be hard to imagine. A century of discoveries in a month is the kind of possibility worth taking seriously."
        let loop = String(repeating: "but I'm going to go into too much detail on this, ", count: 12)
        #expect(!transcript(speech).looksLooped)
        #expect(transcript(speech + " " + loop).looksLooped)
        // Too short to judge.
        #expect(!transcript("yes yes yes yes").looksLooped)
    }

    @Test func aTakesOwnWordsCanBeReadBeforeThereIsACut() async throws {
        let fixture = try await MediaFixture.make(); defer { fixture.cleanup() }
        let asset = try #require(try fixture.store.read().assets.first)
        let words = ["Not", "yet.", "Look", "up."].enumerated().map { i, w in TranscriptWord(text: w, range: .init(start: MediaTime(seconds: Double(i) * 0.5), duration: MediaTime(seconds: 0.4))) }
        try fixture.store.saveTranscript(SourceTranscript(assetID: asset.id, audioTrackID: try #require(asset.audio.first?.id), provider: "test", words: words))
        let page = try await fixture.runtime.invoke("direction_transcript", arguments: .object(["assetID": .string(asset.id), "limit": .number(3)])).value
        #expect(page["text"].string == "Not yet. Look")
        #expect(page["total"].int == 4)
        #expect(page["nextOffset"].int == 3)
        #expect(page["words"].array?.last?["start"].double == 1)
    }

    @Test func transcriptionJobsNameTheirTakeAndOldJobsStillRead() throws {
        let old = #"{"id":"job-1","kind":"transcription","revision":3,"ownerPID":1,"status":"interrupted","phase":"The process running this job exited","createdAt":1,"updatedAt":2}"#
        let job = try JSONDecoder().decode(JobRecord.self, from: Data(old.utf8))
        #expect(job.assetID == nil)
        var named = job; named.assetID = "asset-1"
        let again = try JSONDecoder().decode(JobRecord.self, from: try JSONEncoder().encode(named))
        #expect(again.assetID == "asset-1")
    }

    @Test func theLogMasksKeysAndStaysOutOfTheRealLibraryInTests() throws {
        #expect(!DirectionLog.directory.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs").path))
        #expect(DirectionLog.redact("key sk-or-v1-0123456789abcdef and Bearer abc.def-123") == "key ••• and •••")
        let marker = "marker-\(UUID().uuidString)"
        DirectionLog.error("Request failed with sk-or-v1-0123456789abcdef \(marker)", "tests")
        let line = try #require(DirectionLog.tail(500).last { $0.contains(marker) })
        #expect(line.contains("ERROR [tests]"))
        #expect(!line.contains("sk-or-"))
    }
}
