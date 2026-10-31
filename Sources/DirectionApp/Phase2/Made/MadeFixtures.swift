import SwiftUI
import DirectionCore

// Frames 55, 61 and 62 (design/spec/screens), from real views and sample state. No keychain, ledger or network.
@MainActor
enum MadeFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "61-changes-made": { changesMade() },
            "61-made-checked": { madeChecked() },
            "62-notes-spend": { .film(notesSpend()) },
        ]
    }

    /// The piano bed the editor made for note 4's option B.
    static let pianoBed = MadeRecord(assetID: "made-piano-bed", kind: .music, version: "google/lyria-3-clip", versionName: "Lyria 3 Clip",
                                     asked: "Sparse felt piano, unresolved, around 70 bpm. No swell. 24 seconds, ending on a held note.", seconds: 24, spend: 0.04, estimate: 0.04,
                                     noteID: "note-4", turnoverID: "turnover-3", file: "Made/music-sparse-felt-piano-1a2b.wav", createdAt: SampleFilm.date(10, 28, 14, 2))

    /// Frame 61: Cut 4 in Changes, note 4 answered two ways (decision 19), B with made music, its provenance open.
    private static func changesMade() -> SnapshotScene {
        let m = ChangesFixtures.cut4()
        ChangesFixtures.accept(m, 1); ChangesFixtures.accept(m, 2, pick: "B")
        m.changes.sticky = ["note-1", "note-2"]
        m.changes.chosenTab = .review
        if let i = m.notes.firstIndex(where: { $0.number == 4 }), var a = m.notes[i].answers?.last {
            a.summary = "Two ways. A: the same track, down 6 dB under her line. B: a sparser piano bed I made, with no resolve."
            a.delta = nil; a.preferred = nil
            a.options = [.init(label: "A", summary: "The same track, down 6 dB", revision: 19, delta: "\u{2212}6 dB"), .init(label: "B", summary: "A sparser piano bed", revision: 20, delta: "music")]
            m.notes[i].answers = [a]
        }
        // Option B's version: Cut 4 with the piano bed under the ridge.
        var b = SampleFilm.project(clips: SampleFilm.cut4Clips, revision: 20)
        b.assets.append(MediaAsset(id: pianoBed.assetID, name: "music-sparse-felt-piano-1a2b.wav", path: "/Launch film.direction/Made/music-sparse-felt-piano-1a2b.wav", duration: .init(seconds: 24), audio: [.init(id: 1, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)]))
        b.sequences[0].clips.append(Clip(id: "clip-piano-bed", assetID: pianoBed.assetID, name: "Piano bed", kind: .audio, layer: 1, start: .init(seconds: 95), sourceRange: .init(start: 0, end: 7)))
        CutProjects.preview[20] = b
        m.made.records = [pianoBed]
        m.selectedAnswerNoteID = "note-4"
        m.comparingNoteID = "note-4"
        m.changes.optionFocus = 1
        m.position = SampleFilm.tc(1, 38, 12)
        m.made.provenanceID = "option:" + pianoBed.assetID
        return SnapshotScene(ZStack(alignment: .topLeading) {
            FilmWindow(app: nil, model: m)
            MadeProvenance(film: m, record: pianoBed).background(SystemPopBackground()).offset(x: 524, y: 222)
        })
    }

    /// A made establishing shot whose check found a face changing at 0:03 (decisions.md).
    static let duskShot: MadeRecord = {
        var r = MadeRecord(assetID: "made-dusk-ridge", kind: .shot, version: "minimax/hailuo-3-max", versionName: "MiniMax H3 Max",
                           asked: "Slow push in. Dusk cloud moves over the ridge; the hikers keep walking toward camera. The ridge holds. Cool, quiet evening.", seconds: 5, spend: 0.40, estimate: 0.40,
                           noteID: "note-3", turnoverID: "turnover-3", first: MadeFrame(assetID: "take-3a-t2", at: 12), file: "Made/shot-slow-push-in-dusk-9c1e.mp4", way: 2, createdAt: SampleFilm.date(10, 28, 14, 4))
        let moments = MadeChecker.moments(duration: 5)
        r.check = MadeChecker.check(from: Decisions.Reply(answers: ["look1": .init(choice: "clean"), "look2": .init(choice: "clean"), "look3": .init(choice: "minor"), "look4": .init(choice: "broken"), "look5": .init(choice: "broken"),
                                                                     "morph": .init(choice: "moves"), "same": .init(choice: "drifted"), "asked": .init(choice: "yes")], version: Decisions.version, cost: 0.0004),
                                    moments: moments, now: Date(timeIntervalSince1970: SampleFilm.date(10, 28, 14, 4)))
        return r
    }()

    /// The provenance of a checked shot, by itself on the window's surface.
    private static func madeChecked() -> SnapshotScene {
        let m = ChangesFixtures.cut4()
        m.made.records = [duskShot]
        return SnapshotScene(size: CGSize(width: 420, height: 480), ZStack {
            Gate.Surface.ground
            MadeProvenance(film: m, record: duskShot).background(SystemPopBackground())
        })
    }

    /// Frame 62: the read-back for Cut 4 waits for your OK; the editor asks to spend on note 3.
    static func notesSpend() -> FilmModel {
        let m = NotesFixtures.readBack()
        var q = EditorQuestion(id: "question-spend-3", turnoverID: "turnover-3", kind: "spend", noteIDs: ["note-3"],
                               text: "Note 3 wants less sky. Reframing to 1.6\u{00D7} gets the sky to a third of the frame. To make the sky itself dusk cloud, I\u{2019}d change those 5 seconds of the take with Aleph 2.0, and make an establishing shot of the ridge at dusk to lead in.", detail: nil,
                               choices: [
                                   .init(id: "reframe", label: "Reframe only", detail: "No spend", assetID: "take-3a-t2", recommended: true),
                                   .init(id: "make", label: "Change the sky and add the dusk shot", detail: "About $2.75", assetID: "take-3a-t2"),
                                   .init(id: "find", label: "Find another take", detail: "I\u{2019}ll search the ridge footage first"),
                               ],
                               allowsText: true, answer: nil, createdAt: SampleFilm.date(10, 28, 14, 2) + 10)
        q.spend = SpendAsk(estimate: 2.75, turnoverSpent: 2.90, limit: 5, choiceID: "make", kind: .changedShot, version: "runway/aleph-2")
        m.questions = [q]
        m.notesTab = .questions
        m.notesUI.choices[q.id] = "make"
        m.position = SampleFilm.tc(1, 12, 8)
        return m
    }
}
