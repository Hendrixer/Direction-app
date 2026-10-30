import Testing
import Foundation
@testable import DirectionCore

@Test func rationalTimeEquality() {
    #expect(MediaTime(value: 1, timescale: 2) == MediaTime(value: 300, timescale: 600))
    #expect(Set([MediaTime(value: 1, timescale: 2), MediaTime(value: 300, timescale: 600)]).count == 1)
}

func fixtureProject() -> Project {
    var p = Project(name: "Fixture")
    let asset = MediaAsset(id: "asset-fixture", name: "Two-track.mov", path: "/fixture.mov", duration: .init(seconds: 10), video: [.init(id: 1, width: 320, height: 180, frameRate: 30)], audio: [.init(id: 2, index: 0, label: "Dialogue", channels: 1, sampleRate: 48_000), .init(id: 3, index: 1, label: "Music", channels: 2, sampleRate: 48_000)])
    p.assets = [asset]
    p.sequences[0].clips = [Clip(id: "clip-main", assetID: asset.id, name: asset.name, sourceRange: .init(start: 0, end: 10))]
    return p
}

func temporaryStore() throws -> ProjectStore {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-tests-" + UUID().uuidString + ".direction")
    return try .create(at: path, name: "Test")
}

func seededStore() throws -> ProjectStore {
    let store = try temporaryStore(), source = fixtureProject()
    _ = try store.addAsset(source.assets[0], append: true, expectedRevision: 0)
    return store
}

func expectError(_ code: String, _ body: () throws -> Void) {
    do { try body(); Issue.record("Expected error \(code)") }
    catch let e as DirectionError { #expect(e.code == code) }
    catch { Issue.record("Unexpected error: \(error)") }
}

@Test func theFirstFootageSetsTheFilmsSizeAndRate() throws {
    func take(_ id: String, _ width: Int, _ height: Int, _ fps: Double) -> MediaAsset {
        MediaAsset(id: id, name: id + ".mov", path: "/\(id).mov", duration: .init(seconds: 10), video: [.init(id: 1, width: width, height: height, frameRate: fps)])
    }
    let store = try temporaryStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    var p = try store.addAsset(take("a", 3840, 2160, 29.97), append: false, expectedRevision: 0)
    #expect(p.sequences[0].width == 3840 && p.sequences[0].height == 2160 && p.sequences[0].frameRate == FrameRate(30000, 1001))
    // Later footage leaves it alone.
    p = try store.addAsset(take("b", 1920, 1080, 24), append: false, expectedRevision: p.editRevision)
    #expect(p.sequences[0].width == 3840 && p.sequences[0].frameRate == FrameRate(30000, 1001))
    // A rate chosen in Settings wins over the footage's.
    let other = try temporaryStore(); defer { try? FileManager.default.removeItem(at: other.url) }
    let q = try other.addAsset(take("c", 1080, 1920, 30.00005), append: false, frameRate: .nearest(23.976), expectedRevision: 0)
    #expect(q.sequences[0].width == 1080 && q.sequences[0].height == 1920 && q.sequences[0].frameRate == FrameRate(24000, 1001))
    #expect(FrameRate.nearest(30.000051) == FrameRate(30, 1) && FrameRate.nearest(59.94) == FrameRate(60000, 1001) && FrameRate.nearest(25) == FrameRate(25, 1))
}

@Test func rationalArithmeticPreservesFractionalFrames() {
    let frame = MediaTime(value: 1001, timescale: 30_000)
    #expect(frame.scaled(by: 108_000) == MediaTime(value: 108_108, timescale: 30))
    #expect(frame + frame == MediaTime(value: 2002, timescale: 30_000))
    #expect(frame - frame == .zero)
    #expect(MediaRange(start: 1, end: 2).contains(.init(seconds: 1)))
    #expect(!MediaRange(start: 1, end: 2).contains(.init(seconds: 2)))
}

@Test func rippleCutKeepsAllLayersSynchronized() throws {
    var p = fixtureProject()
    var broll = p.sequences[0].clips[0]; broll.id = "broll"; broll.lineageID = "broll"; broll.layer = 1
    var audio = p.sequences[0].clips[0]; audio.id = "audio"; audio.lineageID = "audio"; audio.kind = .audio
    p.sequences[0].clips += [broll, audio]
    var op = EditOperation("removeRange"); op.range = .init(start: 2, end: 4)
    let result = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p)
    #expect(result.sequences[0].duration == MediaTime(seconds: 8))
    #expect(result.sequences[0].clips.count == 6)
    for lineage in ["clip-main", "broll", "audio"] {
        let pieces = result.sequences[0].clips.filter { $0.lineageID == lineage }.sorted { $0.start < $1.start }
        #expect(pieces[0].sourceRange == MediaRange(start: 0, end: 2))
        #expect(pieces[1].sourceRange == MediaRange(start: 4, end: 10))
        #expect(pieces[1].start == MediaTime(seconds: 2))
    }
}

