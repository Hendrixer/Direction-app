import Testing
import Foundation
@testable import DirectionCore

// The editor's timeline (agent-timeline.md): every edit function, every error, locks, notes per
// revision, and the OpenTimelineIO the editor reads.

/// Three takes on V1 (1A T1 and 1B T2 in scene 1, 2A T1 in scene 2), a fifth take of 1A with the same
/// line, and music under everything on A2. 30 fps, 1920×1080.
///   c1  a 2–6 s   at 0–4      "We waited two years." at 1.0, 1.4, 2.6, 3.0
///   c2  b 3–8 s   at 4–9
///   c3  c 1–5 s   at 9–13
///   m1  music 0–13 at 0–13 on A2
struct TimelineCut {
    var project: Project
    var context: EditContext

    static func make() -> TimelineCut {
        var p = Project(name: "Timeline")
        func take(_ id: String, _ seconds: Double, video: Bool = true) -> MediaAsset {
            MediaAsset(id: id, name: id + ".mov", path: "/\(id).mov", duration: .init(seconds: seconds), video: video ? [.init(id: 1, width: 1920, height: 1080, frameRate: 30)] : [], audio: [.init(id: 2, index: 0, label: "Dialogue", channels: 1, sampleRate: 48_000)])
        }
        p.assets = [take("a", 20), take("b", 20), take("c", 20), take("d", 20), take("music", 30, video: false)]
        p.sequences[0].clips = [
            Clip(id: "c1", assetID: "a", name: "a", start: .zero, sourceRange: .init(start: 2, end: 6)),
            Clip(id: "c2", assetID: "b", name: "b", start: .init(seconds: 4), sourceRange: .init(start: 3, end: 8)),
            Clip(id: "c3", assetID: "c", name: "c", start: .init(seconds: 9), sourceRange: .init(start: 1, end: 5)),
            Clip(id: "m1", assetID: "music", name: "Felt piano", kind: .audio, layer: 1, start: .zero, sourceRange: .init(start: 0, end: 13)),
        ]
        var dailies = Dailies(scenes: [DailiesScene(id: "s1", number: 1, title: "Cold open"), DailiesScene(id: "s2", number: 2, title: "Launch day")], takes: [:])
        for (asset, scene, setup, code) in [("a", "s1", "1A", "T1"), ("b", "s1", "1B", "T2"), ("c", "s2", "2A", "T1"), ("d", "s1", "1A", "T5")] {
            var t = TakeInfo(assetID: asset); t.sceneID = scene; t.setupCode = setup; t.code = code; dailies.takes[asset] = t
        }
        func line(_ asset: String, _ starts: [Double]) -> SourceTranscript {
            SourceTranscript(assetID: asset, audioTrackID: 2, words: zip(["We", "waited", "two", "years."], starts).enumerated().map { i, w in TranscriptWord(id: "\(asset)-w\(i)", text: w.0, range: .init(start: w.1, end: w.1 + 0.3)) })
        }
        return TimelineCut(project: p, context: EditContext(transcripts: [line("a", [3.0, 3.4, 4.6, 5.0]), line("d", [7.13, 7.6, 8.9, 9.25])], dailies: dailies, noteNumbers: [1, 2]))
    }

    func run(_ ops: [String], notes: [Int]? = [1]) throws -> (Project, EditResult) {
        try EditReducer.run(EditBatch(baseEditRevision: 0, notes: notes, operations: ops.map { try op($0) }), on: project, context: context)
    }
    @discardableResult mutating func apply(_ ops: String...) throws -> EditResult { let (p, r) = try run(ops); project = p; return r }
}

func op(_ text: String) throws -> EditOperation { try EditOperation(json: JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) }
func clip(_ p: Project, _ id: String) -> Clip { p.sequences[0].clips.first { $0.id == id }! }
func expectFailure(_ code: String, index: Int?, _ body: () throws -> Void) {
    do { try body(); Issue.record("Expected \(code)") }
    catch let e as DirectionError { #expect(e.code == code, "\(e.code): \(e.message)"); #expect(e.index == index, "index \(String(describing: e.index))") }
    catch { Issue.record("Unexpected error: \(error)") }
}
func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

// MARK: Older films

@Test func olderFilmsAndBatchesStillDecode() throws {
    let old = #"{"schemaVersion":1,"id":"project-x","name":"Old","editRevision":3,"createdAt":0,"assets":[{"id":"a","name":"a.mov","path":"/a.mov","duration":{"value":600,"timescale":60},"video":[{"id":1,"width":320,"height":180,"frameRate":30}],"audio":[],"fileSize":0,"modifiedAt":0,"isImage":false}],"sequences":[{"id":"s","name":"Main edit","width":320,"height":180,"frameRate":{"numerator":30,"denominator":1},"clips":[{"id":"c","lineageID":"c","assetID":"a","name":"a","kind":"video","layer":0,"start":{"value":0,"timescale":1},"sourceRange":{"start":{"value":0,"timescale":1},"duration":{"value":4,"timescale":1}},"speed":1,"grade":{"exposure":0,"contrast":1,"saturation":1,"temperature":0,"tint":0},"framing":{"fit":true,"scale":1,"offsetX":0,"offsetY":0,"opacity":1},"audioOverrides":{}}]}]}"#
    let p = try JSONDecoder().decode(Project.self, from: Data(old.utf8))
    let c = p.sequences[0].clips[0]
    #expect(c.effects == nil && c.transition == nil && c.hold == nil && c.gainKeys == nil && c.aboveLook == nil)
    #expect(c.trackName == "V1" && c.duration == MediaTime(seconds: 4) && c.soundRange == c.range)
    #expect(p.sequences[0].tracks == nil && p.assets[0].cameraLUT == nil && p.assets[0].graphic == nil)
    try EditReducer.validate(p)
    // A batch from before edit functions keeps its meaning: insert places without rippling.
    let batch = try JSONDecoder().decode(EditBatch.self, from: Data(#"{"baseEditRevision":3,"idempotencyKey":"k","summary":"s","operations":[{"type":"insert","assetID":"a","at":{"value":4,"timescale":1}}]}"#.utf8))
    #expect(batch.operations[0].legacy && batch.notes == nil)
    let after = try EditReducer.apply(batch, to: p)
    #expect(after.sequences[0].clips.count == 2 && after.sequences[0].clips[0].start == .zero && after.sequences[0].duration == MediaTime(seconds: 14))
    // Edits round-trip through JSON with times as {value, timescale}.
    let trim = try op(#"{"op":"transition","editPoint":"a|b","type":"dissolve","frames":12,"note":4}"#)
    #expect(try JSONDecoder().decode(EditOperation.self, from: JSONEncoder.direction.encode(trim)) == trim && trim.transitionType == "dissolve" && !trim.legacy)
    expectFailure("bad_argument", index: nil) { _ = try op(#"{"op":"trim","clipID":"c1","colour":"red"}"#) }
}

// MARK: Story

@Test func insertRipplesEveryTrackAndReportsWhereItLanded() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"insert","assetID":"d","sourceRange":{"start":1,"end":3},"at":4}"#)
    let s = cut.project.sequences[0]
    #expect(clip(cut.project, "c2").start == MediaTime(seconds: 6) && clip(cut.project, "c3").start == MediaTime(seconds: 11) && s.duration == MediaTime(seconds: 15))
    // The music under the insert point splits and its tail moves with the story.
    let music = s.clips.filter { $0.assetID == "music" }.sorted { $0.start < $1.start }
    #expect(music.count == 2 && music[1].start == MediaTime(seconds: 6) && music[1].sourceRange.start == MediaTime(seconds: 4))
    let o = r.operations[0]
    #expect(o.changes[0].new == SecondsRange(start: 4, end: 6) && o.changes[0].old == SecondsRange(start: 4, end: 4))
    #expect(o.delta == 2 && o.deltaText == "+2.0 s" && o.notes == [1] && o.changes[0].scenes == [1] && o.clipIDs?.count == 1)
    #expect(r.oldLength == 13 && r.newLength == 15 && !r.committed)
}

@Test func overwritePlacesWithoutMovingAnything() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"overwrite","assetID":"d","sourceRange":{"start":1,"end":3},"at":3}"#)
    let story = cut.project.sequences[0].clips.filter { $0.layer == 0 }.sorted { $0.start < $1.start }
    #expect(story.map(\.assetID) == ["a", "d", "b", "c"] && story[2].start == MediaTime(seconds: 5) && story[2].sourceRange.start == MediaTime(seconds: 4))
    #expect(cut.project.sequences[0].duration == MediaTime(seconds: 13))
}

@Test func eachChangeIsPlacedInTheOldCutAndTheNewOne() throws {
    var cut = TimelineCut.make()
    // Remove 1–2 s, then trim c3's tail by a second: the trim is reported where it was before
    // either operation and where it is after both.
    let r = try cut.apply(#"{"op":"removeRange","range":{"start":1,"end":2}}"#, #"{"op":"trim","clipID":"c3","edge":"tail","frames":-30}"#)
    #expect(r.operations[0].changes[0].old == SecondsRange(start: 1, end: 2) && r.operations[0].changes[0].new == SecondsRange(start: 1, end: 1))
    #expect(r.operations[1].changes[0].old == SecondsRange(start: 12, end: 13) && r.operations[1].changes[0].new == SecondsRange(start: 11, end: 11))
    #expect(r.operations[1].changes[0].scenes == [2] && r.operations[1].deltaText == "\u{2212}1.0 s")
    #expect(r.oldLength == 13 && r.newLength == 11 && r.delta == -2)
}

@Test func removeAClipWithOrWithoutClosingTheGap() throws {
    var cut = TimelineCut.make()
    let (gap, _) = try cut.run([#"{"op":"remove","clipID":"c2"}"#])
    #expect(clip(gap, "c3").start == MediaTime(seconds: 9))
    _ = try cut.apply(#"{"op":"remove","clipID":"c2","ripple":true}"#)
    #expect(clip(cut.project, "c3").start == MediaTime(seconds: 4) && cut.project.sequences[0].duration == MediaTime(seconds: 8))
}

@Test func movingAStoryClipTakesEverythingOverIt() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"move","clipID":"c3","to":{"before":"c1"}}"#)
    let s = cut.project.sequences[0]
    #expect(s.clips.filter { $0.layer == 0 }.sorted { $0.start < $1.start }.map(\.id) == ["c3", "c1", "c2"] && s.duration == MediaTime(seconds: 13))
    // The music that played under c3 plays under it at the head now.
    let head = s.clips.first { $0.assetID == "music" && $0.start == .zero }!
    #expect(head.sourceRange.start == MediaTime(seconds: 9) && head.duration == MediaTime(seconds: 4))
    #expect(r.operations[0].changes[0].old == SecondsRange(start: 9, end: 13) && r.operations[0].changes[0].new == SecondsRange(start: 0, end: 4))
    // Over the story, a clip just moves.
    let (moved, _) = try cut.run([#"{"op":"move","clipID":"m1","to":{"at":1,"track":"A3"}}"#])
    #expect(clip(moved, "m1").start == MediaTime(seconds: 1) && clip(moved, "m1").trackName == "A3")
}

@Test func splitMakesTwoClipsWithTheirOwnEffects() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"addEffect","target":"c2","effect":"blur","params":{"radius":4}}"#)
    let r = try cut.apply(#"{"op":"split","clipID":"c2","at":6}"#)
    let right = clip(cut.project, r.operations[0].clipIDs![0])
    #expect(clip(cut.project, "c2").end == MediaTime(seconds: 6) && right.start == MediaTime(seconds: 6) && right.sourceRange.start == MediaTime(seconds: 5))
    #expect(right.effects?.first?.id != clip(cut.project, "c2").effects?.first?.id)
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"split","clipID":"c2","at":12}"#]) }
}

@Test func trimExtendsOrShortensOneEndWithinTheTake() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"trim","clipID":"c1","edge":"tail","frames":15}"#)
    #expect(clip(cut.project, "c1").end == MediaTime(seconds: 4.5) && clip(cut.project, "c2").start == MediaTime(seconds: 4.5) && clip(cut.project, "c3").start == MediaTime(seconds: 9.5))
    _ = try cut.apply(#"{"op":"trim","clipID":"c2","edge":"head","frames":-30,"ripple":false}"#)
    #expect(clip(cut.project, "c2").start == MediaTime(seconds: 5.5) && clip(cut.project, "c2").sourceRange.start == MediaTime(seconds: 4))
    // c1 starts 2 s into its take: 60 frames of head and no more.
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"trim","clipID":"c1","edge":"head","frames":61}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"trim","clipID":"c1","edge":"middle","frames":1}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"trim","clipID":"nope","edge":"head","frames":1}"#]) }
}

