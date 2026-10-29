import SwiftUI
import DirectionCore

// Owner: Start agent (07–09). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum DailiesFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "07-dailies": {
                let m = film()
                m.selectedSceneID = "scene-2"
                return scene(m, DailiesPreview(art: art, hoverTakeID: "take-2a-t3"))
            },
            "07-dailies-first-circle": {
                // Before anything is circled: the how-to line, and the bar for the selected take.
                let m = film()
                m.selectedSceneID = "scene-2"
                var d = m.dailies
                for id in d.takes.keys { d.takes[id]?.circled = false }
                m.dailies = d
                return scene(m, DailiesPreview(art: art, selectedTakeID: "take-2a-t3"))
            },
            "08-dailies-take": {
                let m = film()
                m.selectedSceneID = "scene-2"
                m.openTakeID = "take-2a-t3"
                return scene(m, DailiesPreview(art: art, takePosition: SampleFilm.tc(0, 19, 2), takePlaying: true))
            },
            "08-dailies-take-synced": {
                // 2A T3 and 2B T2 recorded the same moment: the Angles row, and the line on each card.
                let m = film()
                m.selectedSceneID = "scene-2"
                m.openTakeID = "take-2a-t3"
                var d = m.dailies
                d.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "take-2a-t3", takes: [SyncedTake(assetID: "take-2a-t3", offset: 0, match: 1), SyncedTake(assetID: "take-2b-t2", offset: 0.089, match: 0.99)], method: "sound", createdAt: 0)]
                m.dailies = d
                return scene(m, DailiesPreview(art: art, takePosition: SampleFilm.tc(0, 19, 2), takePlaying: false))
            },
            "09-dailies-unsorted": {
                let m = film()
                m.selectedSceneID = DailiesBin.unsorted
                return scene(m, DailiesPreview(art: art, draggingTakeID: "unsorted-3", dropSceneID: "scene-4"))
            },
        ]
    }

    static func scene(_ m: FilmModel, _ preview: DailiesPreview) -> SnapshotScene {
        SnapshotScene(FilmWindow(app: nil, model: m).environment(\.dailiesPreview, preview))
    }

    /// Launch film before its first cut: 214 takes logged into five scenes, 14 unsorted, 9 set aside, 7 circled.
    static func film() -> FilmModel {
        let m = SampleFilm.make(room: .dailies)
        m.cuts = []; m.notes = []
        m.onboardingDismissed = true
        var p = m.project!
        p.sequences[0].clips = []
        var d = m.dailies
        // Nothing is locked before the first cut. The frame's circles: two in scene 4, none in Launch day.
        for i in d.scenes.indices { d.scenes[i].locked = false }
        d.takes["take-5b-t1"]?.circled = false
        d.takes["take-4b-t1"]?.circled = true
        d.takes["take-2a-t3"]?.suggestion = "warmest read\nWarmest read of the line, and she holds the look after it for two seconds. Fits \u{201C}tired, then proud.\u{201D} T2, your circle, is a little faster."

        for u in unsorted {
            p.assets.append(asset(u.id, u.file, u.duration))
            var t = TakeInfo(assetID: u.id); t.caption = u.caption; t.guessSceneID = u.guess.map { "scene-\($0)" }; t.flags = u.flags
            d.takes[u.id] = t
        }
        // The rest of the shoot, so the counts read like a real day: 214 takes, 3 h 12 m.
        let fillerScenes: [(Int, [String])] = [(1, ["1A", "1B"]), (3, ["3A", "3B"]), (4, ["4A", "4B", "4C"]), (5, ["5A", "5B"])]
        let count = 214 - p.assets.count, seconds = 11_520 - Int(p.assets.reduce(0) { $0 + $1.duration.seconds })
        for i in 0..<count {
            let (scene, setups) = fillerScenes[i % fillerScenes.count]
            let id = "take-filler-\(i)", setup = setups[(i / fillerScenes.count) % setups.count]
            let duration = i == count - 1 ? seconds - (count - 1) * (seconds / count) : seconds / count
            p.assets.append(asset(id, String(format: "F%03d_C%03d_1022.mov", i / 20 + 20, i % 20 + 1), Double(duration)))
            var t = TakeInfo(assetID: id); t.sceneID = "scene-\(scene)"; t.setupCode = setup; t.code = "T\(i / 8 + 6)"; t.caption = "Coverage."
            t.unusable = i < 8
            if i == 9 { t.suggestion = "Steadiest of the wides." }
            d.takes[id] = t
        }
        m.project = p; m.displayed = p
        m.dailies = d
        m.transcripts = transcripts
        return m
    }

    static func asset(_ id: String, _ file: String, _ duration: Double) -> MediaAsset {
        MediaAsset(id: id, name: file, path: "/Volumes/Shoot SSD/\(file)", duration: .init(seconds: duration), video: [.init(id: 1, width: 3840, height: 2160, frameRate: 23.976)], audio: [.init(id: 2, index: 0, label: "Lav", channels: 1, sampleRate: 48_000)])
    }

    struct Unsorted { var id: String; var file: String; var duration: Double; var caption: String; var guess: Int?; var flags: [String] = []; var art: FootageArt }
    static let unsorted: [Unsorted] = [
        .init(id: "unsorted-1", file: "A016_C001_1022.mov", duration: 21, caption: "Whiteboard, wide, no dialogue", guess: 4, art: .hands),
        .init(id: "unsorted-2", file: "A016_C002_1022.mov", duration: 8, caption: "Coffee pour, close", guess: 4, art: .hands),
        .init(id: "unsorted-3", file: "B001_C009_1018.mov", duration: 16, caption: "Street, car passing", guess: nil, art: .night),
        .init(id: "unsorted-4", file: "C004_C010_1026.mov", duration: 33, caption: "Office, people arriving", guess: 5, art: .day),
        .init(id: "unsorted-5", file: "A011_C009_1021.mov", duration: 52, caption: "Interview, room tone only", guess: nil, flags: ["Room tone"], art: .room),
        .init(id: "unsorted-6", file: "B003_C020_1019.mov", duration: 41, caption: "Ridge, drone, high", guess: 3, art: .dusk),
        .init(id: "unsorted-7", file: "B003_C021_1019.mov", duration: 12, caption: "Ridge, lens flare test", guess: nil, flags: ["Camera test?"], art: .dusk),
        .init(id: "unsorted-8", file: "A013_C004_1021.mov", duration: 72, caption: "Maya, phone call, partial", guess: 2, art: .room),
        .init(id: "unsorted-9", file: "C002_C007_1024.mov", duration: 27, caption: "Team, laughing at desk", guess: 4, art: .day),
        .init(id: "unsorted-10", file: "A016_C005_1022.mov", duration: 19, caption: "Hands, sticky notes", guess: 4, art: .hands),
        .init(id: "unsorted-11", file: "B001_C011_1018.mov", duration: 24, caption: "Street, wet reflections", guess: 1, art: .night),
        .init(id: "unsorted-12", file: "C004_C015_1026.mov", duration: 9, caption: "Door closing", guess: nil, flags: ["Room tone"], art: .day),
        .init(id: "unsorted-13", file: "A016_C008_1022.mov", duration: 17, caption: "Keyboard, very close", guess: 4, art: .hands),
        .init(id: "unsorted-14", file: "C004_C019_1026.mov", duration: 30, caption: "Office lights off", guess: nil, art: .day),
    ]

    /// Stand-in pictures: setup 2B is hands on a keyboard; unsorted clips look like where they were shot.
    static var art: [String: FootageArt] {
        var a: [String: FootageArt] = ["take-2b-t1": .hands, "take-2b-t2": .hands, "take-2b-t3": .hands]
        for u in unsorted { a[u.id] = u.art }
        return a
    }

    /// Scene 2's dialogue, as the editor transcribed it.
    static var transcripts: [SourceTranscript] {
        let interview: [(Double, String)] = [(2, "So we started with the edit."), (7, "Everyone said, start with the camera."), (12, "But the camera was never the hard part."), (19, "Editing was the part nobody wanted."), (24, "(pause, looks to the window)"), (31, "Sitting with eight hours of yourself."), (38, "Because somebody has to.")]
        var out = ["take-2a-t1", "take-2a-t2", "take-2a-t3"].map { transcript($0, interview) }
        out.append(transcript("take-2a-t4", [(1, "(breaks, laughs)"), (6, "Sorry. Again.")]))
        out += ["take-2b-t1", "take-2b-t2", "take-2b-t3"].map { transcript($0, [(0, "(keys typing)")]) }
        return out
    }

    static func transcript(_ assetID: String, _ lines: [(Double, String)]) -> SourceTranscript {
        var words: [TranscriptWord] = []
        for (i, (start, text)) in lines.enumerated() {
            let parts = text.split(separator: " ").map(String.init)
            let span = min((i + 1 < lines.count ? lines[i + 1].0 - start - 0.6 : 3), Double(parts.count) * 0.42)
            for (j, word) in parts.enumerated() {
                let a = start + span * Double(j) / Double(parts.count), b = start + span * Double(j + 1) / Double(parts.count)
                words.append(TranscriptWord(id: "\(assetID)-w\(words.count)", text: word, range: MediaRange(start: a, end: b)))
            }
        }
        return SourceTranscript(assetID: assetID, audioTrackID: 2, provider: "local", words: words)
    }
}