@Test func nonRippleCutRetainsGap() throws {
    let p = fixtureProject()
    var op = EditOperation("removeRange"); op.range = .init(start: 2, end: 4); op.ripple = false
    let result = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p)
    #expect(result.sequences[0].duration == MediaTime(seconds: 10))
    #expect(result.sequences[0].clips[1].start == MediaTime(seconds: 4))
}

@Test func splitUsesSourceTimeAtPlaybackSpeed() throws {
    var p = fixtureProject(); p.sequences[0].clips[0].speed = 2
    var op = EditOperation("split"); op.clipID = "clip-main"; op.at = .init(seconds: 2)
    let result = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p)
    #expect(result.sequences[0].clips[0].sourceRange.end == MediaTime(seconds: 4))
    #expect(result.sequences[0].clips[1].sourceRange.start == MediaTime(seconds: 4))
    #expect(result.sequences[0].clips[1].start == MediaTime(seconds: 2))
    #expect(result.sequences[0].duration == MediaTime(seconds: 5))
}

@Test func independentAudioTrackSettingsSurviveCuts() throws {
    var p = fixtureProject()
    p.assets[0].audio[1].settings.muted = true
    var override = AudioSettings(gainDB: -5); override.effects.highPassHz = 100
    p.sequences[0].clips[0].audioOverrides["2"] = override
    var op = EditOperation("removeRange"); op.range = .init(start: 2, end: 3)
    let result = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p)
    #expect(result.assets[0].audio[0].settings.muted == false)
    #expect(result.assets[0].audio[1].settings.muted == true)
    #expect(result.sequences[0].clips.allSatisfy { $0.audioOverrides["2"] == override })
}

@Test func overlappingVideoNeedsAnotherLayer() throws {
    let p = fixtureProject()
    var op = EditOperation("insert"); op.assetID = p.assets[0].id; op.at = .zero
    expectError("overlap") { _ = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p) }
    op.layer = 1
    #expect(try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p).sequences[0].clips.count == 2)
}

@Test func invalidAndOutOfBoundsEditsFail() {
    let p = fixtureProject()
    var op = EditOperation("trim"); op.clipID = "clip-main"; op.range = .init(start: 0, end: 11)
    expectError("bad_argument") { _ = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p) }
    var format = EditOperation("format"); format.width = 1_079
    expectError("bad_argument") { _ = try EditReducer.apply(.init(baseEditRevision: 0, operations: [format]), to: p) }
    var audio = EditOperation("audio"); audio.assetID = p.assets[0].id; audio.audioTrackID = 88; audio.audio = .init(muted: true)
    expectError("bad_argument") { _ = try EditReducer.apply(.init(baseEditRevision: 0, operations: [audio]), to: p) }
}

@Test func removalCanEmptySequenceWithoutCorruptingProject() throws {
    let p = fixtureProject()
    var op = EditOperation("removeRange"); op.range = .init(start: 0, end: 10)
    let result = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p)
    #expect(result.sequences[0].clips.isEmpty)
    #expect(result.assets.count == 1)
}

