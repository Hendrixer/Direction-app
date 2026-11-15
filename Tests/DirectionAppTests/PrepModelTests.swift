import Testing
import Foundation
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// The prep rooms' one button, their place in the room order, and the editor's job text for them
/// (specs/script.md, specs/breakdown.md).
@MainActor
struct PrepModelTests {
    @Test func theRoomsRunInTheOrderAFilmIsMade() {
        #expect(Room.allCases == [.script, .breakdown, .dailies, .cut, .finish])
        #expect(Room.script.shortcut == "1" && Room.dailies.shortcut == "3")
        let m = PrepFixtures.film(room: .script, script: PrepFixtures.script())
        // A film that starts from a script works in its rooms from the start.
        #expect(m.onboardingStep == nil)
        #expect(!m.isEnabled(.breakdown))
        m.script?.okAt = 1
        #expect(m.isEnabled(.breakdown))
        // A film from a script opens where its work is: the script, then the breakdown until footage is in.
        m.script?.okAt = nil
        #expect(m.defaultRoom == .script)
        m.script?.okAt = 1
        #expect(m.defaultRoom == .breakdown)
    }

    @Test func scriptsOneButtonFollowsWhereItIs() {
        let empty = PrepFixtures.film(room: .script, script: nil)
        // A film without footage starts with Bring footage; one that's past it can still start a script.
        #expect(empty.onboardingStep == .footage)
        empty.onboardingDismissed = true
        #expect(empty.primaryAction?.title == "Bring in a script\u{2026}")
        var s = PrepFixtures.script()
        let m = PrepFixtures.film(room: .script, script: s)
        // Row 8 has no picture yet.
        #expect(m.primaryAction?.title == "OK script" && m.primaryAction?.enabled == false)
        s.rows[7].picture = AVPicture(text: "An empty chat box.", board: .made)
        m.script = s
        #expect(m.primaryAction?.enabled == true)
        s.notes = [PrepNote(number: 1, rowIDs: [s.rows[0].id], text: "Faster.")]
        m.script = s
        #expect(m.primaryAction?.title == "Turn over" && m.primaryAction?.count == "1")
        s.notes[0].state = .done; s.okAt = 1
        m.script = s
        #expect(m.primaryAction?.title == "Open Breakdown")
    }

    @Test func breakdownsOneButtonGoesFromOKToFootageToTheAssembly() {
        let m = PrepFixtures.film(room: .breakdown, script: PrepFixtures.script(), breakdown: PrepFixtures.breakdown(ok: false))
        #expect(m.primaryAction?.title == "OK breakdown" && m.primaryAction?.enabled == true)
        m.breakdown = PrepFixtures.breakdown(ok: true)
        #expect(m.primaryAction?.title == "Bring footage")
        var t = TakeInfo(assetID: "take-1"); t.setupCode = "2A"; t.code = "T1"
        m.dailies.takes["take-1"] = t
        // Nothing circled: the editor picks each shot's take. A circle makes the assembly the director's.
        #expect(m.primaryAction?.title == "Assemble" && m.primaryAction?.enabled == !m.isLogging)
        m.dailies.takes["take-1"]?.circled = true
        #expect(m.primaryAction?.title == "Assemble from circles" && m.primaryAction?.enabled == true)
    }

    @Test func theShootListGoesSetupBySetupWithWhatsIn() {
        let m = PrepFixtures.film(room: .breakdown, script: PrepFixtures.script(), breakdown: PrepFixtures.breakdown(ok: true))
        var t = TakeInfo(assetID: "take-1"); t.setupCode = "2A"; t.code = "T1"
        m.dailies.takes["take-1"] = t
        let list = m.shootList
        #expect(list.contains("2  DESK AT NIGHT  \u{2014}  After dark"))
        #expect(list.contains("\u{2713} 2A  Wide from behind.") && list.contains("\u{2610} 2B  Hands on the keyboard."))
        // Made shots and footage you have aren't shot.
        #expect(!list.contains("6A") && !list.contains("TO MAKE"))
    }

