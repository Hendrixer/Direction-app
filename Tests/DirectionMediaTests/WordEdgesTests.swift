import Testing
import Foundation
import DirectionCore
@testable import DirectionMedia
@testable import DirectionTools

/// A word starts where its sound does. Both speech engines put the pause before a phrase inside its first word
/// (on a real narration, 27 of 247 starts sat in silence, up to 2 s early; after, 1 by 0.24 s: 2026-11-12).
@Suite(.serialized)
struct WordEdgesTests {
    /// Sound for the first and third seconds, silence between, every 10 ms.
    static let rms: [Double] = (0..<300).map { (100..<200).contains($0) ? -120 : -20 }

    @Test func aWordStartsAndEndsWhereItsSoundDoes() {
        let words = [TranscriptWord(id: "a", text: "one", range: .init(start: 0.2, end: 0.9)),
                     // The pause before it is inside it, as the engines give it.
                     TranscriptWord(id: "b", text: "two", range: .init(start: 0.9, end: 2.5)),
                     // Its sound stops before it does.
                     TranscriptWord(id: "c", text: "three", range: .init(start: 2.6, end: 2.9))]
        let tight = WordEdges.tighten(words, rms: Self.rms)
        #expect(tight.map(\.id) == ["a", "b", "c"] && tight.map(\.text) == ["one", "two", "three"])
        #expect(tight[0].range == words[0].range && tight[2].range == words[2].range)
        #expect(abs(tight[1].range.start.seconds - 1.97) < 0.011 && abs(tight[1].range.end.seconds - 2.5) < 0.001, "\(tight[1].range)")
        // An end comes back to the sound, with a little tail.
        let trailing = WordEdges.tighten([TranscriptWord(id: "d", text: "end", range: .init(start: 0.5, end: 1.8))], rms: Self.rms)
        #expect(abs(trailing[0].range.end.seconds - 1.06) < 0.011 && trailing[0].range.start.seconds == 0.5)
        // Never outward, never over a neighbour, and a word with no sound in it stays.
        let silent = TranscriptWord(id: "e", text: "uh", range: .init(start: 1.2, end: 1.6))
        #expect(WordEdges.tighten([silent], rms: Self.rms) == [silent])
        // A take with nothing to tell speech from (music throughout): the words stay as they came.
        #expect(WordEdges.tighten(words, rms: [Double](repeating: -20, count: 300)) == words)
        #expect(WordEdges.threshold(Self.rms) == -50)
    }

    /// Apple's words meet exactly, in its own timescale, which isn't on Direction's grid: held to the sound, none
    /// may end a tick past the next one's start (the film refuses words that overlap).
    @Test func wordsThatMeetNeverOverlapAfter() {
        func t(_ frames: Int64) -> MediaTime { MediaTime(value: frames, timescale: 48_000) }
        // Odd frame counts land between ticks of 1/600000 s.
        let edges: [Int64] = [9_601, 43_201, 43_207, 120_001, 139_999]
        let words = (0..<4).map { TranscriptWord(id: "w\($0)", text: "w", range: .init(start: t(edges[$0]), duration: t(edges[$0 + 1] - edges[$0]))) }
        let tight = WordEdges.tighten(words, rms: Self.rms)
        for (a, b) in zip(tight, tight.dropFirst()) { #expect(a.range.end <= b.range.start, "\(a.range) \(b.range)") }
        for (was, now) in zip(words, tight) { #expect(now.range.start >= was.range.start && now.range.end <= was.range.end && now.range.isValid) }
        #expect(tight[2].range.start > words[2].range.start)
    }

    /// Two words cut together take the pause between them, in one clip; a kept word between them stays whole.
    @Test func cuttingWordsTakesThePauseBetweenThem() throws {
        func w(_ id: String, _ a: Double, _ b: Double, clip: String = "c1") throws -> TimelineWord {
            try JSONValue.object(["id": .string(id), "sourceWordID": .string(id), "clipID": .string(clip), "assetID": .string("a"), "text": .string(id), "range": try .wrapping(MediaRange(start: a, end: b))]).decode(TimelineWord.self)
        }
        let words = [try w("a", 0, 0.4), try w("b", 0.9, 1.3), try w("c", 1.8, 2.2), try w("d", 2.6, 3.0, clip: "c2")]
        let together = try TranscriptEditing.deletionRanges(wordIDs: ["a", "b"], words: words)
        #expect(together.count == 1 && together[0].start.seconds == 0 && abs(together[0].end.seconds - 1.3) < 0.0001)
        #expect(try TranscriptEditing.deletionRanges(wordIDs: ["a", "c"], words: words).count == 2)
        // Across clips, each word's own stretch: what's between two clips isn't theirs to take.
        #expect(try TranscriptEditing.deletionRanges(wordIDs: ["c", "d"], words: words).count == 2)
    }

    /// Transcribing, importing, and a transcript from before: all end with words on their sound, and the older one
    /// keeps its ids and which track was chosen.
    @Test func transcriptsAreHeldToTheSound() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let tone = f.directory.appendingPathComponent("voice.wav")
        try MediaFixture.writeTone(to: tone, frequency: 440, seconds: 3, quiet: 1..<2)
        let asset = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(tone.path)])).value["asset"]
        let id = try #require(asset["id"].string), track = try #require(asset["audio"].array?.first?["id"].int)
        let words = [TranscriptWord(id: "a", text: "one", range: .init(start: 0.2, end: 0.9)), TranscriptWord(id: "b", text: "two", range: .init(start: 0.9, end: 2.5))]
        // One from before: saved as the engine gave it.
        try f.store.saveTranscript(SourceTranscript(assetID: id, audioTrackID: Int32(track), words: words))
        let before = try #require(try f.store.transcripts().first { $0.assetID == id })
        #expect(before.edges == nil)
        let read = try await f.runtime.invoke("direction_transcript", arguments: .object(["assetID": .string(id)])).value
        #expect(read["words"].array?.map { $0["start"].double ?? 0 } == [0.2, 1.97] && read["words"].array?.map { $0["id"].string ?? "" } == ["a", "b"])
        let after = try #require(try f.store.transcripts().first { $0.assetID == id })
        #expect(after.edges == WordEdges.version && after.selectedAt == before.selectedAt)
        // Imported: held to the sound as it comes in.
        var imported = SourceTranscript(assetID: id, audioTrackID: Int32(track), words: words)
        imported.provider = "imported"
        _ = try await f.runtime.invoke("direction_import_transcript", arguments: .object(["transcript": try .wrapping(imported)]))
        let kept = try #require(try f.store.transcripts().first { $0.assetID == id })
        #expect(kept.edges == WordEdges.version && abs(kept.words[1].range.start.seconds - 1.97) < 0.011)
        // A transcript that changed while its sound was read isn't written over.
        var stale = kept; stale.words[0].text = "won"
        #expect(try f.store.retime(stale, from: words) == false)
    }
}
