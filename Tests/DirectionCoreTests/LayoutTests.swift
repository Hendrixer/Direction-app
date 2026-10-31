import Testing
import Foundation
@testable import DirectionCore

/// Layouts (layouts.md): the screen and the camera in sync sharing the frame, set by the director or
/// the editor, as ordinary synced clips over the story.
struct LayoutTests {
    /// TimelineCut with a (the story on V1 at 0–4) as the screen recording and d as the camera, in sync:
    /// a's time = d's time + 1.5.
    private func cut() -> TimelineCut {
        var c = TimelineCut.make()
        c.context.dailies.syncGroups = [SyncGroup(id: "sync-1", soundAssetID: "a", takes: [SyncedTake(assetID: "a", offset: 0, match: 1), SyncedTake(assetID: "d", offset: 1.5, match: 0.98)], method: "sound", createdAt: 0)]
        return c
    }
    private func layout(_ json: String, faces: [FaceTrack.Sample] = []) throws -> EditOperation {
        var o = try op(json)
        o.resolved = .init(layout: LayoutMeasure(cameras: ["d"], screens: ["a"], faces: faces.isEmpty ? [:] : ["d": FaceTrack(samples: faces)]))
        return o
    }
    private func run(_ c: TimelineCut, _ ops: [EditOperation], notes: [Int]? = [1], director: Bool = false) throws -> (Project, EditResult) {
        try EditReducer.run(EditBatch(baseEditRevision: 0, notes: director ? nil : notes, operations: ops, byDirector: director ? true : nil), on: c.project, context: c.context)
    }
    private func laidOut(_ p: Project) -> [Clip] { p.sequences[0].clips.filter { $0.layout != nil }.sorted { ($0.start.seconds, $0.layer) < ($1.start.seconds, $1.layer) } }

