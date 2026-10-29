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
