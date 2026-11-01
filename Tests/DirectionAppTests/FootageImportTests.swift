import Testing
import Foundation
import AppKit
import DirectionCore
@testable import DirectionApp

@Suite("Bringing footage")
@MainActor
struct FootageImportTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-footage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func file(_ url: URL, _ text: String = "") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Copy into library (settings.md › 47): the take keeps its file's name, a second file of the same
    /// name gets "C0001 2.MP4", nothing is overwritten, and the same file again isn't copied twice.
    @Test func copyIntoLibraryKeepsTheOriginalsNameAndNeverOverwrites() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("Card A/C0001.MP4"), other = dir.appendingPathComponent("Card B/C0001.MP4")
        try file(original, "the first take"); try file(other, "another take with the same name")
        let copies = MediaAsset.copies(in: dir.appendingPathComponent("Film.direction"))
        let first = try FootageFiles.copy(original, into: copies, via: copies.appendingPathComponent(".a.copying"))
        let second = try FootageFiles.copy(other, into: copies, via: copies.appendingPathComponent(".b.copying"))
        #expect(first.lastPathComponent == "C0001.MP4" && second.lastPathComponent == "C0001 2.MP4")
        #expect(try String(contentsOf: first, encoding: .utf8) == "the first take")
        #expect(try String(contentsOf: second, encoding: .utf8) == "another take with the same name")
        #expect(try FootageFiles.copy(original, into: copies, via: copies.appendingPathComponent(".c.copying")) == first)
        #expect(try FootageFiles.copy(other, into: copies, via: copies.appendingPathComponent(".d.copying")) == second)
        // Nothing half-written is left, and the originals stay where they were.
        #expect(try FileManager.default.contentsOfDirectory(atPath: copies.path).sorted() == ["C0001 2.MP4", "C0001.MP4"])
        #expect(FileManager.default.fileExists(atPath: original.path) && FileManager.default.fileExists(atPath: other.path))
    }

    @Test func aCopiedTakeIsFootageButTheEditorsFilesAreNot() {
        let film = URL(fileURLWithPath: "/tmp/direction-footage/Film.direction")
        let copied = MediaAsset(name: "C0001.MP4", path: MediaAsset.copies(in: film).appendingPathComponent("C0001.MP4").path, duration: MediaTime(seconds: 4))
        let mix = MediaAsset(name: "mix.wav", path: film.appendingPathComponent("Editor/mix.wav").path, duration: MediaTime(seconds: 4))
        #expect(copied.isFootage(film: film))
        #expect(!mix.isFootage(film: film))
    }

    /// The copy runs off the main thread; the logging page says how far it's got, and stops saying so when it's done.
    @Test func copyingSaysHowFarItHasGotUntilItIsDone() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("A001.mov")
        try Data(count: 2_000_000).write(to: original)
        let m = FilmModel(preview: true)
        m.copyingFootage = FootageCopying(done: 2, total: 5)
        #expect(m.loggingStage?.spoken == "Copying into the film, 3 of 5")
        m.copyingFootage = FootageCopying(total: 1)
        let copy = try await m.copyIn(original, to: MediaAsset.copies(in: dir.appendingPathComponent("Film.direction")))
        #expect(m.copyingFootage == nil)
        #expect(copy.lastPathComponent == "A001.mov" && FileManager.default.contentsEqual(atPath: copy.path, andPath: original.path))
    }

    /// Music under dialogue (settings.md › 44) reaches the editor with the turnover; films turned over
    /// before it was asked still read their preferences.
    @Test func theEditorIsToldHowMuchToDuckMusicUnderDialogue() throws {
        #expect(EditorJobs.ducking(6) == "duck it 6 dB (`duck`) where a note doesn\u{2019}t say otherwise")
        #expect(EditorJobs.ducking(0) == "don\u{2019}t duck it unless a note asks")
        let older = try JSONDecoder().decode(EditorPreferences.self, from: Data(#"{"twoWaysForFeeling":true,"askBeforeGuessing":true,"conflictOrder":["feeling","story","pace","picture","sound"],"handleSeconds":2}"#.utf8))
        #expect(older.musicDuckDB == nil)
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Film.direction"), name: "Film")
        _ = try store.updateDirectingState(summary: "Updated the editor's instructions") { $0.preferences = EditorPreferences(musicDuckDB: 0) }
        let t = try store.turnOver(noteIDs: [], kind: "assembly", latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        let text = try EditorJobs.text(for: EditorRun(job: .assemble, program: "claudeCode", version: "", turnoverID: t.id), store: store)
        #expect(text.contains("- Music under dialogue: don\u{2019}t duck it unless a note asks"))
    }

    // MARK: Dropping

    /// A folder brings its footage and sound; a camera card's thumbnails stay out, a still dropped on its
    /// own comes in, and a script is kept apart instead of failing as footage.
    @Test func aDroppedFolderBringsItsFootageAndKeepsScriptsApart() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let card = dir.appendingPathComponent("Card")
        for name in ["A001.mov", "Sound/A001.wav", "THMBNL/A001.JPG", "notes.txt"] { try file(card.appendingPathComponent(name)) }
        let script = dir.appendingPathComponent("Script.pdf"), logo = dir.appendingPathComponent("logo.png"), film = dir.appendingPathComponent("Other.direction")
        try file(script); try file(logo)
        try FileManager.default.createDirectory(at: film, withIntermediateDirectories: true)
        let drop = FootageFiles.route([card, script, logo])
        #expect(drop.footage.map(\.lastPathComponent) == ["A001.mov", "A001.wav", "logo.png"])
        #expect(drop.scripts.map(\.lastPathComponent) == ["Script.pdf"])
        #expect(drop.film == nil)
        #expect(FootageFiles.route([film, card]).film == film)
    }

    /// Several files dropped at once are read one after another, in order: never appended from
    /// several threads at once.
    @Test func droppedFilesArriveInTheOrderTheyWereDropped() async {
        let urls = (1...12).map { URL(fileURLWithPath: "/tmp/direction-drop/A\($0).mov") }
        let got = await FootageFiles.urls(from: urls.map { NSItemProvider(object: $0 as NSURL) })
        #expect(got == urls)
    }

    @Test func aDroppedScriptIsAnsweredInsteadOfImportedAsFootage() {
        let m = FilmModel(preview: true)
        m.bring(FootageDrop(scripts: [URL(fileURLWithPath: "/tmp/direction-drop/Script.fdx")]))
        #expect(m.toast?.title == "Direction can\u{2019}t read scripts yet")
        #expect(m.importingFootage == 0)
        m.bring(FootageDrop())
        #expect(m.toast?.title == "Those aren\u{2019}t video, sound or script files.")
    }
}
