import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent (29–33). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum ChangesFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "29-changes": { .film(arrived()) },
            "30-changes-options": { .film(options()) },
            "31-play-changes": { .film(playing()) },
            "32-changes-thread": { .film(replying()) },
            "33-history": { .film(history()) },
        ]
    }

    /// Cut 4 on screen in Changes, with every earlier cut registered so lengths and "was" ranges resolve.
    static func cut4(room: Room = .changes) -> FilmModel {
        let m = SampleFilm.make(room: room)
        SampleFilm.withCut4(m)
        registerCuts(m)
        m.selectedAnswerNoteID = "note-1"
        return m
    }

    static func registerCuts(_ m: FilmModel) {
        func scaled(_ k: Double) -> [(String, Double, Double)] { SampleFilm.cut3Clips.map { ($0.0, $0.1 * k, $0.2 * k) } }
        CutProjects.preview[4] = SampleFilm.project(clips: scaled(252.0 / 220), revision: 4)
        CutProjects.preview[8] = SampleFilm.project(clips: scaled(232.0 / 220), revision: 8)
        CutProjects.preview[12] = SampleFilm.project(clips: SampleFilm.cut3Clips, revision: 12)
        if let p = m.project { CutProjects.preview[p.editRevision] = p }
    }

    /// A reply as the store writes it (its initializer is internal to DirectionCore).
    static func reply(_ author: String, _ text: String, revision: Int = 19, at time: Double) -> FeedbackReply {
        let json: [String: Any] = ["id": "reply-\(Int(time))", "author": author, "text": text, "revision": revision, "createdAt": time]
        return try! JSONDecoder().decode(FeedbackReply.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// The store's accept, done in memory.
    static func accept(_ m: FilmModel, _ number: Int, pick: String? = nil) {
        guard let i = m.notes.firstIndex(where: { $0.number == number }), var a = m.notes[i].answers?.last else { return }
        a.state = "accepted"; a.pick = pick ?? (a.options == nil ? nil : a.preferred)
        m.notes[i].answers = [a]; m.notes[i].status = "accepted"; m.notes[i].noteState = .accepted
    }

    // 29: Cut 4 just arrived. Sweep, toast, the first answer cued.
    static func arrived() -> FilmModel {
        let m = cut4()
        m.position = SampleFilm.tc(0, 6, 12)
        m.sweepToken = 1
        m.toast = Toast(title: "Cut 4 is ready", detail: "7 answers \u{00B7} 46 s of changes to watch", editor: true)
        return m
    }

    // 30: answer 1 accepted, answer 2's options on the stage, B clicked.
    static func options() -> FilmModel {
        let m = cut4()
        accept(m, 1)
        m.changes.sticky = ["note-1"]
        m.changes.chosenTab = .review
        m.selectedAnswerNoteID = "note-2"
        m.comparingNoteID = "note-2"
        m.changes.optionFocus = 1
        m.position = SampleFilm.tc(0, 48, 4)
        m.playing = true
        return m
    }

    // 31: the reel, on note 3's change.
    static func playing() -> FilmModel {
        let m = cut4()
        accept(m, 1); accept(m, 2, pick: "B")
        m.position = SampleFilm.tc(1, 8, 12)
        m.changeIndex = m.changeReel(in: m.watchedCut).firstIndex { $0.contains(m.position) } ?? 0
        m.playingChanges = true
        m.playing = true
        m.changes.reelOpen = true
        return m
    }

    // 32: answers 1 and 2 done, replying to 3.
    static func replying() -> FilmModel {
        let m = cut4()
        accept(m, 1); accept(m, 2, pick: "B")
        m.changes.sticky = ["note-1", "note-2"]
        m.changes.chosenTab = .review
        if let i = m.notes.firstIndex(where: { $0.number == 3 }) {
            m.notes[i].replies = [reply("Editor", "Reframed to 1.6\u{00D7} on Maya; sky is now a third of the frame. Going past 1.8\u{00D7} softens the image.", at: SampleFilm.cut4.createdAt + 1)]
        }
        m.selectedAnswerNoteID = "note-3"
        m.changes.replyingNoteID = "note-3"
        m.changes.drafts["note-3"] = "Not quite. Still too much sky. Try 1.8\u{00D7} and favour her eyes, I\u{2019}ll live with the softness"
        m.position = SampleFilm.tc(1, 13, 2)
        return m
    }

    // 33: history, note 5's change being reverted.
    static func history() -> FilmModel {
        let m = cut4()
        for n in [1, 3, 4, 6, 7] { accept(m, n) }
        accept(m, 2, pick: "B")
        if let i = m.notes.firstIndex(where: { $0.number == 5 }), var a = m.notes[i].answers?.last {
            a.state = "reopened"; m.notes[i].answers = [a]
            m.notes[i].status = "open"; m.notes[i].noteState = .reopened
            m.notes[i].replies = [reply("Director", "Put this back the way it was in Cut 3.", at: SampleFilm.date(10, 28, 14, 31))]
        }
        m.changes.mode = .history
        m.changes.historyCutID = "cut-4"
        m.changes.historyNoteID = "note-3"
        return m
    }
}
