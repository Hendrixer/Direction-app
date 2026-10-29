import Testing
import Foundation
@testable import DirectionCore

/// The director's look in the store (specs/looks.md): film and scene looks, the renderer's context,
/// camera LUTs, and the rule that only the director sets a look.
@Suite("Looks in the store")
struct LookStoreTests {
    struct World {
        let root: URL
        let store: ProjectStore
        let looks: URL
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    func world() throws -> World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-look-store-" + UUID().uuidString)
        let store = try ProjectStore.create(at: root.appendingPathComponent("Launch film.direction"), name: "Launch film")
        for (i, id) in ["take-1", "take-2", "take-3", "take-loose"].enumerated() {
            _ = try store.addAsset(MediaAsset(id: id, name: "A00\(i).mov", path: "/fixture/\(id).mov", duration: .init(seconds: 10), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)]), append: false, expectedRevision: try store.revision())
        }
        var takes: [String: TakeInfo] = [:]
        for (id, scene) in [("take-1", "scene-1"), ("take-2", "scene-3"), ("take-3", "scene-3")] { var t = TakeInfo(assetID: id); t.sceneID = scene; takes[id] = t }
        _ = try store.logDailies(Dailies(scenes: [DailiesScene(id: "scene-1", number: 1, title: "Cold open"), DailiesScene(id: "scene-3", number: 3, title: "The ridge")], takes: takes))
        let looks = root.appendingPathComponent("Looks")
        try FileManager.default.createDirectory(at: looks.appendingPathComponent("Camera"), withIntermediateDirectories: true)
        return World(root: root, store: store, looks: looks)
    }

    @Test func contextMapsTakesToScenesAndPicksTheScenesOwnLook() throws {
        let w = try world(); defer { w.cleanup() }
        #expect(try w.store.lookContext(looksFolder: w.looks, convertLog: true) == nil)
        let film = LookSettings(name: "Window light", filters: ["grain": 0.4, "halation": 0.3, "vignette": 0.2], options: ["grain": "fine"])
        try w.store.setLook(film, asDirector: true)
        try w.store.setLook(LookSettings(name: "Bleach bypass", filters: ["blackAndWhite": 0.6]), sceneID: "scene-3", asDirector: true)
        let context = try #require(try w.store.lookContext(looksFolder: w.looks, convertLog: true))
        #expect(context.sceneForAsset == ["take-1": "scene-1", "take-2": "scene-3", "take-3": "scene-3"])
        #expect(context.look.look(forScene: context.sceneForAsset["take-1"])?.name == "Window light")
        #expect(context.look.look(forScene: context.sceneForAsset["take-3"])?.name == "Bleach bypass")
        #expect(context.look.look(forScene: context.sceneForAsset["take-loose"])?.name == "Window light")
        #expect(film.active.map(\.filter) == [.halation, .vignette, .grain])

        // "Use the film's look" takes the scene's own away; None gives the scene no look at all.
        try w.store.setLook(nil, sceneID: "scene-3", asDirector: true)
        #expect(try w.store.filmLook().scenes.isEmpty)
        try w.store.setLook(.noLook, sceneID: "scene-3", asDirector: true)
        #expect(try w.store.lookContext(looksFolder: w.looks, convertLog: true)?.look.look(forScene: "scene-3")?.isNone == true)
        // None for the whole film clears it.
        try w.store.setLook(.noLook, asDirector: true)
        #expect(try w.store.filmLook().film == nil)
    }

    @Test func onlyTheDirectorSetsTheLookAndEachChangeIsInHistory() throws {
        let w = try world(); defer { w.cleanup() }
        do { try w.store.setLook(LookSettings(name: "Mine"), asDirector: false); Issue.record("The editor can't set the look") }
        catch let e as DirectionError { #expect(e.code == "look_is_yours") }
        #expect(try w.store.filmLook().film == nil)
        try w.store.setLook(LookSettings(name: "Print film"), asDirector: true)
        try w.store.setLook(LookSettings(name: "Muted"), sceneID: "scene-3", asDirector: true)
        let summaries = try w.store.events().filter { $0.kind == "look.updated" }.map(\.summary)
        #expect(summaries == ["Changed the look of the film", "Changed the look of scene 3"])
        do { try w.store.setLook(LookSettings(name: "Lost"), sceneID: "scene-9", asDirector: true); Issue.record("Unknown scene") }
        catch let e as DirectionError { #expect(e.code == "scene_not_found") }
    }

    @Test func aChosenFolderLUTIsCopiedIntoTheFilm() throws {
        let w = try world(); defer { w.cleanup() }
        let source = w.looks.appendingPathComponent("Print film.cube")
        try "LUT_1D_SIZE 17\n".write(to: source, atomically: true, encoding: .utf8)
        try w.store.setLook(LookSettings(name: "Print film", lut: source.path, strength: 0.8, by: "folder"), asDirector: true)
        let kept = try #require(try w.store.filmLook().film?.lut)
        #expect(kept == w.store.filmLooksFolder.appendingPathComponent("Print film.cube").path)
        // The film keeps working when the folder changes.
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: kept))
        #expect(try w.store.filmLook().film?.strength == 0.8)
    }

    @Test func cameraLUTsFollowTheSettingAndTheEditorsChoice() throws {
        let w = try world(); defer { w.cleanup() }
        try w.store.recordLogDetection(["take-1": "Apple Log", "take-2": "", "take-3": "S-Log3"])
        try "LUT_3D_SIZE 17\n".write(to: w.looks.appendingPathComponent("Camera/Apple Log.cube"), atomically: true, encoding: .utf8)
        let on = try #require(try w.store.lookContext(looksFolder: w.looks, convertLog: true))
        // S-Log3 has no camera LUT in the folder, so it plays as shot.
        #expect(on.cameraLUTs == ["take-1": w.looks.appendingPathComponent("Camera/Apple Log.cube").path])
        #expect(try w.store.lookContext(looksFolder: w.looks, convertLog: false) == nil)
        try w.store.setCameraLUT(assetID: "take-1", lut: "none")
        try w.store.setCameraLUT(assetID: "take-2", lut: "/LUTs/Custom.cube")
        #expect(try w.store.lookContext(looksFolder: w.looks, convertLog: true)?.cameraLUTs == ["take-2": "/LUTs/Custom.cube"])
        try w.store.setCameraLUT(assetID: "take-1", lut: "auto")
        #expect(try w.store.lookContext(looksFolder: w.looks, convertLog: true)?.cameraLUTs["take-1"] != nil)
        do { try w.store.setCameraLUT(assetID: "take-1", lut: "warm"); Issue.record("Not a LUT") }
        catch let e as DirectionError { #expect(e.code == "bad_argument") }
    }

    @Test func settingsHaveDefaultsAndTestsCanMoveTheFolder() {
        #expect(SharedSettings.defaultLooksFolder.hasSuffix("/Movies/Direction/Looks"))
        #expect(LookFilter.allCases.map(\.label) == ["Black and white", "Split tone", "Fade", "Halation", "Bloom", "Soften", "Chromatic aberration", "Vignette", "Grain", "Gate weave", "Letterbox"])
        #expect(LookFilter.splitTone.options.map(LookFilter.optionLabel) == ["Warm·Teal", "Cool·Amber"])
        #expect(LookFilter.grain.options.map(LookFilter.optionLabel) == ["Fine", "Medium", "Coarse"])
    }
}
