import Testing
import Foundation
@testable import DirectionCore

/// Techniques (techniques.md): a folder with technique.json and its files, found by name; styles can name one.
struct TechniqueTests {
    @Test func aTechniqueIsAFolderFoundByNameWithItsVariants() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-techniques-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let part = root.appendingPathComponent("grid.metal")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// metal".utf8).write(to: part)
        let folder = root.appendingPathComponent("Techniques")
        let t = try TechniqueLibrary.save(id: nil, fields: [
            "name": .string("Grid flash"), "kind": .string("transition"), "summary": .string("Squares flip with a flash."), "when": .string("Chapter changes."),
            "transition": .object(["type": .string("shader"), "file": .string("grid.metal"), "frames": .number(20)]),
            "variants": .array([.object(["name": .string("Big"), "params": .object(["cols": .number(3)])])]),
        ], files: [(part, "grid.metal")], in: folder)
        #expect(t.id == "grid-flash" && t.transition?.name == "Grid flash" && t.transition?.frames == 20 && t.variant("big")?.params?["cols"]?.double == 3 && t.variant("Huge") == nil)
        #expect(FileManager.default.fileExists(atPath: t.url.appendingPathComponent("grid.metal").path))
        #expect(TechniqueLibrary.find("GRID FLASH", in: folder)?.id == "grid-flash" && TechniqueLibrary.find("grid-flash", in: folder) != nil)
        // Each kind needs what makes it; every one needs a name, a sentence and when to use it.
        for bad: [String: JSONValue] in [
            ["name": .string("A"), "kind": .string("transition"), "summary": .string("s"), "when": .string("w")],
            ["name": .string("B"), "kind": .string("effect"), "summary": .string("s"), "when": .string("w")],
            ["name": .string("C"), "kind": .string("recipe"), "summary": .string("s"), "when": .string("w")],
            ["name": .string("D"), "kind": .string("trick"), "summary": .string("s"), "when": .string("w"), "steps": .array([.string("x")])],
            ["name": .string("E"), "kind": .string("recipe"), "summary": .string("s"), "steps": .array([.string("x")])],
        ] { #expect(throws: DirectionError.self) { try TechniqueLibrary.save(id: nil, fields: bad, in: folder) } }
        #expect(throws: DirectionError.self) { try TechniqueLibrary.save(id: nil, fields: ["name": .string("F"), "kind": .string("recipe"), "summary": .string("s"), "when": .string("w"), "steps": .array([.string("x")])], files: [(part, "../out.metal")], in: folder) }
        // Changing one keeps what it had.
        let changed = try TechniqueLibrary.save(id: "grid-flash", fields: ["needs": .string("Handles.")], in: folder)
        #expect(changed.needs == "Handles." && changed.transition?.file == "grid.metal")
    }

    @Test func aStylesTransitionCanBeMadeByATechnique() throws {
        let made = try JSONValue.object(["name": .string("Chapter"), "technique": .string("Grid flash"), "variant": .string("Big")]).decode(StyleTransition.self)
        #expect(made.technique == "Grid flash" && made.variant == "Big" && made.frames == 0)
        // Without a technique it still needs its kind and length.
        #expect((try? JSONValue.object(["name": .string("Chapter")]).decode(StyleTransition.self)) == nil)
        #expect((try? JSONValue.object(["name": .string("Chapter"), "type": .string("slide")]).decode(StyleTransition.self)) == nil)
        // An edit can't use a technique on its own: Direction's tools set it up.
        expectFailure("bad_argument", index: 0) {
            _ = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [try op(#"{"op":"technique","name":"Grid flash","editPoint":"c1|c2"}"#)]), on: TimelineCut.make().project, context: TimelineCut.make().context)
        }
        #expect(EditCatalog.operations.contains { $0.op == "technique" } && EditCatalog.effect("pixelGrid") != nil)
    }
}
