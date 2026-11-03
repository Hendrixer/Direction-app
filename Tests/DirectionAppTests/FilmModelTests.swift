import Testing
import Foundation
import DirectionCore
import DirectionTools
@testable import DirectionApp

@Suite("Film model")
@MainActor
struct FilmModelTests {
    /// The assembly has no page of its own (start.md › 06): asking for it leaves you in Dailies, its
    /// questions wait there, and once it's in every room's one button screens it.
    @Test func theAssemblyIsBuiltFromTheRoomYouAskedIn() {
        let building = StartFixtures.assembling()
        #expect(building.onboardingStep == nil && building.room == .dailies)
        #expect(building.primaryAction?.title == "Assembling\u{2026}" && building.primaryAction?.enabled == false)
        let asking = StartFixtures.assemblyQuestion()
        #expect(asking.onboardingStep == nil && asking.pill == .asks(1))
        let ready = StartFixtures.assemblyReady()
        #expect(ready.pill == .cutReady("Assembly ready"))
        for room in [Room.dailies, .breakdown, .notes] {
            ready.room = room
            #expect(ready.primaryAction?.title == "Screen the assembly", "in \(room)")
        }
    }

    @Test func aNewFilmThatTakesATrashedFilmsNameStillShowsInFilms() throws {
        let path = "/tmp/direction-tests-\(UUID().uuidString)/Untitled film.direction"
        func entry(available: Bool) throws -> ProjectEntry {
            try JSONDecoder().decode(ProjectEntry.self, from: JSONSerialization.data(withJSONObject: ["id": path, "name": "AI, the last human invention", "path": path, "lastOpened": 1.0, "available": available]))
        }
        defer { FilmLibraryIndex.noteRestored(path) }
        FilmLibraryIndex.noteTrashed(path)
        let app = AppModel()
        // The empty film that was trashed: gone from disk, so hidden.
        app.films = [try entry(available: false)]
        #expect(app.summaries.isEmpty)
        // The film menu never offers a film that isn't on this Mac.
        #expect(app.openableFilms.isEmpty)
        // A new film at the same path: shown.
        app.films = [try entry(available: true)]
        #expect(app.summaries.map(\.path) == [path] && app.openableFilms.map(\.path) == [path])
        #expect(app.filmName(URL(fileURLWithPath: path)) == "AI, the last human invention")
        FilmLibraryIndex.noteRestored(path)
        #expect(!FilmLibraryIndex.trashed.contains(path))
    }

    @Test func aFilmWithNoPictureShowsTheMarkLitItsOwnWay() throws {
        let a = "/Users/you/Movies/Direction/Coded love.direction", b = "/Users/you/Movies/Direction/Night walk.direction"
        let entry = try JSONDecoder().decode(ProjectEntry.self, from: JSONSerialization.data(withJSONObject: ["id": a, "name": "Coded love", "path": a, "lastOpened": 1.0, "available": true]))
        // A real film never gets a painted stand-in: it shows its own picture, or the mark.
        #expect(FilmLibraryIndex.shared.summary(for: entry).art == nil)
        // The same film is lit the same way every launch, always from above, and two films differently.
        #expect(FilmMarkPoster.light(a) == FilmMarkPoster.light(a))
        #expect(FilmMarkPoster.light(a) != FilmMarkPoster.light(b))
        for path in [a, b, "", "/x"] { #expect((1.1 * Double.pi...1.9 * Double.pi).contains(FilmMarkPoster.light(path))) }
    }

    @Test func openingTheFilmThatIsAlreadyOpenKeepsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-open-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Never the real library.
        if ProcessInfo.processInfo.environment["DIRECTION_LIBRARY_PATH"] == nil { setenv("DIRECTION_LIBRARY_PATH", dir.appendingPathComponent("library.sqlite").path, 1) }
        let url = dir.appendingPathComponent("Film.direction")
        _ = try ProjectStore.create(at: url, name: "Film")
        let app = AppModel()
        app.open(url)
        let first = try #require(app.film)
        // The editor's "show it in the app" opens the same film: it must not close and reopen,
        // which would cancel its running jobs.
        app.open(url)
        #expect(app.film === first)
        first.close()
    }

