import Testing
import Foundation
import CoreGraphics
import ImageIO
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

    @Test func theSheetRendersTheFilmsOwnFramesWithTheDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-looks-frames-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A still on the cut: a warm half and a cool half.
        let space = CGColorSpace(name: CGColorSpace.itur_709)!
        let c = CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 1280, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.3, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 160, height: 180))
        c.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1)); c.fill(CGRect(x: 160, y: 0, width: 160, height: 180))
        let still = root.appendingPathComponent("frame.png")
        let dest = CGImageDestinationCreateWithURL(still as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, c.makeImage()!, nil); CGImageDestinationFinalize(dest)
        let store = try ProjectStore.create(at: root.appendingPathComponent("Film.direction"), name: "Film")
        let runtime = try ToolRuntime(store: store)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(still.path), "append": .bool(true)]))

        let m = FilmModel(preview: false)
        m.runtime = runtime
        m.refresh(force: true)
        m.looks.draft = LookSettings(name: "Mono", filters: ["blackAndWhite": 1])
        m.looks.loadFrames(m)
        for _ in 0..<200 where m.looks.rendered.picture == nil || m.looks.rendered.stills.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        let picture = try #require(m.looks.rendered.picture), plain = try #require(m.looks.rendered.plain)
        #expect(m.looks.rendered.stills.count == 1 && m.looks.rendered.tiles["none"] != nil)
        // The draft is black and white; the plain picture isn't.
        func pixel(_ image: CGImage, _ x: Int) -> (Int, Int, Int) {
            var p = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &p, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: -x, y: -image.height / 2, width: image.width, height: image.height))
            return (Int(p[0]), Int(p[1]), Int(p[2]))
        }
        let graded = pixel(picture, picture.width / 4), original = pixel(plain, plain.width / 4)
        #expect(abs(graded.0 - graded.2) < 4 && original.0 - original.2 > 60, "\(graded) \(original)")
        m.close()
    }

    @Test func tileNamesWrapWordByWordLikeTheFrame() {
        #expect(LookSheet.wrapped("Window light, warmer", width: 104) == ["Window light,", "warmer"])
        #expect(LookSheet.wrapped("Teal & amber", width: 104) == ["Teal & amber"])
    }
}
