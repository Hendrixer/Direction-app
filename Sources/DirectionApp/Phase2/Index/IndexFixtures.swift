import SwiftUI
import DirectionCore

/// Frames 54, 59 and 60 (design/spec/frames.js). 54 is also registered by the System group,
/// which wins in the registry; both draw the same pane.
@MainActor
enum IndexFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "59-dailies-shots": {
                let m = DailiesFixtures.film()
                m.selectedSceneID = "scene-2"
                m.openTakeID = "take-2a-t3"
                m.index.previewShots["take-2a-t3"] = shots
                m.index.previewSounds["take-2a-t3"] = sounds
                return DailiesFixtures.scene(m, DailiesPreview(art: DailiesFixtures.art, takePosition: SampleFilm.tc(0, 19, 2), takePlaying: true))
            },
            "60-dailies-search": {
                let m = searchFilm()
                return DailiesFixtures.scene(m, DailiesPreview(art: DailiesFixtures.art))
            },
        ]
    }

    static func tc(_ s: Int, _ f: Int) -> Double { SampleFilm.tc(0, s, f) }

    /// 2A T3's four shots, as Direction found and described them.
    static var shots: [Shot] {
        [
            Shot(id: "shot-2a-t3-1", assetID: "take-2a-t3", number: 1, start: 0, end: tc(9, 12), keyframes: ["preview:room:1:0.5:0.5:1"], look: ShotLook(description: "Wide on Maya at the window. She settles in.", size: "wide", movement: "static", people: ["woman, dark hair"], setting: "office, dusk")),
            Shot(id: "shot-2a-t3-2", assetID: "take-2a-t3", number: 2, start: tc(9, 12), end: tc(22, 20), keyframes: ["preview:room:1.45:0.68:0.42:0.85"], look: ShotLook(description: "Push in to a medium. Window light on her face.", size: "medium", movement: "push", people: ["woman, dark hair"], setting: "office, dusk")),
            Shot(id: "shot-2a-t3-3", assetID: "take-2a-t3", number: 3, start: tc(22, 20), end: tc(36, 4), keyframes: ["preview:room:1.75:0.70:0.40:0.85"], look: ShotLook(description: "Medium on Maya. She looks down, then out the window.", size: "medium", movement: "static", people: ["woman, dark hair"], setting: "office, dusk")),
            Shot(id: "shot-2a-t3-4", assetID: "take-2a-t3", number: 4, start: tc(36, 4), end: 46, keyframes: ["preview:room:1.75:0.70:0.40:0.72"], look: ShotLook(description: "Medium on Maya. She laughs and looks away.", size: "medium", movement: "static", people: ["woman, dark hair"], setting: "office, dusk", flags: ["soft"])),
        ]
    }

    /// The sounds lane in frame 59: her lines, then the laugh.
    static var sounds: [IndexSound] {
        [(2.0, 5.0), (7.0, 10.5), (12.0, 16.0), (19.0, 22.5), (31.0, 34.5), (38.0, 40.5)].map { IndexSound(assetID: "take-2a-t3", start: $0.0, end: $0.1, kind: .speech, label: "speech", confidence: 0.9) }
            + [IndexSound(assetID: "take-2a-t3", start: 41.0, end: 43.5, kind: .laughter, label: "laughter", confidence: 0.8)]
    }

    /// Frame 60: "Maya laughing" while 126 takes are still being looked at.
    static func searchFilm() -> FilmModel {
        let m = DailiesFixtures.film()
        m.selectedSceneID = "scene-2"
        var p = m.project!, d = m.dailies
        // Takes the frame shows that 07 doesn't, in place of three of the shoot's other takes so the
        // footer still reads 214 takes · 3 h 12 m.
        let spare = p.assets.filter { $0.id.hasPrefix("take-filler-") }.suffix(3)
        p.assets.removeAll { a in spare.contains { $0.id == a.id } }
        for s in spare { d.takes[s.id] = nil }
        for ((id, file, scene, setup, code), old) in zip([("take-4c-t1", "C002_C002_1024.mov", 4, "4C", "T1"), ("take-4b-t3", "A014_C009_1022.mov", 4, "4B", "T3"), ("take-5a-t1", "C004_C029_1026.mov", 5, "5A", "T1")], spare) {
            p.assets.append(DailiesFixtures.asset(id, file, old.duration.seconds))
            var t = TakeInfo(assetID: id); t.sceneID = "scene-\(scene)"; t.setupCode = setup; t.code = code; t.caption = "Coverage."
            d.takes[id] = t
        }
        // The frame's circles and diamonds: 4C T2 circled, 4A T1 not; counts stay 7 and 6.
        d.takes["take-4c-t2"]?.circled = true; d.takes["take-4c-t2"]?.suggestion = nil
        d.takes["take-4a-t1"]?.circled = false
        d.takes["take-filler-10"]?.suggestion = "Cleanest of the team shots."
        m.project = p; m.displayed = p; m.dailies = d

        let i = m.index
        i.searching = true
        i.query = "Maya laughing"; i.searchedQuery = "Maya laughing"
        i.previewStillLooking = 126
        func hit(_ asset: String, _ start: Double, _ end: Double, _ text: String, _ matched: [String], _ why: FootageSearch.Why, _ frame: String) -> FootageSearch.Hit {
            FootageSearch.Hit(shotID: "shot-\(asset)-\(Int(start))", assetID: asset, score: 0.8, why: why, text: text, matched: matched, start: start, end: end, keyframes: [frame])
        }
        i.results = [
            hit("take-2a-t3", tc(36, 4), 46, "Medium on Maya. She laughs and looks away.", ["Maya", "laughs"], .picture, "preview:room:1.75:0.70:0.40:0.85"),
            hit("take-2a-t2", tc(37, 10), 44, "Maya laughs, then looks to the window.", ["Maya", "laughs"], .picture, "preview:room:1.5:0.70:0.40:1"),
            hit("take-2b-t1", tc(12, 4), tc(16, 20), "\u{201C}I remember laughing at the first version.\u{201D}", ["laughing"], .words, "preview:hands:1:0.5:0.5:1"),
            hit("take-2b-t3", tc(2, 0), tc(6, 12), "Over her shoulder. Maya laughs at the screen.", ["Maya", "laughs"], .picture, "preview:hands:1:0.5:0.5:0.85"),
            hit("take-4c-t2", tc(4, 8), tc(11, 0), "Maya laughs with the team at the table.", ["Maya", "laughs"], .picture, "preview:hands:1.3:0.5:0.7:1.05"),
            hit("take-4c-t1", tc(15, 2), tc(19, 16), "Wide on the team. Maya laughs at a joke.", ["Maya", "laughs"], .picture, "preview:hands:1:0.5:0.5:0.85"),
            hit("take-4b-t3", tc(21, 12), tc(25, 4), "\u{201C}We were all laughing at that bug.\u{201D}", ["laughing"], .words, "preview:hands:1:0.5:0.5:0.95"),
            hit("take-5a-t3", tc(8, 20), tc(14, 2), "Maya and the team laughing in the office.", ["Maya", "laughing"], .picture, "preview:day:1:0.5:0.5:1"),
            hit("take-5a-t1", tc(30, 6), tc(33, 18), "\u{201C}Maya, stop laughing, we\u{2019}re live.\u{201D}", ["Maya", "laughing"], .words, "preview:day:1:0.5:0.5:0.85"),
        ]
        return m
    }
}
