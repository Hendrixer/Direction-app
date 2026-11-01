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

    // MARK: Songs in parts

    /// A sound on the shelf, heard for this long.
    private func heard(_ sounds: MediaLibrary, _ dir: URL, _ name: String, _ seconds: Double) throws -> ShelfItem {
        let item = try sounds.add(try file(dir.appendingPathComponent(name), name))
        return try sounds.update(item.file) { var m = ShelfItem.Measured(); m.seconds = seconds; m.tempo = 92; $0.measured = m }
    }

    @Test func aNameReadsAsASongAndAPart() {
        func read(_ n: String) -> String { let r = Stems.read(n); return "\(r.song)|\(r.part ?? "-")" }
        #expect(read("ES_Neon Drive (Drums) - Moss") == "ES Neon Drive - Moss|Drums")
        #expect(read("ES_Try Again (Instrumental Version) STEMS BASS - mr.") == "ES Try Again (Instrumental Version) - mr|Bass")
        #expect(read("ES_Try Again (Instrumental Version) - mr.") == "ES Try Again (Instrumental Version) - mr|-")
        #expect(read("ES_Neon Drive - Moss") == "ES Neon Drive - Moss|-")
        #expect(read("Neon_Drive_STEMS_Bass") == "Neon Drive|Bass")
        #expect(read("Neon Drive Full Mix") == "Neon Drive|Full mix")
        #expect(read("Neon Drive [Melody] - Lead Singer") == "Neon Drive - Lead Singer|Melody")
        // A song with a part's word at its start is a song.
        #expect(read("Bass Drop") == "Bass Drop|-" && read("Bass Drop (Instruments)") == "Bass Drop|Instruments")
    }

    @Test func aSongsStemsAndFullMixComeTogetherByNameAndLength() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let sounds = MediaLibrary(.sounds, folder: dir.appendingPathComponent("Sounds"))
        // As Epidemic Sound's zip unpacks: the full mix and its stems, the artist after " - ".
        _ = try heard(sounds, dir, "ES_Try Again (Instrumental Version) - mr..wav", 134.05)
        for part in ["BASS", "DRUMS", "INSTRUMENTS"] { _ = try heard(sounds, dir, "ES_Try Again (Instrumental Version) STEMS \(part) - mr..wav", 134.0) }
        // Drums on their own were heard as an effect; as long as the song, they're still its stem.
        try sounds.update("ES_Try Again (Instrumental Version) STEMS DRUMS - mr..wav") { $0.kind = .effect }
        // Not with them: the same name at another length, a stem of another song, and a song the director kept on its own.
        _ = try heard(sounds, dir, "ES_Try Again (Instrumental Version) STEMS MELODY - mr. 2.wav", 61)
        _ = try heard(sounds, dir, "Other (Drums).wav", 134)
        let apart = try heard(sounds, dir, "Try Again Radio (Bass).wav", 134)
        try sounds.update(apart.file) { $0.song = "" }
        // A sound effect isn't a song's part, nor anything not listened to yet.
        let whoosh = try sounds.add(try file(dir.appendingPathComponent("Try Again (Drum).wav"), "fx")); try sounds.update(whoosh.file) { $0.kind = .effect }

        let changed = try sounds.groupStems()
        #expect(changed.count == 4)
        let song = try #require(sounds.songs().first)
        #expect(sounds.songs().count == 1 && song.name == "Try Again" && song.source == "Epidemic Sound, by mr.")
        #expect(song.parts.map { $0.part ?? "" } == ["Full mix", "Drums", "Bass", "Instruments"] && song.lead.file == "ES_Try Again (Instrumental Version) - mr..wav" && song.parts.allSatisfy { $0.kind == .music })
        #expect(song.partsText == "full mix and 3 stems: Drums, Bass, Instruments" && song.summary.hasPrefix("Music \u{00B7} 2:14 \u{00B7} 92 BPM \u{00B7} full mix and 3 stems"))
        // Put together again, nothing changes; a stem that comes later named as the others joins it.
        #expect(try sounds.groupStems().isEmpty)
        _ = try heard(sounds, dir, "ES_Try Again (Instrumental Version) STEMS MELODY - mr..wav", 134.01)
        #expect(try sounds.groupStems().map { $0.part } == ["Melody"])
        // The vocal version is another song, so each is named with its version.
        _ = try heard(sounds, dir, "ES_Try Again - mr..wav", 170)
        _ = try heard(sounds, dir, "ES_Try Again STEMS DRUMS - mr..wav", 170)
        try sounds.groupStems()
        #expect(sounds.songs().map(\.name) == ["Try Again", "Try Again - mr."])
        try sounds.renameSong(song, to: "Try Again (Instrumental)")
        try sounds.renameSong(try #require(sounds.findSong("Try Again - mr.")?.song), to: "Try Again")
        // One the director names by hand joins as the part they say.
        try sounds.setSong("ES_Try Again (Instrumental Version) STEMS MELODY - mr. 2.wav", song: "try again", part: "Keys")
        let whole = try #require(sounds.findSong("Try Again (Instrumental)"))
        #expect(whole.part == nil && whole.song.parts.count == 5 && sounds.findSong("Try Again")?.song.parts.count == 3)
        // Found by a part's name in a note, or its file.
        #expect(sounds.findSong("Try Again (Instrumental) Drums")?.part?.file == "ES_Try Again (Instrumental Version) STEMS DRUMS - mr..wav")
        #expect(sounds.findSong("ES_Try Again (Instrumental Version) STEMS BASS - mr..wav")?.part?.part == "Bass")
        // One part each: a second Drums is refused, naming the one it has.
        #expect(throws: DirectionError.self) { try sounds.setSong("Other (Drums).wav", song: "Try Again", part: "Drums") }
        // Taken apart, each is a sound on its own and stays one.
        try sounds.partSong(whole.song)
        #expect(sounds.songs().map(\.name) == ["Try Again"] && sounds.items().filter { $0.song == "" }.count == 6)
        #expect(try sounds.groupStems().isEmpty)
    }

    @Test func aMusicLibrarysNameSaysTheSongTheArtistAndWhereItsFrom() {
        let t = Stems.title("ES_Try Again (Instrumental Version) STEMS BASS - mr.")
        #expect(t.short == "Try Again" && t.long == "Try Again (Instrumental Version)" && t.artist == "mr." && t.library == "Epidemic Sound")
        let plain = Stems.title("Neon Drive Stems - Drums")
        #expect(plain.short == "Neon Drive" && plain.artist == nil && plain.library == nil)
    }

    @Test func aSongIsNamedWholeOrAPartAtATime() throws {
        func item(_ file: String, _ part: String) -> ShelfItem { var i = ShelfItem(file: file, kind: .music); i.song = "Neon Drive"; i.part = part; i.note = "0:32 drums come in"; return i }
        let entries = LibraryCatalog.entries(techniques: [], items: [item("nd.wav", "Full mix"), item("nd-d.wav", "Drums"), item("nd-m.wav", "Melody"), ShelfItem(file: "Felt piano.wav", kind: .music)])
        let song = try #require(entries.first { $0.id == "song:Neon Drive" })
        #expect(song.parts?.count == 3 && song.item?.file == "nd.wav" && song.kind == "music")
        #expect(entries.filter { $0.partOf == "Neon Drive" }.map(\.name) == ["Neon Drive Full mix", "Neon Drive Drums", "Neon Drive Melody"])
        // The parts aren't sounds on their own as well.
        #expect(!entries.contains { $0.name == "nd" } && entries.contains { $0.name == "Felt piano" })
        let found = LibraryCatalog.mentions(in: "@Neon Drive Drums under the open, then @Neon Drive whole", entries: entries)
        #expect(found.map(\.name) == ["Neon Drive Drums", "Neon Drive"])
        let said = LibraryCatalog.explain(found)
        #expect(said.contains("@Neon Drive Drums is the Drums of Neon Drive") && said.contains("@Neon Drive is a song in the director's library, in parts (full mix and 2 stems: Drums, Melody)"))
        #expect(said.contains("0:32 drums come in") && said.contains("placeMusic with parts [\"Drums\"]"))
    }
}