@Test func atomicBatchDoesNotPartiallyPersist() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    let p = try store.read()
    var valid = EditOperation("split"); valid.clipID = p.sequences[0].clips[0].id; valid.at = .init(seconds: 2)
    let invalid = EditOperation("unsupported")
    expectError("unknown_op") { _ = try store.apply(.init(baseEditRevision: 1, operations: [valid, invalid])) }
    #expect(try store.read() == p)
    #expect(try store.revision() == 1)
}

@Test func twoConnectionsCannotOverwriteARevision() async throws {
    let first = try seededStore(); defer { try? FileManager.default.removeItem(at: first.url) }
    let second = try ProjectStore(url: first.url)
    var op = EditOperation("removeRange"); op.range = .init(start: 2, end: 3)
    let batchA = EditBatch(baseEditRevision: 1, operations: [op]), batchB = EditBatch(baseEditRevision: 1, operations: [op])
    let outcomes = await withTaskGroup(of: String.self) { group in
        group.addTask { do { _ = try first.apply(batchA); return "ok" } catch let e as DirectionError { return e.code } catch { return "unexpected" } }
        group.addTask { do { _ = try second.apply(batchB); return "ok" } catch let e as DirectionError { return e.code } catch { return "unexpected" } }
        var values: [String] = []; for await value in group { values.append(value) }; return values
    }
    #expect(outcomes.sorted() == ["ok", "revision_conflict"])
    #expect(try first.revision() == 2)
}

@Test func idempotentRetryDoesNotDuplicateOrRollBackNewerWork() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    var op = EditOperation("removeRange"); op.range = .init(start: 2, end: 3)
    let batch = EditBatch(baseEditRevision: 1, idempotencyKey: "repeat", operations: [op])
    let original = try store.apply(batch)
    var format = EditOperation("format"); format.width = 1080; format.height = 1920
    _ = try store.apply(.init(baseEditRevision: 2, operations: [format]))
    let retry = try store.apply(batch)
    #expect(retry == original)
    #expect(try store.revision() == 3)
    var changed = batch; changed.summary = "Other request"
    expectError("idempotency_conflict") { _ = try store.apply(changed) }
}

@Test func commentsKeepOriginalContextAfterRippleEdits() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    let p = try store.read(), s = p.sequences[0]
    let cut = try store.createCut(name: "Review 1", sequenceID: s.id, revision: 1)
    let comment = try store.addComment(text: "Keep this line", sequenceID: s.id, revision: 1, cutID: cut.id, range: .init(start: 6, end: 8))
    #expect(try store.revision() == 1)
    var op = EditOperation("removeRange"); op.range = .init(start: 1, end: 3)
    let changed = try store.apply(.init(baseEditRevision: 1, operations: [op]))
    let projection = ReviewAnchoring.project(comment.anchors[0], onto: changed.sequences[0])
    #expect(projection.status == "exact")
    #expect(projection.ranges[0] == MediaRange(start: 4, end: 6))
    #expect(try store.comment(comment.id).range == MediaRange(start: 6, end: 8))
    #expect(try store.read(revision: 1).sequences[0].duration == MediaTime(seconds: 10))
}

@Test func removedAndDuplicatedAnchorsAreExplicit() throws {
    var p = fixtureProject(), s = p.sequences[0]
    let anchor = ReviewAnchoring.anchors(project: p, sequence: s, range: .init(start: 2, end: 4), time: nil)[0]
    s.clips = EditReducer.removing(.init(start: 2, end: 4), from: s.clips, ripple: true)
    #expect(ReviewAnchoring.project(anchor, onto: s).status == "removed")
    var duplicate = p.sequences[0].clips[0]; duplicate.id = "duplicate"; duplicate.layer = 1
    p.sequences[0].clips.append(duplicate)
    #expect(ReviewAnchoring.project(anchor, onto: p.sequences[0]).status == "ambiguous")
}

