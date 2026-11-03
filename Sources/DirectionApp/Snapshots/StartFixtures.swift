import SwiftUI
import DirectionCore

// Owner: Start agent (01–06). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum StartFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "01-films-empty": {
                let app = AppModel(); app.previewFilms = []
                return SnapshotScene(FilmsView(app: app))
            },
            "zz-chrome-mark": {
                let at = [0.0, 1.9, 2.5, 2.8, 3.2, 4.4]
                return SnapshotScene(size: CGSize(width: 1260, height: 240), HStack(spacing: 20) { ForEach(at, id: \.self) { ChromeMark(size: 190, at: $0) } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black))
            },
            "zz-chrome-mark-close": {
                SnapshotScene(size: CGSize(width: 1040, height: 520), HStack(spacing: 0) { ChromeMark(size: 500, at: 0); ChromeMark(size: 500, at: 2.8) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black))
            },
            "02-films": {
                let app = AppModel(); app.previewFilms = films
                return SnapshotScene(FilmsView(app: app))
            },
            // Films with nothing to show yet: each mark lit from its own direction, beside one with footage.
            "02-films-no-picture": {
                let app = AppModel()
                app.previewFilms = [films[0]] + [("The last human discovery, ever", "Script \u{00B7} 279 rows"), ("Coded love", "New film \u{00B7} Write the brief"), ("Night walk", "Brief \u{00B7} No footage yet")].map { name, status in
                    FilmSummary(id: name, name: name, path: "/Users/you/Movies/Direction/\(name).direction", duration: nil, status: status + " \u{00B7} Today 19:21")
                }
                return SnapshotScene(FilmsView(app: app))
            },
            "03-brief": {
                let m = newFilm()
                m.brief = Brief()
                let session = OnboardingSession.of(m)
                session.title = "Launch film"; session.brief = SampleFilm.briefValue
                return .film(m)
            },
            "04-footage-drop": {
                let m = newFilm()
                m.project?.assets = []; m.dailies = Dailies(); m.displayed = m.project
                return .film(m)
            },
            "05-footage-logging": { DailiesFixtures.scene(logging(), DailiesPreview(art: DailiesFixtures.art)) },
            "06-assembling": { DailiesFixtures.scene(assembling(), DailiesPreview(art: DailiesFixtures.art)) },
            "06-assembly-question": { DailiesFixtures.scene(assemblyQuestion(), DailiesPreview(art: DailiesFixtures.art)) },
            "06-assembly-ready": { DailiesFixtures.scene(assemblyReady(), DailiesPreview(art: DailiesFixtures.art)) },
        ]
    }

    /// The four films of frame 02.
    static var films: [FilmSummary] {
        [
            FilmSummary(id: "launch", name: "Launch film", path: "/Users/you/Movies/Direction/Launch film.direction", duration: "3:40", status: "Cut 3 \u{00B7} You're giving notes \u{00B7} Today 14:20", waiting: "2 notes waiting", art: .dusk),
            FilmSummary(id: "night", name: "Night shift", path: "/Users/you/Movies/Direction/Night shift.direction", duration: "5:12", status: "Editor is cutting Cut 2 \u{00B7} 4 of 9 notes", editorBusy: true, art: .night),
            FilmSummary(id: "field", name: "Field notes", path: "/Users/you/Movies/Direction/Field notes.direction", duration: "2:58", status: "Cut 6 \u{00B7} Finishing \u{00B7} 3 of 5 done \u{00B7} Oct 12", locked: true, art: .day),
            FilmSummary(id: "ridge", name: "Ridge test", path: "/Users/you/Movies/Direction/Ridge test.direction", duration: "48 takes", status: "Dailies \u{00B7} 3 circled \u{00B7} No cuts yet \u{00B7} Oct 9", art: .hands),
        ]
    }

    /// Launch film before anything is cut: brief written, footage as the step needs.
    static func newFilm() -> FilmModel {
        let m = SampleFilm.make(room: .dailies)
        m.cuts = []; m.notes = []
        m.project?.sequences[0].clips = []; m.displayed = m.project
        return m
    }

    /// Frame 05: 131 of 214 takes logged, 96 transcribed, five scenes so far, two files that need you.
    static func logging() -> FilmModel {
        let m = DailiesFixtures.film()
        m.onboardingDismissed = false
        var p = m.project!, d = m.dailies
        for i in d.scenes.indices { d.scenes[i].locked = false }
        if let i = d.scenes.firstIndex(where: { $0.number == 5 }) { d.scenes[i].title = "Launch day?" }
        // Two files that need you: one with no sound, one the editor couldn't read.
        if let i = p.assets.firstIndex(where: { $0.id == "take-4b-t1" }) { p.assets[i].audio = [] }
        d.takes["take-4b-t1"]?.flags = ["No audio"]
        let removed = p.assets.removeLast()
        p.assets[p.assets.count - 1].duration = .init(seconds: p.assets[p.assets.count - 1].duration.seconds + removed.duration.seconds)
        p.assets.insert(MediaAsset(id: "clip-r3d", name: "CLIP0031.R3D", path: "/Volumes/Shoot SSD/CLIP0031.R3D", duration: .zero), at: 17)
        d.takes["clip-r3d"] = { var t = TakeInfo(assetID: "clip-r3d"); t.flags = ["Unreadable"]; return t }()
        // Still to log: Launch day, the unsorted clips and the last of the coverage.
        let pending = p.assets.filter { a in d.takes[a.id]?.sceneID == "scene-5" || a.id.hasPrefix("unsorted-") }.map(\.id)
        var unlogged = Set(pending)
        for a in p.assets.reversed() where unlogged.count < 214 - 131 && a.id.hasPrefix("take-filler") { unlogged.insert(a.id) }
        for id in unlogged { d.takes[id] = nil }
        d.takes = d.takes.filter { id, _ in p.assets.contains { $0.id == id } }
        // 96 transcribed; 2A T3 is being transcribed now.
        var transcripts = DailiesFixtures.transcripts.filter { $0.assetID != "take-2a-t3" }
        for a in p.assets where transcripts.count < 96 && d.takes[a.id] != nil && a.id.hasPrefix("take-filler") {
            transcripts.append(DailiesFixtures.transcript(a.id, [(0, "(room tone)")]))
        }
        for id in ["take-1a-t5", "take-3a-t2"] { d.takes[id]?.flags = [id == "take-1a-t5" ? "Traffic" : "Wind"] }
        let now = Date().timeIntervalSince1970
        m.project = p; m.displayed = p; m.dailies = d; m.transcripts = transcripts
        m.jobs = [JobRecord(id: "job-transcribe", kind: "transcription", revision: 0, ownerPID: 1, status: "running", phase: "Transcribing", progress: 0.7, result: nil, error: nil, createdAt: now - 20, updatedAt: now)]
        m.editorStatus = decode(["phase": "Logging", "detail": "Five scenes so far, from the dialogue and the light. Rename or merge them in Dailies.", "progress": 0.61, "updatedAt": now])
        m.events = [decode(["id": 1, "kind": "dailies.updated", "revision": 0, "summary": "The editor logged footage", "createdAt": now - 570])].compactMap { $0 }
        return m
    }

    /// Store records without public initializers, as the store would decode them.
    static func decode<T: Decodable>(_ fields: [String: Any]) -> T? {
        (try? JSONSerialization.data(withJSONObject: fields)).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Frame 06: the editor on scene 3 of 5, two scenes cut, its log so far.
    static func assembling() -> FilmModel {
        let m = DailiesFixtures.film()
        m.onboardingDismissed = false
        var p = m.project!
        p.sequences[0].clips = [("take-1a-t5", 0.0, 20.0), ("take-1b-t2", 20, 34), ("take-2a-t2", 34, 70), ("take-2b-t2", 70, 86)].map { id, start, end in
            Clip(id: "clip-\(id)", assetID: id, name: id, start: .init(seconds: start), sourceRange: .init(start: 2, end: 2 + end - start))
        }
        m.project = p; m.displayed = p
        let now = Date().timeIntervalSince1970
        var t = Turnover(id: "turnover-1", number: 1, kind: "assembly", noteIDs: [], baseRevision: 0, baseCutID: nil, sequenceID: "sequence-main", latitude: .faithful, waitForOK: false, state: .cutting, createdAt: now - 195, updatedAt: now)
        t.phase = "Assembling 3 of 5"; t.percent = 0.52
        t.message = [
            "Read the brief. Holding on faces, letting quiet moments run.",
            "Cold open: started on the street, on her face by 0:21. Kept it under 35 seconds.",
            "Scene 2: used your circled T2 for \u{201C}Editing was the part nobody wanted.\u{201D} It\u{2019}s a must-keep.",
            "The ridge: you circled two takes of 3A. Trying both against the music.",
        ].joined(separator: "\n")
        m.turnovers = [t]
        return m
    }

    /// Frame 06, a question: the editor needs your call on the ridge, above the scene it's about.
    static func assemblyQuestion() -> FilmModel {
        let m = assembling()
        m.selectedSceneID = "scene-3"
        m.dailies.takes["take-3a-t2"]?.circled = true; m.dailies.takes["take-3a-t3"]?.circled = true
        m.questions = [EditorQuestion(id: "question-ridge", turnoverID: "turnover-1", kind: "question", noteIDs: [],
                                      text: "You circled two takes of 3A on the ridge. T2 holds the wide longer; T3 lands the line. Which one leads?", detail: nil,
                                      choices: [
                                          .init(id: "t2", label: "Lead with T2", detail: "3A \u{00B7} the wide holds 4 s longer", assetID: "take-3a-t2"),
                                          .init(id: "t3", label: "Lead with T3", detail: "3A \u{00B7} the line lands on her face", assetID: "take-3a-t3"),
                                      ],
                                      allowsText: true, answer: nil, createdAt: Date().timeIntervalSince1970 - 40)]
        return m
    }

    /// Frame 06, done: the assembly is a cut; every room's button screens it, and the toast says so.
    static func assemblyReady() -> FilmModel {
        let m = assembling()
        var p = m.project!
        p.sequences[0].clips += [("take-3a-t1", 86.0, 131.0), ("take-4a-t3", 131, 197), ("take-5a-t1", 197, 241)].map { id, start, end in
            Clip(id: "clip-\(id)", assetID: id, name: id, start: .init(seconds: start), sourceRange: .init(start: 2, end: 2 + end - start))
        }
        m.project = p; m.displayed = p
        var t = m.turnovers[0]
        t.state = .delivered; t.phase = "Assembly is ready"; t.percent = 1; t.resultCutID = "cut-assembly"
        t.message = (t.message ?? "") + "\nScene 5: kept the last look long. Done."
        m.turnovers = [t]
        m.cuts = [ReviewCut(id: "cut-assembly", name: "Assembly", editRevision: p.editRevision, sequenceID: "sequence-main", createdAt: Date().timeIntervalSince1970)]
        m.previewAssemblyReady = true
        m.toast = Toast(title: "The assembly is ready. 4:01.", detail: "Nobody else sees it until you\u{2019}ve screened it. Watch it once all the way through.", editor: true, actionTitle: "Screen it")
        return m
    }
}
