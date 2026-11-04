import SwiftUI
import DirectionCore

// Owner: Notes agent (17–28). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum NotesFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "17-notes-drafts": { .film(drafts()) },
            "18-notes-writing": { .film(writing()) },
            "19-notes-region": { .film(region()) },
            "20-notes-questions": { .film(questions()) },
            "21-notes-outside": { .film(outside()) },
            "22-turnover": { .film(turnover()) },
            "23-readback": { .film(readBack()) },
            "24-readback-adjust": { .film(readBackAdjust()) },
            "25-cutting": { .film(cutting()) },
            "26-cutting-cant": { .film(cuttingCant()) },
            "27-cutting-conflict": { .film(cuttingConflict()) },
            "28-cutting-error": { .film(cuttingError()) },
            "17z-notes-cut-on-v2": { .film(cutOnV2()) },
            "17zz-screening-cut-on-v2": { let m = cutOnV2(); m.watchingCut = true; return .film(m) },
        ]
    }

    /// A delivered cut built on V2 the way an editor can leave it: V1 empty, a title alone on V3 for the
    /// first 4.3 s, then the story cut short and back and forth between scenes, every scene locked.
    static func cutOnV2() -> FilmModel {
        let m = SampleFilm.make()
        func rebuild(_ p: inout Project) {
            for i in p.sequences.indices {
                let story = p.sequences[i].clips.filter { $0.kind == .video && $0.layer == 0 && $0.assetID != nil }
                guard !story.isEmpty else { continue }
                var clips = p.sequences[i].clips.filter { $0.kind != .video }
                var t = 4.3, n = 0
                while t < 120 {
                    let from = story[n % story.count], length = [1.4, 3.2, 2.1, 4.6, 0.9, 2.7][n % 6]
                    clips.append(Clip(assetID: from.assetID, name: from.name, layer: 1, start: MediaTime(seconds: t), sourceRange: MediaRange(start: from.sourceRange.start.seconds, end: from.sourceRange.start.seconds + length)))
                    t += length; n += 1
                }
                clips.append(Clip(assetID: "asset-title", name: "coded-love-title", layer: 2, start: .zero, sourceRange: MediaRange(start: 0, end: 4.3)))
                p.sequences[i].clips = clips
            }
        }
        if var p = m.project { rebuild(&p); m.project = p }
        if var d = m.displayed { rebuild(&d); m.displayed = d }
        for i in m.dailies.scenes.indices { m.dailies.scenes[i].locked = true }
        m.position = 4.3
        return m
    }

    private static func tc(_ m: Int, _ s: Int, _ f: Int = 0) -> Double { SampleFilm.tc(m, s, f) }
    private static func at(_ hour: Int, _ minute: Int, _ second: Double = 0) -> Date {
        Date(timeIntervalSince1970: SampleFilm.date(10, 28, hour, minute) + second)
    }

    // MARK: 17–19 writing

    /// Notes 1–2 written, 3–4 drafts from the screening, note 2 selected.
    static func drafts() -> FilmModel {
        let m = SampleFilm.make()
        m.selectedNoteID = "note-2"
        return m
    }

    /// Draft 3 selected and being written; the editor suggests Picture.
    static func writing() -> FilmModel {
        let m = SampleFilm.make()
        m.position = tc(1, 12, 8)
        m.selectedNoteID = "note-3"
        m.draftText = "Tighter on her. The sky is winning"
        m.composerFocus = 1
        return m
    }

    /// Drawing a region for note 3, kind chosen.
    static func region() -> FilmModel {
        let m = writing()
        m.draftText = "Tighter on her. The sky is winning."
        m.draftKind = .picture
        m.anchorMode = .region
        m.region = CGRect(x: 0.31, y: 0.20, width: 0.24, height: 0.58)
        m.drawingRegion = true
        return m
    }

    // MARK: 20–21 questions and outside notes

    /// Cutting Cut 4; the editor asks which reading of line 12.
    static func questions() -> FilmModel {
        let m = cuttingFilm([1: .done, 5: .done, 3: .done, 4: .working], done: [1, 5, 3], elapsed: 90, now: 210)
        let q = EditorQuestion(id: "question-line-12", turnoverID: "turnover-3", kind: "question", noteIDs: ["note-2"],
                               text: "Line 12 has two good readings. T2 is warmer; T5 sounds more tired, which fits note 2. Which one?", detail: nil,
                               choices: [
                                   .init(id: "t2", label: "Use T2", detail: "2A · \u{201C}Editing was the part nobody wanted.\u{201D}", assetID: "take-2a-t2"),
                                   .init(id: "t5", label: "Use T5", detail: "2A · slower, a breath before \u{201C}nobody\u{201D}", assetID: "take-2a-t5"),
                                   .init(id: "both", label: "Cut both ways", detail: "You pick on the sheet"),
                               ],
                               allowsText: true, answer: nil, createdAt: at(14, 3, 210 - 120).timeIntervalSince1970)
        m.questions = [q]
        m.notesTab = .questions
        m.notesUI.choices[q.id] = "t5"
        m.position = tc(0, 52, 16)
        return m
    }

    /// Six written notes; three notes from people with the screening link wait in the inbox.
    static func outside() -> FilmModel {
        let m = SampleFilm.make()
        let now = SampleFilm.date(10, 28, 12, 0)
        let priya = Person(name: "Priya Shah", role: "Producer"), tom = Person(name: "Tom Reyes", role: "Client")
        var a = SampleFilm.note(nil, "Show the team earlier, it feels like she did it alone.", person: priya, outside: "inbox", scene: "scene-4", created: now - 3600)
        var b = SampleFilm.note(nil, "Can the logo be bigger at the end?", time: tc(3, 31), person: tom, outside: "inbox", created: now - 2400)
        var c = SampleFilm.note(nil, "Love the ridge shot.", time: tc(1, 30), person: tom, outside: "inbox", created: now - 2280)
        a.id = "outside-priya"; b.id = "outside-tom-logo"; c.id = "outside-tom-ridge"
        m.notes = Array(SampleFilm.cut3Notes.prefix(6)) + [a, b, c]
        m.notesTab = .outside
        m.notesUI.selectedOutsideID = a.id
        m.notesUI.clock = Date(timeIntervalSince1970: now)
        m.position = tc(2, 5)
        return m
    }

    // MARK: 22–24 turnover and read-back

    /// All seven notes written; the turnover sheet is open.
    static func turnover() -> FilmModel {
        let m = SampleFilm.make()
        m.notes = SampleFilm.cut3Notes
        m.sheet = .turnover
        return m
    }

    /// The editor read the notes back and waits for your OK.
    static func readBack() -> FilmModel {
        let m = SampleFilm.make()
        SampleFilm.withTurnover(m, state: .readBack, readBack: true)
        m.position = tc(1, 12, 8)
        m.notesUI.clock = at(14, 2, 20)
        return m
    }

    /// Correcting line 3 of the read-back.
    static func readBackAdjust() -> FilmModel {
        let m = readBack()
        m.notesUI.correctingNoteID = "note-3"
        m.notesUI.correction = "Not that tight. Keep the horizon, just lose some of the sky"
        return m
    }

    // MARK: 25–28 cutting

    static func cutting() -> FilmModel {
        let m = cuttingFilm([1: .done, 5: .done, 3: .working], done: [1, 5], elapsed: 96)
        m.position = tc(1, 12, 8)
        return m
    }

    /// Note 7 needs Launch day, which is locked.
    static func cuttingCant() -> FilmModel {
        let m = cuttingFilm([1: .done, 5: .done, 3: .done, 7: .cant, 2: .working], done: [1, 5, 3], elapsed: 140)
        let q = EditorQuestion(id: "cant-note-7", turnoverID: "turnover-3", kind: "cant", noteIDs: ["note-7"],
                               text: "The best team shot, 5A T3, is in Launch day, which you locked. I\u{2019}ve left the rest of the cut moving.", detail: nil,
                               choices: [
                                   .init(id: "unlock", label: "Unlock Launch day and use 5A T3", assetID: "take-5a-t3"),
                                   .init(id: "use-4c", label: "Use 4C T2 instead", detail: "Team at the table, already in scene 4", assetID: "take-4c-t2", recommended: true),
                                   .init(id: "skip", label: "Skip note 7 for this cut"),
                               ],
                               allowsText: false, answer: nil, createdAt: at(14, 5).timeIntervalSince1970)
        m.questions = [q]
        m.notesUI.choices[q.id] = "use-4c"
        m.position = tc(2, 4, 16)
        return m
    }

    /// Notes 2 and 1 overlap; the editor follows Feeling over Pace.
    static func cuttingConflict() -> FilmModel {
        let m = cuttingFilm([1: .done, 5: .done, 3: .done, 2: .working], done: [1, 5, 3], elapsed: 135)
        if let i = m.turnovers[0].readBack.firstIndex(where: { $0.noteID == "note-2" }) {
            m.turnovers[0].readBack[i].conflict?.detail = "Between 00:25 and 00:46, note 2 wants more time on her and note 1 wants to get there sooner."
        }
        m.anchorMode = .range
        m.rangeSelection = 25...46
        m.position = tc(0, 38, 20)
        return m
    }

    /// The disk filled up while rendering note 6.
    static func cuttingError() -> FilmModel {
        let m = cuttingFilm([1: .done, 5: .done, 3: .done, 2: .done, 6: .stopped], done: [1, 5, 3, 2], elapsed: 180)
        m.turnovers[0].state = .failed
        m.turnovers[0].message = "The disk ran out of room while I was rendering note 6. Cut 3 and your notes are safe, and the four notes I finished are kept."
        m.turnovers[0].updatedAt = SampleFilm.date(10, 28, 14, 6)
        m.notesUI.previewDisk = ("Macintosh HD", 1.2e9)
        m.position = tc(2, 20)
        return m
    }

    /// Notes 1–7 turned over at 14:02, read-back approved, cutting since 14:03.
    private static func cuttingFilm(_ progress: [Int: NoteProgress], done: [Int], elapsed: Double, now: Double? = nil) -> FilmModel {
        let m = SampleFilm.make()
        SampleFilm.withTurnover(m, state: .cutting, readBack: true)
        m.turnovers[0].readBackApproved = true
        for (n, p) in progress { m.turnovers[0].progress["note-\(n)"] = p }
        m.notesUI.doneOrder = done.map { "note-\($0)" }
        m.notesUI.cuttingStarted["turnover-3"] = at(14, 3)
        m.notesUI.clock = at(14, 3, now ?? elapsed)
        if let now { m.notesUI.cuttingStarted["turnover-3"] = at(14, 3, now - elapsed) }
        return m
    }
}
