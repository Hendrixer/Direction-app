import SwiftUI
import DirectionCore

// Owner: Script and Screening agent (10–12). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum ScriptFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "10-script": { .film(film(notes: [])) },
            "11-script-marked": {
                let m = film(notes: [5, 8, 9])
                return SnapshotScene(FilmWindow(app: nil, model: m).environment(\.scriptPreview, ScriptPreview(selection: 10...11, editingNoteID: "note-8")))
            },
            "12-script-readings": {
                let m = film(notes: [5, 8, 9])
                return SnapshotScene(FilmWindow(app: nil, model: m).environment(\.scriptPreview, ScriptPreview(selection: 12...12, readingsLine: 12, playingTake: "take-2a-t3", playingProgress: 0.4, editingNoteID: "note-8")))
            },
        ]
    }

    /// Cut 3 in Script with transcripts for every take. Notes 1–4, 6 and 7 are turned over;
    /// `notes` adds the script notes from frame 11 (5 strike, 8 hold, 9 move).
    static func film(notes scriptNotes: [Int]) -> FilmModel {
        let m = SampleFilm.make(room: .script)
        m.project = project()
        m.displayed = m.project
        m.dailies.takes["take-vo-maya"] = {
            var t = TakeInfo(assetID: "take-vo-maya"); t.sceneID = "scene-1"; t.setupCode = "VO"; t.code = "T2"; t.caption = "Maya, voice-over."; t.circled = true; return t
        }()
        m.transcripts = transcripts
        var notes = SampleFilm.cut3Notes.filter { $0.number != 5 }
        for i in notes.indices { notes[i].noteState = .turnedOver; notes[i].turnoverID = "turnover-3" }
        let doc = ScriptDocument.build(project: m.project, sequence: m.sequence, transcripts: m.transcripts, dailies: m.dailies, cutScenes: m.stripScenes)
        func line(_ n: Int) -> ScriptLine { doc.line(number: n)! }
        func scriptNote(_ n: Int, _ text: String, _ kind: NoteKind, _ lines: [ScriptLine], _ action: ScriptAction) -> ReviewComment {
            SampleFilm.note(n, text, kind: kind, range: (lines[0].start, lines.last!.end), script: action, created: SampleFilm.date(10, 27, 16, 0))
        }
        if scriptNotes.contains(5) {
            notes.append(scriptNote(5, "Lose \(ScriptText.quoted(line(14).text))", .story, [line(14)], ScriptAction(gesture: .strike, lineText: line(14).text, lineLabel: "Line 14")))
        }
        if scriptNotes.contains(8) {
            notes.append(scriptNote(8, "Let this breathe.", .pace, [line(10), line(11)], ScriptAction(gesture: .hold, lineText: "\(line(10).text) \(line(11).text)", lineLabel: "Lines 10\u{2013}11")))
        }
        if scriptNotes.contains(9) {
            notes.append(scriptNote(9, "Move \(ScriptText.quoted(line(16).text)) after \(ScriptText.quoted(line(12).text))", .story, [line(16)],
                                    ScriptAction(gesture: .move, lineText: line(16).text, lineLabel: "Line 16 \u{2192} after 12", afterText: line(12).text)))
        }
        m.notes = notes
        m.position = line(12).start
        return m
    }

    // MARK: Sample footage

    /// Cut 3 with a voice-over under the cold open, and source ranges that keep each
    /// take's dialogue where the cut uses it.
    static func project() -> Project {
        var p = SampleFilm.project(clips: SampleFilm.cut3Clips, revision: 12)
        p.assets.append(MediaAsset(id: "take-vo-maya", name: "VO_Maya_T2.wav", path: "/Volumes/Shoot SSD/VO_Maya_T2.wav", duration: .init(seconds: 40), audio: [.init(id: 2, index: 0, label: "VO", channels: 1, sampleRate: 48_000)]))
        // The cutaway on 2B T2 uses its first seconds; her off-camera lines come later in the take.
        if let i = p.assets.firstIndex(where: { $0.id == "take-2b-t2" }) { p.assets[i].duration = .init(seconds: 40) }
        p.sequences[0].clips.append(Clip(id: "clip-vo-maya", assetID: "take-vo-maya", name: "VO_Maya_T2", kind: .audio, layer: 0, start: .init(seconds: 3), sourceRange: .init(start: 13.4, end: 26.6)))
        return p
    }

    enum Say {
        case speaker(String)
        case line(String, Double? = nil)
        case action(String)
        case aside(String)
        case slug(String)
        case at(Double)
    }

    /// Timed words for one take. Labels and bracketed phrases follow ScriptDocument's conventions.
    static func take(_ asset: String, pace: Double, gap: Double = 0.42, _ items: [Say]) -> SourceTranscript {
        var words: [TranscriptWord] = []
        var t = 0.0, lastEnd = 0.0
        func add(_ tokens: [String], each: Double) {
            for token in tokens {
                words.append(TranscriptWord(id: "\(asset)-w\(words.count)", text: token, range: MediaRange(start: t, end: t + each * 0.92)))
                lastEnd = t + each * 0.92; t += each
            }
        }
        func bracketed(_ text: String) -> [String] {
            var tokens = text.split(separator: " ").map(String.init)
            tokens[0] = "[" + tokens[0]; tokens[tokens.count - 1] += "]"
            return tokens
        }
        for item in items {
            switch item {
            case .at(let s): t = s
            case .slug(let text): add(bracketed(text), each: 0.05); t += gap
            case .speaker(let name):
                var tokens = name.split(separator: " ").map(String.init); tokens[tokens.count - 1] += ":"
                add(tokens, each: 0.02); t += 0.03
            case .line(let text, let duration):
                let tokens = text.split(separator: " ").map(String.init)
                add(tokens, each: (duration ?? pace * Double(tokens.count)) / Double(tokens.count)); t += gap
            case .action(let text): add(bracketed(text), each: 0.12); t += gap
            case .aside(let text): t = lastEnd + 0.02; add(bracketed(text), each: 0.12); t += gap
            }
        }
        return SourceTranscript(assetID: asset, audioTrackID: 2, provider: "imported", words: words)
    }

    static let ten = "Every film I ever loved was made twice."
    static var transcripts: [SourceTranscript] {
        let open: [Say] = [.speaker("MAYA"), .line("So we started with the edit."), .line("Everyone said, start with the camera."), .line("But the camera was never the hard part."),
                           .line("The hard part was the two weeks after."), .line("Sitting with eight hours of yourself.")]
        let close: [Say] = [.line("And that\u{2019}s when everything changed."), .speaker("INTERVIEWER"), .line("Why build that part?"), .speaker("MAYA"), .line("Because somebody has to.")]
        return [
            take("take-1a-t5", pace: 0.5, [.slug("EXT. STREET, NIGHT")]),
            take("take-vo-maya", pace: 0.5, [.at(0.5), .speaker("MAYA"), .line("I didn\u{2019}t set out to build a tool."), .line("I set out to make a film."), .line("Then I tried to finish it."),
                                              .at(13.5), .line(ten), .line("Once when you shoot it,"), .line("and once in a dark room, when you find it.")]),
            take("take-2a-t2", pace: 0.4, [.slug("INT. MAYA\u{2019}S OFFICE, DAY"), .at(2.1)] + open + [.line("Editing was the part nobody wanted.", 2.4), .action("She looks to the window.")] + close),
            take("take-2a-t1", pace: 0.36, [.at(1.0)] + open + [.line("Editing was the part no one wanted.", 2.1)]),
            take("take-2a-t3", pace: 0.42, [.at(1.4)] + open + [.line("Editing was the part nobody wanted.", 2.9), .action("She looks to the window.")] + close),
            take("take-2a-t4", pace: 0.22, gap: 0.36, [.at(0.3)] + open + [.line("Editing was the part\u{2014}", 1.2), .aside("Breaks off, laughs."), .action("She looks to the window.")]),
            take("take-2b-t1", pace: 0.38, [.at(3.0), .speaker("MAYA (O.S.)"), .line("But the camera was never the hard part."), .line("The hard part was the two weeks after."), .line("Sitting with eight hours of yourself.")]),
            take("take-2b-t2", pace: 0.38, [.at(22.0), .speaker("MAYA (O.S.)"), .line("But the camera was never the hard part."), .line("The hard part was the two weeks after."),
                                            .line("Sitting with eight hours of yourself."), .line("Editing was the part nobody wanted.", 2.3)]),
            take("take-2b-t3", pace: 0.38, [.at(4.0), .speaker("MAYA (O.S.)"), .line("And that\u{2019}s when everything changed.")]),
            take("take-3a-t2", pace: 0.584, [.slug("EXT. THE RIDGE, DUSK"), .at(3.0), .action("Wind. Maya walks to the edge and stops."), .at(9.0), .speaker("MAYA"),
                                            .line("I came up here the night I almost quit."), .line("It was the only place quiet enough to think."), .at(24.0), .action("She sits. The light goes.")]),
            take("take-3a-t3", pace: 0.6, [.at(2.5), .action("Wind. Maya walks to the edge and stops."), .at(8.0), .speaker("MAYA"), .line("I came up here the night I almost quit."), .line("It was the only place quiet enough to think.")]),
            take("take-3b-t1", pace: 0.55, [.at(4.0), .speaker("MAYA"), .line("I came up here the night I almost quit.")]),
            take("take-4a-t1", pace: 0.584, [.slug("INT. MAYA\u{2019}S OFFICE, NIGHT"), .at(2.6), .speaker("MAYA (O.S.)"), .line("The first version took four months."), .line("Nobody used it."),
                                            .line("The second version took six."), .line("Two people used it."), .line("One of them was my mom."), .at(24.0), .action("Typing. A long breath.")]),
            take("take-4b-t1", pace: 0.584, [.at(2.6), .speaker("MAYA"), .line("So I stopped building features."), .line("I started watching editors work."), .line("Every one of them did the same thing."),
                                            .line("They watched, they stopped, they wrote it down."), .line("Notes."), .line("So that\u{2019}s what we built.")]),
            take("take-5a-t3", pace: 0.584, [.slug("INT. OFFICE, LAUNCH DAY"), .at(3.0), .speaker("SAM"), .line("Is it live?"), .speaker("MAYA"), .line("It\u{2019}s live."),
                                            .at(9.0), .action("The team cheers. Maya doesn\u{2019}t."), .at(14.0), .speaker("MAYA"), .line("Okay."), .line("Back to work.")]),
            take("take-5b-t1", pace: 0.5, [.at(5.0), .action("Evening. The office is empty. Her chair is still turning.")]),
        ]
    }
}