    /// Closing a film stops its delivery, so opening another one, or Films, asks first: Keep Delivering
    /// leaves everything as it was, Stop and Open opens the other film.
    @Test func openingAnotherFilmDuringADeliveryAsksFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-switch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        if ProcessInfo.processInfo.environment["DIRECTION_LIBRARY_PATH"] == nil { setenv("DIRECTION_LIBRARY_PATH", dir.appendingPathComponent("library.sqlite").path, 1) }
        let a = dir.appendingPathComponent("Launch.direction"), b = dir.appendingPathComponent("Teaser.direction")
        _ = try ProjectStore.create(at: a, name: "Launch"); _ = try ProjectStore.create(at: b, name: "Teaser")
        let app = AppModel()
        app.open(a)
        let first = try #require(app.film)
        let now = Date().timeIntervalSince1970
        try first.store?.saveJob(JobRecord(id: "job-delivery", kind: "export", revision: 0, ownerPID: getpid(), status: "running", phase: "Exporting", progress: 0.3, result: nil, error: nil, createdAt: now, updatedAt: now))
        first.refresh(force: true)
        var asked: [String?] = []
        app.askToStopDelivering = { _, opening in asked.append(opening); return false }
        app.open(b)
        #expect(app.film === first)
        #expect(!app.closeFilm() && app.film === first)
        #expect(asked == ["\u{201C}Teaser\u{201D}", nil])
        app.askToStopDelivering = { _, _ in true }
        app.open(b)
        #expect(app.film !== first && app.film?.url?.lastPathComponent == "Teaser.direction")
        app.film?.close()
    }

    /// The last film's delivery stopped when it closed; its job must not keep the next film's
    /// "is delivered" from being said.
    @Test func aDeliveryStoppedWithTheLastFilmDoesNotSilenceTheNext() {
        func export(_ id: String, _ status: String, path: String? = nil) -> JobRecord {
            JobRecord(id: id, kind: "export", revision: 0, ownerPID: getpid(), status: status, phase: "", progress: nil, result: path.map { .object(["path": .string($0)]) }, error: nil, createdAt: 0, updatedAt: 0)
        }
        let last = FilmModel(preview: true), next = FilmModel(preview: true)
        last.jobs = [export("job-last", "running")]
        DeliveryWatch.check(last)
        var told: [String] = []
        next.onNotify = { title, _, _ in told.append(title) }
        next.jobs = [export("job-next", "running")]
        DeliveryWatch.check(next)
        next.jobs = [export("job-next", "completed", path: "/tmp/direction-none/Film.mp4")]
        DeliveryWatch.check(next)
        #expect(told == ["Film is delivered"])
    }

    @Test func closingAFilmTakesItsUndoStepsWithIt() {
        let m = FilmModel(preview: true), undo = UndoManager()
        undo.groupsByEvent = false
        m.undoManager = undo
        undo.beginUndoGrouping(); m.registerUndo("Circle Take") { _ in }; undo.endUndoGrouping()
        #expect(undo.canUndo)
        m.close()
        #expect(!undo.canUndo)
    }

    @Test func changingRoomsStopsTheCutWhereItIs() {
        let m = SampleFilm.make(room: .screening)
        m.playing = true
        m.go(.dailies)
        #expect(!m.playing)
        #expect(m.room == .dailies)
    }

    @Test func deliveryOffersTheFootagesSizeWhenItIsBiggerThanTheCut() {
        let m = SampleFilm.make()
        // 3840 × 2160 takes in a 1920 × 1080 cut.
        let size = m.footageSize(m.sequence)
        #expect(size?.width == 3840 && size?.height == 2160)
        var native = m.sequence; native?.width = 3840; native?.height = 2160
        #expect(m.footageSize(native) == nil)
    }

    @Test func stripMergesClipsIntoScenesAtTheirRealLengths() {
        let m = SampleFilm.make()
        let scenes = m.stripScenes
        #expect(scenes.map(\.number) == [1, 2, 3, 4, 5])
        #expect(scenes.map(\.duration) == [25, 40, 45, 66, 44])
        #expect(scenes.last?.locked == true)
        #expect(m.stripScene(at: SampleFilm.tc(1, 12, 8))?.number == 3)
    }

    @Test func sheetListsNotesInNumberOrderWithDraftsSeparate() {
        let m = SampleFilm.make()
        #expect(m.sheetNotes.compactMap(\.number) == [1, 2, 3, 4])
        #expect(m.readyNotes.compactMap(\.number) == [1, 2])
        #expect(m.draftNotes.compactMap(\.number) == [3, 4])
        #expect(m.badge(for: .notes)?.0 == "2")
    }

    @Test func pillTellsTheTruthAboutTheEditor() {
        let m = SampleFilm.make()
        #expect(m.pill == .ready)
        SampleFilm.withTurnover(m, state: .waiting)
        #expect(m.pill == .waiting)
        SampleFilm.withTurnover(m, state: .readBack, readBack: true)
        #expect(m.pill == .readBackReady)
        SampleFilm.withTurnover(m, state: .cutting)
        if case .working(let text, _) = m.pill { #expect(text == "Cutting 1 of 7") } else { Issue.record("Expected working, got \(m.pill)") }
        m.questions = [EditorQuestion(id: "q", turnoverID: "turnover-3", kind: "cant", noteIDs: ["note-7"], text: "Launch day is locked.", detail: nil, choices: [], allowsText: true, answer: nil, createdAt: 0)]
        #expect(m.pill == .cant(1))
    }

    @Test func changesReelPadsWithHandlesAndMergesNeighbours() {
        let m = SampleFilm.make()
        SampleFilm.withCut4(m)
        m.handleSeconds = 2
        let reel = m.changeReel(in: m.latestCut)
        #expect(reel.first?.lowerBound == 0)
        let inside = reel.allSatisfy { r in r.upperBound <= m.duration }
        #expect(inside)
        let separated = zip(reel, reel.dropFirst()).allSatisfy { a, b in a.upperBound < b.lowerBound }
        #expect(separated)
        #expect(m.unreviewedAnswers.count == 7)
        #expect(m.defaultRoom == .changes)
        let changed = m.stripScenes.contains { s in s.changed }
        #expect(changed)
    }

    /// Use This Take's Sound asks for it where the cut plays the group with another take's sound.
    @Test func aNewSoundTakeIsAskedForWhereTheCutPlaysAnotherSound() {
        let m = FilmModel(preview: true)
        var p = Project(name: "Sound")
        p.sequences[0].clips = [
            Clip(id: "c1", assetID: "cam", name: "cam", start: .zero, sourceRange: .init(start: 0, end: 4)),
            Clip(id: "c2", assetID: "other", name: "other", start: .init(seconds: 4), sourceRange: .init(start: 0, end: 3)),
            Clip(id: "c3", assetID: "screen", name: "screen", start: .init(seconds: 7), sourceRange: .init(start: 10, end: 12)),
        ]
        m.project = p
        let g = SyncGroup(id: "g", soundAssetID: "cam", takes: [.init(assetID: "cam", offset: 0, match: 1), .init(assetID: "screen", offset: 0.089, match: 0.97)], method: "sound", createdAt: 0)
        // Using the screen's sound: the camera at 0–4 plays its own, the screen at 7–9 already plays the screen's.
        #expect(m.soundNoteRange(g, sound: "screen") == 0...4)
        // Using the camera's: only the screen clip needs it.
        #expect(m.soundNoteRange(g, sound: "cam") == 7...9)
        // Sound already laid in sync under the screen clip counts as what it plays.
        var laid = Clip(assetID: "cam", name: "cam", kind: .audio, layer: 1, start: .init(seconds: 7), sourceRange: .init(start: 9.9, end: 11.9)); laid.synced = true
        m.project?.sequences[0].clips.append(laid)
        #expect(m.soundNoteRange(g, sound: "cam") == nil)
    }

    @Test func onboardingWalksBriefThenFootageUntilTheFirstCut() {
        let m = FilmModel(preview: true)
        m.project = Project(name: "New")
        #expect(m.onboardingStep == .brief)
        m.brief = SampleFilm.briefValue
        #expect(m.onboardingStep == .footage)
        m.project = SampleFilm.project(clips: [], revision: 1)
        #expect(m.onboardingStep == .footage)
        m.dailies = SampleFilm.dailies()
        #expect(m.onboardingStep == nil)
        m.dailies = Dailies()
        m.onboardingDismissed = true
        #expect(m.onboardingStep == nil)
        m.cuts = SampleFilm.cuts
        #expect(m.onboardingStep == nil)
    }

    @Test func finishStaysClosedUntilPictureLock() {
        let m = SampleFilm.make()
        #expect(!m.isEnabled(.finish))
        m.directing.pictureLocked = true
        #expect(m.isEnabled(.finish))
    }
}

