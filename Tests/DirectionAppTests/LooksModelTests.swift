import Testing
import Foundation
import DirectionCore
@testable import DirectionApp
@testable import DirectionTools

@Suite("Looks in the app")
@MainActor
struct LooksModelTests {
    @Test func theSheetOpensOnTheEditorsLookAndPreviewsWithoutChangingTheFilm() {
        let m = LooksFixtures.lookSheet()
        let l = m.looks
        #expect(m.sheet == .look)
        #expect(l.draft.name == "Window light")
        #expect(LookFilter.allCases.filter(l.isOn) == [.halation, .vignette, .grain])
        #expect(l.amount(.grain) == 0.4 && l.option(.grain) == "fine")
        #expect(l.currentTileID == nil) // The film has no look: None is Current.
        #expect(l.rendered.picture != nil && l.rendered.tiles.count == 8 && l.rendered.stills.count == 5)

        // Switching a filter off and on keeps its amount; a folder LUT keeps the filters.
        l.setOn(.grain, false); #expect(!l.isOn(.grain))
        l.setOn(.grain, true); #expect(l.amount(.grain) == 0.4)
        let print = l.allEntries.first { $0.name == "Print film" }
        l.select(print)
        #expect(l.draft.lut == print?.settings.lut && l.isOn(.halation))
        #expect(m.looks.look.film == nil)
    }

    @Test func useThisLookIsOneUndoableActForTheFilmOrAScene() {
        let m = LooksFixtures.lookSheet()
        let undo = UndoManager(); undo.groupsByEvent = false; m.undoManager = undo
        undo.beginUndoGrouping(); m.looks.use(m); undo.endUndoGrouping()
        #expect(m.sheet == nil)
        #expect(m.looks.look.film?.name == "Window light")
        #expect(undo.undoActionName == "Change Look")
        undo.undo()
        #expect(m.looks.look.film == nil)
        undo.redo()
        #expect(m.looks.look.film?.name == "Window light")

        // A scene with its own look, then back to the film's.
        m.looks.open(m)
        m.looks.setApplyTo("scene-3")
        m.looks.select(m.looks.allEntries.first { $0.name == "Muted" })
        undo.beginUndoGrouping(); m.looks.use(m); undo.endUndoGrouping()
        #expect(m.looks.look.scenes["scene-3"]?.name == "Muted")
        m.looks.open(m); m.looks.setApplyTo("scene-3")
        #expect(m.looks.sceneHasOwnLook("scene-3"))
        m.looks.chooseFilmLook()
        undo.beginUndoGrouping(); m.looks.use(m); undo.endUndoGrouping()
        #expect(m.looks.look.scenes["scene-3"] == nil)
        undo.undo()
        #expect(m.looks.look.scenes["scene-3"]?.name == "Muted")
    }

    @Test func theDirectorsActIsStoredWithHistoryAndUndo() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("direction-looks-app-" + UUID().uuidString + ".direction")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try ProjectStore.create(at: path, name: "Launch film")
        _ = try store.logDailies(Dailies(scenes: [DailiesScene(id: "scene-3", number: 3, title: "The ridge")], takes: [:]))
        let m = FilmModel(preview: false)
        m.runtime = try ToolRuntime(store: store)
        m.refresh(force: true)
        let undo = UndoManager(); undo.groupsByEvent = false; m.undoManager = undo

        undo.beginUndoGrouping(); m.setLook(LookSettings(name: "Window light", filters: ["grain": 0.4]), sceneID: nil); undo.endUndoGrouping()
        undo.beginUndoGrouping(); m.setLook(LookSettings(name: "Muted", filters: ["fade": 0.3]), sceneID: "scene-3"); undo.endUndoGrouping()
        #expect(try store.filmLook().film?.name == "Window light")
        #expect(m.looks.look.scenes["scene-3"]?.name == "Muted")
        let history = try store.events().filter { $0.kind == "look.updated" }.map(\.summary)
        #expect(history == ["Changed the look of the film", "Changed the look of scene 3"])
        undo.undo()
        #expect(try store.filmLook().scenes.isEmpty)
        undo.undo()
        #expect(try store.filmLook().film == nil)
        m.close()
    }

    @Test func tileNamesWrapWordByWordLikeTheFrame() {
        #expect(LookSheet.wrapped("Window light, warmer", width: 104) == ["Window light,", "warmer"])
        #expect(LookSheet.wrapped("Teal & amber", width: 104) == ["Teal & amber"])
    }
}