@Test func rollMovesTheCutWithoutChangingTheLength() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"roll","editPoint":"c1|c2","frames":-12}"#)
    #expect(clip(cut.project, "c1").end == MediaTime(seconds: 3.6) && clip(cut.project, "c2").start == MediaTime(seconds: 3.6) && clip(cut.project, "c2").sourceRange.start == MediaTime(seconds: 2.6))
    #expect(r.delta == 0 && cut.project.sequences[0].duration == MediaTime(seconds: 13) && r.operations[0].changes[0].new == SecondsRange(start: 3.6, end: 4))
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"roll","editPoint":"c1|c3","frames":2}"#]) }
}

@Test func slipChangesTheFootageNotThePlace() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"slip","clipID":"c2","frames":30}"#)
    #expect(clip(cut.project, "c2").sourceRange == MediaRange(start: 4, end: 9) && clip(cut.project, "c2").start == MediaTime(seconds: 4))
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"slip","clipID":"c2","frames":-121}"#]) }
}

@Test func slideMovesAClipBetweenItsNeighbors() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"slide","clipID":"c2","frames":15}"#)
    #expect(clip(cut.project, "c1").end == MediaTime(seconds: 4.5) && clip(cut.project, "c2").start == MediaTime(seconds: 4.5) && clip(cut.project, "c2").sourceRange == MediaRange(start: 3, end: 8))
    #expect(clip(cut.project, "c3").start == MediaTime(seconds: 9.5) && clip(cut.project, "c3").end == MediaTime(seconds: 13) && cut.project.sequences[0].duration == MediaTime(seconds: 13))
}

