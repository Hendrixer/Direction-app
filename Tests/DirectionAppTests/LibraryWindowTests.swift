import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

/// The Library window's kinds (library.md): Direction's own, the director's sounds and images, and what the editor learned.
@MainActor
struct LibraryWindowTests {
    @Test func eachKindShowsItsOwn() {
        let entries = LibraryCatalog.entries(techniques: [], items: [ShelfItem(file: "Bed.m4a", kind: .music), ShelfItem(file: "Whoosh.wav", kind: .effect), ShelfItem(file: "Logo.png", kind: .image)])
        func names(_ kind: String?) -> [String] { entries.filter { LibraryModel.shown($0, kind: kind) }.map(\.name) }
        #expect(names("sounds") == ["Bed", "Whoosh"] && names("images") == ["Logo"] && names("yours").isEmpty)
        // A sound effect isn't one of Direction's effects on the picture.
        #expect(!names("effect").contains("Whoosh") && names("effect").contains("Film grain") && names(nil).count == entries.count)
    }

    @Test func aDroppedFolderBringsTheSoundsInIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-stems-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Try Again"), withIntermediateDirectories: true)
        for name in ["ES_Try Again (Instrumental Version) STEMS DRUMS - mr..wav", "ES_Try Again (Instrumental Version) - mr..wav", "License.pdf", ".DS_Store"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent("Try Again/" + name))
        }
        #expect(LibraryModel.inside(dir).map(\.lastPathComponent) == ["ES_Try Again (Instrumental Version) - mr..wav", "ES_Try Again (Instrumental Version) STEMS DRUMS - mr..wav"])
        let one = dir.appendingPathComponent("Try Again/License.pdf")
        #expect(LibraryModel.inside(one) == [one])
    }
}
