import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

/// The editor's side of styles (specs/styles.md): reading the film's, and writing one when asked.
@Suite("The editor's styles", .serialized)
struct StyleToolTests {
    @Test func theEditorSavesAStyleAndReadsTheFilms() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-style-tools-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let styles = root.appendingPathComponent("Styles")
        SharedSettings.stylesFolderOverride = styles
        defer { SharedSettings.stylesFolderOverride = nil }
        let store = try ProjectStore.create(at: root.appendingPathComponent("Launch film.direction"), name: "Launch film")
        let runtime = try ToolRuntime(store: store)
        #expect(try await runtime.invoke("direction_brief").value["style"] == .null)
        do { _ = try await runtime.invoke("direction_style"); Issue.record("A film without a style has none to read") } catch let e as DirectionError { #expect(e.code == "style_not_found") }

        // Parts come from the editor's working folder.
        let editor = store.url.appendingPathComponent("Editor")
        try FileManager.default.createDirectory(at: editor.appendingPathComponent("Graphics/lower-third"), withIntermediateDirectories: true)
        try Data("<script>direction.graphic({})</script>".utf8).write(to: editor.appendingPathComponent("Graphics/lower-third/index.html"))
        let saved = try await runtime.invoke("direction_save_style", arguments: .object([
            "name": .string("Desk Talk"), "summary": .string("Quick explainers."),
            "tokens": .object(["captions": .object(["wordsAtATime": .number(3)])]), "guide": .string("# Desk Talk\n\n## Pace\nThree-second shots.\n"),
            "files": .array([.object(["from": .string("Graphics/lower-third"), "to": .string("graphics/lower-third")])]),
        ])).value
        #expect(saved["id"].string == "desk-talk" && saved["parts"]["graphics"].array?.first?["copyTo"].string == "Graphics/lower-third")
        do {
            _ = try await runtime.invoke("direction_save_style", arguments: .object(["id": .string("desk-talk"), "files": .array([.object(["from": .string("/etc/hosts"), "to": .string("sounds/hosts.wav")])])]))
            Issue.record("Only files in the film go into a style")
        } catch let e as DirectionError { #expect(e.code == "invalid_arguments") }
        #expect(try await runtime.invoke("direction_styles").value["styles"].array?.map { $0["name"].string } == ["Desk Talk"])

        // Once the brief names it, the film's copy is what the editor reads.
        var brief = Brief(); brief.logline = "Maya builds it."; brief.feeling = "Proud."; brief.style = "desk-talk"
        try store.saveBrief(brief, styles: styles)
        let named = try await runtime.invoke("direction_brief").value["style"]
        #expect(named["name"].string == "Desk Talk")
        let read = try await runtime.invoke("direction_style").value
        #expect(read["tokens"]["captions"]["wordsAtATime"].double == 3 && read["guide"].string?.contains("Three-second shots") == true)
        #expect(read["parts"]["graphics"].array?.first?["path"].string?.hasPrefix(store.url.appendingPathComponent("Style").path) == true)
        #expect(try await runtime.invoke("direction_graphic_examples").value["fromStyle"].array?.first?["name"].string == "lower-third")

        // Changing the film's own style copies it again.
        _ = try await runtime.invoke("direction_save_style", arguments: .object(["id": .string("desk-talk"), "summary": .string("Faster now.")]))
        #expect(try await runtime.invoke("direction_style").value["summary"].string == "Faster now.")
    }
}
