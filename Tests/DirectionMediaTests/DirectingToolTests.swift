import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// The editor's side of a turnover, through the same runtime the MCP server uses.
@Test func editorReadsBackWaitsForTheOKAndDeliversAnsweredCut() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-directing-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "Launch film")
    let asset = MediaAsset(id: "take-1", name: "A011_C001.mov", path: "/fixture.mov", duration: .init(seconds: 10), video: [.init(id: 1, width: 320, height: 180, frameRate: 24)], audio: [])
    _ = try store.addAsset(asset, append: true, expectedRevision: 0)
    let runtime = try ToolRuntime(store: store)

    _ = try await runtime.invoke("direction_log_dailies", arguments: .object([
        "scenes": .array([.object(["number": .number(1), "title": .string("Cold open")])]),
        "takes": .array([.object(["assetID": .string("take-1"), "sceneNumber": .number(1), "code": .string("T1"), "suggestion": .string("Steadiest")])]),
    ]))
    #expect(try store.dailies().take("take-1").suggestion == "Steadiest")
    #expect(try !store.dailies().take("take-1").circled)

    let p = try store.read()
    let draft = try store.addComment(text: "", sequenceID: nil, revision: p.editRevision, time: .init(seconds: 2), extra: NoteFields(noteState: .draft))
    let note = try store.addComment(text: "Too long to her face.", sequenceID: nil, revision: p.editRevision, time: .init(seconds: 1), extra: NoteFields(kind: .pace))
    let feedback = try await runtime.invoke("direction_feedback")
    #expect(feedback.value["comments"].array?.compactMap { $0["id"].string } == [note.id])
    _ = draft

    let turnover = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: true, cutID: nil, sequenceID: nil)
    let open = try await runtime.invoke("direction_turnovers")
    #expect(open.value["turnovers"].array?.first?["mayStartCutting"].bool == false)

    _ = try await runtime.invoke("direction_turnover_update", arguments: .object(["turnoverID": .string(turnover.id), "readBack": .array([.object(["noteID": .string(note.id), "plan": .string("Drop the second wide. On her face by 0:09."), "delta": .string("−4.2 s")])])]))
    do { _ = try await runtime.invoke("direction_turnover_update", arguments: .object(["turnoverID": .string(turnover.id), "state": .string("cutting")])); Issue.record("Cutting must wait for the OK") }
    catch let e as DirectionError { #expect(e.code == "readback_not_approved") }
    _ = try store.approveReadBack(turnoverID: turnover.id)

    let asked = try await runtime.invoke("direction_ask", arguments: .object(["turnoverID": .string(turnover.id), "kind": .string("question"), "noteIDs": .array([.string(note.id)]), "text": .string("Which street wide?"), "choices": .array([.object(["label": .string("First")]), .object(["label": .string("Second")])])]))
    #expect(asked.value["choices"].array?.count == 2)

    let delivered = try await runtime.invoke("direction_turnover_complete", arguments: .object(["turnoverID": .string(turnover.id), "answers": .array([.object(["noteID": .string(note.id), "summary": .string("Cut the second street wide."), "delta": .string("−4.2 s"), "start": .number(0), "end": .number(2)])])]))
    #expect(delivered.value["cut"]["name"].string == "Assembly")
    let answered = try store.notes().first { $0.id == note.id }
    #expect(answered?.lifecycle == .answered && answered?.latestAnswer?.delta == "−4.2 s")
}

/// A film with one take of `seconds` with sound, cut whole, and the runtime the editor uses.
private func oneTakeFilm(_ seconds: Double = 10) throws -> (ProjectStore, ToolRuntime) {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-directing-" + UUID().uuidString + ".direction")
    let store = try ProjectStore.create(at: path, name: "Launch film")
    let asset = MediaAsset(id: "take-1", name: "A011_C001.mov", path: "/fixture.mov", duration: .init(seconds: seconds), video: [.init(id: 1, width: 320, height: 180, frameRate: 24)], audio: [.init(id: 2, index: 0, label: "Dialogue", channels: 1, sampleRate: 48_000)])
    _ = try store.addAsset(asset, append: true, expectedRevision: 0)
    return (store, try ToolRuntime(store: store))
}

