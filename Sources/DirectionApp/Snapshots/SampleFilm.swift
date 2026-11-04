import Foundation
import SwiftUI
import DirectionCore

/// "Launch film" from design/spec/specs/story.md, as model state for previews and snapshots.
/// No files are touched; pictures use the footage stand-ins.
@MainActor
enum SampleFilm {
    static let fps = 24.0
    /// Seconds from MM:SS:FF at 24 fps.
    static func tc(_ m: Int, _ s: Int, _ f: Int = 0) -> Double { Double(m * 60 + s) + Double(f) / fps }

    struct TakeSpec { var id: String; var file: String; var scene: Int; var setup: String; var code: String; var duration: Double; var caption: String; var circled = false; var suggestion: String? = nil; var flags: [String] = []; var unusable = false }

    static let sceneSpecs: [(Int, String, [DailiesSetup])] = [
        (1, "Cold open", [.init(code: "1A", description: "Street, night"), .init(code: "1B", description: "Window, close")]),
        (2, "Maya, the problem", [.init(code: "2A", description: "Wide, window light"), .init(code: "2B", description: "Close, over shoulder")]),
        (3, "The ridge", [.init(code: "3A", description: "Wide, dusk"), .init(code: "3B", description: "Close, profile")]),
        (4, "Building it", [.init(code: "4A", description: "Hands, keyboard"), .init(code: "4B", description: "Whiteboard"), .init(code: "4C", description: "Team")]),
        (5, "Launch day", [.init(code: "5A", description: "Office, day"), .init(code: "5B", description: "Empty office")]),
    ]

    static let takeSpecs: [TakeSpec] = [
        .init(id: "take-1a-t5", file: "B001_C004_1018.mov", scene: 1, setup: "1A", code: "T5", duration: 22, caption: "Street, car passing", circled: true),
        .init(id: "take-1b-t2", file: "B001_C006_1018.mov", scene: 1, setup: "1B", code: "T2", duration: 18, caption: "Window, her reflection", circled: true),
        .init(id: "take-2a-t1", file: "A010_C009_1021.mov", scene: 2, setup: "2A", code: "T1", duration: 48, caption: "\u{201C}So we started with the edit, and everyone said, start with the camera.\u{201D}", flags: ["Flubbed line at 0:31"]),
        .init(id: "take-2a-t2", file: "A011_C001_1021.mov", scene: 2, setup: "2A", code: "T2", duration: 44, caption: "\u{201C}Editing was the part nobody wanted.\u{201D}", circled: true),
        .init(id: "take-2a-t3", file: "A011_C002_1021.mov", scene: 2, setup: "2A", code: "T3", duration: 46, caption: "\u{201C}Editing was the part nobody wanted.\u{201D}", suggestion: "Warmest read of the line, and she holds the look after it for two seconds."),
        .init(id: "take-2a-t4", file: "A011_C003_1021.mov", scene: 2, setup: "2A", code: "T4", duration: 12, caption: "Breaks, laughs, looks to the window.", unusable: true),
        .init(id: "take-2b-t1", file: "A012_C001_1021.mov", scene: 2, setup: "2B", code: "T1", duration: 21, caption: "Hands on the keyboard, timeline scrolling.", flags: ["B-roll"]),
        .init(id: "take-2b-t2", file: "A012_C002_1021.mov", scene: 2, setup: "2B", code: "T2", duration: 19, caption: "Hands, slower push in.", suggestion: "Steadier."),
        .init(id: "take-2b-t3", file: "A012_C003_1021.mov", scene: 2, setup: "2B", code: "T3", duration: 20, caption: "Hands, rack focus to the screen.", flags: ["Soft at 0:06"]),
        .init(id: "take-3a-t2", file: "B003_C012_1019.mov", scene: 3, setup: "3A", code: "T2", duration: 64, caption: "Wide, dusk. Maya walks to the edge.", circled: true),
        .init(id: "take-3a-t3", file: "B003_C013_1019.mov", scene: 3, setup: "3A", code: "T3", duration: 58, caption: "Wide, dusk, later light.", circled: true),
        .init(id: "take-3b-t1", file: "B003_C015_1019.mov", scene: 3, setup: "3B", code: "T1", duration: 31, caption: "Profile against the sky.", suggestion: "Her face reads; the sky doesn't win."),
        .init(id: "take-4a-t1", file: "A014_C004_1022.mov", scene: 4, setup: "4A", code: "T1", duration: 40, caption: "Hands, keyboard.", circled: true),
        .init(id: "take-4b-t1", file: "A014_C007_1022.mov", scene: 4, setup: "4B", code: "T1", duration: 38, caption: "Whiteboard, sticky notes."),
        .init(id: "take-4c-t2", file: "C002_C001_1024.mov", scene: 4, setup: "4C", code: "T2", duration: 57, caption: "Team at the table.", suggestion: "Shows she didn't do it alone."),
        .init(id: "take-5a-t3", file: "C004_C031_1026.mov", scene: 5, setup: "5A", code: "T3", duration: 41, caption: "Office, team arriving.", suggestion: "Best team shot."),
        .init(id: "take-5b-t1", file: "C004_C032_1026.mov", scene: 5, setup: "5B", code: "T1", duration: 33, caption: "The empty office.", circled: true),
    ]

