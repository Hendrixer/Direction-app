import Testing
import Foundation
@testable import DirectionCore

/// Styles (specs/styles.md): a folder with its values, a guide and its parts, and a film's own copy.
@Suite("Styles")
struct StyleTests {
    struct World {
        let root: URL
        let styles: URL
        let store: ProjectStore
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    func world() throws -> World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-styles-" + UUID().uuidString)
        let styles = root.appendingPathComponent("Styles")
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
        return World(root: root, styles: styles, store: try ProjectStore.create(at: root.appendingPathComponent("Launch film.direction"), name: "Launch film"))
    }

    @Test func aStyleIsAFolderWithItsValuesItsGuideAndItsParts() throws {
        let w = try world(); defer { w.cleanup() }
        let made = try StyleLibrary.create(name: "Desk Talk", summary: "Quick explainers.", in: w.styles)
        #expect(made.id == "desk-talk" && made.guide.contains("## Pace") && made.guide.hasPrefix("# Desk Talk") && made.contents.line.isEmpty)
        #expect(try StyleLibrary.create(name: "Desk Talk", summary: "", in: w.styles).id == "desk-talk-2")

        // Parts come from anywhere on disk into a path inside the style; values merge key by key.
        let parts = w.root.appendingPathComponent("parts")
        try FileManager.default.createDirectory(at: parts.appendingPathComponent("lower-third"), withIntermediateDirectories: true)
        try Data("<script>direction.graphic({})</script>".utf8).write(to: parts.appendingPathComponent("lower-third/index.html"))
        try Data([0, 1, 2]).write(to: parts.appendingPathComponent("whoosh.wav"))
        let saved = try StyleLibrary.save(id: "desk-talk", name: nil, summary: nil, tokens: .object(["colors": .object(["accent": .string("#FFC800")]), "pace": .object(["averageShotSeconds": .number(3)])]), guide: nil,
                                          files: [(parts.appendingPathComponent("lower-third"), "graphics/lower-third"), (parts.appendingPathComponent("whoosh.wav"), "sounds/whoosh.wav")], in: w.styles)
        #expect(saved.name == "Desk Talk" && saved.summary == "Quick explainers." && saved.tokens["colors"]["accent"].string == "#FFC800")
        #expect(saved.contents.graphics == ["lower-third"] && saved.contents.sounds == ["whoosh.wav"] && saved.contents.line == "1 graphic \u{00B7} 1 sound")
        #expect(saved.guide.hasPrefix("# Desk Talk"))
        let pruned = try StyleLibrary.save(id: "desk-talk", name: nil, summary: nil, tokens: .object(["pace": .null]), guide: "# Desk Talk\n\nHard cuts.\n", in: w.styles)
        #expect(pruned.tokens["pace"] == .null && pruned.tokens["colors"]["accent"].string == "#FFC800" && pruned.guide == "# Desk Talk\n\nHard cuts.\n")

        // Nothing lands outside the style, and nothing is written when one part can't be.
        for bad in ["../escape.wav", "/tmp/x.wav", "sounds/.hidden.wav", "sounds/../../x.wav"] {
            #expect(throws: DirectionError.self) { try StyleLibrary.save(id: "desk-talk", name: nil, summary: nil, tokens: nil, guide: nil, files: [(parts.appendingPathComponent("whoosh.wav"), bad)], in: w.styles) }
        }
        #expect(throws: DirectionError.self) { try StyleLibrary.save(id: "nope", name: nil, summary: nil, tokens: nil, guide: nil, in: w.styles) }
        #expect(throws: DirectionError.self) { try StyleLibrary.save(id: nil, name: " ", summary: nil, tokens: nil, guide: nil, in: w.styles) }

        // A folder without a readable name isn't a style.
        try FileManager.default.createDirectory(at: w.styles.appendingPathComponent("loose"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: w.styles.appendingPathComponent("loose/style.json"))
        #expect(StyleLibrary.list(in: w.styles).map(\.id) == ["desk-talk", "desk-talk-2"])
    }

    @Test func theBriefGivesTheFilmItsOwnCopy() throws {
        let w = try world(); defer { w.cleanup() }
        let style = try StyleLibrary.create(name: "Desk Talk", summary: "Quick explainers.", in: w.styles)
        var brief = Brief(); brief.logline = "Maya builds it."; brief.feeling = "Proud."; brief.style = style.id
        try w.store.saveBrief(brief, styles: w.styles)
        let copy = w.store.url.appendingPathComponent("Style")
        #expect(FileManager.default.fileExists(atPath: copy.appendingPathComponent("style.json").path))
        let named = try w.store.style()
        #expect(named?.id == "desk-talk" && named?.name == "Desk Talk")

        // Changing the style later doesn't change the film until it's copied again.
        _ = try StyleLibrary.save(id: style.id, name: nil, summary: "Faster now.", tokens: nil, guide: nil, in: w.styles)
        #expect(try w.store.style()?.summary == "Quick explainers.")
        try w.store.refreshStyle(styles: w.styles)
        #expect(try w.store.style()?.summary == "Faster now.")

        // The film keeps working without the style in the folder.
        try FileManager.default.removeItem(at: style.url)
        brief.feeling = "Proud, then quiet."
        try w.store.saveBrief(brief, styles: w.styles)
        #expect(try w.store.style()?.name == "Desk Talk")

        // Another style that isn't there is refused; None removes the copy.
        brief.style = "gone"
        #expect(throws: DirectionError.self) { try w.store.saveBrief(brief, styles: w.styles) }
        brief.style = "../escape"
        #expect(throws: DirectionError.self) { try w.store.saveBrief(brief, styles: w.styles) }
        brief.style = nil
        try w.store.saveBrief(brief, styles: w.styles)
        let none = try w.store.style()
        #expect(!FileManager.default.fileExists(atPath: copy.path) && none == nil)
    }
}
