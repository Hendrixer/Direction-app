import Testing
import Foundation
import AppKit
import DirectionCore
import DirectionTools
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

    /// Dropping a folder again brings in what's new; a file that's already in says nothing.
    @Test func bringingTheSameFileAgainIsNotAProblem() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A second of quiet: a 48 kHz mono WAV.
        var wav = Data("RIFF".utf8); let samples = 48_000
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        u32(UInt32(36 + samples * 2)); wav.append(contentsOf: "WAVEfmt ".utf8); u32(16); u16(1); u16(1); u32(48_000); u32(96_000); u16(2); u16(16)
        wav.append(contentsOf: "data".utf8); u32(UInt32(samples * 2)); wav.append(Data(count: samples * 2))
        let sound = dir.appendingPathComponent("narration.wav")
        try wav.write(to: sound)
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Film.direction"), name: "Film")
        let m = FilmModel(preview: false)
        m.runtime = try ToolRuntime(store: store)
        m.refresh(force: true)
        for _ in 0..<2 {
            m.importFootage([sound])
            for _ in 0..<500 where m.importingFootage > 0 { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(m.importingFootage == 0 && m.error == nil, "\(m.error ?? "")")
        #expect(try store.read().assets.map(\.name) == ["narration.wav"])
        m.close()
    }

    /// A take that moves while a saved cut is on screen (relinked, or copied so it plays from any frame) plays
    /// from where it is now, without opening the film again.
    @Test func aSavedCutPlaysATakeFromWhereItIsNow() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        var wav = Data("RIFF".utf8); let samples = 48_000
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        u32(UInt32(36 + samples * 2)); wav.append(contentsOf: "WAVEfmt ".utf8); u32(16); u16(1); u16(1); u32(48_000); u32(96_000); u16(2); u16(16)
        wav.append(contentsOf: "data".utf8); u32(UInt32(samples * 2)); wav.append(Data(count: samples * 2))
        let first = dir.appendingPathComponent("narration.wav"), moved = dir.appendingPathComponent("Moved/narration.wav")
        try wav.write(to: first); try file(moved); try wav.write(to: moved)
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Film.direction"), name: "Film")
        let runtime = try ToolRuntime(store: store)
        let id = try #require(try await runtime.invoke("direction_import", arguments: .object(["path": .string(first.path), "append": .bool(true)])).value["asset"]["id"].string)
        _ = try await runtime.invoke("direction_create_cut", arguments: .object(["name": .string("Assembly")]))
        let m = FilmModel(preview: false)
        m.runtime = runtime
        m.refresh(force: true)
        #expect(m.displayed?.assets.first?.path == first.path)
        let values = try moved.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        try store.relink([AssetRelink(assetID: id, path: moved.path, fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0, duration: MediaTime(seconds: 1))])
        m.refresh(force: true)
        #expect(m.displayed?.editRevision == 1 && m.displayed?.assets.first?.path == moved.path)
        m.close()
    }

    /// B-roll with nothing said in it has no dialogue; it didn't fail. A job from before codes says so in words.
    @Test func aTakeWithNothingSaidHasNoDialogueNotAFailure() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Film.direction"), name: "Film")
        func job(_ asset: String, _ error: String, code: String?) throws {
            var j = JobRecord(id: newID("job"), kind: "transcription", revision: 0, ownerPID: 1, status: "failed", phase: "Failed", progress: nil, result: nil, error: error, createdAt: 1, updatedAt: 1, assetID: asset)
            j.errorCode = code
            try store.saveJob(j)
        }
        try job("broll", "No timed speech was recognized on this audio track.", code: "no_speech")
        try job("older-broll", "No timed speech was recognized on this audio track.", code: nil)
        try job("broken", "The audio track couldn\u{2019}t be read.", code: "audio_unreadable")
        let m = FilmModel(preview: false)
        m.runtime = try ToolRuntime(store: store)
        m.refresh(force: true)
        #expect(m.transcriptStatus("broll") == .none && m.transcriptStatus("older-broll") == .none)
        #expect(m.transcriptStatus("broken") == .failed("The audio track couldn\u{2019}t be read."))
        m.close()
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