    @Test func theEditorsPrepJobsSayWhatThisPassIs() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-job-" + UUID().uuidString + ".direction")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try ProjectStore.create(at: path, name: "The Chat Box")
        let s = try store.importScript(PrepFixtures.essay, fileName: "The Chat Box.md")
        var v = try EditorJobs.prepValues(.script, store: store)
        #expect(v["task"]?.contains("The director brought in \u{201C}The Chat Box.md\u{201D}") == true && v["notes"] == "None this pass.")
        _ = try store.addScriptNote(rowIDs: [s.rows[2].id, s.rows[3].id, s.rows[4].id], kind: .pace, text: "Too many screens.")
        _ = try store.turnOverScriptNotes()
        v = try EditorJobs.prepValues(.script, store: store)
        #expect(v["notes"]?.contains("Note 1") == true && v["notes"]?.contains("Rows 3\u{2013}5") == true && v["task"]?.contains("turned over 1 note") == true)
        for job in ["script", "breakdown"] {
            let t = EditorJobs.template(job)
            #expect(t?.contains("{{task}}") == true && t?.contains("{{notes}}") == true && t?.contains("{{skill}}") == true, "\(job)")
        }
        _ = try store.okScript()
        v = try EditorJobs.prepValues(.breakdown, store: store)
        #expect(v["task"]?.contains("Break it down into shots, grouped by setup") == true)
        #expect(EditorJobs.rowList([1, 2, 3, 7, 9]) == "1\u{2013}3, 7 and 9")
    }

    /// A film from a story: the job says both columns are the editor's, and it isn't finished until every
    /// beat has a picture and a sound.
    /// A cut built on V2 with V1 left empty, titles above, still has its scenes on the strip.
    @Test func aCutBuiltOnV2StillShowsItsScenes() {
        let m = FilmModel(preview: true)
        var p = Project(name: "Coded love")
        let take = MediaAsset(name: "Take 1.mov", path: "/tmp/direction-v2/Take 1.mov", duration: MediaTime(seconds: 30))
        p.assets = [take]
        p.sequences[0].clips = [
            Clip(assetID: take.id, name: take.name, layer: 1, start: .zero, sourceRange: MediaRange(start: 0, end: 8)),
            Clip(assetID: take.id, name: take.name, layer: 1, start: MediaTime(seconds: 8), sourceRange: MediaRange(start: 12, end: 18)),
            Clip(assetID: "asset-captions", name: "captions-1", layer: 2, start: .zero, sourceRange: MediaRange(start: 0, end: 4)),
        ]
        m.project = p; m.displayed = p
        #expect(p.sequences[0].storyLayer == 1)
        #expect(m.stripScenes.map(\.start) == [0, 8])
        // With picture on V1, V1 is the story, whatever is above it.
        p.sequences[0].clips.append(Clip(assetID: take.id, name: take.name, layer: 0, start: MediaTime(seconds: 14), sourceRange: MediaRange(start: 20, end: 22)))
        #expect(p.sequences[0].storyLayer == 0)
    }

    /// A title alone on V3 before the story starts, and black at the end, still have their place on the strip:
    /// it runs from 0 to the end, so every moment can be reached.
    @Test func theStripCoversTheWholeCut() {
        let m = FilmModel(preview: true)
        var p = Project(name: "Coded love")
        let take = MediaAsset(name: "Take 1.mov", path: "/tmp/direction-v2/Take 1.mov", duration: MediaTime(seconds: 30))
        p.assets = [take]
        p.sequences[0].clips = [
            Clip(assetID: "asset-title", name: "coded-love-title", layer: 2, start: .zero, sourceRange: MediaRange(start: 0, end: 4.3)),
            Clip(assetID: take.id, name: take.name, layer: 1, start: MediaTime(seconds: 4.3), sourceRange: MediaRange(start: 0, end: 6)),
            Clip(assetID: take.id, name: take.name, layer: 1, start: MediaTime(seconds: 10.3), sourceRange: MediaRange(start: 12, end: 15)),
            Clip(assetID: "asset-end", name: "end-card", layer: 2, start: MediaTime(seconds: 13.3), sourceRange: MediaRange(start: 0, end: 2)),
        ]
        m.project = p; m.displayed = p
        let strip = m.stripScenes
        #expect(strip.first?.start == 0 && strip.first?.passage == true && strip.first?.label == "")
        #expect(abs((strip.last?.end ?? 0) - 15.3) < 0.001 && strip.last?.passage == true)
        #expect(strip.filter { !$0.passage }.count == 2)
        // Each place on the strip follows the last: nothing is left out, nothing overlaps.
        #expect(zip(strip, strip.dropFirst()).allSatisfy { abs($0.end - $1.start) < 0.001 })
        // Scene lookups never land on a passage as a scene: locking sees only scenes.
        #expect(LockBar.lockable(strip, scenes: m.sceneIDs).scenes.allSatisfy { !$0.passage })
    }

    /// A film started from its footage keeps Script, to bring in a script or a story; Breakdown comes with one.
    @Test func roomsFollowTheFilm() {
        let m = FilmModel(preview: true)
        #expect(m.isShown(.script) && m.isShown(.breakdown))
        var p = Project(name: "Short"); p.assets = [MediaAsset(name: "Take 1.mov", path: "/tmp/direction-short/Take 1.mov", duration: MediaTime(seconds: 30))]
        m.project = p; m.displayed = p
        #expect(m.isShown(.script) && m.isEnabled(.script) && !m.isShown(.breakdown))
        #expect(m.isShown(.dailies) && m.isShown(.cut) && m.isShown(.finish))
        m.script = PrepFixtures.script()
        #expect(m.isShown(.script) && m.isEnabled(.script) && m.isShown(.breakdown))
    }

    /// A film started from its footage that brings in a story: the script job writes pictures from the takes it has,
    /// and the breakdown marks those as footage the director has. A film with no footage hears nothing of it.
    @Test func aScriptAfterFootageWritesFromTheTakes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("footage-first-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir, name: "Bodies")
        _ = try store.importScript("Why we look inside.\n\nThe heart, up close.", fileName: "story.md", as: .story)
        let before = try EditorJobs.text(for: EditorRun(job: .script, program: "claudeCode", version: "", turnoverID: nil), store: store)
        #expect(!before.contains("already has its footage") && !before.contains("{{"))
        let take = MediaAsset(name: "Take 3.mov", path: "/tmp/direction-footage-first/Take 3.mov", duration: MediaTime(seconds: 12))
        _ = try store.addAsset(take, append: false, expectedRevision: store.read().editRevision)
        let script = try EditorJobs.text(for: EditorRun(job: .script, program: "claudeCode", version: "", turnoverID: nil), store: store)
        #expect(script.contains("The film already has its footage: 1 take") && script.contains("direction.dailies") && !script.contains("{{"))
        let breakdown = try EditorJobs.text(for: EditorRun(job: .breakdown, program: "claudeCode", version: "", turnoverID: nil), store: store)
        #expect(breakdown.contains("source `have`") && !breakdown.contains("{{"))
        #expect(ToolCatalog.names(for: .script).isSuperset(of: ["direction_dailies", "direction_search_footage"]))
        // Footage shot from an OK'd breakdown is that plan's: a later script pass isn't told to start from it.
        let row = try #require(try store.script()?.rows.first?.id)
        _ = try store.updateBreakdown(setups: [try JSONDecoder().decode(SetupInput.self, from: Data(#"{"name":"Desk"}"#.utf8))],
                                      shots: [try JSONDecoder().decode(ShotInput.self, from: Data(#"{"setup":"Desk","rowIDs":["\#(row)"],"what":"The heart.","source":"shoot"}"#.utf8))])
        _ = try store.okBreakdown()
        let later = try EditorJobs.text(for: EditorRun(job: .script, program: "claudeCode", version: "", turnoverID: nil), store: store)
        #expect(!later.contains("already has its footage") && !later.contains("{{"))
    }

    /// A voice-over: its job carries the ask, the cut and the word budget on the quicker version; it's finished once
    /// lines are written; the Script room copies it for recording, and there's no Breakdown for it.
    @Test func aVoiceOverIsWrittenToTheCut() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-over-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir, name: "Bodies")
        _ = try store.startVoiceOver(VoiceOverAsk(ask: "Why the bodies look this way.\nCurious, a little funny.", cutID: "cut-10", cutName: "Cut 10", cutRevision: 47, cutSeconds: 40))
        let run = EditorRun(job: .voiceOver, program: "claudeCode", version: "", turnoverID: nil)
        let text = try EditorJobs.text(for: run, store: store)
        #expect(text.contains("> Why the bodies look this way.\n> Curious, a little funny.") && text.contains("written to Cut 10, 0:40 long") && text.contains("`revision: 47`") && text.contains("about 80 words") && !text.contains("{{"))
        // Its first read is that cut's outline, not the edit as it is now.
        #expect(EditorOpening.reads(.voiceOver, hasScript: true, hasStyle: false, voiceOverCut: 47).contains { $0.name == "direction_timeline" && $0.arguments["revision"].int == 47 })
        #expect(text.contains("`write-voice-over`"))
        #expect(!EditorRunner.finished(run, store: store))
        _ = try store.updateScript(lines: [VoiceLineInput(at: 0, picture: "The full body.", text: "This was a person once.")])
        #expect(EditorRunner.finished(run, store: store))
        #expect(EditorPicks.listed(.claudeCode, .voiceOver, .balanced).version == "claude-sonnet-5-5" && EditorPicks.listed(.claudeCode, .voiceOver, .best).version == "claude-opus-5-5")
        #expect(ToolCatalog.names(for: .voiceOver).isSuperset(of: ["direction_timeline", "direction_frame", "direction_watch", "direction_transcript", "direction_script_update"]))

        let m = PrepFixtures.film(room: .script, script: try store.script())
        #expect(!m.isShown(.breakdown) && m.scriptPrimary?.title == "Copy for Recording" && m.scriptPrimary?.enabled == true)
        #expect(m.script?.forRecording == "Voice-over for Cut 10\n\n0:00  This was a person once.")
    }

    /// Every answer the director gave on the script or the breakdown goes to every job after as settled.
    @Test func answeredQuestionsAreAlreadyDecided() {
        var s = PrepFixtures.script()
        var q = PrepQuestion(id: "ask-name", text: "Is \u{201C}Notes\u{201D} the film\u{2019}s name?", choices: [.init(id: "yes", label: "Yes, kept off screen"), .init(id: "later", label: "Later")])
        s.rows[0].question = q
        // Still open: nothing is decided yet.
        #expect(EditorJobs.decisions(script: s, breakdown: nil).isEmpty)
        q.answer = "yes"; q.answeredAt = 1; s.rows[0].question = q
        var b = Breakdown()
        var shot = BreakdownShot(id: "shot-2C", code: "2C", setupID: "setup-2", rowIDs: [s.rows[1].id], what: "A sticky note.", seconds: 2, source: .shoot)
        var asked = PrepQuestion(id: "ask-note", text: "Handwriting or printed?", choices: [.init(id: "hand", label: "My handwriting")])
        asked.answerText = "Mine, in pencil"; asked.answeredAt = 2; shot.question = asked
        b.shots = [shot]
        #expect(EditorJobs.decisions(script: s, breakdown: b) == [
            "Row 1, \u{201C}Is \u{201C}Notes\u{201D} the film\u{2019}s name?\u{201D}: Yes, kept off screen",
            "Shot 2C, \u{201C}Handwriting or printed?\u{201D}: Mine, in pencil",
        ])
    }

    /// Writer's notes open as headings and what's under them, bullets as bullets, markdown marks gone.
    @Test func theWritersNotesReadAsTheyWereWritten() {
        let blocks = WritersNotes.blocks("## The idea\n\nA walk home.\n\n## Questions\n* **Which** bridge?\n- Do we hear `him`?")
        #expect(blocks.map(\.heading) == [true, false, true, false])
        #expect(blocks.map(\.text) == ["The idea", "A walk home.", "Questions", "\u{2022} Which bridge?\n\u{2022} Do we hear him?"])
    }

    @Test func theEditorIsToldHowToLayOutAStory() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-story-job-" + UUID().uuidString + ".direction")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try ProjectStore.create(at: path, name: "Night walk")
        let s = try store.importScript(PrepFixtures.story, fileName: "Night walk.md", as: .story)
        let v = try EditorJobs.prepValues(.script, store: store)
        #expect(v["task"]?.contains("brought in a story") == true && v["task"]?.contains("\(s.rows.count) beats") == true)
        #expect(v["columns"]?.contains("nobody\u{2019}s words are written") == true && v["story"]?.contains("ownWords: true") == true && v["done"] == "a picture and a sound")
        let job = EditorJobs.fill(EditorJobs.template("script") ?? "", v)
        let mine = ["{{columns}}", "{{write}}", "{{whole}}", "{{theirs}}", "{{story}}", "{{done}}"]
        #expect(!mine.contains(where: job.contains) && job.contains("pictures and sounds"))
        let essayPath = FileManager.default.temporaryDirectory.appendingPathComponent("direction-prep-script-job-" + UUID().uuidString + ".direction")
        defer { try? FileManager.default.removeItem(at: essayPath) }
        let essay = try ProjectStore.create(at: essayPath, name: "The Chat Box")
        _ = try essay.importScript(PrepFixtures.essay, fileName: "The Chat Box.md")
        let script = EditorJobs.fill(EditorJobs.template("script") ?? "", try EditorJobs.prepValues(.script, store: essay))
        #expect(!mine.contains(where: script.contains) && script.contains("The sound is the script\u{2019}s own words") && !script.contains("ownWords"))

        #expect(!job.contains("The writer\u{2019}s notes"))
        // A treatment's notes come with the job, below the steps.
        _ = try essay.importScript("## Rules\n\nNo dialogue.\n\n## Story\n\n**1 · Dark · 0:00–0:06.** He climbs the ladder.", fileName: "porch.md", as: .story)
        let treatment = EditorJobs.fill(EditorJobs.template("script") ?? "", try EditorJobs.prepValues(.script, store: essay))
        #expect(treatment.contains("## The writer\u{2019}s notes\n## Rules\n\nNo dialogue.") && treatment.contains("1 beats") == false)

        let run = EditorRun(job: .script, program: "claudeCode", version: "")
        _ = try store.updateScript(pictures: s.rows.map { PictureInput(rowID: $0.id, text: "Something we see.") })
        #expect(!EditorRunner.finished(run, store: store))
        _ = try store.updateScript(sounds: s.rows.map { SoundInput(rowID: $0.id, kind: .silence, text: "", seconds: 3) })
        #expect(EditorRunner.finished(run, store: store))
    }
}
