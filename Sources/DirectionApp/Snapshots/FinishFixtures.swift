import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent (34–38). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum FinishFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "34-lock-scenes": { .film(lockingScenes()) },
            "35-lock-picture": { let m = lockingScenes(); m.sheet = .lockPicture; return .film(m) },
            "36-finish": { .film(finishing()) },
            "37-export": { let m = finishing(); m.sheet = .deliver; DeliveredPreview.check = nil; return .film(m) },
            // The check found the mix quiet and a crop that loses a face.
            "37-export-checks": {
                let m = finishing(); m.sheet = .deliver
                DeliveredPreview.check = .object(["ready": .bool(false), "loudness": .object(["ready": .bool(false), "target": .number(-14), "ceiling": .number(-1), "integratedLUFS": .number(-19.2), "truePeakDBTP": .number(-6.4), "says": .string("The mix is \u{2212}19.2 LUFS, 5.2 LU under the \u{2212}14 LUFS target.")]),
                                                  "framing": .array([.object(["kind": .string("faceLost"), "at": .number(42), "says": .string("At 0:42 the frame loses the face in 2C Take 3: the crop leaves it out.")])])])
                return .film(m)
            },
            "38-delivered": { .film(delivered()) },
        ]
    }

    /// Every answer in Cut 4 accepted (B used for note 2).
    static func allAccepted(room: Room) -> FilmModel {
        let m = ChangesFixtures.cut4(room: room)
        for n in [1, 3, 4, 5, 6, 7] { ChangesFixtures.accept(m, n) }
        ChangesFixtures.accept(m, 2, pick: "B")
        return m
    }

    static func lock(_ m: FilmModel, _ numbers: Set<Int>) {
        for i in m.dailies.scenes.indices { m.dailies.scenes[i].locked = numbers.contains(m.dailies.scenes[i].number) }
    }

    // 34: nothing left to review; 3 of 5 scenes locked, The ridge under the pointer.
    static func lockingScenes() -> FilmModel {
        let m = allAccepted(room: .cut)
        lock(m, [1, 2, 5])
        m.changes.lockSceneID = "scene-3"
        m.position = SampleFilm.tc(1, 30, 0)
        return m
    }

    static let sampleFinishing: [FinishingItem] = [
        .init(id: "color", title: "Color", detail: "Matched shots across all five scenes to the window-light reference. Night exteriors lifted half a stop.", state: "done", by: ["editor"]),
        .init(id: "sound", title: "Sound mix", detail: "Dialogue first, music under. Mixing to \u{2212}14 LUFS for web and \u{2212}24 for broadcast.", state: "working", by: ["editor"], progress: 0.62),
        .init(id: "captions", title: "Captions", detail: "41 English captions. Check the spelling of names: Maya Okafor, Priya Shah.", state: "needsYou", by: ["editor", "you"]),
        .init(id: "titles", title: "Titles and credits", detail: "Opening title off. End card: logo on black, 3 s. Credits not written yet.", state: "todo", by: ["you"]),
        .init(id: "licenses", title: "Music licenses", detail: "2 tracks. \u{201C}Slow Rooms\u{201D} is licensed. \u{201C}North Light\u{201D} needs a license before you publish.", state: "blocked", by: ["you"]),
        .init(id: "deliver", title: "Deliver", detail: "Master and web from the locked cut. You can deliver now; open items are listed first.", state: "todo", by: ["editor", "you"]),
    ]

    // 36: picture locked on Cut 4, the editor mixing sound.
    static func finishing() -> FilmModel {
        let m = allAccepted(room: .finish)
        lock(m, [1, 2, 3, 4, 5])
        m.directing.pictureLocked = true
        m.directing.pictureLockedAt = SampleFilm.date(10, 28, 15, 2)
        m.directing.pictureLockedCutID = "cut-4"
        m.directing.finishing = sampleFinishing
        m.position = SampleFilm.tc(2, 58, 0)
        return m
    }

    // 38: four written to Movies › Launch film › Delivery, the last a folder for another editing app.
    static func delivered() -> FilmModel {
        let m = finishing()
        let folder = DeliveryFormat.defaultFolder(film: "Launch film")
        let names = ["Launch film \u{2013} Master.mov", "Launch film \u{2013} Web.mp4", "Launch film \u{2013} Captions.srt", "Launch film \u{2013} Timeline"]
        DeliveredPreview.sizes = [names[0]: 3_710_000_000, names[1]: 176_000_000, names[2]: 8_200, names[3]: 412_000_000]
        m.directing.deliveredPaths = names.map { folder.appendingPathComponent($0).path }
        m.directing.deliveredAt = SampleFilm.date(10, 28, 16, 40)
        m.directing.finishing = sampleFinishing.map { item in var i = item; if i.id == "deliver" { i.state = "done" }; return i }
        m.position = m.duration
        return m
    }
}
