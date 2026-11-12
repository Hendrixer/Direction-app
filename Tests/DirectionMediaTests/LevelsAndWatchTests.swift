import Testing
import Foundation
import DirectionCore
import DirectionMedia
@testable import DirectionTools

/// What the runs of 11 Nov 2026 showed the editor needed: the level every frame in one call (it had measured a
/// narration 217 calls at a time to find its edges), and every changed passage watched in one call before
/// delivering (each run was refused once for a passage it hadn't watched).
@Suite(.serialized)
struct LevelsAndWatchTests {
    /// A take's own track and the cut's mix, every frame or every so often, in one answer.
    @Test func levelsEveryFrameInOneCall() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let tone = f.directory.appendingPathComponent("voice.wav")
        try MediaFixture.writeTone(to: tone, frequency: 440, seconds: 2, quiet: 1..<2)
        let asset = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(tone.path)])).value["asset"]
        let id = try #require(asset["id"].string)
        let take = try await f.runtime.invoke("direction_measure_audio", arguments: .object(["assetID": .string(id), "levels": .object(["start": .number(0), "end": .number(2), "every": .number(0.1)])])).value
        let peaks = (take["peakDBFS"].array ?? []).compactMap { $0.double }
        #expect(peaks.count == 20 && take["every"].double == 0.1 && take["start"].double == 0)
        // The tone is about −13 dBFS; the second second is silent.
        #expect(peaks.prefix(9).allSatisfy { $0 > -20 } && peaks.suffix(9).allSatisfy { $0 <= -100 }, "\(peaks)")
        // The cut's mix, one frame each by default.
        let cut = try await f.runtime.invoke("direction_measure_audio", arguments: .object(["levels": .object(["start": .number(0), "end": .number(2)])])).value
        #expect(cut["count"].double == 60 && abs((cut["every"].double ?? 0) - 1.0 / 30) < 0.0001 && cut["rmsDBFS"].array?.count == 60)
        // Bounded, and says how.
        do { _ = try await f.runtime.invoke("direction_measure_audio", arguments: .object(["levels": .object(["start": .number(0), "end": .number(2), "every": .number(0.0001)])])); Issue.record("too fine") }
        catch let e as DirectionError { #expect(e.code == "bad_argument") }
    }

    /// Delivering says what isn't watched and how to watch it all at once; changed: true does, and then it delivers.
    @Test func everyChangedPassageWatchedInOneCall() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        let p = try f.store.read()
        let note = try f.store.addComment(text: "Shorter.", sequenceID: nil, revision: p.editRevision, time: .init(seconds: 1), extra: NoteFields(kind: .pace))
        let turnover = try f.store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        let clip = try #require(p.sequences[0].clips.first { $0.kind != .audio })
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "notes": .array([.number(Double(note.number ?? 1))]),
                                                                            "operations": .array([.object(["op": .string("trim"), "clipID": .string(clip.id), "edge": .string("tail"), "frames": .number(-10)])])]))
        let deliver: () async throws -> ToolResponse = {
            try await f.runtime.invoke("direction_turnover_complete", arguments: .object(["turnoverID": .string(turnover.id), "answers": .array([.object(["noteID": .string(note.id), "summary": .string("Trimmed the end."), "start": .number(0), "end": .number(3)])])]))
        }
        do { _ = try await deliver(); Issue.record("Delivering must wait for the change to be watched") }
        catch let e as DirectionError { #expect(e.code == "not_watched" && e.message.contains("changed: true"), "\(e.message)") }
        let watched = try await f.runtime.invoke("direction_watch", arguments: .object(["changed": .bool(true)]))
        let passages = try #require(watched.value["passages"].array)
        #expect(!passages.isEmpty && watched.imagePaths.count == passages.count && passages.allSatisfy { $0["watched"].bool == true })
        let again = try await f.runtime.invoke("direction_watch", arguments: .object(["changed": .bool(true)]))
        #expect(again.value["passages"].array?.isEmpty == true && again.imagePaths.isEmpty)
        #expect(try await deliver().value["cut"] != .null)
    }
}
