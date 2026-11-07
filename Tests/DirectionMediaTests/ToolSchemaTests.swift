import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// The editor reads each tool's arguments from its schema (MCP inputSchema), and Direction checks every call
/// against it before running anything, naming the field that's wrong. A shape written only in the description
/// is a guess for the editor and unchecked here.
struct ToolSchemaTests {
    /// Objects whose fields are the editor's own to choose: an effect's or a transition's settings, keyframes, a style's tokens.
    static let freeForm: Set<String> = [
        "direction_edit.operations[].params", "direction_edit.operations[].keys", "direction_edit.batch",
        "direction_save_style.tokens", "direction_save_technique.transition.params", "direction_save_technique.effect.params", "direction_save_technique.variants[].params",
    ]

    /// Every object in a schema that says nothing of its fields, and every field with no type, by path. Codex
    /// turns a field with no type into {} and drops its description.
    static func shapeless(_ schema: JSONValue, _ path: String) -> [String] {
        var out: [String] = []
        if let shapes = schema["anyOf"].array { return shapes.flatMap { shapeless($0, path + "|") } }
        if schema["type"] == .null && schema["enum"] == .null { return [path + " (no type)"] }
        if schema["type"].string == "object" {
            if case .object(let fields) = schema["properties"] { for (k, v) in fields { out += shapeless(v, path + "." + k) } }
            else if schema["additionalProperties"] == .null || schema["additionalProperties"].bool == true { out.append(path) }
            if case .object = schema["additionalProperties"] { out += shapeless(schema["additionalProperties"], path + ".*") }
        }
        if schema["type"].string == "array" {
            if schema["items"] == .null { out.append(path + "[]") } else { out += shapeless(schema["items"], path + "[]") }
        }
        return out
    }

    /// Every edit argument says what it is on the argument itself: a gain's target is a clip or a track, not "clip".
    @Test func everyEditArgumentHasWords() throws {
        let edit = try #require(ToolCatalog.definitions.first { $0.name == "direction_edit" })
        guard case .object(let fields) = edit.inputSchema["properties"]["operations"]["items"]["properties"] else { Issue.record("no operation fields"); return }
        let bare = fields.filter { $0.value["description"] == .null }.map(\.key).sorted()
        #expect(bare.isEmpty, "\(bare)")
        #expect(fields["target"]?["description"].string?.contains("Not the word clip") == true)
    }

    @Test func everyArgumentSaysItsShape() {
        let loose = ToolCatalog.definitions.flatMap { d in Self.shapeless(d.inputSchema, d.name) }.filter { !Self.freeForm.contains($0) }.sorted()
        #expect(loose.isEmpty, "\(loose.joined(separator: "\n"))")
    }

    /// Each tool fits where the editors read it: Claude Code cuts a description at 4,096 characters, and Codex
    /// strips a schema past the 32,768 bytes Direction allows its server (EditorPrograms).
    @Test func everyToolFitsWhereTheEditorsReadIt() throws {
        for d in ToolCatalog.definitions {
            #expect(d.description.count <= 4_096, "\(d.name): \(d.description.count) characters")
            #expect(try JSONEncoder().encode(d.inputSchema).count <= 32_768, "\(d.name)")
        }
    }

    /// What the check says, without the closing words every refusal ends with.
    private func refused(_ tool: String, _ arguments: JSONValue) -> String? {
        do { try ToolCatalog.validate(arguments, for: tool); return nil }
        catch let e as DirectionError { return e.message.components(separatedBy: " Nothing was changed;").first }
        catch { return "\(error)" }
    }