@Test func exactBoundaryMomentBelongsToTheFollowingClip() throws {
    var p = fixtureProject()
    var op = EditOperation("split"); op.clipID = "clip-main"; op.at = .init(seconds: 5)
    p = try EditReducer.apply(.init(baseEditRevision: 0, operations: [op]), to: p)
    let anchors = ReviewAnchoring.anchors(project: p, sequence: p.sequences[0], range: nil, time: .init(seconds: 5))
    #expect(anchors.count == 1)
    #expect(anchors[0].clipID == p.sequences[0].clips[1].id)
}

@Test func feedbackCannotBeApprovedByAgent() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    let c = try store.addComment(text: "Change this", sequenceID: nil, revision: 1, time: .init(seconds: 1))
    let addressed = try store.reply(commentID: c.id, text: "Changed", author: "Agent", revision: 1, status: "addressed")
    #expect(addressed.status == "addressed")
    expectError("director_action_required") { _ = try store.reply(commentID: c.id, text: "Approved", author: "Agent", status: "accepted") }
    #expect(try store.reply(commentID: c.id, text: "Accepted", author: "Director", status: "accepted", asDirector: true).status == "accepted")
    #expect(try store.comments(since: c.cursor).count == 1)
}

func transcriptFixture() -> (Project, SourceTranscript) {
    let p = fixtureProject()
    let words = ["Make", "a", "better", "video"].enumerated().map { i, text in TranscriptWord(id: "w\(i)", text: text, range: .init(start: Double(i), end: Double(i) + 0.8)) }
    return (p, SourceTranscript(assetID: p.assets[0].id, audioTrackID: 2, words: words))
}

@Test func transcriptUsesTheLatestChosenEmbeddedTrack() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    let assetID = try store.read().assets[0].id
    var first = transcriptFixture().1; first.assetID = assetID
    try store.saveTranscript(first)
    var second = first; second.audioTrackID = 3; second.words[0].text = "Second"
    try store.saveTranscript(second)
    let words = TranscriptEditing.words(in: try store.read().sequences[0], transcripts: try store.transcripts())
    #expect(words.first?.text == "Second")
    #expect(try store.transcripts().count == 2)
}

@Test func voiceoverTranscriptIsAvailableOverUntranscribedVideo() throws {
    var (p, transcript) = transcriptFixture()
    var audio = p.assets[0]; audio.id = "voice"; audio.video = []
    p.assets.append(audio)
    let clip = Clip(assetID: audio.id, name: "Voiceover", kind: .audio, sourceRange: .init(start: 0, end: 10))
    p.sequences[0].clips.append(clip)
    transcript.assetID = audio.id
    let words = TranscriptEditing.words(in: p.sequences[0], transcripts: [transcript])
    #expect(words.count == 4)
    #expect(words[0].clipID == clip.id)
}

@Test func transcriptTextDeletionMapsToTimedFootage() throws {
    let (p, t) = transcriptFixture(), words = TranscriptEditing.words(in: p.sequences[0], transcripts: [t])
    let ids = try TranscriptEditing.deletedIDs(original: words, editedText: "Make a video")
    #expect(ids == ["clip-main:w2"])
    #expect(try TranscriptEditing.deletionRanges(wordIDs: ids, words: words) == [MediaRange(start: 2, end: 2.8)])
    expectError("transcript_insert_not_supported") { _ = try TranscriptEditing.deletedIDs(original: words, editedText: "Make a brilliant video") }
}

@Test func repeatedTranscriptWordsRequireExactSelection() throws {
    let (p, t) = transcriptFixture()
    var words = TranscriptEditing.words(in: p.sequences[0], transcripts: [t])
    words[0].text = "Go"; words[1].text = "go"; words[2].text = "home"; words.removeLast()
    expectError("ambiguous_transcript_edit") { _ = try TranscriptEditing.deletedIDs(original: words, editedText: "go home") }
    #expect(try TranscriptEditing.deletionRanges(wordIDs: [words[0].id], words: words).first?.start == .zero)
}

