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

/// A long script is read a page at a time, so the editor writes as it reads and the director sees the
/// picture column fill in.
@Test func aLongScriptIsReadAPageAtATime() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-pages-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "Long")
    let runtime = try ToolRuntime(store: store)
    _ = try store.importScript((1...100).map { "Line number \($0) of the essay is here." }.joined(separator: "\n\n"), fileName: "long.txt")
    let first = try await runtime.invoke("direction_script")
    #expect(first.value["rows"].array?.count == 40 && first.value["total"].int == 100 && first.value["next"].int == 41 && first.value["withoutPicture"].int == 100)
    #expect(first.value["rows"].array?.first?["picture"] == .null)
    let last = try await runtime.invoke("direction_script", arguments: .object(["from": .number(81), "count": .number(40)]))
    #expect(last.value["rows"].array?.count == 20 && last.value["rows"].array?.first?["number"].int == 81 && last.value["next"] == .null)
}

/// A film from a story: the editor reads each beat's part of the story and writes what we hear as well as
/// what we see, with talk left to the speaker's own words.
@Test func theEditorLaysOutAStory() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-story-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "Night walk")
    let runtime = try ToolRuntime(store: store)
    _ = try store.importScript("Maya locks the studio at midnight.\n\nShe stops on the bridge and calls her dad.", fileName: "walk.md", as: .story)
    let read = try await runtime.invoke("direction_script")
    let rows = read.value["rows"].array ?? []
    #expect(read.value["kind"].string == "story" && read.value["withoutSound"].int == 2)
    #expect(rows.count == 2 && rows[1]["story"].string == "She stops on the bridge and calls her dad.")
    let ids = rows.compactMap { $0["id"].string }
    let wrote = try await runtime.invoke("direction_script_update", arguments: .object([
        "pictures": .array([.object(["rowID": .string(ids[0]), "text": .string("Maya locks the door from outside.")]), .object(["rowID": .string(ids[1]), "text": .string("Maya on the bridge, phone to her ear.")])]),
        "sounds": .array([
            .object(["rowID": .string(ids[0]), "kind": .string("effect"), "text": .string("Keys in the lock."), "seconds": .number(4)]),
            .object(["rowID": .string(ids[1]), "kind": .string("onCamera"), "speaker": .string("Maya"), "text": .string("Calling her dad: the hello"), "ownWords": .bool(true), "seconds": .number(6)]),
        ]),
    ]))
    #expect(wrote.value["refused"].array?.isEmpty == true && wrote.value["rowsWithoutSound"].array?.isEmpty == true)
    let again = try await runtime.invoke("direction_script")
    #expect(again.value["rows"].array?[1]["sound"]["ownWords"] == .bool(true) && again.value["rows"].array?[1]["seconds"].int == 6)
}

/// A treatment's writer's notes come with the first page of the script, never as rows.
@Test func theEditorReadsTheWritersNotes() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-notes-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "Porch")
    let runtime = try ToolRuntime(store: store)
    _ = try store.importScript("## Rules\n\nNo dialogue.\n\n## Story\n\n**1 · Dark · 0:00–0:06.** He climbs the ladder.\n\n**2 · Light · 0:06–0:10.** The bulb holds.", fileName: "porch.md", as: .story)
    let first = try await runtime.invoke("direction_script", arguments: .object(["count": .number(1)]))
    #expect(first.value["total"].int == 2 && first.value["storyNotes"].string == "## Rules\n\nNo dialogue.")
    let second = try await runtime.invoke("direction_script", arguments: .object(["from": .number(2)]))
    #expect(second.value["storyNotes"] == .null)
}

