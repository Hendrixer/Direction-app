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
        "direction_edit.operations[].params", "direction_edit.operations[].keys", "direction_edit.batch.operations[].params", "direction_edit.batch.operations[].keys",
        "direction_save_style.tokens", "direction_save_technique.transition.params", "direction_save_technique.effect.params", "direction_save_technique.variants[].params",
    ]

    /// Every object in a schema that says nothing of its fields, by path.
    static func shapeless(_ schema: JSONValue, _ path: String) -> [String] {
        var out: [String] = []
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

    @Test func everyArgumentSaysItsShape() {
        let loose = ToolCatalog.definitions.flatMap { d in Self.shapeless(d.inputSchema, d.name) }.filter { !Self.freeForm.contains($0) }.sorted()
        #expect(loose.isEmpty, "\(loose.joined(separator: "\n"))")
    }

    private func refused(_ tool: String, _ arguments: JSONValue) -> String? {
        do { try ToolCatalog.validate(arguments, for: tool); return nil } catch let e as DirectionError { return e.message } catch { return "\(error)" }
    }

    /// The calls that went wrong in Coded love's finishing are stopped at the door, saying which field and what it takes.
    @Test func aWrongShapeIsRefusedWithItsFieldAndWhatItTakes() throws {
        let said = refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "state": .string("working"), "progress": .string("Reading the mix: narration on A1, no music in the cut.")])])]))
        #expect(said == "arguments.items[0].progress: expected a number, not the text \u{201C}Reading the mix: narration on A1, no mus\u{2026}\u{201D}.", "\(said ?? "accepted")")
        #expect(refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "state": .string("in progress")])])])) == "arguments.items[0].state: use one of todo, working, done, needsYou, blocked.")
        #expect(refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "progress": .number(40)])])])) == "arguments.items[0].progress: must be at most 1.")
        #expect(refused("direction_turnover_update", .object(["turnoverID": .string("t"), "progress": .object(["note-1": .string("finished")])])) == "arguments.progress.note-1: use one of queued, working, done, cant, stopped.")
        #expect(refused("direction_ask", .object(["kind": .string("question"), "noteIDs": .array([]), "text": .string("Which?"), "choices": .array([.object(["title": .string("A")])])]))?.hasPrefix("arguments.choices[0]: label is required.") == true)
        #expect(refused("direction_log_dailies", .object(["takes": .array([.object(["assetID": .string("a"), "scene": .number(2)])])])) == "arguments.takes[0]: unknown field scene; it takes assetID, caption, code, flags, guessSceneNumber, sceneID, sceneNumber, setupCode, suggestion, unusable.")
    }

    /// What the descriptions promise goes through as written.
    @Test func whatTheDescriptionsShowIsAccepted() {
        #expect(refused("direction_finishing", .object(["items": .array([.object(["id": .string("sound"), "state": .string("working"), "detail": .string("Reading the mix."), "progress": .number(0.3), "by": .array([.string("editor")])])])])) == nil)
        #expect(refused("direction_turnover_update", .object(["turnoverID": .string("t"), "readBack": .array([
            .object(["noteID": .string("n1"), "plan": .string("Open on black."), "delta": .string("0 s"), "range": .object(["start": .number(0), "end": .number(6.6)]), "detail": .string("Narration stays.")]),
            .object(["noteID": .string("n2"), "plan": .string("Letterbox the end."), "conflictWithNoteID": .string("n1"), "following": .string("n1"), "range": .string("0:00\u{2013}0:06")]),
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
