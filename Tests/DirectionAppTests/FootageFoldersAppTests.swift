import Testing
import Foundation
import DirectionCore
@testable import DirectionApp

/// A dropped folder brings its takes with where the director filed them, and the editor's logging job
/// says so for each take and scene.
@Test func aDroppedFolderFilesItsTakesAndTheLoggingJobSaysSo() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-folders-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let shoot = root.appendingPathComponent("Launch film")
    for path in ["02 Pricing/A Talking head/T3.mov", "02 Pricing/B Slides/deck.mov", "02 Pricing/A Talking head/._T3.mov", "loose.mov", "02 Pricing/A Talking head/notes.txt"] {
        let file = shoot.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("take".utf8).write(to: file)
    }
    let drop = FootageFiles.route([shoot])
    #expect(drop.footage.map(\.lastPathComponent).sorted() == ["T3.mov", "deck.mov", "loose.mov"])
    let t3 = try #require(drop.footage.first { $0.lastPathComponent == "T3.mov" }).path
    #expect(drop.places[t3]?.setupCode == "2A" && drop.places[t3]?.take == 3)
    #expect(drop.places.count == 2)

    let store = try ProjectStore.create(at: root.appendingPathComponent("Film.direction"), name: "Launch film")
    let asset = MediaAsset(id: "take-t3", name: "T3.mov", path: t3, duration: .init(seconds: 12), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)])
    _ = try store.addAsset(asset, append: false, expectedRevision: 0)
    let dailies = try store.fileTakes([asset.id: drop.places[t3]!])
    let take = LoggingDigest.take(asset, store: store, dailies: dailies, transcripts: [])
    #expect(take.contains("Filed by the director in \u{201C}02 Pricing/A Talking head\u{201D}: scene 2 Pricing \u{00B7} setup 2A Talking head \u{00B7} take T3."))
    #expect(LoggingDigest.scenes(dailies).contains("the director\u{2019}s folder \u{201C}02 Pricing\u{201D}: 2A Talking head"))
}

/// A turnover's note that names a take with "@" reaches the editor with which take it is.
@Test func aNoteNamingATakeTellsTheEditorWhichOne() {
    var d = Dailies(scenes: [DailiesScene(id: "scene-2", number: 2, title: "Pricing", setups: [DailiesSetup(code: "2A", description: "Talking head")])], takes: [:])
    var t = TakeInfo(assetID: "t3"); t.sceneID = "scene-2"; t.setupCode = "2A"; t.code = "T3"; t.circled = true; d.takes["t3"] = t
    let assets = [MediaAsset(id: "t3", name: "T3.mov", path: "/T3.mov", duration: .init(seconds: 12), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)])]
    let note = ReviewComment(id: "c1", cutID: nil, editRevision: 1, sequenceID: "s", scope: "time", range: nil, time: .init(seconds: 72), region: nil, text: "Use @2A Take 3 here.", author: "Director", status: "open", anchors: [], transcriptContext: [], replies: [], createdAt: 0, cursor: 0)
    let line = EditorJobs.noteLine(note, footage: .init(names: FootageNames.all(d, assets: assets), dailies: d, assets: assets, cut: nil))
    #expect(line.hasSuffix("Use @2A Take 3 here.\n  (@2A Take 3 is the take T3.mov (assetID t3) in scene 2 Pricing, setup 2A Talking head: circled. Not in the cut.)"))
}
