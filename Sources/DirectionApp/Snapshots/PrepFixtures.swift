import SwiftUI
import DirectionCore

// Frames 70–76: the Script and Breakdown rooms (specs/script.md, specs/breakdown.md), on a narrated essay.
@MainActor
enum PrepFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "70-script-empty": { let m = film(room: .script, script: nil); m.onboardingDismissed = true; return .film(m) },
            "71-script-drafting": { drafting() },
            "72-script-notes": { notes() },
            "73-script-pass": { pass() },
            "74-breakdown-draft": { breakdownScene(draft(), shot: "2C") },
            "75-breakdown-ready": { breakdownScene(ready(), shot: "6B") },
            "76-breakdown-coverage": { breakdownScene(coverage(), shot: "2D") },
            "zz-boards": {
                SnapshotScene(size: CGSize(width: 1240, height: 200), HStack(spacing: 16) {
                    ForEach(BoardKind.allCases, id: \.self) { k in BoardView(kind: k, move: k == .detail ? .push : nil, label: k == .close ? "Close · still" : nil).frame(width: 96) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Gate.Surface.ground))
            },
        ]
    }

    static let essay = """
    # The Chat Box

    ## Cold open
    [Black. The question types on.]

    Open any app you used five years ago. It has a chat box now.

    I build these for a living. [me at the desk, dark]

    And lately I'm not sure we should.

    ## Everyone added one
    It started with the obvious ones. Writing apps. Code editors.

    Then the calendar got one.

    Then my thermostat.

    At some point it stopped being a feature and became a reflex.

    Nobody asked for it. Not once.

    So why does every team ship it?

    ## What actually happened
    [ON CAMERA]
    Here's what I think actually happened.

    A chat box is the cheapest way to look like you're keeping up.
    """

    /// The essay as Direction lays it out, with the editor's picture column written down to `upTo`.
    static func script(upTo written: Int = .max, pass: Int = 1) -> AVScript {
        let read = ScriptImport.read(essay, fileName: "The Chat Box.md")
        var s = AVScript()
        s.sections = read.sections
        s.rows = read.rows.enumerated().map { i, r in var r = r; r.id = "row-\(i + 1)"; return r }
        s.source = ScriptSource(fileName: "The Chat Box.md", path: nil, words: read.words, importedAt: SampleFilm.date(11, 2, 9, 41))
        let pictures: [(String, ShotSize?, ShotMove?, BoardKind)] = [
            ("Black. The question types on: \u{201C}Why does every app have a chat box now?\u{201D} Apps you know open their chat panels behind it.", nil, nil, .title),
            ("Scott at the desk from behind. Dark room, only the screen lit.", .wide, .still, .wide),
            ("The chat panel, close. The cursor blinks in an empty box.", .close, .still, .screen),
            ("A writing app. The chat panel slides in from the right.", nil, nil, .screen),
            ("A calendar with a chat box under the week.", nil, nil, .screen),
            ("A thermostat app asks, \u{201C}How can I help?\u{201D}", nil, nil, .screen),
            ("Scott, close, in profile, lit by the screen. He laughs once.", .close, .still, .close),
            ("", nil, nil, .empty),
            ("A whiteboard of crossed-out sketches.", .detail, .push, .detail),
            ("On camera at the desk, medium.", .medium, .still, .onCamera),
            ("On camera. He leans in.", .medium, .push, .onCamera),
        ]
        for (i, p) in pictures.enumerated() where i < s.rows.count && i < written && !p.0.isEmpty {
            s.rows[i].picture = AVPicture(text: p.0, size: p.1, move: p.2, board: p.3); s.rows[i].picture.pass = 1
        }
        s.pass = pass
        s.revision = 4
        return s
    }

    static func film(room: Room, script: AVScript?, breakdown: Breakdown? = nil) -> FilmModel {
        let m = FilmModel(preview: true)
        var p = Project(name: "The Chat Box"); p.id = "project-chatbox"
        m.project = p; m.displayed = p
        m.brief = Brief(); m.brief.style = "narrated-essay"; m.brief.logline = "Why every app has a chat box now, from someone who builds them."; m.brief.feeling = "Curious, a little tired of it, never smug."
        m.script = script
        m.breakdown = breakdown
        m.room = room
        return m
    }

    private static func working(_ m: FilmModel, _ job: EditorJob) {
        m.runs.previewStarts = true
        var r = EditorRun(id: "run-prep", job: job, state: .working, program: "claudeCode", version: "", createdAt: SampleFilm.date(11, 2, 9, 42))
        r.startedAt = r.createdAt
        m.runs.runs = [r]
    }

    // MARK: Script

    private static func drafting() -> SnapshotScene {
        let m = film(room: .script, script: script(upTo: 6))
        working(m, .script)
        return .film(m)
    }

    private static func notes() -> SnapshotScene {
        var s = script()
        s.notes = [
            PrepNote(id: "pn-1", number: 1, rowIDs: ["row-3"], kind: .picture, text: "This should be my hands, not the screen."),
            PrepNote(id: "pn-2", number: 2, rowIDs: ["row-4", "row-5", "row-6"], kind: .pace, text: "Three screens in a row is a lot. Break it up with something physical."),
        ]
        s.rows[7].question = PrepQuestion(id: "ask-1", text: "Row 8 has no picture. What should we see under \u{201C}Nobody asked for it\u{201D}?", choices: [
            .init(id: "make", label: "Make it", detail: "An empty chat box, the cursor blinking. A graphic, so it\u{2019}s free.", recommended: true),
            .init(id: "shoot", label: "I\u{2019}ll shoot something", detail: "Tell me what, and it goes in the breakdown."),
            .init(id: "lose", label: "Lose the line", detail: "Row 8 comes out of the script."),
        ])
        let m = film(room: .script, script: s)
        return SnapshotScene(FilmWindow(app: nil, model: m).environment(\.prepPreview, PrepPreview(selected: [7], editing: 7, editingText: "Scott, close, in profile, lit by the screen. He laughs once, under his breath.")))
    }

    private static func pass() -> SnapshotScene {
        var s = script(pass: 2)
        s.rows[2].picture = AVPicture(text: "Scott\u{2019}s hands on the keyboard, close. They type, stop, and lift off the keys.", size: .detail, move: .still, board: .detail); s.rows[2].picture.pass = 2
        s.rows[4].picture = AVPicture(text: "Scott sticks a note on the monitor. It says \u{201C}chat box?\u{201D}", size: .medium, move: .still, board: .action); s.rows[4].picture.pass = 2
        s.rows[6].picture.text = "Scott, close, in profile, lit by the screen. He laughs once, under his breath."; s.rows[6].picture.yours = true
        s.rows[7].picture = AVPicture(text: "An empty chat box over black. The cursor blinks; nothing is typed.", board: .made); s.rows[7].picture.pass = 2
        s.notes = [
            { var n = PrepNote(id: "pn-1", number: 1, rowIDs: ["row-3"], kind: .picture, text: "This should be my hands, not the screen.", state: .done); n.reply = "Row 3 is your hands now. That\u{2019}s a new shot for the breakdown."; return n }(),
            { var n = PrepNote(id: "pn-2", number: 2, rowIDs: ["row-4", "row-5", "row-6"], kind: .pace, text: "Three screens in a row is a lot. Break it up with something physical.", state: .done); n.reply = "I kept 4 and 6 as screens and put you at the monitor with a sticky note at 5."; return n }(),
        ]
        return SnapshotScene(FilmWindow(app: nil, model: film(room: .script, script: s)).environment(\.prepPreview, PrepPreview(selected: [3])))
    }

    // MARK: Breakdown

    static func breakdown(ok: Bool) -> Breakdown {
        var b = Breakdown()
        b.setups = [
            BreakdownSetup(id: "setup-1", number: 1, name: "Narration", needs: "The good mic, a quiet room"),
            BreakdownSetup(id: "setup-2", number: 2, name: "Desk at night", needs: "After dark \u{00B7} lamp off \u{00B7} the chat app open on the monitor"),
            BreakdownSetup(id: "setup-3", number: 3, name: "On camera", needs: "Day \u{00B7} key light \u{00B7} the good mic"),
            BreakdownSetup(id: "setup-4", number: 4, name: "Whiteboard", needs: "Sketches, half crossed out"),
            BreakdownSetup(id: "setup-5", number: 5, name: "Screen recordings", needs: "Record on this Mac", noCamera: true),
            BreakdownSetup(id: "setup-6", number: 6, name: "To make", needs: "The editor makes these", noCamera: true),
        ]
        func shot(_ code: String, _ setup: Int, _ rows: [Int], _ what: String, _ size: ShotSize?, _ move: ShotMove?, _ source: ShotSource, _ board: BoardKind?, _ seconds: Double) -> BreakdownShot {
            BreakdownShot(id: "shot-\(code)", code: code, setupID: "setup-\(setup)", rowIDs: rows.map { "row-\($0)" }, what: what, size: size, move: move, seconds: seconds, source: source, board: board)
        }
        b.shots = [
            shot("1A", 1, Array(1...9), "The whole narration, read through once for each section.", nil, nil, .sound, nil, 38),
            shot("2A", 2, [2], "Wide from behind. Dark room, only the screen lit.", .wide, .still, .shoot, .wide, 2),
            shot("2B", 2, [3], "Hands on the keyboard. They type, stop, and lift off the keys.", .detail, .still, .shoot, .detail, 3),
            shot("2C", 2, [5], "A sticky note that says \u{201C}chat box?\u{201D} goes on the monitor.", .medium, .still, .shoot, .action, 2),
            shot("2D", 2, [7], "Close, in profile, lit by the screen. He laughs once, under his breath.", .close, .still, .shoot, .close, 4),
            shot("3A", 3, [10, 11], "On camera at the desk, the whole second half.", .medium, .still, .shoot, .onCamera, 6),
            shot("4A", 4, [9], "A whiteboard of crossed-out sketches.", .detail, .push, .shoot, .detail, 3),
            shot("5A", 5, [1], "Apps you know, one after another, opening their chat panels.", nil, nil, .screen, .screen, 4),
            shot("5B", 5, [4], "A writing app. The chat panel slides in from the right.", nil, nil, .screen, .screen, 4),
            shot("5C", 5, [6], "A thermostat app asks, \u{201C}How can I help?\u{201D}", nil, nil, .screen, .screen, 2),
            shot("6A", 6, [8], "An empty chat box over black. The cursor blinks; nothing is typed.", nil, nil, .make, .made, 3),
            shot("6B", 6, [1], "The question types on over black.", nil, nil, .make, .title, 4),
        ]
        b.shots[10].makePlan = "A graphic Direction draws. Free."
        b.scriptRevision = 5
        b.pass = 1
        if ok { b.okAt = SampleFilm.date(11, 2, 10, 40) }
        return b
    }

    private static func passScript() -> AVScript {
        var s = script(pass: 2)
        s.rows[2].picture = AVPicture(text: "Scott\u{2019}s hands on the keyboard, close.", size: .detail, board: .detail)
        s.rows[4].picture = AVPicture(text: "Scott sticks a note on the monitor.", size: .medium, board: .action)
        s.rows[7].picture = AVPicture(text: "An empty chat box over black.", board: .made)
        s.okAt = SampleFilm.date(11, 2, 10, 12)
        s.revision = 5; s.okRevision = 5
        return s
    }

    private static func draft() -> FilmModel {
        let m = film(room: .breakdown, script: passScript(), breakdown: breakdown(ok: false))
        m.runs.previewStarts = true
        var r = EditorRun(id: "run-bd", job: .breakdown, state: .done, program: "claudeCode", version: "")
        r.summary = "12 shots in 6 setups. Desk at night is the biggest: shoot it first, after dark, then the whiteboard while the room is set."
        m.runs.runs = [r]
        return m
    }

    private static func ready() -> FilmModel {
        var s = passScript(); s.revision = 6
        var b = breakdown(ok: true)
        b.shots.append({ var x = BreakdownShot(id: "shot-6C", code: "6C", setupID: "setup-6", rowIDs: ["row-11"], what: "Chat bubbles rising over a city at night, slowly.", seconds: 4, source: .make, board: .made); x.estimate = 1.8; x.makePlan = "A still of the city at night, then motion: bubbles rising."; x.addedAfterOK = true; return x }())
        return film(room: .breakdown, script: s, breakdown: b)
    }

    private static func coverage() -> FilmModel {
        let m = film(room: .breakdown, script: passScript(), breakdown: breakdown(ok: true))
        var d = Dailies()
        d.scenes = (1...6).map { n in DailiesScene(id: "scene-setup-\(n)", number: n, title: m.breakdown!.setups[n - 1].name) }
        var assets: [MediaAsset] = []
        func take(_ code: String, _ n: Int, circled: Bool = false) {
            let id = "take-\(code)-\(n)"
            assets.append(MediaAsset(id: id, name: "\(code) T\(n).mov", path: "/footage/\(code) T\(n).mov", duration: .init(seconds: 12)))
            var t = TakeInfo(assetID: id); t.sceneID = "scene-setup-\(code.prefix(1))"; t.setupCode = code; t.code = "T\(n)"; t.circled = circled
            d.takes[id] = t
        }
        take("1A", 1); take("1A", 2); take("1A", 3, circled: true)
        take("2A", 1); take("2A", 2, circled: true); take("2A", 3)
        take("2B", 1); take("2B", 2); take("2B", 3); take("2B", 4, circled: true)
        take("2C", 1, circled: true)
        take("3A", 1, circled: true)
        take("5A", 1, circled: true); take("5B", 1, circled: true)
        m.dailies = d
        m.project?.assets = assets; m.displayed = m.project
        return m
    }

    private static func breakdownScene(_ m: FilmModel, shot: String) -> SnapshotScene {
        SnapshotScene(FilmWindow(app: nil, model: m).environment(\.prepPreview, PrepPreview(shot: shot)))
    }
}