    @Test func theScreenAndTheCameraPlayTheSameMomentOverTheStory() throws {
        let (p, r) = try run(cut(), [try layout(#"{"op":"layout","range":{"start":0,"end":6},"layout":{"kind":"screenAndYou"}}"#)])
        let clips = laidOut(p)
        // Only over a: b at 4–9 isn't in sync with a camera, and says so.
        #expect(clips.count == 2 && clips.allSatisfy { close($0.start.seconds, 0) && close($0.end.seconds, 4, 0.001) && $0.synced == true })
        let screen = try #require(clips.first { $0.layout?.role == .screen }), camera = try #require(clips.first { $0.layout?.role == .camera })
        #expect(screen.assetID == "a" && screen.layer == 1 && close(screen.sourceRange.start.seconds, 2, 0.001) && screen.effects == nil)
        #expect(camera.assetID == "d" && camera.layer == 2 && close(camera.sourceRange.start.seconds, 0.5, 0.001))
        // Silent: the story's sound keeps playing.
        #expect(camera.audioOverrides.values.allSatisfy(\.muted) && screen.audioOverrides.values.allSatisfy(\.muted))
        #expect(camera.effects?.map(\.name) == ["transform", "card"] && camera.effects?[1].params["radius"]?.double == 0.5)
        #expect(r.operations[0].summary == "Layout: Screen and you \u{00B7} bottom right, 00:00:00–00:06:00")
        #expect(r.warnings.contains { $0.contains("isn\u{2019}t in sync with a camera and a screen") })
        #expect(p.sequences[0].layout(at: 2) == .standard && p.sequences[0].layout(at: 5) == nil)
    }

    @Test func theBubbleLandsInItsCornerWithTheFaceInIt() throws {
        let face = [FaceTrack.Sample(t: 0, x: 0.3, y: 0.4, h: 0.2), FaceTrack.Sample(t: 1, x: 0.3, y: 0.4, h: 0.2), FaceTrack.Sample(t: 2, x: 0.3, y: 0.4, h: 0.2)]
        let (p, _) = try run(cut(), [try layout(#"{"op":"layout","range":{"start":0,"end":4},"layout":{"kind":"screenAndYou","corner":"topLeft","size":"large"}}"#, faces: face)])
        let camera = try #require(laidOut(p).first { $0.layout?.role == .camera })
        let t = try #require(camera.effects?.first { $0.name == "transform" })
        // A still face: one placement, no keys.
        #expect(t.keys == nil)
        // The crop is about the face: 0.2 high in a 0.5 crop, a little above its middle.
        let crop = (l: t.number("crop.l", at: nil, default: 0), r: t.number("crop.r", at: nil, default: 0), t: t.number("crop.t", at: nil, default: 0), b: t.number("crop.b", at: nil, default: 0))
        #expect(close(1 - crop.t - crop.b, 0.5, 0.001) && close(crop.l + (1 - crop.l - crop.r) / 2, 0.3, 0.001) && close(crop.t, 0.19, 0.001))
        // Placed as the renderer places it (fit, scale, then x and y over the frame), the crop fills the
        // top left bubble: 36 % of the frame's height, 4 % in from both edges.
        let W = 1920.0, H = 1080.0, size = 1920 * t.number("scale", at: nil, default: 1)
        let left = (W - size) / 2 + t.number("x", at: nil, default: 0) * W, top = (H - size * 1080 / 1920) / 2 + t.number("y", at: nil, default: 0) * H
        let cropLeft = left + crop.l * size, cropTop = top + crop.t * size * 1080 / 1920, cropWidth = (1 - crop.l - crop.r) * size
        #expect(close(cropLeft, 0.04 * H, 0.5) && close(cropTop, 0.04 * H, 0.5) && close(cropWidth, 0.36 * H, 0.5))
    }

    @Test func theBubbleFollowsAFaceThatMovesWithoutTwitching() {
        let frame = LayoutGeometry.Size(1920, 1080), source = LayoutGeometry.Size(1920, 1080)
        let rect = LayoutGeometry.cameraRect(.standard, frame: frame)
        // Leaning right over ten seconds, with a little jitter.
        let samples = (0...10).map { FaceTrack.Sample(t: Double($0), x: 0.3 + 0.03 * Double($0) + ($0 % 2 == 0 ? 0.004 : -0.004), y: 0.4, h: 0.2) }
        let keys = LayoutGeometry.follow(FaceTrack(samples: samples), from: 0, to: 10, rect: rect, frame: frame, source: source)
        #expect(keys.count >= 3 && keys.count <= 6)
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $1.t - $0.t >= 2 - 1e-6 && $1.crop.x > $0.crop.x })
        // Sitting still: one key.
        let still = (0...10).map { FaceTrack.Sample(t: Double($0), x: 0.5 + ($0 % 2 == 0 ? 0.003 : -0.003), y: 0.4, h: 0.2) }
        #expect(LayoutGeometry.follow(FaceTrack(samples: still), from: 0, to: 10, rect: rect, frame: frame, source: source).count == 1)
        let effect = LayoutGeometry.transform(crop: keys, into: rect, frame: frame, source: source)
        #expect(effect.keys?["x"]?.count == keys.count && effect.keys?["crop.l"]?.allSatisfy { $0.ease == "smooth" } == true)
    }

    @Test func aNewLayoutTakesThePlaceOfWhatShowedThoseMoments() throws {
        var c = cut()
        // The editor's own bubble from before layouts: a cutaway to the camera, in sync.
        c.project = try run(c, [try op(#"{"op":"cutaway","assetID":"d","at":0,"seconds":2}"#)]).0
        // And a graphic on V2 over the same stretch.
        c.project.sequences[0].clips.append(Clip(id: "g1", assetID: "c", name: "Title", layer: 2, start: .init(seconds: 0.5), sourceRange: .init(start: 0, end: 1)))
        c.project = try run(c, [try layout(#"{"op":"layout","range":{"start":0,"end":4},"layout":{"kind":"screenAndYou"}}"#)]).0
        let clips = c.project.sequences[0].clips
        #expect(!clips.contains { $0.assetID == "d" && $0.layout == nil })
        // The graphic moves up over the layout.
        #expect(clip(c.project, "g1").layer == 4)
        // You, from 1 to 3: the first layout keeps the rest.
        c.project = try run(c, [try layout(#"{"op":"layout","range":{"start":1,"end":3},"layout":{"kind":"you"}}"#)]).0
        let spans = c.project.sequences[0].layoutSpans.map { ($0.start, $0.end, $0.layout.kind) }
        #expect(spans.count == 3 && spans[1].2 == .you && close(spans[1].0, 1, 0.001) && close(spans[1].1, 3, 0.001) && spans[0].2 == .screenAndYou && spans[2].2 == .screenAndYou)
        let you = try #require(laidOut(c.project).first { $0.layout?.layout.kind == .you })
        #expect(you.assetID == "d" && you.layer == 1 && you.effects == nil)
        // Framed: the screen fits inside a padded frame on a background, with rounded corners.
        c.project = try run(c, [try layout(#"{"op":"layout","range":{"start":0,"end":1},"layout":{"kind":"screen","screen":"framed"}}"#)]).0
        let framed = try #require(laidOut(c.project).first { $0.layout?.layout.kind == .screen })
        #expect(framed.effects?.map(\.name) == ["transform", "card"] && framed.effects?[1].params["background"]?.string == LayoutGeometry.background)
        #expect(framed.effects![0].number("scale", at: nil, default: 1) < 0.95)
    }

    @Test func aLayoutTheDirectorSetIsTheirs() throws {
        var c = cut()
        let (mine, result) = try run(c, [try layout(#"{"op":"layout","range":{"start":0,"end":4},"layout":{"kind":"screenAndYou"}}"#)], director: true)
        #expect(result.byDirector == true && laidOut(mine).allSatisfy { $0.layout?.byDirector == true })
        c.project = mine
        // The editor, with no note asking: no new layout over it, no changing its effects.
        let card = try #require(laidOut(mine).first { $0.layout?.role == .camera }?.effects?.first { $0.name == "card" })
        expectFailure("layout_is_yours", index: 0) { _ = try run(c, [try layout(#"{"op":"layout","range":{"start":2,"end":3},"layout":{"kind":"you"}}"#)], notes: nil) }
        expectFailure("layout_is_yours", index: 0) { _ = try run(c, [try op("{\"op\":\"removeEffect\",\"effectID\":\"\(card.id)\"}")], notes: nil) }
        // For a note it may, and cutting the story still carries the layout with it.
        _ = try run(c, [try layout(#"{"op":"layout","range":{"start":2,"end":3},"layout":{"kind":"you"}}"#)], notes: [1])
        let trimmed = try run(c, [try op(#"{"op":"removeRange","range":{"start":1,"end":2}}"#)], notes: nil).0
        let spans = trimmed.sequences[0].layoutSpans
        #expect(spans.count == 1 && close(spans[0].start, 0) && close(spans[0].end, 3, 0.001) && spans[0].byDirector)
    }

    @Test func aLayoutNeedsDirectionsMeasurementsAndSomethingInSync() throws {
        let c = cut()
        expectFailure("bad_argument", index: 0) { _ = try run(c, [try op(#"{"op":"layout","range":{"start":0,"end":4},"layout":{"kind":"you"}}"#)]) }
        expectFailure("not_in_sync", index: 0) { _ = try run(c, [try layout(#"{"op":"layout","range":{"start":4,"end":9},"layout":{"kind":"you"}}"#)]) }
        expectFailure("bad_argument", index: nil) { _ = try op(#"{"op":"layout","range":{"start":0,"end":4},"layout":{"kind":"pip"}}"#) }
        #expect(EditCatalog.operations.contains { $0.op == "layout" } && EditCatalog.effect("card") != nil && EditCatalog.errors.contains { $0.code == "layout_is_yours" })
    }

    @Test func theDirectorsLayoutPlaysInTheLatestCutAndUndoesWhileNothingElseChanged() throws {
        let store = try seededStore()
        var p = try store.read()
        let screen = p.assets[0]
        var camera = screen; camera.id = "asset-camera"; camera.name = "Camera.mov"; camera.path = "/Camera.mov"
        _ = try store.addAsset(camera, append: false, expectedRevision: p.editRevision)
        try store.saveSync([SyncGroup(id: "sync-1", soundAssetID: screen.id, takes: [SyncedTake(assetID: screen.id, offset: 0, match: 1), SyncedTake(assetID: camera.id, offset: 0, match: 1)], method: "sound", createdAt: 0)], checked: [screen.id, camera.id])
        p = try store.read()
        let cut = try store.createCut(name: "Cut 1", sequenceID: nil, revision: nil)
        let length = p.sequences[0].duration.seconds
        var o = try op("{\"op\":\"layout\",\"range\":{\"start\":0,\"end\":\(length)},\"layout\":{\"kind\":\"screenAndYou\"}}")
        o.resolved = .init(layout: LayoutMeasure(cameras: [camera.id], screens: [screen.id]))
        let made = try store.directorEdit([o], summary: "Layout: Screen and you", expectedRevision: p.editRevision)
        #expect(made.byDirector == true && made.editRevision == p.editRevision + 1)
        // The cut plays it now, and History knows it was the director's.
        #expect(try store.cuts().first { $0.id == cut.id }?.editRevision == made.editRevision)
        #expect(try store.editRecord(revision: made.editRevision)?.byDirector == true)
        #expect(try store.read().sequences[0].layout(at: 0.1) == .standard)
        // Undo puts the cut back as it was, as a new revision it plays.
        try store.undoDirectorEdit(revision: made.editRevision)
        let back = try store.read()
        #expect(back.editRevision == made.editRevision + 1 && back.sequences[0].layout(at: 0.1) == nil && back.sequences[0].clips == p.sequences[0].clips)
        #expect(try store.cuts().first { $0.id == cut.id }?.editRevision == back.editRevision)
        expectError("cut_moved_on") { try store.undoDirectorEdit(revision: made.editRevision) }
        // While the editor is making the next cut, the latest cut isn't the cut as it stands.
        _ = try store.edit(EditBatch(baseEditRevision: back.editRevision, operations: [try op("{\"op\":\"split\",\"clipID\":\"\(back.sequences[0].clips[0].id)\",\"at\":0.5}")]))
        expectError("editor_working") { _ = try store.directorEdit([o], summary: "Layout", expectedRevision: back.editRevision + 1) }
    }
}