    /// Cut 3's clips: (take, start, end) in the cut. 3:40 total.
    static let cut3Clips: [(String, Double, Double)] = [
        ("take-1a-t5", 0, 14), ("take-1b-t2", 14, 25),
        ("take-2a-t2", 25, 52), ("take-2b-t2", 52, 65),
        ("take-3a-t2", 65, 110),
        ("take-4a-t1", 110, 140), ("take-4b-t1", 140, 176),
        ("take-5a-t3", 176, 200), ("take-5b-t1", 200, 220),
    ]
    /// Cut 4: 3:31, the answers applied.
    static let cut4Clips: [(String, Double, Double)] = [
        ("take-1a-t5", 0, 9.8), ("take-1b-t2", 9.8, 20.8),
        ("take-2a-t2", 20.8, 49.4), ("take-2b-t2", 49.4, 59.3),
        ("take-3a-t2", 59.3, 104.3),
        ("take-4c-t2", 104.3, 112), ("take-4a-t1", 112, 140), ("take-4b-t1", 140, 167),
        ("take-5a-t3", 167, 191), ("take-5b-t1", 191, 211),
    ]

    static func project(clips: [(String, Double, Double)], revision: Int) -> Project {
        var p = Project(name: "Launch film")
        p.assets = takeSpecs.map { t in
            MediaAsset(id: t.id, name: t.file, path: "/Volumes/Shoot SSD/\(t.file)", duration: .init(seconds: t.duration), video: [.init(id: 1, width: 3840, height: 2160, frameRate: 23.976)], audio: [.init(id: 2, index: 0, label: "Lav", channels: 1, sampleRate: 48_000)])
        }
        p.sequences = [DirectionCore.Sequence(id: "sequence-main", name: "Launch film", width: 1920, height: 1080, frameRate: .init(24, 1), clips: clips.map { id, start, end in
            Clip(id: "clip-\(id)-\(Int(start))", assetID: id, name: id, start: .init(seconds: start), sourceRange: .init(start: 2, end: 2 + end - start))
        })]
        p.editRevision = revision
        return p
    }

    static func dailies(lockLaunch: Bool = true) -> Dailies {
        var d = Dailies(scenes: sceneSpecs.map { DailiesScene(id: "scene-\($0.0)", number: $0.0, title: $0.1, setups: $0.2, locked: $0.0 == 5 && lockLaunch) }, takes: [:])
        for t in takeSpecs {
            var info = TakeInfo(assetID: t.id)
            info.sceneID = "scene-\(t.scene)"; info.setupCode = t.setup; info.code = t.code; info.caption = t.caption
            info.circled = t.circled; info.suggestion = t.suggestion; info.flags = t.flags; info.unusable = t.unusable
            d.takes[t.id] = info
        }
        return d
    }

    static let cuts: [ReviewCut] = [
        .init(id: "cut-assembly", name: "Assembly", editRevision: 4, sequenceID: "sequence-main", createdAt: date(10, 20, 9, 12)),
        .init(id: "cut-2", name: "Cut 2", editRevision: 8, sequenceID: "sequence-main", createdAt: date(10, 22, 17, 5)),
        .init(id: "cut-3", name: "Cut 3", editRevision: 12, sequenceID: "sequence-main", createdAt: date(10, 26, 11, 40)),
    ]
    static let cut4 = ReviewCut(id: "cut-4", name: "Cut 4", editRevision: 19, sequenceID: "sequence-main", createdAt: date(10, 28, 14, 9))

