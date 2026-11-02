import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// The editor's side of prep: it writes the picture, answers a note, breaks the script into shots and
/// reads coverage back, through the same runtime the MCP server uses.
@Test func theEditorWritesThePictureAndBreaksTheScriptDown() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "The Chat Box")
    let runtime = try ToolRuntime(store: store)

    let empty = try await runtime.invoke("direction_script")
    #expect(empty.value["script"] == .null)

    _ = try store.importScript("""
    ## Cold open
    Open any app you used five years ago. It has a chat box now.

    I build these for a living. [me at the desk]

    [ON CAMERA]
    So here's what I think happened.
    """, fileName: "chat.md")
    let read = try await runtime.invoke("direction_script")
    let rows = read.value["rows"].array ?? []
    #expect(rows.count == 3 && rows[1]["hint"].string == "me at the desk" && rows[2]["sound"]["kind"].string == "onCamera")
    let ids = rows.compactMap { $0["id"].string }

    _ = try store.editRow(ids[2], picture: "On camera at the desk, medium.")
    let wrote = try await runtime.invoke("direction_script_update", arguments: .object(["pictures": .array([
        .object(["rowID": .string(ids[0]), "text": .string("Apps opening their chat panels."), "board": .string("screen")]),
        .object(["rowID": .string(ids[1]), "text": .string("Me at the desk from behind, dark."), "size": .string("wide")]),
        .object(["rowID": .string(ids[2]), "text": .string("Something else.")]),
    ])]))
    #expect(wrote.value["refused"].array?.count == 1 && wrote.value["rowsWithoutPicture"].array?.isEmpty == true)

    let note = try store.addScriptNote(rowIDs: [ids[1]], kind: .picture, text: "My hands, not the desk.")
    _ = try store.turnOverScriptNotes()
    let answered = try await runtime.invoke("direction_script_update", arguments: .object([
        "pictures": .array([.object(["rowID": .string(ids[1]), "text": .string("My hands on the keys."), "size": .string("close")])]),
        "replies": .array([.object(["noteID": .string("1"), "reply": .string("Row 2 is your hands now.")])]),
        "questions": .array([.object(["rowID": .string(ids[0]), "text": .string("Which apps?"), "choices": .array([.object(["label": .string("Ones you use")]), .object(["label": .string("Famous ones")])])])]),
    ]))
    #expect(answered.value["refused"].array?.isEmpty == true && answered.value["notesWaiting"].array?.isEmpty == true)
    #expect(try store.script()?.notes.first { $0.id == note.id }?.reply == "Row 2 is your hands now.")
    #expect(try store.script()?.rows[0].question?.choices.count == 2)

    _ = try store.okScript()
    let none = try await runtime.invoke("direction_breakdown")
    #expect(none.value["breakdown"] == .null)
    let broke = try await runtime.invoke("direction_breakdown_update", arguments: .object([
        "setups": .array([.object(["name": .string("Desk at night"), "needs": .string("After dark")]), .object(["name": .string("Screen recordings"), "noCamera": .bool(true)])]),
        "shots": .array([
            .object(["setup": .string("Screen recordings"), "rowIDs": .array([.string(ids[0])]), "what": .string("Apps opening chat panels."), "source": .string("screen")]),
            .object(["setup": .string("Desk at night"), "rowIDs": .array([.string(ids[1])]), "what": .string("Hands on the keys."), "size": .string("close"), "source": .string("shoot")]),
        ]),
    ]))
    #expect(broke.value["shots"].array?.compactMap(\.string) == ["1A Hands on the keys.", "2A Apps opening chat panels."])
    #expect(broke.value["rowsWithoutShot"].array?.compactMap(\.int) == [3])
    let breakdown = try await runtime.invoke("direction_breakdown")
    let setups = breakdown.value["setups"].array ?? []
    #expect(setups.count == 2 && setups[0]["shots"].array?.first?["coverage"].string == "planned" && breakdown.value["scriptChanged"] == .bool(false))
}