private func expectRefused(_ code: String, _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(code)") }
    catch let e as DirectionError { #expect(e.code == code, "\(e.code): \(e.message)") }
    catch { Issue.record("Unexpected error: \(error)") }
}

@Test func aNoteOnTheWholeCutReachesTheEditorAsAShortExcerpt() async throws {
    let (store, runtime) = try oneTakeFilm(400)
    defer { try? FileManager.default.removeItem(at: store.url) }
    try store.saveTranscript(SourceTranscript(assetID: "take-1", audioTrackID: 2, words: (0..<700).map { i in TranscriptWord(id: "w\(i)", text: "word\(i)", range: .init(start: Double(i) * 0.5, end: Double(i) * 0.5 + 0.3)) }))
    let note = try store.addComment(text: "Shorter all over.", sequenceID: nil, revision: try store.revision(), extra: NoteFields(kind: .pace))
    #expect(note.transcriptContext.count == 500)
    _ = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
    let turnovers = try await runtime.invoke("direction_turnovers").value, feedback = try await runtime.invoke("direction_feedback").value
    let shown = try #require(turnovers["turnovers"].array?.first?["notes"].array?.first)
    let excerpt = try #require(shown["transcriptContext"]["excerpt"].string)
    #expect(excerpt.hasPrefix("word0 word1 ") && excerpt.hasSuffix(" word39\u{2026}") && shown["transcriptContext"]["wordCount"].int == 500)
    #expect(try turnovers.data().count < 8_000 && feedback.data().count < 4_000)
    // A moment's excerpt is the words around it.
    let moment = try store.addComment(text: "Hold here.", sequenceID: nil, revision: try store.revision(), time: .init(seconds: 100))
    #expect(moment.transcriptExcerpt(limit: 4) == "\u{2026}word198 word199 word200 word201\u{2026}")
}

@Test func editsAndRestoreHoldToTheLocks() async throws {
    let (store, runtime) = try oneTakeFilm()
    defer { try? FileManager.default.removeItem(at: store.url) }
    func call(_ name: String, _ args: [String: JSONValue]) async throws -> JSONValue { try await runtime.invoke(name, arguments: .object(args)).value }
    func edit(_ op: String) async throws {
        _ = try await call("direction_edit", ["baseEditRevision": .number(Double(try store.revision())), "operations": .array([try JSONDecoder().decode(JSONValue.self, from: Data(op.utf8))])])
    }
    let whole = Double(try store.revision())
    try await edit(#"{"op":"removeRange","range":{"start":1,"end":2},"ripple":true}"#)
    let trimmed = Double(try store.revision())
    let id = try #require(try store.read().sequences[0].clips.min { $0.start < $1.start }).id
    try await edit(#"{"op":"addEffect","target":"\#(id)","effect":"blur","params":{"radius":3}}"#)
    let blurred = Double(try store.revision())
    try await edit(#"{"op":"balance","clipID":"\#(id)","exposure":0.3}"#)
    let warm = Double(try store.revision())
    // After picture lock: no timing and no taking the blur off, but the color can go back.
    try store.lockPicture(cutID: nil, locked: true)
    await expectRefused("picture_locked") { try await edit(#"{"op":"removeRange","range":{"start":3,"end":4},"ripple":true}"#) }
    await expectRefused("picture_locked") { _ = try await call("direction_restore", ["revision": .number(whole), "baseEditRevision": .number(warm)]) }
    await expectRefused("picture_locked") { _ = try await call("direction_restore", ["revision": .number(trimmed), "baseEditRevision": .number(warm)]) }
    _ = try await call("direction_restore", ["revision": .number(blurred), "baseEditRevision": .number(warm)])
    let clip = try #require(try store.read().sequences[0].clips.first { $0.id == id })
    let restored = Double(try store.revision())
    #expect(clip.grade.exposure == 0 && clip.effects?.first?.name == "blur" && restored == warm + 1)
    try store.lockPicture(cutID: nil, locked: false)
    // A locked scene keeps its blur through a restore.
    _ = try await call("direction_log_dailies", ["scenes": .array([.object(["number": .number(1), "title": .string("Cold open")])]), "takes": .array([.object(["assetID": .string("take-1"), "sceneNumber": .number(1)])])])
    try store.lockScene(id: try store.dailies().scenes[0].id, locked: true)
    await expectRefused("scene_locked") { _ = try await call("direction_restore", ["revision": .number(trimmed), "baseEditRevision": .number(Double(try store.revision()))]) }
}

@Test func anEditSaysWhichNoteItAnswers() async throws {
    let (store, runtime) = try oneTakeFilm()
    defer { try? FileManager.default.removeItem(at: store.url) }
    let note = try store.addComment(text: "Lose the pause.", sequenceID: nil, revision: try store.revision(), time: .init(seconds: 1), extra: NoteFields(kind: .pace))
    _ = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
    let args: [String: JSONValue] = ["baseEditRevision": .number(Double(try store.revision())), "operations": .array([.object(["op": .string("removeRange"), "range": .object(["start": .number(5), "end": .number(6)]), "ripple": .bool(true)])])]
    await expectRefused("bad_argument") { _ = try await runtime.invoke("direction_edit", arguments: .object(args)) }
    _ = try await runtime.invoke("direction_edit", arguments: .object(args.merging(["notes": .array([.number(Double(note.number ?? 0))])]) { _, b in b }))
    let record = try store.editRecords().last
    #expect(try store.read().sequences[0].duration == MediaTime(seconds: 9) && record?.notes == [note.number ?? 0])
}

/// A note that names a take with "@" reaches the editor's turnover with which take it is and where it plays.
@Test func aTurnoverSaysWhichTakeANoteNames() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-named-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "Launch film")
    _ = try store.addAsset(MediaAsset(id: "take-1", name: "A011_C001.mov", path: "/fixture.mov", duration: .init(seconds: 10), video: [.init(id: 1, width: 320, height: 180, frameRate: 24)], audio: []), append: true, expectedRevision: 0)
    let runtime = try ToolRuntime(store: store)
    _ = try await runtime.invoke("direction_log_dailies", arguments: .object([
        "scenes": .array([.object(["number": .number(1), "title": .string("Cold open"), "setups": .array([.object(["code": .string("1A"), "description": .string("Street")])])])]),
        "takes": .array([.object(["assetID": .string("take-1"), "sceneNumber": .number(1), "setupCode": .string("1A"), "code": .string("T1")])]),
    ]))
    let p = try store.read()
    let note = try store.addComment(text: "Open on @1A Take 1 instead.", sequenceID: nil, revision: p.editRevision, time: .init(seconds: 1), extra: NoteFields(kind: .picture))
    _ = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
    let named = try await runtime.invoke("direction_turnovers").value["turnovers"].array?.first?["footageNamed"].array?.first
    #expect(named?["noteID"].string == note.id)
    #expect(named?["names"].string == "@1A Take 1 is the take A011_C001.mov (assetID take-1) in scene 1 Cold open, setup 1A Street. In the cut at 0:00\u{2013}0:10.")
}