    static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Double {
        DateComponents(calendar: .current, year: 2026, month: month, day: day, hour: hour, minute: minute).date!.timeIntervalSince1970
    }

    static var briefValue: Brief {
        var b = Brief()
        b.logline = "Maya spent two years building the part nobody wanted to build."
        b.feeling = "Tired, then proud. Quiet, not triumphant. Let her face do the work."
        b.lengthMin = 180; b.lengthMax = 240; b.audience = "People who make things"
        b.mustKeep = ["Editing was the part nobody wanted.", "Final shot of the empty office"]
        b.references = [.init(id: "ref-jiro", title: "Jiro Dreams of Sushi, opening", why: "For the pace. Patient, then it moves."), .init(id: "ref-window", title: "Window light still", why: "For the look. Warm, one source, a lot of shadow.")]
        b.avoid = "Stock music swells"
        return b
    }

    /// One note. Times are seconds in Cut 3.
    static func note(_ number: Int?, _ text: String, kind: NoteKind? = nil, time: Double? = nil, range: (Double, Double)? = nil, region: FrameRegion? = nil, state: NoteState = .written, cut: String = "cut-3", revision: Int = 12, person: Person? = nil, outside: String? = nil, script: ScriptAction? = nil, scene: String? = nil, created: Double = date(10, 27, 10, 0)) -> ReviewComment {
        var c = ReviewComment(id: number.map { "note-\($0)" } ?? "note-\(UUID().uuidString.prefix(6))", cutID: cut, editRevision: revision, sequenceID: "sequence-main", scope: range != nil ? "range" : time != nil ? "moment" : "cut",
                              range: range.map { MediaRange(start: $0.0, end: $0.1) }, time: time.map { MediaTime(seconds: $0) }, region: region, text: text, author: person?.name ?? "Director", status: "open", anchors: [], transcriptContext: [], replies: [], createdAt: created + Double(number ?? 0), cursor: Int64(number ?? 0))
        c.number = number; c.kind = kind; c.noteState = state; c.person = person; c.scriptAction = script; c.sceneID = scene
        if person != nil { c.authorRole = "outside"; c.outsideState = outside ?? "inbox" }
        return c
    }

    /// The seven notes on Cut 3, written.
    static var cut3Notes: [ReviewComment] {
        [
            note(1, "Cold open takes too long to get to her face.", kind: .pace, time: tc(0, 18, 4)),
            note(2, "I want to feel how tired she was here. Let it sit.", kind: .feeling, range: (tc(0, 46), tc(0, 58, 12))),
            note(3, "Tighter on her. The sky is winning.", kind: .picture, time: tc(1, 12, 8), region: .init(x: 0.30, y: 0.22, width: 0.22, height: 0.52)),
            note(4, "Music is too sure of itself here.", kind: .sound, time: tc(1, 43, 20)),
            note(5, "Lose \u{201C}and that\u{2019}s when everything changed.\u{201D}", kind: .story, time: tc(1, 2), script: .init(gesture: .strike, lineText: "And that\u{2019}s when everything changed.", lineLabel: "Line 14")),
            note(6, "The building montage is one beat too long.", kind: .pace, range: (tc(2, 20), tc(2, 41))),
            note(7, "Show the team earlier.", kind: .story, person: Person(name: "Priya Shah", role: "Producer"), outside: "accepted", scene: "scene-4"),
        ]
    }

    /// The base world: Cut 3 on screen in the Cut room, notes 1–2 written and 3–4 still drafts from the screening.
    static func make(room: Room = .cut) -> FilmModel {
        let m = FilmModel(preview: true)
        m.project = project(clips: cut3Clips, revision: 12)
        m.displayed = m.project
        m.brief = briefValue
        m.dailies = dailies()
        m.cuts = cuts
        var notes = Array(cut3Notes.prefix(2))
        notes.append(note(3, "", time: tc(1, 12, 8), state: .draft))
        notes.append(note(4, "", time: tc(1, 43, 20), state: .draft))
        m.notes = notes
        m.room = room
        m.position = tc(0, 46, 12)
        return m
    }

