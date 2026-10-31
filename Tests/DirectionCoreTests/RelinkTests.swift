import Testing
import Foundation
@testable import DirectionCore

/// A film with one take whose file sits in a temporary folder, logged into scene 1.
private func filmWithFootage() throws -> (ProjectStore, URL, MediaAsset) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-relink-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("A001_C002.mov")
    try Data("take".utf8).write(to: file)
    let store = try temporaryStore()
    let asset = MediaAsset(id: "take-2a-t2", name: file.lastPathComponent, path: file.path, duration: .init(seconds: 44), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 24)], fileSize: 4, modifiedAt: 1)
    _ = try store.addAsset(asset, append: true, expectedRevision: 0)
    _ = try store.logDailies(Dailies(scenes: [DailiesScene(id: "scene-2", number: 2, title: "Maya, the problem")], takes: [asset.id: { var t = TakeInfo(assetID: asset.id); t.sceneID = "scene-2"; t.code = "T2"; return t }()]))
    return (store, folder, asset)
}

@Test func footageGoesMissingWhenItsFileIsGone() throws {
    let (store, folder, asset) = try filmWithFootage()
    #expect(try store.missingAssets().isEmpty)
    try FileManager.default.removeItem(at: folder)
    #expect(try store.missingAssets().map(\.id) == [asset.id])
}

@Test func relinkPointsTheTakeAtItsNewFileAsOneRevision() throws {
    let (store, folder, asset) = try filmWithFootage()
    try FileManager.default.removeItem(at: folder)
    let backup = FileManager.default.temporaryDirectory.appendingPathComponent("direction-backup-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: backup.appendingPathComponent("Day 1"), withIntermediateDirectories: true)
    let moved = backup.appendingPathComponent("Day 1/A001_C002.mov")
    try Data("take, moved".utf8).write(to: moved)
    let before = try store.read()

    let matches = FootageMatch.candidates(for: try store.missingAssets(), in: [backup.appendingPathComponent("Day 1/other.mov"), moved])
    #expect(matches[asset.id] == [moved])

    let after = try store.relink([AssetRelink(assetID: asset.id, path: moved.path, fileSize: 11, modifiedAt: 2, duration: .init(seconds: 44.02))])
    #expect(after.editRevision == before.editRevision + 1)
    let relinked = try after.asset(asset.id)
    #expect(relinked.path == moved.standardizedFileURL.path && relinked.fileSize == 11 && relinked.modifiedAt == 2)
    #expect(after.sequences == before.sequences)
    #expect(try store.missingAssets().isEmpty)
    #expect(try store.events().last?.summary == "Relinked A001_C002.mov")
    // Every saved cut plays the take from its new place, the ones before the relink too.
    #expect(try store.read(revision: before.editRevision).asset(asset.id).path == moved.standardizedFileURL.path)
    #expect(try store.read(revision: before.editRevision).asset(asset.id).fileSize == 11)
}

@Test func relinkOnlyAcceptsAFileOfTheSameLengthWithinOneFrame() throws {
    let (store, _, asset) = try filmWithFootage()
    #expect(FootageMatch.durationMatches(asset, .init(seconds: 44 + 1.0 / 24)))
    #expect(!FootageMatch.durationMatches(asset, .init(seconds: 44.1)))
    expectError("relink_length_mismatch") { _ = try store.relink([AssetRelink(assetID: asset.id, path: "/Volumes/Backup/A001_C002.mov", fileSize: 4, modifiedAt: 1, duration: .init(seconds: 46))]) }
    expectError("asset_not_found") { _ = try store.relink([AssetRelink(assetID: "nope", path: "/Volumes/Backup/x.mov", fileSize: 4, modifiedAt: 1, duration: .init(seconds: 44))]) }
    expectError("nothing_to_relink") { _ = try store.relink([]) }
}

@Test func relinkWorksOnALockedSceneAndKeepsNotesAndCircles() throws {
    let (store, _, asset) = try filmWithFootage()
    try store.setCircle(assetID: asset.id, circled: true)
    try store.lockScene(id: "scene-2", locked: true)
    let p = try store.read()
    let cut = try store.createCut(name: "Assembly", sequenceID: nil, revision: nil)
    let note = try store.addComment(text: "Let it sit.", sequenceID: nil, revision: p.editRevision, cutID: cut.id, time: .init(seconds: 2), extra: NoteFields(kind: .feeling))
    _ = try store.relink([AssetRelink(assetID: asset.id, path: "/Volumes/Backup/A001_C002.mov", fileSize: 4, modifiedAt: 1, duration: .init(seconds: 44))])
    #expect(try store.dailies().take(asset.id).circled)
    #expect(try store.notes().contains { $0.id == note.id && $0.text == "Let it sit." })
    #expect(try store.cuts().count == 1)
}
