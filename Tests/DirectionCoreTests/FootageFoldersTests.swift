import Testing
import Foundation
@testable import DirectionCore

private let root = URL(fileURLWithPath: "/Volumes/Shoot/Launch film")
private func places(_ paths: [String], under r: URL = root) -> [String: FootagePlace] {
    FootageFolders.places(paths.map { (r.appendingPathComponent($0), r) })
}
private func place(_ path: String, _ all: [String: FootagePlace]) -> FootagePlace? { all[root.appendingPathComponent(path).path] }

@Test func scenesSetupsAndTakesComeFromTheDirectorsFolders() {
    let all = places([
        "Footage/01 Intro/A Talking head/T1.mov", "Footage/01 Intro/A Talking head/T2.mov",
        "Footage/01 Intro/B Screen/Screen Recording.mov",
        "Footage/Scene 2 - Pricing/2A - Wide/S02_A_T03.mov", "Footage/Scene 2 - Pricing/2A - Wide/S02_A_T04.mov",
        "Footage/S03_the_ending/Close/MVI_0001.MP4", "Footage/S03_the_ending/Close/MVI_0002.MP4", "Footage/S03_the_ending/Wide/MVI_0005.MP4",
        "Footage/s04/take 2.mov",
        "loose.mov", "B-roll/drone.mov", "2026-10-18/clip.mov", "4K exports/final.mov",
    ])
    #expect(place("Footage/01 Intro/A Talking head/T2.mov", all) == FootagePlace(scene: 1, sceneTitle: "Intro", setup: "A", setupDescription: "Talking head", take: 2, folder: "01 Intro/A Talking head"))
    #expect(place("Footage/01 Intro/B Screen/Screen Recording.mov", all)?.setupCode == "1B")
    #expect(place("Footage/01 Intro/B Screen/Screen Recording.mov", all)?.take == 1)
    let wide = place("Footage/Scene 2 - Pricing/2A - Wide/S02_A_T04.mov", all)
    #expect(wide?.sceneTitle == "Pricing" && wide?.setupCode == "2A" && wide?.setupDescription == "Wide" && wide?.take == 4)
    // Unlettered setups take letters in name order; takes without numbers are numbered in name order.
    let close = place("Footage/S03_the_ending/Close/MVI_0002.MP4", all)
    #expect(close?.sceneTitle == "the ending" && close?.setup == "A" && close?.setupDescription == "Close" && close?.take == 2)
    #expect(place("Footage/S03_the_ending/Wide/MVI_0005.MP4", all)?.setup == "B")
    // A file right in a scene folder has a scene and no setup.
    let s4 = place("Footage/s04/take 2.mov", all)
    #expect(s4?.scene == 4 && s4?.sceneTitle == "Scene 4" && s4?.setup == nil && s4?.take == 2)
    // Not scenes: loose files, unnumbered folders, dates, resolutions.
    for path in ["loose.mov", "B-roll/drone.mov", "2026-10-18/clip.mov", "4K exports/final.mov"] { #expect(place(path, all) == nil) }
}

@Test func aDroppedSceneFolderCountsAndCameraCardsArePassedOver() {
    let scene = URL(fileURLWithPath: "/Users/d/Shoot/02 Pricing")
    let all = places(["A Cam/DCIM/100CANON/MVI_0001.MP4", "B Cam/PRIVATE/M4ROOT/CLIP/C0004.MP4"], under: scene)
    let a = all[scene.appendingPathComponent("A Cam/DCIM/100CANON/MVI_0001.MP4").path]
    #expect(a?.scene == 2 && a?.setupCode == "2A" && a?.setupDescription == "A Cam" && a?.folder == "02 Pricing/A Cam")
    #expect(all[scene.appendingPathComponent("B Cam/PRIVATE/M4ROOT/CLIP/C0004.MP4").path]?.setupCode == "2B")
    // A camera folder above the scenes is the setup.
    let byCamera = places(["Cam B/03 Outro/C0001.MP4"])
    #expect(place("Cam B/03 Outro/C0001.MP4", byCamera)?.setupCode == "3B")
}

@Test func namesReadAsScenesSetupsAndTakes() {
    #expect(FootageFolders.scene("01 Intro")! == (1, "Intro"))
    #expect(FootageFolders.scene("Sc4")! == (4, "Scene 4"))
    for name in ["1080p", "2026 shoot", "10-18 shoot", "Session 1", "Day 2", "Selects"] { #expect(FootageFolders.scene(name) == nil) }
    #expect(FootageFolders.setup("Setup C") == ("C", ""))
    #expect(FootageFolders.setup("Camera B") == ("B", "Camera B"))
    #expect(FootageFolders.setup("A_Close") == ("A", "Close"))
    #expect(FootageFolders.setup("Talking head") == ("", "Talking head"))
    #expect(FootageFolders.take("Take 03") == 3 && FootageFolders.take("intro_take2") == 2 && FootageFolders.take("1A-3") == 3)
    for name in ["MVI_0001", "C0004", "Test 1", "GX010001", "A001C003_220101"] { #expect(FootageFolders.take(name) == nil) }
    #expect(FootageFolders.isCard("100CANON") && FootageFolders.isCard("DCIM") && !FootageFolders.isCard("A Cam"))
}

@Test func filedTakesKeepTheirPlaceWhenTheEditorLogs() throws {
    let store = try seededStore(), id = "asset-fixture"
    let p = FootagePlace(scene: 2, sceneTitle: "Pricing", setup: "A", setupDescription: "", take: 3, folder: "02 Pricing/A")
    let filed = try store.fileTakes([id: p])
    let scene = try #require(filed.scenes.first)
    #expect(scene.number == 2 && scene.title == "Pricing" && scene.folder == "02 Pricing" && scene.setups == [DailiesSetup(code: "2A", description: "")])
    #expect(filed.takes[id]?.sceneID == scene.id && filed.takes[id]?.setupCode == "2A" && filed.takes[id]?.code == "T3" && filed.takes[id]?.folder == "02 Pricing/A")

    // The editor puts it elsewhere and renames the scene: the folders win; its caption, its description of the setup and its new scene go in.
    var t = filed.takes[id]!; t.sceneID = "scene-9"; t.setupCode = "9A"; t.code = "T1"; t.caption = "\u{201C}It costs less than lunch.\u{201D}"
    var renamed = scene; renamed.title = "Price talk"; renamed.setups = [DailiesSetup(code: "2A", description: "Talking head, close"), DailiesSetup(code: "2B", description: "Slides")]
    let logged = try store.logDailies(Dailies(scenes: [renamed, DailiesScene(id: "scene-9", number: 9, title: "Extras")], takes: [id: t]))
    let kept = try #require(logged.scenes.first { $0.id == scene.id })
    #expect(kept.title == "Pricing" && kept.folder == "02 Pricing")
    #expect(kept.setups == [DailiesSetup(code: "2A", description: "Talking head, close"), DailiesSetup(code: "2B", description: "Slides")])
    #expect(logged.takes[id]?.sceneID == scene.id && logged.takes[id]?.setupCode == "2A" && logged.takes[id]?.code == "T3")
    #expect(logged.takes[id]?.caption == "\u{201C}It costs less than lunch.\u{201D}")

    // The director can still move it, and filing again leaves a take that's in a scene where it is.
    try store.setTakeScene(assetID: id, sceneID: "scene-9")
    let again = try store.fileTakes([id: p])
    #expect(again.takes[id]?.sceneID == "scene-9")
}