/// The assembly and turnover jobs list the takes in sync with the rules for cutting them, and say
/// nothing about sync when a film has none.
@Test func cuttingJobsCarryTheTakesInSync() {
    var d = Dailies()
    for (id, setup, code) in [("cam", "1A", "T1"), ("screen", "1B", "T1")] { var t = TakeInfo(assetID: id); t.setupCode = setup; t.code = code; d.takes[id] = t }
    d.takes["screen"]?.circled = true
    #expect(EditorJobs.syncRules(d, assets: []).isEmpty)
    d.syncGroups = [SyncGroup(id: "g", soundAssetID: "cam", takes: [.init(assetID: "cam", offset: 0, match: 1), .init(assetID: "screen", offset: 0.089, match: 0.97)], method: "sound", createdAt: 0)]
    let rules = EditorJobs.syncRules(d, assets: [])
    #expect(rules.contains("- 1A T1 (its sound) \u{00B7} 1B T1, circled") && rules.contains("never two angles end to end") && rules.contains("`syncSound`"))
    #expect(rules.contains("Screen and you, bottom right, unless the director chooses another"))
    #expect(EditorJobs.syncRules(d, assets: [], layout: FrameLayout(kind: .screenAndYou, corner: .topLeft)).contains("the director chose Screen and you \u{00B7} top left for this film"))
    for job in ["assemble", "turnover"] { #expect(EditorJobs.template(job)?.contains("{{sync}}") == true, "\(job)") }
}

/// Settings › Engines recommends from the Mac: the largest local version that fits memory and disk,
/// OpenRouter only where nothing local can run, Apple for transcription, an installed editor.
@MainActor
@Test func enginesRecommendWhatThisMacRunsBest() {
    var mac = MacFacts(chip: "Apple M4 Max", memory: 64 << 30, appleSilicon: true, freeBytes: 500_000_000_000, volume: "Macintosh HD", mlxVLM: true, downloaded: [], hasOpenRouterKey: false)
    let both: Set<EditorProgram> = [.claudeCode, .codex]
    var a = EngineAdvice.advise(mac, editor: .codex, installed: both)
    #expect(a.lookEngine == .thisMac && a.lookDetail == "best" && a.transcription == .apple && a.editor == .codex && a.missing.isEmpty)
    mac.memory = 16 << 30
    #expect(EngineAdvice.advise(mac, editor: .codex, installed: both).lookDetail == "standard")
    mac.memory = 8 << 30
    #expect(EngineAdvice.advise(mac, editor: .codex, installed: both).lookDetail == "quick")
    // No room for Best's download, but Standard is already here.
    mac.memory = 64 << 30; mac.freeBytes = 4_000_000_000; mac.downloaded = ["standard"]
    #expect(EngineAdvice.advise(mac, editor: .codex, installed: both).lookDetail == "standard")
    // No room for anything and a key: OpenRouter. Without Apple silicon: OpenRouter.
    mac.downloaded = []; mac.freeBytes = 1_000_000_000; mac.hasOpenRouterKey = true
    #expect(EngineAdvice.advise(mac, editor: .codex, installed: both).lookEngine == .openRouter)
    mac.freeBytes = 500_000_000_000; mac.appleSilicon = false
    #expect(EngineAdvice.advise(mac, editor: .codex, installed: both).lookEngine == .openRouter)
    // mlx-vlm missing is something to install, not a reason to send footage away.
    mac.appleSilicon = true; mac.mlxVLM = false
    a = EngineAdvice.advise(mac, editor: .codex, installed: both)
    #expect(a.lookEngine == .thisMac && a.missing.map(\.name) == ["mlx-vlm"])
    // The editor: the chosen program while it's installed, else whichever is; your own session stays.
    mac.mlxVLM = true
    #expect(EngineAdvice.advise(mac, editor: .codex, installed: [.claudeCode]).editor == .claudeCode)
    #expect(EngineAdvice.advise(mac, editor: .yourOwn, installed: both).editor == nil)
    a = EngineAdvice.advise(mac, editor: .claudeCode, installed: [])
    #expect(a.editor == nil && a.missing.map(\.name) == ["Claude Code"])
    // Footage and Services went into Engines.
    #expect(SettingsTab.stored("services") == .engines && SettingsTab.stored("footage") == .engines && SettingsTab.stored("cutting") == .cutting && SettingsTab.stored(nil) == nil)
}

/// Use B in Changes puts B in the cut: Screening plays the new revision, and ⌘Z puts A back.
@MainActor @Test func usingAnOptionPlaysItInScreeningAndUndoes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-options-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ProjectStore.create(at: directory.appendingPathComponent("Film.direction"), name: "Two ways")
    func take(_ id: String) -> MediaAsset { MediaAsset(id: id, name: id + ".mov", path: "/\(id).mov", duration: .init(seconds: 20), video: [.init(id: 1, width: 640, height: 360, frameRate: 30)]) }
    for a in ["a", "b", "w"] { _ = try store.addAsset(take(a), append: true, expectedRevision: store.revision()) }
    let shots = try store.read().sequences[0].clips
    let assembly = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
    let note = try store.addComment(text: "Let her be tired.", sequenceID: nil, revision: store.revision(), cutID: assembly.id, time: .init(seconds: 21), extra: NoteFields(kind: .feeling))
    let t = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: assembly.id, sequenceID: nil)
    func edit(_ json: String) throws -> Int { try store.edit(EditBatch(baseEditRevision: store.revision(), notes: [1], operations: [EditOperation(json: JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))])).editRevision }
    // A cuts b two seconds shorter; B (in last) puts them back.
    let a = try edit(#"{"op":"trim","clipID":"\#(shots[1].id)","edge":"tail","frames":-60}"#)
    let b = try edit(#"{"op":"trim","clipID":"\#(shots[1].id)","edge":"tail","frames":60}"#)
    _ = try store.completeTurnover(id: t.id, revision: b, sequenceID: nil, answers: [AnswerInput(noteID: note.id, summary: "Two ways.", start: 20, end: 40, options: [NoteOption(label: "A", summary: "Shorter", revision: a), NoteOption(label: "B", summary: "As it was", revision: b)], preferred: "A")])

    let m = FilmModel(), undo = UndoManager()
    undo.groupsByEvent = false
    m.runtime = try ToolRuntime(store: store); m.undoManager = undo
    m.refresh(force: true)
    #expect(m.duration == 60 && m.displayed?.editRevision == b)
    undo.beginUndoGrouping()
    m.useOption(note.id, "A")
    undo.endUndoGrouping()
    #expect(m.error == nil, "\(m.error ?? "")")
    #expect(m.reviewCut?.editRevision == b + 1 && m.displayed?.editRevision == b + 1 && m.duration == 58)
    #expect(m.note(note.id)?.latestAnswer?.pick == "A" && m.status(m.note(note.id)!) == .accepted)
    // Messages written on Cut 2 as delivered still say Cut 2.
    #expect(m.cut(atRevision: b)?.name == "Cut 2" && m.cut(atRevision: a)?.name == "Assembly")
    undo.undo()
    #expect(m.reviewCut?.editRevision == b + 2 && m.duration == 60 && m.note(note.id)?.latestAnswer?.optionInCut == "B")
}
