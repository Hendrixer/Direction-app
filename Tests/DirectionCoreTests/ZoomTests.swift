import Testing
import Foundation
@testable import DirectionCore

/// Screen zooms and a style's transitions (agent-timeline.md › Moves): moments found in what changes on
/// screen, eased zooms to them, and a named transition that brings its sound.
struct ZoomTests {
    /// Something small changing around (cx, cy) every quarter second from `from` to `to`.
    private func action(_ from: Double, _ to: Double, _ cx: Double, _ cy: Double, size: Double = 0.04) -> [ActivitySample] {
        stride(from: from, through: to, by: 0.25).map { ActivitySample(t: $0, amount: 0.002, cx: cx, cy: cy, x: cx - size / 2, y: cy - size / 2, w: size, h: size) }
    }
    private func run(_ c: TimelineCut, _ ops: [EditOperation]) throws -> (Project, EditResult) {
        try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: ops), on: c.project, context: c.context)
    }
    private let zoom = StyleMoves.standard.screenZoom!

    @Test func momentsAreWhereTheActionStaysAndANewPageEndsOne() {
        var samples = action(1, 3, 0.2, 0.2) + action(4, 5.5, 0.75, 0.7, size: 0.3)
        samples.append(ActivitySample(t: 3.25, amount: 0.5, cx: 0.5, cy: 0.5, x: 0, y: 0, w: 1, h: 1))
        // The cursor flying across the screen: one look here, one there, nothing to watch.
        samples += [ActivitySample(t: 6, amount: 0.001, cx: 0.5, cy: 0.5, x: 0.49, y: 0.49, w: 0.02, h: 0.02), ActivitySample(t: 6.25, amount: 0.001, cx: 0.9, cy: 0.1, x: 0.89, y: 0.09, w: 0.02, h: 0.02)]
        let moments = ZoomPlanner.moments(samples, from: 0, to: 8, hold: 1.5)
        #expect(moments.count == 2 && close(moments[0].start, 1) && close(moments[0].cx, 0.2) && close(moments[1].cx, 0.75) && close(moments[1].end, 5.5))
        // Small action zooms as far as the style goes; a wide one as little.
        #expect(ZoomPlanner.scale(moments[0], zoom: zoom) == 2 && ZoomPlanner.scale(moments[1], zoom: zoom) == 1.83)
        // Never past the picture's edges: the top left corner at 2× can only come halfway.
        let at = ZoomPlanner.offset(cx: 0.05, cy: 0.05, scale: 2, fitted: (1, 1), crop: (0, 0, 0, 0))
        #expect(at.x == 0.5 && at.y == 0.5)
        // A crop counts: the middle of what's left is where the picture centers.
        #expect(ZoomPlanner.offset(cx: 0.6, cy: 0.5, scale: 2, fitted: (1, 1), crop: (0.2, 0, 0, 0)).x == 0)
    }

    @Test func autoZoomEasesInPansAndEasesOutOnTheScreenClip() throws {
        let c = TimelineCut.make()
        // c1 shows a's 2–6 s at 0–4 in the cut. Action at 2.5–3.5 top left, then 3.75–5 a little right of it.
        var o = try op(#"{"op":"autoZoom","range":{"start":0,"end":4}}"#)
        o.resolved = .init(); o.resolved?.zoom = zoom
        o.resolved?.activity = ["a": action(2.5, 3.5, 0.3, 0.3) + action(3.75, 5, 0.55, 0.35)]
        let (p, r) = try run(c, [o])
        let t = try #require(p.sequences[0].clips.first { $0.id == "c1" }?.effects?.first { $0.name == "transform" })
        let scale = try #require(t.keys?["scale"]), x = try #require(t.keys?["x"])
        // In from the resting view, still zoomed for the second moment (a pan, not a bounce), out after.
        #expect(scale.first?.v == 1 && scale.last?.v == 1 && scale.contains { $0.v == 2 } && scale.allSatisfy { $0.ease == "smooth" })
        // The way in starts 0.6 s ahead of the action, but not before the clip does (its 2 s).
        #expect(close(scale.first!.t, 2, 0.001) && scale.filter { $0.v == 1 }.count == 2)
        #expect(x.contains { close($0.v, 0.4, 0.001) } && x.contains { close($0.v, -0.1, 0.001) })
        #expect(r.operations[0].summary.hasPrefix("Zoomed to 2 moments"))
        // Nothing to look at: it says so.
        var still = o; still.resolved?.activity = ["a": []]
        expectFailure("bad_argument", index: 0) { _ = try run(c, [still]) }
    }

    @Test func zoomToGoesInAtTheStartAndOutByTheEnd() throws {
        let c = TimelineCut.make()
        var o = try op(#"{"op":"zoomTo","range":{"start":1,"end":3},"focus":{"x":0.7,"y":0.4},"scale":1.5}"#)
        o.resolved = .init(); o.resolved?.zoom = zoom; o.resolved?.activity = ["a": []]
        let (p, _) = try run(c, [o])
        let t = try #require(p.sequences[0].clips.first { $0.id == "c1" }?.effects?.first { $0.name == "transform" })
        // In source seconds: the clip starts at 2, so 1–3 in the cut is 3–5 in the take.
        #expect(t.keys?["scale"]?.map(\.v) == [1, 1.5, 1.5, 1] && t.keys?["scale"]?.map(\.t) == [3, 3.6, 4.5, 5])
        #expect(close(t.keys!["x"]![1].v, -0.25, 0.001))
        expectFailure("bad_argument", index: nil) { _ = try op(#"{"op":"zoomTo","range":{"start":1,"end":3},"focus":"there"}"#) }
        var short = o; short.range = MediaRange(start: 1, end: 1.5)
        expectFailure("bad_argument", index: 0) { _ = try run(c, [short]) }
    }

    @Test func aStylesTransitionBringsItsSoundUnderTheCut() throws {
        let c = TimelineCut.make()
        let named = try op(#"{"op":"transition","editPoint":"c1|c2","name":"Chapter"}"#)
        #expect(named.transitionName == "Chapter" && named.json["name"] == .string("Chapter"))
        expectFailure("bad_argument", index: 0) { _ = try run(c, [named]) }
        // As Direction's tools leave it: the style's kind and length, and its sound.
        var o = named; o.transitionType = "dissolve"; o.frames = 10
        o.resolved = .init(); o.resolved?.soundDB = -20
        o.resolved?.sound = MediaAsset(id: "whoosh", name: "whoosh.wav", path: "/Styles/desk-talk/sounds/whoosh.wav", duration: .init(seconds: 0.6), audio: [.init(id: 1, index: 0, label: "Sound", channels: 2, sampleRate: 48_000)])
        let (p, r) = try run(c, [o])
        let whoosh = try #require(p.sequences[0].clips.first { $0.assetID == "whoosh" })
        // Centered on the cut at 4, on A3 over the music on A2, at the style's level.
        #expect(whoosh.kind == .audio && whoosh.layer == 2 && close(whoosh.start.seconds, 3.7, 0.02) && whoosh.gainDB == -20 && p.assets.contains { $0.id == "whoosh" })
        #expect(r.operations[0].summary.hasPrefix("Chapter: dissolved") && r.operations[0].summary.hasSuffix("whoosh under it"))
        #expect(["autoZoom", "zoomTo"].allSatisfy { name in EditCatalog.operations.contains { $0.op == name } })
    }
}
