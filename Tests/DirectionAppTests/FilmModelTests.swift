import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

@Suite("Film model")
@MainActor
struct FilmModelTests {
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
        // A new film at the same path: shown.
        app.films = [try entry(available: true)]
        #expect(app.summaries.map(\.path) == [path])
        FilmLibraryIndex.noteRestored(path)
        #expect(!FilmLibraryIndex.trashed.contains(path))
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

    @Test func changingRoomsStopsTheCutWhereItIs() {
        let m = SampleFilm.make(room: .screening)
        m.playing = true
        m.go(.dailies)
        #expect(!m.playing)
        #expect(m.room == .dailies)
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
