import SwiftUI
import DirectionCore

// Frame 64 (graphics.md). An alternate sample (open-questions.md › 19): Cut 4 carries an eighth
// answer, a title over the cold open, and the director is fixing its words.
@MainActor
enum GraphicsFixtures {
    static var frames: [String: () -> SnapshotScene] {
        ["64-changes-graphic": { .film(changesGraphic()) }]
    }

    /// The title the editor made for note 8, as the store records it.
    static let title = Graphic(name: "title", folder: "/Users/you/Movies/Direction/Launch film.direction/Editor/Graphics/title", duration: 4,
                               words: [GraphicWord(key: "title", label: "Title", text: "Two years.", maxLength: 40)], assetID: "asset-graphic-title", noteID: "note-8")

    /// Note 8 answered with the title: "In at 00:02, out at 00:06".
    static func withTitle(_ m: FilmModel) {
        var n = SampleFilm.note(8, "Put a title over the cold open: two years.", kind: .story, time: SampleFilm.tc(0, 2), scene: "scene-1")
        var a = NoteAnswer(cutID: "cut-4", revision: 19, summary: "Added a title over the street wide: \u{201C}Two years.\u{201D} In at 00:02, out at 00:06.", delta: "title", range: MediaRange(start: 2, end: 6), createdAt: SampleFilm.cut4.createdAt)
        a.state = "unreviewed"
        n.answers = [a]; n.status = "addressed"; n.noteState = .answered; n.turnoverID = "turnover-3"
        m.notes.append(n)
        m.graphics.graphics = [title]
    }

    // 64: answers 1 and 2 accepted, note 8 selected at 00:04:00, its Words popover open mid-typing.
    static func changesGraphic() -> FilmModel {
        let m = ChangesFixtures.cut4()
        ChangesFixtures.accept(m, 1); ChangesFixtures.accept(m, 2, pick: "B")
        m.changes.sticky = ["note-1", "note-2"]
        m.changes.chosenTab = .review
        withTitle(m)
        m.selectedAnswerNoteID = "note-8"
        m.position = SampleFilm.tc(0, 4)
        m.graphics.openWords(title, for: m.notes.last!)
        m.graphics.type("Two years, alone.", into: title.words[0])
        return m
    }
}
