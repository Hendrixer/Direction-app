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

/// A study's music in its notes: the cues, the breaks, how far under the voice, the sounds heard and what the
/// page credits, and the style keeps the cues but not every sound heard.
@Test func aStudysMusicIsWrittenOutAndTheStyleKeepsItsCues() {
    let cues = [VideoStudy.Cue(start: 0, end: 112, instruments: ["piano", "bowed strings"], tempo: 92, key: "A minor", underSpeech: 0.8, startsOnCut: nil, endsOnCut: true),
                VideoStudy.Cue(start: 130, end: 190, instruments: ["synth"], tempo: nil, key: nil, underSpeech: 0, startsOnCut: true, endsOnCut: false)]
    let sound = VideoStudy.Sound(loudness: -14.2, truePeak: -1.1, music: 0.8, musicUnderSpeech: 0.5, cues: cues, stings: [111, 129.5], breaks: [VideoStudy.Stretch(start: 112, end: 130)],
                                 musicUnderVoiceDB: -18, musicAloneDB: -6.5, effects: [VideoStudy.Effect(at: 12, sound: "whoosh", onCut: true), VideoStudy.Effect(at: 40, sound: "whoosh", onCut: false), VideoStudy.Effect(at: 41, sound: "ticking clock", onCut: false)],
                                 key: "A minor", cutsHeard: 30, hitsOnCuts: 6, cutsClearOfTalk: 12, risersIntoCuts: 2)
    let study = VideoStudy(title: "Consumerism", by: "A filmmaker", seconds: 200, pace: .init(shots: 31, cutsPerMinute: 9, averageShot: 6.5, medianShot: 5, longestShot: 20, firstCut: 3, cutsByMinute: [9, 10, 8, 4]),
                           sound: sound, picture: .init(close: 0.5, medium: 0.3, wide: 0.2, noFace: 0.2, punchIns: 0.1, brightness: 0.4, contrast: 0.2, saturation: 0.3, warmth: 0.05),
                           musicCredits: ["Music: Film Score Collection Vol. 3"], shots: [])
    let md = study.markdown
    #expect(study.summary.contains("2 music cues"))
    #expect(md.contains("- In the pauses between words the music sits 18 dB under the voice; with nobody talking it plays 7 dB under it."))
    #expect(md.contains("- 2 music cues, 1:26 on average, the longest 1:52; 0.6 a minute."))
    #expect(md.contains("- The music stops for 1 stretch of talk, the longest 0:18: at 1:52."))
    #expect(md.contains("- 2 short bursts of music (risers, transitions, hits) at 1:51, 2:10."))
    #expect(md.contains("- Of the 30 cuts with music playing and no word starting on them, 6 have a sound starting right on the cut: a hit, or the next shot\u{2019}s own sound."))
    #expect(md.contains("- Of the 12 cuts with no talk in the two seconds before, the level rises into 2 (a riser)."))
    #expect(md.contains("- Across the cues, the notes fit A minor best."))
    #expect(md.contains("whoosh 2 (1 on a cut) at 0:12, 0:40; ticking clock 1 at 0:41."))
    #expect(md.contains("1. 0:00\u{2013}1:52 (1:52): piano, bowed strings \u{00B7} about 92 beats a minute \u{00B7} A minor \u{00B7} under the voice 80% of it \u{00B7} ends on a cut"))
    #expect(md.contains("2. 2:10\u{2013}3:10 (1:00): synth \u{00B7} no steady beat \u{00B7} no one talking over it \u{00B7} starts on a cut"))
    #expect(md.contains("## Music on the page") && md.contains("- Music: Film Score Collection Vol. 3"))
    let kept = StyleSource(study).measured?.sound
    #expect(kept?.cues == cues && kept?.effects == nil && kept?.musicUnderVoiceDB == -18)
}

@Test func thePageSaysWhatMusicItUses() {
    let description = """
    How we got here, and why it matters.

    ♪ Music: Story Loops, Film Score Collection Vol. 3
    Song: "Late Night" by Jazz Trio (licensed from Musicbed)
    Our tracking app helps you save money
    Follow me on Instagram
    """
    let credits = VideoStudy.musicCredits(description: description, track: "Late Night", artist: "Jazz Trio")
    #expect(credits == ["\u{201C}Late Night\u{201D} by Jazz Trio", "\u{266A} Music: Story Loops, Film Score Collection Vol. 3", "Song: \"Late Night\" by Jazz Trio (licensed from Musicbed)"])
    #expect(VideoStudy.musicCredits(description: nil, track: nil, artist: nil).isEmpty)
}
