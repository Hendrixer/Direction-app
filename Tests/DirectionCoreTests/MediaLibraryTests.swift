import Testing
import Foundation
@testable import DirectionCore

/// The director's sounds and images (library.md): shelves outside any film, named with "@", never footage.
struct MediaLibraryTests {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-shelf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func file(_ url: URL, _ text: String) throws -> URL { try Data(text.utf8).write(to: url); return url }

    @Test func aFileComesOntoItsShelfOnceUnderItsOwnName() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let sounds = MediaLibrary(.sounds, folder: dir.appendingPathComponent("Sounds"))
        let song = try file(dir.appendingPathComponent("Felt piano.wav"), "a song")
        let item = try sounds.add(song, source: "Epidemic Sound")
        #expect(item.file == "Felt piano.wav" && item.name == "Felt piano" && item.kind == .music && item.source == "Epidemic Sound")
        // The same file again is the one there; another with its name gets "Name 2"; the original stays.
        #expect(try sounds.add(song) == item)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("other"), withIntermediateDirectories: true)
        let other = try file(dir.appendingPathComponent("other/Felt piano.wav"), "another song")
        #expect(try sounds.add(other).file == "Felt piano 2.wav")
        #expect(FileManager.default.fileExists(atPath: song.path))
        // A picture isn't a sound, and nothing half-copied is left.
        #expect(throws: DirectionError.self) { try sounds.add(try file(dir.appendingPathComponent("logo.png"), "png")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: sounds.folder.path).filter { $0.hasPrefix(".") && $0 != ".library.json" }.isEmpty)
        // A file put in the folder in the Finder is on the shelf too, music until it's listened to.
        _ = try file(sounds.folder.appendingPathComponent("Whoosh.aif"), "whoosh")
        #expect(sounds.items().map(\.name) == ["Felt piano", "Felt piano 2", "Whoosh"])
        #expect(sounds.needsMeasuring(sounds.find("whoosh")!))
    }

    @Test func whatTheDirectorWritesIsKeptAndANameChangeKeepsIt() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let images = MediaLibrary(.images, folder: dir.appendingPathComponent("Images"))
        let logo = try images.add(try file(dir.appendingPathComponent("logo.png"), "png"))
        try images.update(logo.file) { $0.note = "Bottom right, from the first chapter on" }
        #expect(MediaLibrary(.images, folder: images.folder).find("LOGO")?.note == "Bottom right, from the first chapter on")
        let renamed = try images.rename(images.find("logo")!, to: "Channel mark")
        #expect(renamed.file == "Channel mark.png" && renamed.note == "Bottom right, from the first chapter on")
        #expect(images.items().map(\.file) == ["Channel mark.png"])
        _ = try images.add(try file(dir.appendingPathComponent("still.jpg"), "jpg"))
        #expect(throws: DirectionError.self) { try images.rename(images.find("still")!, to: "channel MARK") }
        #expect(throws: DirectionError.self) { try images.rename(renamed, to: "a/b") }
        // Taken off the shelf, its file goes to the Trash.
        var trashed: [String] = []
        try images.remove(renamed) { trashed.append($0.lastPathComponent); try FileManager.default.removeItem(at: $0) }
        #expect(trashed == ["Channel mark.png"] && images.items().map(\.name) == ["still"])
    }

    @Test func eachSaysWhatItIsInOneLine() {
        var song = ShelfItem(file: "Felt piano.m4a", kind: .music)
        #expect(song.summary == "Music, not listened to yet")
        var m = ShelfItem.Measured(); m.seconds = 134.4; m.tempo = 92; m.key = "D minor"; m.instruments = ["piano", "bowed strings"]; m.vocals = false
        song.measured = m
        #expect(song.summary == "Music \u{00B7} 2:14 \u{00B7} 92 BPM \u{00B7} D minor \u{00B7} piano, bowed strings \u{00B7} no vocals")
        var whoosh = ShelfItem(file: "Whoosh.wav", kind: .effect), w = ShelfItem.Measured(); w.seconds = 1.24; w.sounds = ["whoosh"]; whoosh.measured = w
        #expect(whoosh.summary == "Sound effect \u{00B7} 1.2 s \u{00B7} whoosh")
        var logo = ShelfItem(file: "Logo.png", kind: .image), l = ShelfItem.Measured(); l.width = 1200; l.height = 400; l.transparent = true; l.words = "SCOTT MOSS"; logo.measured = l
        #expect(logo.summary == "Image \u{00B7} 1200 \u{00D7} 400 with transparency \u{00B7} reads \u{201C}SCOTT MOSS\u{201D}")
    }

    @Test func nothingOnAShelfIsFootage() {
        let film = URL(fileURLWithPath: "/tmp/direction-shelf/Film.direction")
        let song = MediaAsset(name: "Felt piano.wav", path: SharedSettings.soundsFolder.appendingPathComponent("Felt piano.wav").path, duration: MediaTime(seconds: 30))
        var copy = MediaAsset(name: "Felt piano.wav", path: film.appendingPathComponent("Library/Sounds/Felt piano.wav").path, duration: MediaTime(seconds: 30))
        copy.fromLibrary = "Felt piano.wav"
        #expect(!song.isFootage(film: film) && !copy.isFootage(film: film))
        #expect(MediaLibrary.holding(URL(fileURLWithPath: song.path)) == .sounds)
    }

    @Test func atNamesASoundOrImageAndTellsTheEditorHowToUseIt() {
        var song = ShelfItem(file: "Felt piano.m4a", kind: .music, note: "Under the opening.", source: "Epidemic Sound")
        var m = ShelfItem.Measured(); m.seconds = 134; song.measured = m
        let logo = ShelfItem(file: "Logo.png", kind: .image)
        let entries = LibraryCatalog.entries(techniques: [], items: [song, logo])
        let found = LibraryCatalog.mentions(in: "Put @Felt piano under the open and @logo in the corner.", entries: entries)
        #expect(found.map(\.name) == ["Felt piano", "Logo"] && found.map(\.kind) == ["music", "image"] && !found[0].isBuiltIn)
        let said = LibraryCatalog.explain(found)
        #expect(said.contains("@Felt piano is music in the director's library: Music \u{00B7} 2:14. Under the opening. From Epidemic Sound."), "\(said)")
        #expect(said.contains("direction_import with library \"Felt piano\"") && said.contains("placeMusic") && said.contains("@Logo is an image") && said.contains("cutaway"))
        // Direction's own names win over a sound called the same.
        #expect(LibraryCatalog.entries(techniques: [], items: [ShelfItem(file: "Whip.wav", kind: .effect)]).filter { $0.name == "Whip" }.map(\.kind) == ["transition"])
    }
}