@Test func transcriptContextIsCapturedAndRestoreKeepsHistory() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    let assetID = try store.read().assets[0].id
    var transcript = transcriptFixture().1; transcript.assetID = assetID
    try store.saveTranscript(transcript)
    let c = try store.addComment(text: "Keep better", sequenceID: nil, revision: 1, range: .init(start: 2, end: 3))
    #expect(c.transcriptContext.map(\.text) == ["better"])
    transcript.words[2].text = "changed"; try store.saveTranscript(transcript)
    #expect(try store.comment(c.id).transcriptContext[0].text == "better")
    var op = EditOperation("removeRange"); op.range = .init(start: 1, end: 2)
    _ = try store.apply(.init(baseEditRevision: 1, operations: [op]))
    let restored = try store.restore(revision: 1, expectedRevision: 2, key: "restore")
    #expect(restored.editRevision == 3)
    #expect(restored.sequences[0].duration == MediaTime(seconds: 10))
    #expect(try store.read(revision: 2).sequences[0].duration == MediaTime(seconds: 9))
}

@Test func invalidRegionsAndTranscriptsAreRejected() throws {
    let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
    expectError("invalid_region") { _ = try store.addComment(text: "Here", sequenceID: nil, revision: 1, time: .init(seconds: 1), region: .init(x: 0.9, y: 0, width: 0.2, height: 0.5)) }
    var t = transcriptFixture().1; t.assetID = try store.read().assets[0].id; t.words[0].range = .init(start: 20, end: 21)
    expectError("invalid_transcript") { try store.saveTranscript(t) }
}

@Test func reviewMarkersFollowRippleAndDisappearWithRemovedSource() throws {
    let store = try seededStore(), original = try store.read()
    let note = try store.addComment(text: "Review this", sequenceID: original.sequences[0].id, revision: 1, range: .init(start: 6, end: 8))
    #expect(ReviewAnchoring.markerTime(note, in: original.sequences[0], revision: 1) == 6)
    var op = EditOperation("removeRange"); op.range = .init(start: 0, end: 2)
    let cut = try store.apply(.init(baseEditRevision: 1, operations: [op]))
    #expect(ReviewAnchoring.markerTime(note, in: cut.sequences[0], revision: cut.editRevision) == 4)
    op.range = .init(start: 4, end: 6)
    let removed = try store.apply(.init(baseEditRevision: 2, operations: [op]))
    #expect(ReviewAnchoring.markerTime(note, in: removed.sequences[0], revision: removed.editRevision) == nil)
    #expect(try store.comment(note.id).range == MediaRange(start: 6, end: 8))
}

@Test func reviewMarkersDoNotInventLocationsForAmbiguousOrGlobalNotes() throws {
    let store = try seededStore(), p = try store.read()
    let note = try store.addComment(text: "Moment", sequenceID: p.sequences[0].id, revision: 1, time: .init(seconds: 2))
    let global = try store.addComment(text: "Whole cut", sequenceID: p.sequences[0].id, revision: 1)
    var sequence = p.sequences[0], duplicate = p.sequences[0].clips[0]
    duplicate.id = "repeated"; duplicate.start = .init(seconds: 10); sequence.clips.append(duplicate)
    #expect(ReviewAnchoring.markerTime(note, in: sequence, revision: 2) == nil)
    #expect(ReviewAnchoring.markerTime(global, in: sequence, revision: 1) == nil)
    sequence.id = "other-sequence"
    #expect(ReviewAnchoring.markerTime(note, in: sequence, revision: 1) == nil)
}

@Test func projectLibraryDeduplicatesPathsAndRetainsMultipleProjects() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let library = try ProjectLibrary(url: folder.appendingPathComponent("index.sqlite"))
    let first = try ProjectStore.create(at: folder.appendingPathComponent("First.direction"), name: "First")
    let second = try ProjectStore.create(at: folder.appendingPathComponent("Second.direction"), name: "Second")
    try library.register(first); try library.register(second); try library.register(first)
    let entries = try library.list()
    #expect(entries.count == 2)
    #expect(entries.first?.name == "First")
    #expect(entries.allSatisfy { $0.available })
    try FileManager.default.moveItem(at: second.url, to: folder.appendingPathComponent("Moved.direction"))
    #expect(try library.list().first { $0.name == "Second" }?.available == false)
}
