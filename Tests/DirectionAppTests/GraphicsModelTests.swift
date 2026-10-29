import Testing
import Foundation
import AppKit
import DirectionCore
import DirectionMedia
import DirectionTools
@testable import DirectionApp

@Suite("Graphics words")
@MainActor
struct GraphicsModelTests {
    @Test func wordsLongerThanTheirMaxCantBeTyped() {
        let m = GraphicsFixtures.changesGraphic(), word = GraphicsFixtures.title.words[0]
        m.graphics.type(String(repeating: "x", count: 45), into: word)
        #expect(m.graphics.draft["title"]?.count == 40)
        #expect(GraphicsModel.limited("Two years, alone.", max: 40) == "Two years, alone.")
        #expect(GraphicsModel.limited("abcdef", max: nil) == "abcdef")
    }

    @Test func aGraphicAnswerOpensWordsAndTheTitlebarStandsDown() {
        let m = GraphicsFixtures.changesGraphic()
        let note = try! #require(m.selectedAnswer)
        #expect(m.graphics.graphic(for: note)?.name == "title")
        #expect(m.graphics.draft["title"] == "Two years, alone.")
        // One steel button per window state: the popover's Change Words.
        #expect(m.primaryIsInert)
        m.graphics.cancelWords()
        #expect(!m.primaryIsInert)
        #expect(m.graphics.draft.isEmpty)
    }

    @Test func changeWordsIsUndoable() {
        let m = GraphicsFixtures.changesGraphic(), undo = UndoManager()
        m.undoManager = undo
        m.graphics.changeWords(m, GraphicsFixtures.title)
        #expect(m.graphics.wordsNoteID == nil)
        #expect(m.graphics.graphics[0].resolvedWords["title"] == "Two years, alone.")
        #expect(undo.undoActionName == "Change Words")
        undo.undo()
        #expect(m.graphics.graphics[0].resolvedWords["title"] == "Two years.")
        undo.redo()
        #expect(m.graphics.graphics[0].resolvedWords["title"] == "Two years, alone.")
    }

    /// The real thing: a rendered title, the director's words, History, ⌘Z.
    @Test func changingWordsRerendersRecordsHistoryAndUndoes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("direction-words-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ProjectStore.create(at: directory.appendingPathComponent("Film.direction"), name: "Words")
        var format = EditOperation("format"); format.width = 640; format.height = 360
        _ = try store.apply(.init(baseEditRevision: store.revision(), operations: [format]))
        let (_, example) = try GraphicResources.example("title-card")
        let folder = store.graphicsFolder.appendingPathComponent("title", isDirectory: true)
        try FileManager.default.createDirectory(at: store.graphicsFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: example, to: folder)
        let runtime = try ToolRuntime(store: store)
        let note = try store.addComment(text: "Put a title over the cold open: two years.", sequenceID: nil, revision: store.revision())
        let made = try await GraphicMaker.make(store: store, name: "title", noteID: note.id, checkOnly: false, cacheDirectory: runtime.cacheDirectory)

        let m = FilmModel(), undo = UndoManager()
        m.runtime = runtime; m.undoManager = undo
        m.refresh(force: true)
        let g = try #require(m.graphics.graphics.first)
        #expect(g.render?.path == made.movie?.path)
        m.graphics.openWords(g, for: note)
        m.graphics.type("Two years, alone.", into: g.words[0])
        m.graphics.changeWords(m, g)
        #expect(m.graphics.isRendering(g))
        try await until { !m.graphics.isRendering(g) }
        #expect(m.error == nil, "\(m.error ?? "")")
        #expect(try store.graphic("title")?.resolvedWords["title"] == "Two years, alone.")
        #expect(m.events.contains { $0.summary == "You changed the words of the title" })
        #expect(try store.cuts().isEmpty)

        undo.undo()
        try await until { !m.graphics.isRendering(g) }
        #expect(try store.graphic("title")?.resolvedWords["title"] == "Two years.")
        #expect(try store.graphic("title")?.render?.path == made.movie?.path)
    }

    private func until(_ done: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !done() { try await Task.sleep(for: .milliseconds(50)) }
        #expect(done())
    }
}