    /// The calls that went wrong in Coded love's finishing are stopped at the door, saying which field and what it takes.
    @Test func aWrongShapeIsRefusedWithItsFieldAndWhatItTakes() throws {
        let said = refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "state": .string("working"), "progress": .string("Reading the mix: narration on A1, no music in the cut.")])])]))
        #expect(said == "arguments.items[0].progress: expected a number, not the text \u{201C}Reading the mix: narration on A1, no mus\u{2026}\u{201D}.", "\(said ?? "accepted")")
        #expect(refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "state": .string("in progress")])])])) == "arguments.items[0].state: use one of todo, working, done, needsYou, blocked.")
        #expect(refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "progress": .number(40)])])])) == "arguments.items[0].progress: must be at most 1.")
        #expect(refused("direction_turnover_update", .object(["turnoverID": .string("t"), "progress": .object(["note-1": .string("finished")])])) == "arguments.progress.note-1: use one of queued, working, done, cant, stopped.")
        #expect(refused("direction_ask", .object(["kind": .string("question"), "noteIDs": .array([]), "text": .string("Which?"), "choices": .array([.object(["title": .string("A")])])]))
                == "arguments.choices[0]: label is required. arguments.choices[0]: unknown field title; it takes assetID, detail, id, label, recommended.")
        // A read-back range is {start, end} in seconds, one shape.
        #expect(refused("direction_turnover_update", .object(["turnoverID": .string("t"), "readBack": .array([.object(["noteID": .string("n"), "plan": .string("p"), "range": .string("0:00\u{2013}0:06")])])]))
                == "arguments.readBack[0].range: expected an object, not the text \u{201C}0:00\u{2013}0:06\u{201D}.")
        // An edit time is seconds or {value, timescale}, nothing else.
        #expect(refused("direction_edit", .object(["baseEditRevision": .number(1), "operations": .array([.object(["op": .string("split"), "clipID": .string("c"), "at": .string("4.2")])])]))
                == "arguments.operations[0].at: expected a number or {timescale, value} or {bar, beat, clip}, not the text \u{201C}4.2\u{201D}.")
        #expect(refused("direction_log_dailies", .object(["takes": .array([.object(["assetID": .string("a"), "scene": .number(2)])])])) == "arguments.takes[0]: unknown field scene; it takes assetID, caption, code, flags, guessSceneNumber, sceneID, sceneNumber, setupCode, suggestion, unusable.")
    }

    /// Every problem in a call comes back at once, saying nothing changed: Codex doesn't tell the model a result was an error.
    @Test func aRefusalNamesEveryProblemAndSaysNothingChanged() {
        do { try ToolCatalog.validate(.object(["items": .array([.object(["id": .string("a"), "state": .string("busy")]), .object(["progress": .number(2)])])]), for: "direction_finishing"); Issue.record("Expected a refusal") }
        catch let e as DirectionError {
            #expect(e.code == "invalid_arguments")
            #expect(e.message == "arguments.items[0].state: use one of todo, working, done, needsYou, blocked. arguments.items[1]: id is required. arguments.items[1].progress: must be at most 1. Nothing was changed; call direction_finishing again with these put right.", "\(e.message)")
        } catch { Issue.record("\(error)") }
    }

    /// What the descriptions promise goes through as written.
    @Test func whatTheDescriptionsShowIsAccepted() {
        #expect(refused("direction_edit", .object(["baseEditRevision": .number(1), "operations": .array([
            .object(["op": .string("split"), "clipID": .string("c"), "at": .number(4.2)]),
            .object(["op": .string("split"), "clipID": .string("c"), "at": .object(["value": .number(126), "timescale": .number(30)])]),
            .object(["op": .string("removeRange"), "range": .object(["start": .number(1), "end": .number(2)])]),
            .object(["op": .string("insert"), "assetID": .string("a"), "at": .number(0), "sourceRange": .object(["start": .object(["value": .number(30), "timescale": .number(30)]), "duration": .number(2)])]),
            .object(["op": .string("move"), "clipID": .string("c"), "to": .object(["before": .string("d")])]),
            .object(["op": .string("tightenPauses"), "range": .object(["start": .number(0), "end": .number(9)]), "longerThan": .number(0.8), "to": .number(0.4)]),
            .object(["op": .string("placeMusic"), "assetID": .string("m"), "at": .number(0), "endOn": .object(["cut": .string("c|d")])]),
        ])])) == nil)
        #expect(refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "state": .string("working"), "detail": .string("Reading the mix."), "progress": .number(0.3), "by": .array([.string("editor")])])])])) == nil)
        #expect(refused("direction_turnover_update", .object(["turnoverID": .string("t"), "readBack": .array([
            .object(["noteID": .string("n1"), "plan": .string("Open on black."), "delta": .string("0 s"), "range": .object(["start": .number(0), "end": .number(6.6)]), "detail": .string("Narration stays.")]),
            .object(["noteID": .string("n2"), "plan": .string("Letterbox the end."), "conflictWithNoteID": .string("n1"), "following": .string("n1"), "range": .object(["start": .number(0), "end": .number(6)])]),
        ]), "progress": .object(["n1": .string("working")])])) == nil)
        #expect(refused("direction_turnover_complete", .object(["turnoverID": .string("t"), "answers": .array([
            .object(["noteID": .string("n1"), "summary": .string("Opened on black."), "delta": .string("+3 s"), "start": .number(0), "end": .number(6),
                     "options": .array([.object(["label": .string("A"), "summary": .string("Black card"), "revision": .number(20)]), .object(["label": .string("B"), "summary": .string("White card"), "revision": .number(21)])]),
                     "preferred": .string("A"), "rule": .object(["text": .string("Open on black"), "area": .string("pace"), "scope": .string("style")])]),
            .object(["unasked": .bool(true), "summary": .string("Tightened a pause."), "kind": .string("pace")]),
        ])])) == nil)
        #expect(refused("direction_ask", .object(["kind": .string("question"), "noteIDs": .array([.string("n1")]), "text": .string("Which?"), "choices": .array([.object(["id": .string("a"), "label": .string("The wide"), "recommended": .bool(true)])])])) == nil)
        #expect(refused("direction_log_dailies", .object(["scenes": .array([.object(["number": .number(2), "title": .string("Desk"), "setups": .array([.object(["code": .string("2A"), "description": .string("Wide")])])])]),
                                                          "takes": .array([.object(["assetID": .string("a"), "sceneNumber": .number(2), "setupCode": .string("2A"), "code": .string("T1"), "flags": .array([.string("soft")])])])])) == nil)
        #expect(refused("direction_save_technique", .object(["name": .string("Grid flash"), "kind": .string("transition"), "transition": .object(["type": .string("shader"), "frames": .number(12), "params": .object(["cells": .number(8)]), "file": .string("transition.metal")]),
                                                             "variants": .array([.object(["name": .string("Big squares"), "params": .object(["cells": .number(4)])])]), "source": .object(["title": .string("A tutorial"), "at": .string("0:42")])])) == nil)
    }
}
