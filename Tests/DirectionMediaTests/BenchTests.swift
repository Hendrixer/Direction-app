import Testing
import Foundation
import DirectionCore
import DirectionMedia
@testable import DirectionTools

/// The editor's work scored without a person (issue #6): the brief, the checks, the director's own cut, and what
/// got worse since the last scorecard.
@Suite("Bench", .serialized)
struct BenchTests {
    @Test func aCutIsScoredAgainstItsBriefItsChecksAndTheDirectorsCut() async throws {
        let f = try await MediaFixture.make()
        defer { f.cleanup() }
        let asset = try #require(try f.store.read().assets.first)
        try f.store.saveTranscript(.init(assetID: asset.id, audioTrackID: asset.audio.first?.id ?? 2, provider: "test", words: [
            TranscriptWord(id: "a", text: "We", range: .init(start: 0.2, end: 0.4)), TranscriptWord(id: "b", text: "made", range: .init(start: 0.45, end: 0.7)), TranscriptWord(id: "c", text: "it.", range: .init(start: 0.75, end: 1.0)),
        ]))
        var brief = Brief(); brief.logline = "A test"; brief.feeling = "Calm"; brief.lengthMax = 2; brief.mustKeep = ["We made it!", "the ridge"]
        try f.store.saveBrief(brief, styles: f.directory.appendingPathComponent("Styles"))
        // The director's cut is the take whole; the editor's is cut at 1.5 s and 2.4 s.
        _ = try f.store.createCut(name: "Director", sequenceID: nil, revision: nil)
        let first = try #require(try f.store.read().sequences[0].clips.first)
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Cut"), "operations": .array([
            .object(["op": .string("split"), "clipID": .string(first.id), "at": .number(1.5)]),
        ])]))
        _ = try f.store.createCut(name: "Cut 2", sequenceID: nil, revision: nil)

        let card = try await f.runtime.benchScore(cut: "Cut 2", reference: "Director")
        let m = card["measures"]
        #expect(m["lengthOffSeconds"].double == 1)
        #expect(m["mustKeepNotHeard"].double == 1 && card["mustKeep"].array?.first?["inTheWords"].bool == true, "\(card["mustKeep"])")
        // The split plays straight on, so the material is the same; its cut point isn't one of the director's.
        #expect(m["sameMaterial"].double == 1 && m["cutPointPrecision"].double == 0 && m["cutPointRecall"].double == 0, "\(m)")
        #expect(card["pace"]["shots"].double == 2 && m["soundOffTarget"] != .null && m["framingProblems"].double == 0)
        // The split plays straight on: no jump and no word cut.
        #expect(m["jumpCuts"].double == 0 && m["cutsInsideWords"].double == 0, "\(card["check"]["cuts"])")
    }

    @Test func whatGotWorseIsSaidInPlainWords() {
        func card(_ m: [String: Double]) -> JSONValue { .object(["measures": .object(m.mapValues(JSONValue.number))]) }
        let before = card(["jumpCuts": 1, "cutPointRecall": 0.8, "tokens": 100_000, "runSeconds": 600])
        let after = card(["jumpCuts": 3, "cutPointRecall": 0.9, "tokens": 120_000, "runSeconds": 900, "framingProblems": 2])
        #expect(Bench.worse(than: before, after) == ["jumpCuts went from 1 to 3", "runSeconds went from 600 to 900"])
        #expect(Bench.worse(than: after, before) == ["cutPointRecall went from 0.9 to 0.8"])
    }
}