@Test func splitEditsLetSoundLeadOrCarry() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"splitEdit","editPoint":"c1|c2","lead":"sound","frames":12}"#)
    #expect(clip(cut.project, "c2").soundLead == 0.4 && clip(cut.project, "c1").soundTail == -0.4 && clip(cut.project, "c2").soundRange.start == MediaTime(seconds: 3.6))
    #expect(r.operations[0].changes[0].tracks == ["A1"] && r.operations[0].summary.hasPrefix("J-cut"))
    _ = try cut.apply(#"{"op":"splitEdit","editPoint":"c2|c3","lead":"picture","frames":6}"#)
    #expect(clip(cut.project, "c2").soundTail == 0.2 && clip(cut.project, "c3").soundLead == -0.2)
    _ = try cut.apply(#"{"op":"splitEdit","editPoint":"c1|c2","lead":"sound","frames":0}"#)
    #expect(clip(cut.project, "c2").soundLead == nil && clip(cut.project, "c1").soundTail == nil)
}

@Test func replaceTakeLinesTheReadingUpWordForWord() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"replaceTake","clipID":"c1","withAssetID":"d","alignOn":"words"}"#)
    let c = clip(cut.project, "c1")
    #expect(c.assetID == "d" && r.operations[0].summary.contains("1A T5"))
    // "We" was 1.0 s into the cut; T5's "We" lands within a frame of it.
    let we = TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts).first { $0.clipID == "c1" }!
    #expect(we.text == "We" && abs(we.range.start.seconds - 1.0) <= 1.0 / 30)
    // The tail keeps the same room after "years.", in whole frames, and the rest of the cut moves to fit.
    #expect(abs(c.end.seconds - 4.12) <= 1.0 / 30 && close((c.end.seconds * 30).rounded(), c.end.seconds * 30) && close(clip(cut.project, "c2").start.seconds, c.end.seconds))
    expectFailure("no_words", index: 0) { _ = try cut.run([#"{"op":"replaceTake","clipID":"c2","withAssetID":"a","alignOn":"words"}"#]) }
    let (head, _) = try TimelineCut.make().run([#"{"op":"replaceTake","clipID":"c2","withAssetID":"c","alignOn":"head"}"#])
    #expect(clip(head, "c2").sourceRange == MediaRange(start: 3, end: 8) && clip(head, "c2").assetID == "c")
}

@Test func removeWordsCutsTheWordsOnEveryLayer() throws {
    var cut = TimelineCut.make()
    let two = TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts).first { $0.text == "two" }!
    let r = try cut.apply(#"{"op":"removeWords","wordIDs":["\#(two.id)"]}"#)
    #expect(cut.project.sequences[0].duration == MediaTime(seconds: 12.7))
    #expect(TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts).map(\.text) == ["We", "waited", "years."])
    #expect(r.operations[0].changes[0].old == SecondsRange(start: 2.6, end: 2.9) && r.operations[0].changes[0].new == SecondsRange(start: 2.6, end: 2.6))
    expectFailure("no_words", index: 0) { _ = try TimelineCut(project: cut.project, context: EditContext(noteNumbers: [1])).run([#"{"op":"removeWords","wordIDs":["x"]}"#]) }
}

@Test func tightenPausesNeverCutsIntoAWord() throws {
    var cut = TimelineCut.make()
    let before = TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts)
    let r = try cut.apply(#"{"op":"tightenPauses","range":{"start":0,"end":4},"longerThan":0.5,"to":0.2}"#)
    let after = TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts)
    // Every word is whole, in order; "waited" to "two" was 0.9 s and is 0.2 s.
    #expect(after.map(\.text) == before.map(\.text) && zip(before, after).allSatisfy { close($0.range.duration.seconds, $1.range.duration.seconds) })
    #expect(close(after[2].range.start.seconds - after[1].range.end.seconds, 0.2, 1.0 / 30 + 1e-6) && r.operations[0].changes.count == 1)
    // With measured sound only the quiet part goes, so a laugh in the pause stays.
    var quiet = try op(#"{"op":"tightenPauses","range":{"start":0,"end":4},"longerThan":0.5,"to":0.2}"#)
    quiet.resolved = ResolvedValues(quiet: [MediaRange(start: 1.7, end: 2.0)])
    let (p, _) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [quiet]), on: TimelineCut.make().project, context: cut.context)
    #expect(close(p.sequences[0].duration.seconds, 12.7))
    expectFailure("no_words", index: 0) { _ = try cut.run([#"{"op":"tightenPauses","range":{"start":9,"end":13},"longerThan":0.5,"to":0.2}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"tightenPauses","range":{"start":0,"end":4},"longerThan":0.5,"to":0.8}"#]) }
}

/// An essay: a narration on A1 with b-roll over it, then the narrator on camera. Both voices are the cut's words;
/// the b-roll's own sound isn't, whether it's a cutaway or on V1 with its sound off.
@Test func aNarrationIsTheCutsWordsUnderItsPictureAndBesideTheTalkingHead() throws {
    var cut = TimelineCut.make()
    func take(_ id: String, video: Bool) -> MediaAsset {
        MediaAsset(id: id, name: id + (video ? ".mov" : ".wav"), path: "/\(id)", duration: .init(seconds: 20), video: video ? [.init(id: 1, width: 1920, height: 1080, frameRate: 30)] : [], audio: [.init(id: 2, index: 0, label: "Dialogue", channels: 1, sampleRate: 48_000)])
    }
    func line(_ asset: String, _ words: [(String, Double)]) -> SourceTranscript {
        SourceTranscript(assetID: asset, audioTrackID: 2, words: words.enumerated().map { i, w in TranscriptWord(id: "\(asset)-w\(i)", text: w.0, range: .init(start: w.1, end: w.1 + 0.3)) })
    }
    cut.project.assets += [take("vo", video: false), take("street", video: true), take("head", video: true)]
    cut.project.sequences[0].clips = []
    cut.context.transcripts = [line("vo", [("Cinematic", 0.5), ("means", 1.2), ("chosen.", 3.0)]), line("street", [("horn", 1.0), ("dog", 6.0)]), line("head", [("Here\u{2019}s", 0.4), ("why.", 0.9)])]
    try cut.apply(
        #"{"op":"insert","assetID":"vo","sourceRange":{"start":0,"end":4}}"#,
        #"{"op":"cutaway","assetID":"street","sourceRange":{"start":0,"end":2},"at":0}"#,
        #"{"op":"insert","assetID":"head","sourceRange":{"start":0,"end":2},"at":4}"#
    )
    // B-roll on V1 under the narration, its sound off.
    let s = cut.project.sequences[0]
    #expect(s.clips.first { $0.assetID == "vo" }?.trackName == "A1" && s.clips.first { $0.assetID == "street" }?.trackName == "V2")
    var silent = Clip(id: "broll", assetID: "street", name: "street", start: .init(seconds: 2), sourceRange: .init(start: 5, end: 7))
    silent.audioOverrides["2"] = AudioSettings(muted: true)
    cut.project.sequences[0].clips.append(silent)
    let words = { TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts) }
    #expect(words().map(\.text) == ["Cinematic", "means", "chosen.", "Here\u{2019}s", "why."])

    // The narration's words cut and tighten like a take's; everything over them moves with them.
    let means = try #require(words().first { $0.text == "means" })
    try cut.apply(#"{"op":"removeWords","wordIDs":["\#(means.id)"]}"#)
    #expect(words().map(\.text) == ["Cinematic", "chosen.", "Here\u{2019}s", "why."] && close(cut.project.sequences[0].duration.seconds, 5.7))
    try cut.apply(#"{"op":"tightenPauses","range":{"start":0,"end":3.7},"longerThan":0.5,"to":0.2}"#)
    let tight = words()
    // The 1.9 s pause in the narration is 0.2 s; the one before the narrator comes on camera is outside the range and stays.
    #expect(close(tight[1].range.start.seconds - tight[0].range.end.seconds, 0.2, 1.0 / 30 + 1e-6) && close(tight[2].range.start.seconds - tight[1].range.end.seconds, 1.1, 1.0 / 30 + 1e-6))
    // Music ducks under both voices: the narration's line and the narrator's on camera.
    try cut.apply(#"{"op":"overwrite","assetID":"music","sourceRange":{"start":0,"end":4},"at":0,"track":"A2"}"#, #"{"op":"duck","track":"A2","under":"A1","dB":-12}"#)
    #expect(cut.project.sequences[0].clips.first { $0.assetID == "music" }?.duckKeys?.count == 8)
}

@Test func speedAndFreezeKeepTheStoryInSync() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"speed","clipID":"c2","rate":2}"#)
    #expect(clip(cut.project, "c2").duration == MediaTime(seconds: 2.5) && clip(cut.project, "c3").start == MediaTime(seconds: 6.5))
    let r = try cut.apply(#"{"op":"freeze","clipID":"c1","at":1,"seconds":2}"#)
    let s = cut.project.sequences[0]
    let hold = s.clips.first { $0.hold != nil }!
    #expect(hold.start == MediaTime(seconds: 1) && hold.duration == MediaTime(seconds: 2) && hold.sourceRange.start == MediaTime(seconds: 3) && r.operations[0].clipIDs == [hold.id])
    #expect(clip(cut.project, "c3").end == MediaTime(seconds: 12.5) && s.duration == MediaTime(seconds: 15))
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"speed","clipID":"c3","rate":9}"#]) }
}

// MARK: Picture

@Test func pictureOperationsWriteBalanceAndTransforms() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"reframe","clipID":"c1","scale":1.1,"x":0.05}"#)
    let fx = clip(cut.project, "c1").effects!.first!
    #expect(fx.name == "transform" && fx.params["scale"] == .number(1.1) && r.operations[0].effectID == fx.id)
    // follow is measured by the tools layer, which hands the keys in.
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"reframe","clipID":"c1","scale":1.6,"follow":"face"}"#]) }
    var follow = try op(#"{"op":"reframe","clipID":"c1","scale":1.6,"follow":"face","keepIn":"thirds"}"#)
    follow.resolved = ResolvedValues(keys: ["x": [.init(t: 2, v: 0.1), .init(t: 6, v: -0.1)], "y": [.init(t: 2, v: 0)]])
    let (followed, _) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [follow]), on: cut.project, context: cut.context)
    #expect(clip(followed, "c1").effects?.first?.keys?["x"]?.count == 2 && clip(followed, "c1").effects?.count == 1)
    _ = try cut.apply(#"{"op":"balance","clipID":"c2","exposure":0.3,"temperature":-200}"#)
    #expect(clip(cut.project, "c2").grade.exposure == 0.3 && clip(cut.project, "c2").grade.temperature == -200 && clip(cut.project, "c2").grade.contrast == 1)
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"balance","clipID":"c2","saturation":4}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"matchBalance","clipID":"c3","toClipID":"c2"}"#]) }
    var match = try op(#"{"op":"matchBalance","clipID":"c3","toClipID":"c2"}"#)
    var g = ColorGrade(); g.exposure = -0.2; match.resolved = ResolvedValues(grade: g)
    let (matched, result) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [match]), on: cut.project, context: cut.context)
    #expect(clip(matched, "c3").grade.exposure == -0.2 && result.operations[0].summary == "Matched 2A T1’s balance to 1B T2")
    _ = try cut.apply(#"{"op":"cameraLUT","assetID":"a","lut":"none"}"#)
    #expect(cut.project.assets[0].cameraLUT == "none")
    expectFailure("missing_media", index: 0) { _ = try cut.run([#"{"op":"cameraLUT","assetID":"a","lut":"/nowhere/LogC.cube"}"#]) }
    expectFailure("missing_media", index: 0) { _ = try cut.run([#"{"op":"cameraLUT","assetID":"zzz","lut":"auto"}"#]) }
}

@Test func effectsAreAddedChangedAndRemovedByID() throws {
    var cut = TimelineCut.make()
    let added = try cut.apply(#"{"op":"addEffect","target":"c2","effect":"blur","params":{"radius":8},"keys":{"radius":[{"t":4,"v":0},{"t":5,"v":20}]}}"#)
    let id = try #require(added.operations[0].effectID)
    // Keys arrive in cut seconds and are kept in the take's, so they ride along with trims.
    #expect(clip(cut.project, "c2").effect(id)?.keys?["radius"]?.map(\.t) == [3, 4])
    _ = try cut.apply(#"{"op":"setEffect","effectID":"\#(id)","params":{"radius":12}}"#)
    #expect(clip(cut.project, "c2").effect(id)?.params["radius"] == .number(12))
    _ = try cut.apply(#"{"op":"removeEffect","effectID":"\#(id)"}"#)
    #expect(clip(cut.project, "c2").effects == nil)
    for bad in [#"{"op":"addEffect","target":"c2","effect":"glow","params":{}}"#, #"{"op":"addEffect","target":"c2","effect":"blur","params":{"radius":400}}"#,
                #"{"op":"addEffect","target":"c2","effect":"sharpen","params":{"amount":0.5},"keys":{"amount":[{"t":4,"v":0.2}]}}"#, #"{"op":"addEffect","target":"c1","effect":"blend","params":{"mode":"screen"}}"#,
                #"{"op":"addEffect","target":"c2","effect":"shader","params":{"file":"Effects/x.metal"}}"#, #"{"op":"setEffect","effectID":"fx-none","params":{"radius":1}}"#,
                #"{"op":"addEffect","target":"c2","effect":"mask","params":{"shape":"star"}}"#] {
        expectFailure("bad_argument", index: 0) { _ = try cut.run([bad]) }
    }
    expectFailure("look_is_yours", index: 0) { _ = try cut.run([#"{"op":"addEffect","target":"V1","effect":"look","params":{}}"#]) }
    _ = try cut.apply(#"{"op":"addEffect","target":"V1","effect":"filter.grain","params":{"amount":0.3,"option":"fine"}}"#, #"{"op":"addEffect","target":"c2","effect":"mask","params":{"shape":"ellipse","x":0.3,"y":0.2,"w":0.3,"h":0.4}}"#)
    #expect(cut.project.sequences[0].tracks?["V1"]?.effects?.first?.name == "filter.grain")
    // A cutaway on V2 can blend.
    let away = try cut.apply(#"{"op":"cutaway","assetID":"d","sourceRange":{"start":1,"end":3},"at":5}"#)
    let blended = try cut.apply(#"{"op":"addEffect","target":"\#(away.operations[0].clipIDs![0])","effect":"blend","params":{"mode":"screen"}}"#)
    #expect(clip(cut.project, away.operations[0].clipIDs![0]).blend == "screen" && blended.operations[0].effectID?.hasSuffix(":blend") == true)
}

@Test func transitionsNeedHandlesForADissolveAndNoneForADip() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"transition","editPoint":"c1|c2","type":"dissolve","frames":12}"#)
    let t = try #require(clip(cut.project, "c2").transition)
    #expect(t.type == "dissolve" && t.frames == 12 && t.before == 0.2 && t.after == 0.2 && r.operations[0].changes[0].new == SecondsRange(start: 3.8, end: 4.2))
    _ = try cut.apply(#"{"op":"transition","editPoint":"|c1","type":"dipToBlack","frames":15}"#)
    #expect(clip(cut.project, "c1").transition?.before == 0 && clip(cut.project, "c1").transition?.after == 0.5)
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"transition","editPoint":"|c1","type":"dissolve","frames":15}"#]) }
    // c3 starts 1 s into its take: a 90-frame dissolve needs 45 frames before it.
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"transition","editPoint":"c2|c3","type":"dissolve","frames":90}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"transition","editPoint":"c2|c3","type":"wipe","frames":10}"#]) }
    // Taking away the handles makes it a straight cut, and says so.
    let slipped = try cut.apply(#"{"op":"slip","clipID":"c2","frames":-90}"#)
    #expect(clip(cut.project, "c2").transition == nil && slipped.warnings.count == 1)
    _ = try cut.apply(#"{"op":"transition","editPoint":"c2|c3","type":"dipToWhite","frames":10}"#, #"{"op":"removeTransition","editPoint":"c2|c3"}"#)
    #expect(clip(cut.project, "c3").transition == nil)
}

// MARK: Layers and sound

@Test func layersGoAboveTheStory() throws {
    var cut = TimelineCut.make()
    let r = try cut.apply(#"{"op":"cutaway","assetID":"d","sourceRange":{"start":10,"end":12},"cover":"c1|c2"}"#)
    let away = clip(cut.project, r.operations[0].clipIDs![0])
    #expect(away.layer == 1 && away.start == MediaTime(seconds: 3) && away.audioOverrides["2"]?.muted == true)
    // A graphic is an asset: the graphics area's ProRes 4444 render, named on the asset.
    var graphic = MediaAsset(id: "g", name: "Title.mov", path: "/Title.mov", duration: .init(seconds: 4), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)]); graphic.graphic = "Title · Two years."
    cut.project.assets.append(graphic)
    let placed = try cut.apply(#"{"op":"placeGraphic","graphic":"Title · Two years.","at":2,"seconds":3}"#)
    let title = clip(cut.project, placed.operations[0].clipIDs![0])
    #expect(title.layer == 2 && title.aboveLook == true && title.duration == MediaTime(seconds: 3) && title.sourceRange.start == .zero)
    expectFailure("missing_media", index: 0) { _ = try cut.run([#"{"op":"placeGraphic","graphic":"Nope","at":2}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"placeGraphic","graphic":"Title · Two years.","at":2,"seconds":9}"#]) }
    var made = MediaAsset(id: "made-1", name: "Dusk sky.mov", path: "/sky.mov", duration: .init(seconds: 6), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)]); made.madeID = "made-record-1"
    cut.project.assets.append(made)
    _ = try cut.apply(#"{"op":"placeMade","madeID":"made-record-1","at":6,"track":"V2"}"#)
    expectFailure("overlap", index: 0) { _ = try cut.run([#"{"op":"placeMade","madeID":"made-1","at":7,"track":"V2"}"#]) }
    expectFailure("missing_media", index: 0) { _ = try cut.run([#"{"op":"placeMade","madeID":"made-9","at":7,"track":"V3"}"#]) }
}

@Test func soundOperationsWriteGainKeysAndPlaceMusic() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"gain","target":"c2","dB":-3}"#, #"{"op":"gain","target":"A2","dB":-2,"keys":{"dB":[{"t":0,"v":0},{"t":2,"v":-6}]}}"#, #"{"op":"fade","clipID":"m1","in":15,"out":30}"#)
    #expect(clip(cut.project, "c2").gainDB == -3 && cut.project.sequences[0].tracks?["A2"]?.gainDB == -2 && cut.project.sequences[0].tracks?["A2"]?.gainKeys?.count == 2)
    #expect(clip(cut.project, "m1").fadeIn == 0.5 && clip(cut.project, "m1").fadeOut == 1)
    let r = try cut.apply(#"{"op":"duck","track":"A2","under":"A1","dB":-6}"#)
    // Two lines (1.0–1.7 and 2.6–3.3 s): down by each first word, back up after each last.
    let keys = try #require(clip(cut.project, "m1").duckKeys)
    #expect(keys.map(\.v) == [0, -6, -6, 0, 0, -6, -6, 0] && close(keys[1].t, 1.0, 1e-4) && close(keys[6].t, 3.3, 1e-4) && close(keys[7].t, 3.8, 1e-4))
    #expect(r.operations[0].summary == "Ducked A2 \u{2212}6 dB under A1 for 2 lines" && cut.project.sequences[0].tracks?["A2"]?.ducked?.under == "A1")
    expectFailure("no_words", index: 0) { _ = try TimelineCut(project: cut.project, context: EditContext(noteNumbers: [1])).run([#"{"op":"duck","track":"A2","dB":-6}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"gain","target":"c2","dB":40}"#]) }
    // Music ends on the cut into c3, trimmed from its head.
    var piano = MediaAsset(id: "piano", name: "Sparse piano.m4a", path: "/piano.m4a", duration: .init(seconds: 24), audio: [.init(id: 1, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)]); piano.madeID = "made-piano"
    cut.project.assets.append(piano)
    let placed = try cut.apply(#"{"op":"placeMusic","madeID":"made-piano","at":2,"endOn":{"cut":"c2|c3"}}"#)
    let music = clip(cut.project, placed.operations[0].clipIDs![0])
    #expect(music.start == MediaTime(seconds: 2) && music.end == MediaTime(seconds: 9) && music.sourceRange.end == MediaTime(seconds: 24) && music.trackName == "A3")
    let word = TranscriptEditing.words(in: cut.project.sequences[0], transcripts: cut.context.transcripts).first { $0.text == "years." }!
    let (onWord, _) = try cut.run([#"{"op":"placeMusic","assetID":"piano","at":0,"endOn":{"word":"\#(word.id)"},"track":"A4"}"#])
    #expect(onWord.sequences[0].clips.first { $0.trackName == "A4" }?.end == MediaTime(seconds: 3))
}

// MARK: Songs in parts

/// Neon Drive, a library song in parts: its full mix and three stems, a minute each.
func neonDrive(_ cut: inout TimelineCut) {
    for part in ["Full mix", "Drums", "Bass", "Melody"] {
        var a = MediaAsset(id: "nd-" + part.lowercased().replacingOccurrences(of: " ", with: ""), name: "Neon Drive \(part)", path: "/nd-\(part).wav", duration: .init(seconds: 60), audio: [.init(id: 1, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)])
        a.song = "Neon Drive"; a.part = part
        cut.project.assets.append(a)
    }
}
func songClips(_ p: Project) -> [Clip] { p.sequences[0].clips.filter { $0.assetID?.hasPrefix("nd-") == true } }
/// Where the song's beginning falls in the cut, for a clip of one of its parts.
func songStart(_ c: Clip) -> Double { c.start.seconds - c.sourceRange.start.seconds }

@Test func aSongsPartsPlayInTimeWhereverTheyMeet() throws {
    var cut = TimelineCut.make(); neonDrive(&cut)
    // Drums and bass from 0:10 in the song, under the whole cut, each on a track of its own.
    let placed = try cut.apply(#"{"op":"placeMusic","assetID":"nd-drums","at":0,"endOn":13,"from":10,"parts":["Drums","bass"]}"#)
    let ids = try #require(placed.operations[0].clipIDs)
    let drums = clip(cut.project, ids[0]), bass = clip(cut.project, ids[1])
    #expect(drums.trackName == "A3" && bass.trackName == "A4" && drums.sourceRange == bass.sourceRange && drums.sourceRange.start == MediaTime(seconds: 10) && drums.end == MediaTime(seconds: 13))
    #expect(placed.operations[0].summary.hasPrefix("Placed Neon Drive (Drums, Bass) on A3, A4 from"))
    // The melody comes in at 6 s as the bass goes: the same moment of the song, ramped where the song plays on.
    let changed = try cut.apply(#"{"op":"parts","clipID":"\#(ids[0])","heard":{"Melody":[{"start":6,"end":13}],"Bass":[{"start":0,"end":6}]}}"#)
    let melody = try #require(songClips(cut.project).first { $0.assetID == "nd-melody" }), bassNow = try #require(songClips(cut.project).first { $0.assetID == "nd-bass" })
    #expect(melody.start == MediaTime(seconds: 6) && melody.sourceRange.start == MediaTime(seconds: 16) && melody.trackName == "A5" && close(melody.fadeIn ?? 0, 2.0 / 30) && melody.fadeOut == nil)
    #expect(bassNow.end == MediaTime(seconds: 6) && bassNow.trackName == "A4" && close(bassNow.fadeOut ?? 0, 2.0 / 30) && bassNow.fadeIn == nil)
    #expect(changed.operations[0].summary.hasPrefix("Neon Drive: Bass ") && changed.operations[0].summary.contains("; Melody "))
    // Moving or slipping any part takes the stretch of the song with it.
    let moved = try cut.apply(#"{"op":"move","clipID":"\#(melody.id)","to":{"at":7}}"#)
    #expect(songClips(cut.project).allSatisfy { close(songStart($0), -9) } && songClips(cut.project).map(\.start.seconds).min() == 1 && moved.operations[0].summary.hasPrefix("Moved Neon Drive to"))
    _ = try cut.apply(#"{"op":"slip","clipID":"\#(ids[0])","frames":30}"#)
    #expect(songClips(cut.project).allSatisfy { close(songStart($0), -10) })
    // A part trims where it stands. Sliding one or changing its speed would take it out of time.
    _ = try cut.apply(#"{"op":"trim","clipID":"\#(melody.id)","edge":"tail","frames":-15}"#)
    #expect(clip(cut.project, melody.id).end == MediaTime(seconds: 13.5) && clip(cut.project, ids[0]).end == MediaTime(seconds: 14))
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"slide","clipID":"\#(ids[0])","frames":5}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"speed","clipID":"\#(ids[0])","rate":1.5}"#]) }
    // Another moment of the song over these is refused; the same moment (the full mix over the drums) isn't.
    expectFailure("not_in_sync", index: 0) { _ = try cut.run([#"{"op":"overwrite","assetID":"nd-fullmix","sourceRange":{"start":30,"end":34},"at":2,"track":"A6"}"#]) }
    _ = try cut.run([#"{"op":"overwrite","assetID":"nd-fullmix","sourceRange":{"start":11,"end":15},"at":1,"track":"A6"}"#])
    // A cut in the story cuts every part at once; what follows it still plays in time with itself.
    _ = try cut.apply(#"{"op":"removeRange","range":{"start":4,"end":5}}"#)
    let after = songClips(cut.project)
    #expect(after.count == 5 && Set(after.map { (songStart($0) * 1_000).rounded() }) == [-10_000, -11_000])
    // Ducking one part ducks them all; gain is the part's; a fade in fades every part that starts there.
    let ducked = try cut.apply(#"{"op":"duck","track":"A3","under":"A1","dB":-6}"#)
    #expect(ducked.operations[0].summary.hasPrefix("Ducked A3, A4, A5 \u{2212}6 dB under A1") && cut.project.sequences[0].tracks?["A5"]?.ducked?.under == "A1")
    let first = try #require(songClips(cut.project).first { $0.assetID == "nd-drums" && $0.start == MediaTime(seconds: 1) })
    let firstBass = try #require(songClips(cut.project).first { $0.assetID == "nd-bass" && $0.start == MediaTime(seconds: 1) })
    _ = try cut.apply(#"{"op":"gain","target":"\#(firstBass.id)","dB":-4}"#)
    #expect(clip(cut.project, firstBass.id).gainDB == -4 && clip(cut.project, first.id).gainDB == nil)
    let faded = try cut.apply(#"{"op":"fade","clipID":"\#(first.id)","in":15}"#)
    #expect(clip(cut.project, first.id).fadeIn == 0.5 && clip(cut.project, firstBass.id).fadeIn == 0.5 && faded.operations[0].summary == "Faded Neon Drive in over 15 frames")
}

@Test func aSongsPartsAreRefusedWhatTheyCantDo() throws {
    var cut = TimelineCut.make(); neonDrive(&cut)
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"placeMusic","assetID":"nd-drums","at":0,"endOn":13,"from":55}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"placeMusic","assetID":"nd-drums","at":0,"endOn":13,"parts":["Cowbell"]}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"placeMusic","assetID":"music","at":0,"endOn":4,"parts":["Drums"]}"#]) }
    let placed = try cut.apply(#"{"op":"placeMusic","assetID":"nd-fullmix","at":0,"endOn":{"cut":"c2|c3"}}"#)
    let id = placed.operations[0].clipIDs![0]
    // Without from, the song ends on the mark: its last nine seconds.
    #expect(clip(cut.project, id).sourceRange.start == MediaTime(seconds: 51) && placed.operations[0].summary.hasPrefix("Placed Neon Drive Full mix on A3 to end on the cut"))
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"parts","clipID":"\#(id)","heard":{"Drums":[{"start":-2,"end":4}]}}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"parts","clipID":"m1","heard":{"Drums":[{"start":0,"end":4}]}}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"parts","clipID":"\#(id)","heard":{"Drums":[{"start":0,"end":4}]},"frames":-1}"#]) }
}

@Test func aSongsPartsStayOpenAfterPictureLock() throws {
    var cut = TimelineCut.make(); neonDrive(&cut)
    let picture = cut.project.sequences[0].clips.filter { $0.kind != .audio }
    cut.context.state.pictureLocked = true
    // The big part, from 0:40, drums then the full mix; moved and trimmed, the picture stays as it was locked.
    let placed = try cut.apply(#"{"op":"placeMusic","assetID":"nd-fullmix","at":0,"endOn":{"cut":"c2|c3"},"from":40,"parts":["Drums","Bass"]}"#)
    _ = try cut.apply(#"{"op":"parts","clipID":"\#(placed.operations[0].clipIDs![1])","heard":{"Full mix":[{"start":4,"end":9}],"Drums":[{"start":0,"end":4}]},"frames":0}"#)
    let drums = try #require(songClips(cut.project).first { $0.assetID == "nd-drums" })
    _ = try cut.apply(#"{"op":"move","clipID":"\#(drums.id)","to":{"at":1}}"#, #"{"op":"trim","clipID":"\#(drums.id)","edge":"head","frames":10}"#)
    #expect(songClips(cut.project).count == 3 && songClips(cut.project).allSatisfy { close(songStart($0), -39) } && songClips(cut.project).allSatisfy { $0.fadeIn == nil && $0.fadeOut == nil })
    #expect(cut.project.sequences[0].clips.filter { $0.kind != .audio } == picture)
    expectFailure("picture_locked", index: 0) { _ = try cut.run([#"{"op":"trim","clipID":"c1","edge":"tail","frames":-3}"#]) }
}

// MARK: Errors, locks and notes

@Test func unknownOperationsAndTheLookAreRefusedWithTheirIndex() {
    let cut = TimelineCut.make()
    expectFailure("unknown_op", index: 1) { _ = try cut.run([#"{"op":"slip","clipID":"c2","frames":3}"#, #"{"op":"teleport","clipID":"c2"}"#]) }
    expectFailure("look_is_yours", index: 0) { _ = try cut.run([#"{"op":"setLook"}"#]) }
    expectFailure("overlap", index: 0) { _ = try cut.run([#"{"type":"insert","assetID":"d","range":{"start":0,"end":2},"at":0}"#]) }
}

@Test func batchesNameTheirNotesDuringATurnoverUnlessLatitudeIsFree() throws {
    var cut = TimelineCut.make()
    cut.context.turnoverLatitude = .faithful
    let slip = try op(#"{"op":"slip","clipID":"c2","frames":3}"#)
    expectFailure("bad_argument", index: 0) { _ = try EditReducer.run(EditBatch(baseEditRevision: 0, operations: [slip]), on: cut.project, context: cut.context) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"slip","clipID":"c2","frames":3}"#], notes: [9]) }
    let (_, own) = try EditReducer.run(EditBatch(baseEditRevision: 0, operations: [try op(#"{"op":"slip","clipID":"c2","frames":3,"note":2}"#)]), on: cut.project, context: cut.context)
    #expect(own.operations[0].notes == [2] && own.notes == [2] && !own.operations[0].unasked)
    cut.context.turnoverLatitude = .free
    let (_, free) = try EditReducer.run(EditBatch(baseEditRevision: 0, operations: [slip]), on: cut.project, context: cut.context)
    #expect(free.operations[0].unasked && free.operations[0].notes.isEmpty)
}

@Test func lockedScenesKeepTheirCutButNotTheirColorOrSound() throws {
    var cut = TimelineCut.make()
    cut.context.dailies.scenes[1].locked = true
    // A trim before Launch day moves it whole.
    let (moved, _) = try cut.run([#"{"op":"trim","clipID":"c1","edge":"tail","frames":-15}"#])
    #expect(clip(moved, "c3").start == MediaTime(seconds: 8.5))
    // Anything that changes it, on any track, fails at its index.
    expectFailure("scene_locked", index: 1) { _ = try cut.run([#"{"op":"slip","clipID":"c2","frames":3}"#, #"{"op":"trim","clipID":"c3","edge":"tail","frames":-3}"#]) }
    for change in [#"{"op":"cutaway","assetID":"d","sourceRange":{"start":1,"end":3},"at":10}"#, #"{"op":"reframe","clipID":"c3","scale":1.2}"#,
                   #"{"op":"transition","editPoint":"c2|c3","type":"dipToBlack","frames":10}"#, #"{"op":"removeRange","range":{"start":10,"end":11}}"#,
                   #"{"op":"splitEdit","editPoint":"c2|c3","lead":"sound","frames":6}"#] {
        expectFailure("scene_locked", index: 0) { _ = try cut.run([change]) }
    }
    // Its color and sound still change, as after picture lock.
    let (_, open) = try cut.run([#"{"op":"balance","clipID":"c3","exposure":0.2}"#, #"{"op":"cameraLUT","assetID":"c","lut":"none"}"#,
                                 #"{"op":"gain","target":"m1","dB":-4}"#, #"{"op":"gain","target":"c3","dB":-2}"#, #"{"op":"fade","clipID":"c3","out":6}"#])
    #expect(open.operations.count == 5)
}

@Test func pictureLockLeavesOnlyColorAndSound() throws {
    var cut = TimelineCut.make()
    cut.context.state.pictureLocked = true
    expectFailure("picture_locked", index: 0) { _ = try cut.run([#"{"op":"trim","clipID":"c1","edge":"tail","frames":-3}"#]) }
    expectFailure("picture_locked", index: 1) { _ = try cut.run([#"{"op":"balance","clipID":"c1","exposure":0.2}"#, #"{"op":"addEffect","target":"c1","effect":"blur","params":{"radius":3}}"#]) }
    let (_, r) = try cut.run([#"{"op":"balance","clipID":"c1","exposure":0.2}"#, #"{"op":"gain","target":"m1","dB":-3}"#, #"{"op":"duck","track":"A2","dB":-6}"#])
    #expect(r.operations.count == 3)
}

@Test func pictureLockLeavesTheGraphicsOverThePictureOpen() throws {
    var cut = TimelineCut.make()
    var captions = MediaAsset(id: "g", name: "captions-1.mov", path: "/captions-1.mov", duration: .init(seconds: 9), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)]); captions.graphic = "captions-1"
    cut.project.assets.append(captions)
    cut.context.state.pictureLocked = true
    let locked = cut.project.sequences[0]
    // Captions go on over the picture, move and come off; a title can follow the last shot, on black.
    let placed = try cut.apply(#"{"op":"placeGraphic","graphic":"captions-1","at":1,"seconds":3}"#)
    let id = try #require(placed.operations[0].clipIDs?.first)
    _ = try cut.apply(#"{"op":"move","clipID":"\#(id)","to":{"at":5}}"#, #"{"op":"title","text":"Thanks for watching","at":13}"#)
    #expect(clip(cut.project, id).start == MediaTime(seconds: 5) && clip(cut.project, id).trackName == "V2" && cut.project.sequences[0].duration == MediaTime(seconds: 16))
    _ = try cut.apply(#"{"op":"remove","clipID":"\#(id)","ripple":true}"#)
    #expect(cut.project.sequences[0].clips.filter { $0.kind != .title } == locked.clips)
    // Everything else stays as it was locked.
    expectFailure("picture_locked", index: 0) { _ = try cut.run([#"{"op":"trim","clipID":"c1","edge":"tail","frames":-3}"#]) }
    expectFailure("picture_locked", index: 0) { _ = try cut.run([#"{"op":"cutaway","assetID":"d","sourceRange":{"start":1,"end":3},"at":10}"#]) }
    expectFailure("picture_locked", index: 0) { _ = try cut.run([#"{"op":"title","text":"In the story","at":2,"layer":0}"#]) }
    expectFailure("picture_locked", index: 1) { _ = try cut.run([#"{"op":"placeGraphic","graphic":"captions-1","at":1,"seconds":3}"#, #"{"op":"addEffect","target":"c2","effect":"blur","params":{"radius":3}}"#]) }
    let again = try cut.apply(#"{"op":"placeGraphic","graphic":"captions-1","at":1,"seconds":3}"#)
    expectFailure("picture_locked", index: 0) { _ = try cut.run([#"{"op":"move","clipID":"\#(again.operations[0].clipIDs![0])","to":{"at":16,"track":"V1"}}"#]) }
    // Picture lock locks every scene, so captions go over one locked before it; before picture lock they don't.
    cut.context.dailies.scenes[1].locked = true
    _ = try cut.run([#"{"op":"placeGraphic","graphic":"captions-1","at":10,"seconds":2}"#])
    cut.context.state.pictureLocked = false
    expectFailure("scene_locked", index: 0) { _ = try cut.run([#"{"op":"placeGraphic","graphic":"captions-1","at":10,"seconds":2}"#]) }
}

// MARK: The store

@Test func editsCommitAsOneRevisionAndKeepTheirNotes() throws {
    let store = try temporaryStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    let cut = TimelineCut.make()
    for a in cut.project.assets { _ = try store.addAsset(a, append: false, expectedRevision: try store.revision()) }
    let inserts = cut.project.sequences[0].clips.map { c -> EditOperation in var o = EditOperation("insert"); o.assetID = c.assetID; o.range = c.sourceRange; o.at = c.start; o.layer = c.layer; return o }
    let seeded = try store.apply(.init(baseEditRevision: try store.revision(), operations: inserts))
    let id = Dictionary(seeded.sequences[0].clips.map { ($0.assetID!, $0.id) }, uniquingKeysWith: { a, _ in a })
    _ = try store.logDailies(Dailies(scenes: cut.context.dailies.scenes, takes: cut.context.dailies.takes))
    _ = try store.addComment(text: "Get to her face sooner.", sequenceID: nil, revision: seeded.editRevision, time: .init(seconds: 1))
    _ = try store.addComment(text: "Hold on the street.", sequenceID: nil, revision: seeded.editRevision, time: .init(seconds: 5))
    let base = try store.revision()
    let batch = EditBatch(baseEditRevision: base, idempotencyKey: "t3-note1", summary: "Get to her face sooner", notes: [1], operations: [try op(#"{"op":"trim","clipID":"\#(id["a"]!)","edge":"tail","frames":-15}"#), try op(#"{"op":"slip","clipID":"\#(id["b"]!)","frames":3,"note":2}"#)])
    let predicted = try store.edit(batch, validateOnly: true)
    #expect(try !predicted.committed && predicted.newLength == 12.5 && store.revision() == base)
    let result = try store.edit(batch)
    #expect(result.committed && result.editRevision == base + 1 && result.operations.map(\.notes) == [[1], [2]] && result.notes == [1, 2])
    #expect(result.operations.map(\.summary) == predicted.operations.map(\.summary) && result.operations[0].summary == "Trimmed 1A T1’s tail, \u{2212}0.5 s")
    #expect(try store.editRecord(revision: base + 1) == result && store.editRecords(after: base).count == 1 && store.read().sequences[0].duration == MediaTime(seconds: 12.5))
    // A retry returns the same result; the same key with another batch is refused.
    #expect(try store.edit(batch) == result && store.revision() == base + 1)
    var other = batch; other.summary = "Something else"
    expectFailure("idempotency_conflict", index: nil) { _ = try store.edit(other) }
    expectFailure("stale_revision", index: nil) { _ = try store.edit(EditBatch(baseEditRevision: base, operations: [try op(#"{"op":"slip","clipID":"\#(id["b"]!)","frames":3}"#)])) }
    // A locked scene refuses the batch at its index, and nothing in it commits.
    try store.lockScene(id: "s2", locked: true)
    expectFailure("scene_locked", index: 1) { _ = try store.edit(EditBatch(baseEditRevision: base + 1, notes: [1], operations: [try op(#"{"op":"slip","clipID":"\#(id["b"]!)","frames":3}"#), try op(#"{"op":"trim","clipID":"\#(id["c"]!)","edge":"tail","frames":-3}"#)])) }
    #expect(try store.revision() == base + 1 && store.read().sequences[0].clips.first { $0.assetID == "b" }?.sourceRange.start == MediaTime(seconds: 3.1))
    // Its color and sound still change.
    let finished = try store.edit(EditBatch(baseEditRevision: base + 1, notes: [1], operations: [try op(#"{"op":"balance","clipID":"\#(id["c"]!)","exposure":0.2}"#), try op(#"{"op":"gain","target":"\#(id["c"]!)","dB":-2}"#)]))
    #expect(finished.committed)
}

// MARK: Two ways

/// Cut 2 with note 1 two ways (A holds on b a second longer; B cuts to d over it, then back), and
/// note 2 cut after them (c's tail −0.5 s). B went in last, so it plays.
struct TwoWays {
    var store: ProjectStore, feel: ReviewComment, pace: ReviewComment, a: Int, b: Int, delivered: Int

    static func make() throws -> TwoWays {
        let store = try temporaryStore(), cut = TimelineCut.make()
        for a in cut.project.assets { _ = try store.addAsset(a, append: false, expectedRevision: try store.revision()) }
        let inserts = cut.project.sequences[0].clips.map { c -> EditOperation in var o = EditOperation("insert"); o.assetID = c.assetID; o.range = c.sourceRange; o.at = c.start; o.layer = c.layer; return o }
        let seeded = try store.apply(.init(baseEditRevision: try store.revision(), operations: inserts))
        let id = Dictionary(seeded.sequences[0].clips.map { ($0.assetID!, $0.id) }, uniquingKeysWith: { a, _ in a })
        _ = try store.logDailies(Dailies(scenes: cut.context.dailies.scenes, takes: cut.context.dailies.takes))
        let assembly = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
        let feel = try store.addComment(text: "I want to feel how tired she was.", sequenceID: nil, revision: seeded.editRevision, cutID: assembly.id, time: .init(seconds: 6), extra: NoteFields(kind: .feeling))
        let pace = try store.addComment(text: "Out of the launch sooner.", sequenceID: nil, revision: seeded.editRevision, cutID: assembly.id, time: .init(seconds: 11), extra: NoteFields(kind: .pace))
        _ = try store.turnOver(noteIDs: [feel.id, pace.id], latitude: .faithful, waitForOK: false, cutID: assembly.id, sequenceID: nil)
        func edit(_ note: Int, _ ops: String...) throws -> Int { try store.edit(EditBatch(baseEditRevision: store.revision(), notes: [note], operations: ops.map(op))).editRevision }
        let a = try edit(1, #"{"op":"trim","clipID":"\#(id["b"]!)","edge":"tail","frames":30}"#)
        let b = try edit(1, #"{"op":"trim","clipID":"\#(id["b"]!)","edge":"tail","frames":-30}"#, #"{"op":"cutaway","assetID":"d","sourceRange":{"start":1,"end":2},"at":5}"#)
        let delivered = try edit(2, #"{"op":"trim","clipID":"\#(id["c"]!)","edge":"tail","frames":-15}"#)
        return TwoWays(store: store, feel: feel, pace: pace, a: a, b: b, delivered: delivered)
    }

    func deliver(_ revisions: (Int?, Int?)? = nil) throws -> ReviewCut {
        let r = revisions ?? (a, b)
        let options = [NoteOption(label: "A", summary: "Hold on her", revision: r.0, delta: "+1.0 s"), NoteOption(label: "B", summary: "Window, then back", revision: r.1, delta: "0.0 s")]
        let t = try store.turnovers().last!
        return try store.completeTurnover(id: t.id, revision: delivered, sequenceID: nil, answers: [
            AnswerInput(noteID: feel.id, summary: "Two ways. A holds on her, B cuts to the window and back.", start: 4, end: 9, options: options, preferred: "A"),
            AnswerInput(noteID: pace.id, summary: "Out of the launch half a second sooner.", delta: "\u{2212}0.5 s", start: 9, end: 12.5),
        ]).1
    }
    func answer(_ note: ReviewComment) throws -> NoteAnswer { try store.notes().first { $0.id == note.id }!.latestAnswer! }
    func playing() throws -> Sequence { try store.read(revision: store.cuts().first!.editRevision).sequences[0] }
    func clip(_ asset: String) throws -> Clip? { try playing().clips.first { $0.assetID == asset } }
}

@Test func twoWaysAreDeliveredAsTwoRevisions() throws {
    let w = try TwoWays.make(); defer { try? FileManager.default.removeItem(at: w.store.url) }
    expectFailure("invalid_options", index: nil) { _ = try w.deliver((w.a, nil)) }
    #expect(try w.store.cuts().count == 1 && w.store.turnovers().last!.state.isOpen)
    _ = try w.deliver()
    // The version committed last plays; accepting without a pick keeps it, whatever the editor prefers.
    #expect(try w.answer(w.feel).optionInCut == "B" && w.clip("d") != nil)
    try w.store.acceptAnswer(noteID: w.feel.id)
    #expect(try w.answer(w.feel).pick == "B" && w.store.revision() == w.delivered)
}

@Test func optionsThatArentVersionsOfTheCutOnlyRecordThePick() throws {
    // Looks: the director's pick is the look; the cut doesn't change.
    let w = try TwoWays.make(); defer { try? FileManager.default.removeItem(at: w.store.url) }
    let cut = try w.deliver((nil, nil))
    try w.store.pickOption(noteID: w.feel.id, label: "A")
    #expect(try w.answer(w.feel).pick == "A" && w.answer(w.feel).inCut == nil && w.store.revision() == w.delivered && w.store.cuts().first == cut)
}

@Test func usingTheOtherOptionPutsItsVersionInTheCut() throws {
    let w = try TwoWays.make(); defer { try? FileManager.default.removeItem(at: w.store.url) }
    let cut = try w.deliver()
    // Making B from A shortened b, which cut a second out of the music under it.
    #expect(try w.playing().clips.filter { $0.assetID == "music" }.count == 2)
    try w.store.pickOption(noteID: w.feel.id, label: "A")
    // A new revision, and Cut 2 plays it: b held a second longer, no window, the music whole as in A, note 2's trim kept.
    let after = try w.store.cuts().first!
    #expect(try after.id == cut.id && after.editRevision == w.delivered + 1 && w.store.revision() == w.delivered + 1)
    #expect(try w.clip("d") == nil && w.clip("b")?.range == MediaRange(start: 4, end: 10) && w.clip("c")?.range == MediaRange(start: 10, end: 13.5) && w.playing().clips.filter { $0.assetID == "music" }.map(\.range) == [MediaRange(start: 0, end: 13)])
    var feel = try w.answer(w.feel)
    #expect(feel.pick == "A" && feel.inCut == "A" && feel.range == MediaRange(start: 4, end: 10))
    // Note 2's change moved with it, so Play changes still lands on it.
    #expect(try w.answer(w.pace).range == MediaRange(start: 10, end: 13.5))
    #expect(try w.store.events(since: 0).contains { $0.summary == "Used option A for note 1" })

    // Change pick: B again, exactly as delivered.
    try w.store.pickOption(noteID: w.feel.id, label: "B")
    #expect(try OptionSwap.plain(w.playing().clips, origin: .zero) == OptionSwap.plain(w.store.read(revision: w.delivered).sequences[0].clips, origin: .zero))
    #expect(try w.store.cuts().first!.editRevision == w.delivered + 2 && w.answer(w.pace).range == MediaRange(start: 9, end: 12.5))
    // Undo of a first pick puts the version back and leaves no pick.
    try w.store.pickOption(noteID: w.feel.id, label: "B", record: false)
    feel = try w.answer(w.feel)
    #expect(try feel.pick == nil && feel.inCut == "B" && w.store.revision() == w.delivered + 2)

    // A locked scene keeps its cut.
    try w.store.lockScene(id: "s1", locked: true)
    expectFailure("scene_locked", index: nil) { try w.store.pickOption(noteID: w.feel.id, label: "A") }
    #expect(try w.store.revision() == w.delivered + 2 && w.answer(w.feel).inCut == "B")
    try w.store.lockScene(id: "s1", locked: false)
    // Only the latest cut can change.
    _ = try w.store.createCut(name: "Cut 3", sequenceID: nil, revision: nil)
    expectFailure("cut_moved_on", index: nil) { try w.store.pickOption(noteID: w.feel.id, label: "A") }
}

@Test func optionSwapFindsTheShotsWhereverTheySitNow() throws {
    var cut = TimelineCut.make()
    let (b, _) = try cut.run([#"{"op":"cutaway","assetID":"d","sourceRange":{"start":1,"end":2},"at":5}"#])
    let (a, _) = try cut.run([#"{"op":"trim","clipID":"c2","edge":"tail","frames":30}"#])
    // Nothing else changed: A exactly as cut.
    #expect(try OptionSwap.swap(b.sequences[0], from: b.sequences[0], to: a.sequences[0])?.sequence.clips == a.sequences[0].clips)
    // A later note shortened the first shot, so B's shots sit half a second earlier now.
    cut.project = b
    let (later, _) = try cut.run([#"{"op":"trim","clipID":"c1","edge":"tail","frames":-15}"#], notes: [2])
    let swapped = try #require(try OptionSwap.swap(later.sequences[0], from: b.sequences[0], to: a.sequences[0]))
    let s = swapped.sequence
    #expect(s.clips.first { $0.id == "c1" }?.range == MediaRange(start: 0, end: 3.5) && s.clips.first { $0.id == "c2" }?.range == MediaRange(start: 3.5, end: 9.5))
    #expect(s.clips.first { $0.id == "c3" }?.range == MediaRange(start: 9.5, end: 13.5) && !s.clips.contains { $0.assetID == "d" })
    #expect(swapped.at == MediaTime(seconds: 3.5) && swapped.removed == MediaTime(seconds: 5) && swapped.inserted == MediaTime(seconds: 6))
    // A shot that only one version has takes in the one before it, so there's something to find.
    var shots = TimelineCut.make().project.sequences[0]; shots.clips.removeAll { $0.id == "m1" }
    var added = shots; added.clips[2].start = MediaTime(seconds: 11); added.clips.append(Clip(id: "x", assetID: "d", name: "d", start: .init(seconds: 9), sourceRange: .init(start: 0, end: 2)))
    let w = try #require(OptionSwap.window(OptionSwap.units(shots), OptionSwap.units(added)))
    #expect(w.0 == 1..<2 && w.1 == 1..<3)
    #expect(OptionSwap.window(OptionSwap.units(shots), OptionSwap.units(shots)) == nil)
    // The same shots changed since: it says so instead of guessing.
    cut.project = b
    let (regraded, _) = try cut.run([#"{"op":"reframe","clipID":"c2","scale":1.2}"#], notes: [2])
    expectFailure("option_moved", index: nil) { _ = try OptionSwap.swap(regraded.sequences[0], from: b.sequences[0], to: a.sequences[0]) }
}

// MARK: Reading

@Test func theTimelineReadsAsOpenTimelineIOAndAnOutline() throws {
    var cut = TimelineCut.make()
    _ = try cut.apply(#"{"op":"transition","editPoint":"c1|c2","type":"dissolve","frames":12}"#, #"{"op":"reframe","clipID":"c1","scale":1.1}"#, #"{"op":"duck","track":"A2","dB":-6}"#)
    var graphic = MediaAsset(id: "g", name: "Title.mov", path: "/Title.mov", duration: .init(seconds: 4), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)]); graphic.graphic = "Title · Two years."
    cut.project.assets.append(graphic)
    let placed = try cut.apply(#"{"op":"placeGraphic","graphic":"Title · Two years.","at":2,"seconds":4}"#)
    let doc = TimelineExport.document(.init(project: cut.project, sequence: cut.project.sequences[0], cutName: "Cut 3", dailies: cut.context.dailies))
    let otio = doc.otio
    #expect(otio["OTIO_SCHEMA"].string == "Timeline.1" && otio["tracks"]["OTIO_SCHEMA"].string == "Stack.1")
    #expect(otio["metadata"]["direction"]["cut"].string == "Cut 3" && otio["metadata"]["direction"]["rate"].double == 30 && otio["metadata"]["direction"]["width"].int == 1920)
    let tracks = otio["tracks"]["children"].array!
    #expect(tracks.map { $0["name"].string! } == ["V1", "V2", "A1", "A2"] && tracks.map { $0["kind"].string! } == ["Video", "Video", "Audio", "Audio"])
    let v1 = tracks[0]["children"].array!
    #expect(v1.map { $0["OTIO_SCHEMA"].string! } == ["Clip.2", "Transition.1", "Clip.2", "Clip.2"])
    #expect(v1[0]["metadata"]["direction"]["id"].string == "c1" && v1[0]["metadata"]["direction"]["take"].string == "1A T1" && v1[0]["media_references"]["DEFAULT_MEDIA"]["OTIO_SCHEMA"].string == "ExternalReference.1")
    #expect(v1[0]["source_range"]["start_time"]["value"].double == 60 && v1[0]["source_range"]["duration"]["value"].double == 120 && v1[0]["effects"].array?[0]["effect_name"].string == "transform")
    #expect(v1[1]["transition_type"].string == "SMPTE_Dissolve" && v1[1]["in_offset"]["value"].double == 6 && v1[1]["out_offset"]["value"].double == 6)
    #expect(tracks[0]["markers"].array?.first?["metadata"]["direction"]["scene"]["number"].int == 1)
    let v2 = tracks[1]["children"].array!
    #expect(v2[0]["OTIO_SCHEMA"].string == "Gap.1" && v2[1]["media_references"]["DEFAULT_MEDIA"]["generator_kind"].string == "direction.graphic" && v2[1]["metadata"]["direction"]["aboveLook"].bool == true)
    #expect(tracks[2]["children"].array?[0]["metadata"]["direction"]["linked"].string == "picture" && tracks[3]["children"].array?[0]["metadata"]["direction"]["duckKeys"].array?.count == 8)
    let lines = doc.outline.split(separator: "\n").map(String.init)
    #expect(lines[0] == "Cut 3 · 0:13:00 · 1920×1080 · 30 · no look")
    #expect(lines[1] == "V2  00:02:00–00:06:00  \(placed.operations[0].clipIDs![0])  graphic \"Title · Two years.\"  above look")
    #expect(lines[2] == "V1  00:00:00–00:04:00  c1  1A T1  src 00:02:00–00:06:00  reframe(1.1)")
    #expect(lines[3] == "V1  00:04:00–00:09:00  c2  1B T2  src 00:03:00–00:08:00  dissolve 12f in  ‹scene 1›")
    #expect(lines[5] == "A2  00:00:00–00:13:00  m1  music \"Felt piano\"  src 00:00:00–00:13:00  ducked \u{2212}6 dB under A1")
    // With a range, only what overlaps it.
    let late = TimelineExport.document(.init(project: cut.project, sequence: cut.project.sequences[0], cutName: "Cut 3", dailies: cut.context.dailies, range: MediaRange(start: 9.5, end: 12)))
    #expect(late.otio["tracks"]["children"].array?[0]["children"].array?.compactMap { $0["metadata"]["direction"]["id"].string } == ["c3"])
}

@Test func theCatalogCoversEverySpecOperationAndEffect() throws {
    let ops = Set(EditCatalog.operations.map(\.op))
    for name in ["insert", "overwrite", "removeRange", "remove", "move", "split", "trim", "roll", "slip", "slide", "splitEdit", "replaceTake", "removeWords", "tightenPauses", "speed", "freeze", "reframe", "balance", "matchBalance", "cameraLUT", "addEffect", "setEffect", "removeEffect", "transition", "removeTransition", "cutaway", "placeGraphic", "placeMade", "gain", "fade", "duck", "placeMusic", "syncSound", "audio", "format", "duplicateSequence"] { #expect(ops.contains(name), "\(name)") }
    for name in ["transform", "blend", "mask", "blur", "sharpen", "stabilize", "filter.grain", "filter.letterbox", "shader"] { #expect(EditCatalog.effect(name) != nil, "\(name)") }
    #expect(EditCatalog.errors.map(\.code).contains("words_are_yours") && EditCatalog.json()["operations"].array?.count == EditCatalog.operations.count)
    let params = try ShaderHeader.params("// direction: param amount 0 1 0.5\n// direction: param tint color #F2A33A\n[[ stitchable ]] half4 effect(coreimage::sample_h s, float amount, float3 tint) { return s; }")
    #expect(params.map(\.name) == ["amount", "tint"] && params[1].kind == "color" && params[0].max == 1)
    expectFailure("shader_invalid", index: nil) { _ = try ShaderHeader.params("// direction: param amount 1 0 0.5") }
    #expect(CutTimecode.string(72.27, rate: 30) == "01:12:08" && CutTimecode.rate(24_000.0 / 1_001) == "23.976" && CutTimecode.length(220, rate: 24) == "3:40:00")
}

// MARK: Sync (footage-index.md › Sync)

@Test func aCutawayWithoutASourceRangePlaysTheSameMomentFromASyncedTake() throws {
    var cut = TimelineCut.make()
    // d started recording 1.5 s after a: a's time = d's time + 1.5.
    cut.context.dailies.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "a", takes: [SyncedTake(assetID: "a", offset: 0, match: 1), SyncedTake(assetID: "d", offset: 1.5, match: 0.98)], method: "sound", createdAt: 0)]
    // At cut 1.0, V1 plays a at 3.0, which is d at 1.5.
    let r = try cut.apply(#"{"op":"cutaway","assetID":"d","at":1,"seconds":2}"#)
    let away = clip(cut.project, r.operations[0].clipIDs![0])
    #expect(close(away.sourceRange.start.seconds, 1.5, 0.001) && close(away.sourceRange.duration.seconds, 2, 0.001) && away.layer == 1)
    // Under the cut between c1 and c2 the story is b, which isn't in sync with d.
    expectFailure("not_in_sync", index: 0) { _ = try cut.run([#"{"op":"cutaway","assetID":"d","at":5,"seconds":2}"#]) }
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"cutaway","assetID":"d","at":1}"#]) }
    // d hadn't started at cut 0 (a at 2.0 is d at 0.5, but 0.6 s earlier it wasn't recording).
    cut.context.dailies.syncGroups![0].takes[1].offset = 2.6
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"cutaway","assetID":"d","at":0,"seconds":1}"#]) }
}

@Test func syncedClipsFollowTheStoryAsTheCutChanges() throws {
    var cut = TimelineCut.make()
    cut.context.dailies.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "a", takes: [SyncedTake(assetID: "a", offset: 0, match: 1), SyncedTake(assetID: "d", offset: 1.5, match: 0.98)], method: "sound", createdAt: 0)]
    let id = try cut.apply(#"{"op":"cutaway","assetID":"d","at":1,"seconds":2}"#).operations[0].clipIDs![0]
    #expect(clip(cut.project, id).synced == true)
    // Slipping the story half a second later: the cutaway follows (a at 3.5 is d at 2.0).
    let slipped = try cut.apply(#"{"op":"slip","clipID":"c1","frames":15}"#)
    #expect(close(clip(cut.project, id).sourceRange.start.seconds, 2.0, 0.001))
    #expect(slipped.warnings.isEmpty && slipped.operations[0].changes.contains { $0.tracks == ["V2"] })
    // Removing a passage before it moves it with everything else and keeps it lined up.
    try cut.apply(#"{"op":"removeRange","range":{"start":0.5,"end":0.8}}"#)
    let after = clip(cut.project, id)
    #expect(close(after.start.seconds, 0.7, 0.001) && close(after.sourceRange.start.seconds, 2.0, 0.001) && after.synced == true)
    // Another take on V1 that isn't in sync: it keeps what it plays, stops following, and says so.
    let under = try #require(cut.project.sequences[0].clips.first { $0.layer == 0 && $0.kind == .video && $0.start.seconds <= 0.7 && $0.end.seconds > 0.7 })
    let swapped = try cut.apply("{\"op\":\"replaceTake\",\"clipID\":\"\(under.id)\",\"withAssetID\":\"b\",\"alignOn\":\"head\"}")
    #expect(clip(cut.project, id).synced == nil && swapped.warnings.contains { $0.contains("isn't over a take it's in sync with") })

    // Slipping the cutaway itself is choosing another moment by hand: no longer synced, no warning.
    var hand = TimelineCut.make()
    hand.context.dailies.syncGroups = cut.context.dailies.syncGroups
    let away = try hand.apply(#"{"op":"cutaway","assetID":"d","at":1,"seconds":2}"#).operations[0].clipIDs![0]
    let r = try hand.apply("{\"op\":\"slip\",\"clipID\":\"\(away)\",\"frames\":6}")
    #expect(clip(hand.project, away).synced == nil && r.warnings.isEmpty && close(clip(hand.project, away).sourceRange.start.seconds, 1.7, 0.001))
}

@Test func aSyncedCutawaySplitsWhereTheStoryJumps() throws {
    var cut = TimelineCut.make()
    cut.context.dailies.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "a", takes: [SyncedTake(assetID: "a", offset: 0, match: 1), SyncedTake(assetID: "d", offset: 1.5, match: 0.98)], method: "sound", createdAt: 0)]
    // V1 plays a 2–6, then jumps to a 10–15.
    cut.project.sequences[0].clips[1] = Clip(id: "c2", assetID: "a", name: "a", start: .init(seconds: 4), sourceRange: .init(start: 10, end: 15))
    try cut.apply(#"{"op":"cutaway","assetID":"d","at":3,"seconds":2}"#)
    let pieces = cut.project.sequences[0].clips.filter { $0.assetID == "d" }.sorted { $0.start < $1.start }
    #expect(pieces.count == 2 && pieces.allSatisfy { $0.synced == true })
    // a at 5 is d at 3.5; a at 10 is d at 8.5.
    #expect(close(pieces[0].start.seconds, 3) && close(pieces[0].sourceRange.start.seconds, 3.5, 0.001) && close(pieces[0].end.seconds, 4, 0.001))
    #expect(close(pieces[1].start.seconds, 4) && close(pieces[1].sourceRange.start.seconds, 8.5, 0.001) && close(pieces[1].end.seconds, 5, 0.001))
}

@Test func syncSoundPlaysAnotherTakesSoundUnderAStoryClip() throws {
    var cut = TimelineCut.make()
    cut.context.dailies.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "a", takes: [SyncedTake(assetID: "a", offset: 0, match: 1), SyncedTake(assetID: "d", offset: 1.5, match: 0.98)], method: "sound", createdAt: 0)]
    // c1 is the sound take already.
    expectFailure("bad_argument", index: 0) { _ = try cut.run([#"{"op":"syncSound","clipID":"c1"}"#]) }
    expectFailure("not_in_sync", index: 0) { _ = try cut.run([#"{"op":"syncSound","clipID":"c2"}"#]) }
    let r = try cut.apply(#"{"op":"syncSound","clipID":"c1","assetID":"d"}"#)
    let sound = clip(cut.project, r.operations[0].clipIDs![0])
    // Lined up (a at 2.0 is d at 0.5), on the first free sound track (the music has A2), and c1's own sound is off.
    #expect(sound.kind == .audio && sound.trackName == "A3" && sound.synced == true && close(sound.start.seconds, 0) && close(sound.sourceRange.start.seconds, 0.5, 0.001) && close(sound.duration.seconds, 4, 0.001))
    #expect(clip(cut.project, "c1").audioOverrides["2"]?.muted == true)
    #expect(TimelineExport.document(.init(project: cut.project, sequence: cut.project.sequences[0], cutName: "Cut 1", dailies: cut.context.dailies)).outline.contains("in sync"))
    // It follows the story too.
    try cut.apply(#"{"op":"slip","clipID":"c1","frames":15}"#)
    #expect(close(clip(cut.project, sound.id).sourceRange.start.seconds, 1.0, 0.001))
    // Naming the clip's own take puts its own sound back.
    let back = try cut.apply(#"{"op":"syncSound","clipID":"c1","assetID":"a"}"#)
    #expect(!cut.project.sequences[0].clips.contains { $0.id == sound.id } && clip(cut.project, "c1").audioOverrides["2"]?.muted == false)
    #expect(back.operations[0].summary.contains("own sound again"))
}

@Test func ownSoundBackOnHalfASplitClipLeavesTheOtherHalfInSync() throws {
    var cut = TimelineCut.make()
    cut.context.dailies.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "a", takes: [SyncedTake(assetID: "a", offset: 0, match: 1), SyncedTake(assetID: "d", offset: 1.5, match: 0.98)], method: "sound", createdAt: 0)]
    try cut.apply(#"{"op":"syncSound","clipID":"c1","assetID":"d"}"#)
    try cut.apply(#"{"op":"split","clipID":"c1","at":2}"#)
    let right = try #require(cut.project.sequences[0].clips.first { $0.layer == 0 && $0.kind == .video && $0.id != "c1" && close($0.start.seconds, 2) })
    try cut.apply(#"{"op":"syncSound","clipID":"c1","assetID":"a"}"#)
    // d's sound is gone from under c1 only: the right half still plays it, lined up.
    let laid = cut.project.sequences[0].clips.filter { $0.synced == true && $0.kind == .audio }
    #expect(laid.count == 1 && close(laid[0].start.seconds, 2) && close(laid[0].end.seconds, 4, 0.001) && close(laid[0].sourceRange.start.seconds, 2.5, 0.001))
    #expect(clip(cut.project, "c1").audioOverrides["2"]?.muted == false && clip(cut.project, right.id).audioOverrides["2"]?.muted == true)
}

@Test func theDirectorShapesSyncAndDirectionKeepsTheirChoices() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-sync-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try ProjectStore.create(at: dir.appendingPathComponent("Sync.direction"), name: "Sync")
    let found = SyncGroup(id: "g", soundAssetID: "cam", takes: [SyncedTake(assetID: "cam", offset: 0, match: 1), SyncedTake(assetID: "screen", offset: -0.089, match: 0.99), SyncedTake(assetID: "phone", offset: 2.5, match: 0.8)], method: "sound", createdAt: 0)
    try store.saveSync([found], checked: ["cam", "screen", "phone"])
    // Use the screen recording's sound: every offset moves to its clock.
    try store.setSyncSound(assetID: "screen")
    var g = try #require(try store.dailies().syncGroups?.first)
    #expect(g.soundAssetID == "screen" && g.take("screen")?.offset == 0 && g.take("cam")?.offset == 0.089 && g.take("phone")?.offset == 2.589)
    #expect(try store.dailies().syncedTime(10, from: "phone", to: "cam") == 12.5)
    // A fresh pass finds the same takes: the director's sound stays.
    try store.saveSync([found], checked: [])
    #expect(try store.dailies().syncGroups?.first?.soundAssetID == "screen")
    // Not in Sync: the phone leaves, and the pair is remembered.
    try store.unsync(assetID: "phone")
    let d = try store.dailies()
    g = try #require(d.syncGroups?.first)
    #expect(g.takes.map(\.assetID).sorted() == ["cam", "screen"] && d.notInSync?.contains(["cam", "phone"]) == true && d.notInSync?.contains(["phone", "screen"]) == true)
    // A group of one is no group.
    try store.unsync(assetID: "cam")
    #expect(try store.dailies().syncGroups?.isEmpty == true)
    #expect(Set(try store.dailies().syncChecked ?? []) == ["cam", "screen", "phone"])
}
