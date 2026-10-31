import Testing
import Foundation
@testable import DirectionCore

/// Styles (specs/styles.md): a folder with its rules, layouts, moves, values and parts; the house style under
/// every film; a film's own copy; keeping a rule from an answer.
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

    @Test func aStyleIsAFolderWithItsRulesValuesAndParts() throws {
        let w = try world(); defer { w.cleanup() }
        let made = try StyleLibrary.create(name: "Desk Talk", summary: "Quick explainers.", rules: [StyleRule(area: "pace", text: "Tighten every pause longer than 0.35 s.")], in: w.styles)
        #expect(made.id == "desk-talk" && made.tokens["format"].int == 2 && made.rules.map(\.text) == ["Tighten every pause longer than 0.35 s."] && made.rules[0].area == "pace" && made.contents.line.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: made.url.appendingPathComponent("guide.md").path))
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
        #expect(saved.rules.count == 1)
        // A guide in words (the older way) becomes rules, one per line under its heading.
        let pruned = try StyleLibrary.save(id: "desk-talk", name: nil, summary: nil, tokens: .object(["pace": .null]), guide: "# Desk Talk\n\n## Transitions\nHard cuts.\n\n## Avoid\n- Dissolves.\n- Whips.\n", in: w.styles)
        #expect(pruned.tokens["pace"] == .null && pruned.tokens["colors"]["accent"].string == "#FFC800")
        #expect(pruned.rules.map(\.text) == ["Hard cuts.", "Dissolves.", "Whips."] && pruned.rules.map(\.area) == ["transitions", "avoid", "avoid"])
        // Layouts need names; moves need their numbers.
        #expect(throws: DirectionError.self) { try StyleLibrary.save(id: "desk-talk", name: nil, summary: nil, tokens: .object(["layouts": .array([.object(["kind": .string("you")])])]), guide: nil, in: w.styles) }
        #expect(throws: DirectionError.self) { try StyleLibrary.save(id: "desk-talk", name: nil, summary: nil, tokens: .object(["moves": .object(["punchIn": .object(["keepIn": .string("thirds")])])]), guide: nil, in: w.styles) }

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

    @Test func aStyleWrittenAsAGuideReadsAsRules() throws {
        let w = try world(); defer { w.cleanup() }
        let folder = w.styles.appendingPathComponent("old")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"format": 1, "name": "Old Way", "pace": {"tightenPausesLongerThan": 0.4}}"#.utf8).write(to: folder.appendingPathComponent("style.json"))
        try Data(StyleLibrary.template(name: "Old Way", summary: "").replacingOccurrences(of: "## Pace\nHow long shots hold, how tight the pauses are, how soon it gets to the point.", with: "## Pace\n- **Hook** within 2 s.\n\nKeep breaths\nbefore punchlines.").utf8).write(to: folder.appendingPathComponent("guide.md"))
        let old = try StyleLibrary.read(folder)
        // The template's own placeholder lines aren't rules; bold goes; a paragraph is one rule.
        #expect(old.rules.map(\.text) == ["Hook within 2 s.", "Keep breaths before punchlines."] && old.rules.allSatisfy { $0.area == "pace" })
        // The first change writes them into style.json, so they stay put.
        let kept = try StyleLibrary.keep(StyleRule(area: "captions", text: "Captions off over the title."), in: "old", folder: w.styles)
        #expect(kept.tokens["format"].int == 2 && kept.rules.count == 3 && kept.rules.last?.area == "captions")
        #expect(try StyleLibrary.remove(rules: [kept.rules[0].id], from: "old", folder: w.styles).rules.map(\.text) == ["Keep breaths before punchlines.", "Captions off over the title."])
    }

    @Test func theHouseStyleIsUnderEveryFilmAndTheStyleWinsOverIt() throws {
        let w = try world(); defer { w.cleanup() }
        // Until something is kept in it, the house style is empty and isn't a folder.
        #expect(StyleLibrary.house(in: w.styles).rules.isEmpty && !FileManager.default.fileExists(atPath: w.styles.appendingPathComponent("house").path))
        try StyleLibrary.keep(StyleRule(area: "graphics", text: "Text never covers my face."), in: StyleLibrary.houseID, folder: w.styles)
        try StyleLibrary.save(id: StyleLibrary.houseID, name: "Renamed", summary: nil, tokens: .object(["moves": .object(["punchIn": .object(["scales": .array([.number(1), .number(1.1)])])])]), guide: nil, in: w.styles)
        let house = StyleLibrary.house(in: w.styles)
        #expect(house.name == "House style" && house.rules.map(\.text) == ["Text never covers my face."])
        // It isn't one of the styles a brief picks, and no style takes its folder's name.
        #expect(StyleLibrary.list(in: w.styles).isEmpty)
        #expect(try StyleLibrary.create(name: "House", summary: "", in: w.styles).id == "house-2")

        let style = try StyleLibrary.save(id: nil, name: "Desk + Screen", summary: "", tokens: .object([
            "layouts": .array([.object(["name": .string("Talking"), "kind": .string("you")]), .object(["name": .string("Showing"), "kind": .string("screenAndYou"), "shape": .string("rounded"), "edge": .string("#FFD43B")])]),
            "moves": .object(["emphasisPunch": .object(["scale": .number(1.32)])]),
            "pace": .object(["tightenPauses": .object(["longerThan": .number(0.4), "to": .number(0.15)])]),
        ]), guide: nil, rules: [StyleRule(area: "captions", text: "Captions only where they don't cover the screen.")], in: w.styles)
        let applied = StyleLibrary.applied(style, folder: w.styles)
        // House rules first, then the style's; the style's layouts by name; each move from the narrowest that sets it.
        #expect(applied.rules.map(\.styleName) == ["House style", "Desk + Screen"])
        #expect(applied.layout(named: "showing")?.edge == "#FFD43B" && applied.layout(named: "Showing")?.shape == .rounded && applied.layout(named: "Detail") == nil)
        #expect(applied.moves.punchIn?.scales == [1, 1.1] && applied.moves.emphasisPunch?.scale == 1.32 && applied.moves.tightenPauses?.longerThan == 0.4 && applied.moves.slowPush == StyleMoves.standard.slowPush)
        // Without a style: the house style and Direction's own.
        #expect(StyleLibrary.applied(nil, folder: w.styles).moves.emphasisPunch?.scale == StyleMoves.standard.emphasisPunch?.scale)
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