/// A voice-over written to a cut (specs/script.md › A voice-over): the director asks, the editor writes lines timed to
/// the cut, a line the director changed stays theirs, overlaps are said, and a script brought in after puts it away.
@Test func theEditorWritesAVoiceOverToTheCut() async throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-voiceover-" + UUID().uuidString + ".direction")
    defer { try? FileManager.default.removeItem(at: path) }
    let store = try ProjectStore.create(at: path, name: "Bodies")
    let runtime = try ToolRuntime(store: store)
    refuses("invalid_voice_over") { _ = try store.startVoiceOver(VoiceOverAsk(ask: "  ")) }
    _ = try store.startVoiceOver(VoiceOverAsk(ask: "Why the bodies look this way. Curious, a little funny.", cutID: "cut-10", cutName: "Cut 10", cutSeconds: 40))
    let read = try await runtime.invoke("direction_script")
    #expect(read.value["kind"].string == "voiceOver" && read.value["voiceOver"]["cutName"].string == "Cut 10" && read.value["voiceOver"]["wordsThatFit"].double == 80)

    // Written out of order, they read in the order they play; a line that runs into the next is said.
    let wrote = try await runtime.invoke("direction_script_update", arguments: .object(["lines": .array([
        .object(["at": .number(12), "picture": .string("The nervous system, lit up."), "text": .string("Every nerve you have, laid out like a map.")]),
        .object(["at": .number(0), "picture": .string("FOR SCIENCE over the full body."), "text": .string("This was a person once, and they said yes to this so you could see inside yourself without a scalpel.")]),
    ])]))
    #expect(wrote.value["lines"].double == 2 && wrote.value["overlaps"].array?.count == 0)
    var s = try #require(try store.script())
    #expect(s.rows.map(\.at) == [0, 12] && s.rows.allSatisfy { $0.sound.kind == .voice && $0.sound.ownWords == nil })
    let crowded = try await runtime.invoke("direction_script_update", arguments: .object(["lines": .array([
        .object(["at": .number(5), "picture": .string("Hands."), "text": .string("Look at the hands, every tendon still there, every one of them doing its job.")]),
    ])]))
    #expect(crowded.value["overlaps"].array?.isEmpty == false)

    // The director's words stay theirs until a note asks.
    let first = s.rows[0].id
    _ = try store.editRow(first, sound: "This was a person once.")
    let refused = try await runtime.invoke("direction_script_update", arguments: .object(["lines": .array([.object(["rowID": .string(first), "at": .number(0), "picture": .string("x"), "text": .string("Something else.")])])]))
    #expect(refused.value["refused"].array?.count == 1)
    s = try #require(try store.script())
    #expect(s.rows[0].sound.text == "This was a person once." && s.forRecording.contains("0:00  This was a person once."))

    // The editor takes out a line it wrote; the director's order is the cut's; there's nothing to break down; a line the
    // director adds starts where the one before it ends.
    let fiveSeconds = try #require(try store.script()?.rows.first { $0.at == 5 })
    let removed = try await runtime.invoke("direction_script_update", arguments: .object(["removeLines": .array([.string(fiveSeconds.id)])]))
    #expect(removed.value["lines"].double == 2)
    refuses("voice_over_order") { _ = try store.moveRow(first, before: nil) }
    refuses("voice_over") { _ = try store.updateBreakdown(setups: [try JSONDecoder().decode(SetupInput.self, from: Data(#"{"name":"Desk"}"#.utf8))]) }
    let (added, newID) = try store.addRow(after: first)
    #expect(added.row(newID)?.at == added.rows[0].seconds)
    let marked = try await runtime.invoke("direction_script")
    #expect(marked.value["rows"].array?.first?["yours"].bool == true)

    // Asking again replaces it only when told to; a script brought in after is a script, not a voice-over.
    refuses("script_exists") { _ = try store.startVoiceOver(VoiceOverAsk(ask: "Again.")) }
    _ = try store.startVoiceOver(VoiceOverAsk(ask: "Again."), replace: true)
    let again = try store.script()
    #expect(again?.rows.isEmpty == true && again?.voiceOver?.ask == "Again.")
    _ = try store.importScript("A line to say.", fileName: "script.md")
    let script = try store.script()
    #expect(script?.isVoiceOver == false && script?.voiceOver == nil)
}

private func refuses(_ code: String, _ body: () throws -> Void) {
    do { try body(); Issue.record("Expected \(code)") } catch let e as DirectionError { #expect(e.code == code, "\(e.code): \(e.message)") } catch { Issue.record("Unexpected \(error)") }
}
