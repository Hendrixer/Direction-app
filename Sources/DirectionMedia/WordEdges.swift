import Foundation
import AVFoundation
import Accelerate
import DirectionCore

/// A word's times, held to the take's own sound. Both speech engines put the silence before a phrase inside that
/// phrase's first word: on a narration with 48 pauses, 31 of Apple's word starts and 38 of Whisper's sat in
/// silence, up to 1.95 s early, while the ends were right (2026-11-11). So cuts "inside a word" were reported in
/// silence, half the real pause time went missing, and the editor measured the sound itself. Each word now starts
/// where its sound does and ends where it stops, once, when the transcript is made.
public enum WordEdges {
    /// The version written to a transcript checked this way.
    public static let version = 1
    /// The sound's level every 10 ms.
    public static let every = 0.01
    /// A word has at least this much sound (50 ms), so a click isn't one; this much quiet (250 ms) is a pause.
    static let hold = 5, pause = 25
    static let lead = 0.03, tail = 0.06, shortest = 0.08

    /// The level speech is over, from the take itself: well above its room (its quietest fifth of a second) and
    /// well under its speech (the level it's over a tenth of the time). Nil when the two are too close to tell
    /// apart (music throughout, a noisy room), and the words stay as they came.
    static func threshold(_ rms: [Double]) -> Double? {
        let span = 20
        guard rms.count >= span * 3 else { return nil }
        var sum = rms[0..<span].reduce(0, +), quietest = sum
        for i in span..<rms.count { sum += rms[i] - rms[i - span]; quietest = min(quietest, sum) }
        let room = max(-90, quietest / Double(span)), speech = rms.sorted()[rms.count * 9 / 10]
        guard speech - room >= 24 else { return nil }
        return min(max(room + 12, speech - 30), speech - 18)
    }

    /// The words with their edges moved in to the sound: a start forward to where speech begins, an end back to
    /// where it stops. Never outward, never past a neighbour, never to less than a short word, and a word with no
    /// sound found in it stays as it was. `rms` is the take's level every `every` seconds from its start.
    public static func tighten(_ words: [TranscriptWord], rms: [Double], every: Double = WordEdges.every) -> [TranscriptWord] {
        guard let threshold = threshold(rms) else { return words }
        return words.map { word in
            let from = max(0, Int((word.range.start.seconds / every).rounded(.down))), to = min(rms.count, Int((word.range.end.seconds / every).rounded(.up)))
            guard to - from > hold, let last = (from..<to).last(where: { rms[$0] >= threshold }) else { return word }
            // Back from where its sound stops to the pause before it: what's on the far side of a pause is the tail of
            // the word before (the engines' ends are right; it's the starts that take in the pause).
            var first = last, quiet = 0, heard = 0
            for i in stride(from: last, through: from, by: -1) {
                if rms[i] >= threshold { first = i; quiet = 0; heard += 1 } else { quiet += 1; if quiet >= pause { break } }
            }
            guard heard >= hold else { return word }
            var start = max(word.range.start.seconds, Double(first) * every - lead), end = min(word.range.end.seconds, Double(last + 1) * every + tail)
            if end - start < shortest {
                // A short sound in a long stretch: keep it whole, inside what the engine gave.
                let middle = (start + end) / 2
                start = max(word.range.start.seconds, middle - shortest / 2); end = min(word.range.end.seconds, start + shortest)
            }
            // In the engine's own times where an edge stays (Apple's aren't on Direction's grid, and its words meet
            // exactly), and never outside them: a word rounded a tick past its neighbour would overlap it.
            let begins = max(word.range.start, MediaTime(seconds: start)), ends = min(word.range.end, MediaTime(seconds: end))
            guard ends > begins, begins >= word.range.start, ends <= word.range.end else { return word }
            if begins == word.range.start && ends == word.range.end { return word }
            var out = word
            out.range = MediaRange(start: begins, duration: ends - begins)
            return out.range.end <= word.range.end && out.range.isValid ? out : word
        }
    }

    /// A transcript with its words held to the take's sound, marked so it's done once.
    public static func tighten(_ transcript: SourceTranscript, asset: MediaAsset, directory: URL) async throws -> SourceTranscript {
        var out = transcript
        out.edges = version
        guard !transcript.words.isEmpty else { return out }
        let rms = try await level(asset: asset, trackID: transcript.audioTrackID, directory: directory)
        out.words = tighten(transcript.words, rms: rms, every: every).map { w in
            // Inside the recording, as the film keeps it.
            var w = w
            if w.range.end > asset.duration { w.range = MediaRange(start: w.range.start, duration: asset.duration - w.range.start) }
            return w
        }.filter { $0.range.duration > .zero }
        return out
    }

    /// The whole take's RMS every 10 ms, in dBFS: an hour in about a second.
    static func level(asset: MediaAsset, trackID: Int32, directory: URL) async throws -> [Double] {
        let path = try await AudioProcessor.extract(asset: asset, trackID: trackID, directory: directory)
        let file = try AVAudioFile(forReading: path)
        let channels = Int(file.processingFormat.channelCount), window = max(1, Int((every * file.processingFormat.sampleRate).rounded()))
        guard channels > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(window * 256)) else { throw DirectionError("audio_buffer_failed", "Cannot allocate a buffer to measure.") }
        var out: [Double] = []
        out.reserveCapacity(Int(file.length) / window + 1)
        while file.framePosition < file.length {
            try Task.checkCancellation()
            buffer.frameLength = 0
            try file.read(into: buffer)
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            var at = 0
            while at < n {
                let count = min(window, n - at)
                var sum: Float = 0
                for c in 0..<channels { var mean: Float = 0; vDSP_measqv(data[c] + at, 1, &mean, vDSP_Length(count)); sum += mean }
                let mean = Double(sum) / Double(channels)
                out.append(mean > 0 ? max(Levels.floor, 10 * log10(mean)) : Levels.floor)
                at += count
            }
        }
        return out
    }
}