    /// Cut 4 delivered with answers to notes 1–7.
    static func withCut4(_ m: FilmModel) {
        var notes = cut3Notes
        let answers: [(Int, String, String?, (Double, Double), [NoteOption]?)] = [
            (1, "Cut the second street wide; we\u{2019}re on her face by 0:09.", "\u{2212}4.2 s", (0, 9.8), nil),
            (2, "Two ways. A holds on her, B cuts to the window and back.", nil, (40.9, 49.4), [.init(label: "A", summary: "Hold on her", delta: "+1.6 s"), .init(label: "B", summary: "Window, then back", delta: "0.0 s")]),
            (3, "Reframed to 1.6\u{00D7} on Maya; sky is now a third of the frame.", "crop", (64, 71.5), nil),
            (4, "Music down 6 dB under her line, back up at the cut.", "\u{2212}6 dB", (95, 102), nil),
            (5, "Struck \u{201C}and that\u{2019}s when everything changed.\u{201D}", "\u{2212}3.1 s", (56, 58), nil),
            (6, "Dropped the second whiteboard shot.", "\u{2212}2.0 s", (140, 144), nil),
            (7, "Moved 4C T2, the team at the table, to open scene 4.", "0.0 s", (104.3, 112), nil),
        ]
        for (n, summary, delta, r, options) in answers {
            guard let i = notes.firstIndex(where: { $0.number == n }) else { continue }
            var a = NoteAnswer(cutID: "cut-4", revision: 19, summary: summary, delta: delta, range: MediaRange(start: r.0, end: r.1), options: options, preferred: options == nil ? nil : "B", createdAt: cut4.createdAt)
            a.state = "unreviewed"
            notes[i].answers = [a]; notes[i].status = "addressed"; notes[i].noteState = .answered; notes[i].turnoverID = "turnover-3"
        }
        m.notes = notes
        m.cuts = cuts + [cut4]
        m.project = project(clips: cut4Clips, revision: 19)
        m.displayed = m.project
        m.turnovers = [Turnover(id: "turnover-3", number: 3, kind: "notes", noteIDs: notes.map(\.id), baseRevision: 12, baseCutID: "cut-3", sequenceID: "sequence-main", latitude: .faithful, waitForOK: true, state: .delivered, readBackApproved: true, resultCutID: "cut-4", createdAt: date(10, 28, 14, 2), updatedAt: date(10, 28, 14, 9))]
    }

    /// Notes 1–7 turned over to the editor (turnover 3), Cut 3 on screen.
    static func withTurnover(_ m: FilmModel, state: TurnoverState, readBack: Bool = false) {
        var notes = cut3Notes
        for i in notes.indices { notes[i].noteState = .turnedOver; notes[i].turnoverID = "turnover-3" }
        m.notes = notes
        var t = Turnover(id: "turnover-3", number: 3, kind: "notes", noteIDs: notes.map(\.id), baseRevision: 12, baseCutID: "cut-3", sequenceID: "sequence-main", latitude: .faithful, waitForOK: true, state: state, createdAt: date(10, 28, 14, 2), updatedAt: date(10, 28, 14, 3))
        t.progress = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, NoteProgress.queued) })
        if readBack { t.readBack = sampleReadBack }
        m.turnovers = [t]
    }

    static var sampleReadBack: [ReadBackLine] {
        [
            .init(noteID: "note-1", plan: "Drop the second street wide. On her face by 0:09.", delta: "\u{2212}4.2 s"),
            .init(noteID: "note-2", plan: "Two ways: hold on her (+1.6 s), or cut to the window and back.", twoWays: true, conflict: .init(withNoteID: "note-1", following: "note-2", range: "00:25\u{2013}00:46", detail: "Following 2 (Feeling) over 1 (Pace) there.")),
            .init(noteID: "note-3", plan: "Reframe to about 1.6\u{00D7} on Maya; sky down to a third.", delta: "crop"),
            .init(noteID: "note-4", plan: "Music down 6 dB under her line, back up at the cut.", delta: "\u{2212}6 dB"),
            .init(noteID: "note-5", plan: "Strike line 14.", delta: "\u{2212}3.1 s"),
            .init(noteID: "note-6", plan: "Drop the second whiteboard shot.", delta: "\u{2212}2.0 s"),
            .init(noteID: "note-7", plan: "Open scene 4 on the team. The best team shot is in Launch day, which is locked; I\u{2019}ll look for another.", cantYet: "Launch day is locked"),
        ]
    }
}
