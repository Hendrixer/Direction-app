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
}
