import Testing
import Foundation
@testable import DirectionCore

/// Moves (agent-timeline.md › Moves): punch-ins on jump cuts, the emphasis punch and the slow push, framed
/// on the face by Direction instead of worked out by the editor.
struct MovesTests {
    /// TimelineCut with a split at 2, so 0–2 and 2–4 are a jump cut on take a; b at 4–9 is another take.
    private func cut() throws -> TimelineCut {
        var c = TimelineCut.make()
        c.project = try run(c, [try op(#"{"op":"split","clipID":"c1","at":2}"#)]).0
        return c
    }
    /// A face left of middle, the same all through take a and take b.
    private let faces: [String: FaceTrack] = ["a": FaceTrack(samples: (0...20).map { FaceTrack.Sample(t: Double($0), x: 0.3, y: 0.4, h: 0.25) }), "b": FaceTrack(samples: (0...20).map { FaceTrack.Sample(t: Double($0), x: 0.5, y: 0.45, h: 0.25) })]
    private func move(_ json: String) throws -> EditOperation { var o = try op(json); o.resolved = .init(faces: faces); return o }
    private func run(_ c: TimelineCut, _ ops: [EditOperation]) throws -> (Project, EditResult) {
        try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: ops), on: c.project, context: c.context)
    }
    private func story(_ p: Project) -> [Clip] { p.sequences[0].clips.filter { $0.layer == 0 && $0.kind == .video }.sorted { $0.start < $1.start } }
    private func transform(_ c: Clip) -> ClipEffect? { c.effects?.first { $0.name == "transform" } }

    @Test func punchInChangesTheFramingOnEveryJumpCutAndStartsAgainOnAnotherTake() throws {
        let c = try cut()
        let (p, r) = try run(c, [try move(#"{"op":"punchIn","range":{"start":0,"end":9},"scales":[1,1.15]}"#)])
        let clips = story(p)
        #expect(clips.prefix(3).map { transform($0)?.params["scale"]?.double } == [1, 1.15, 1])
        // On the medium, the face stays where it was across the frame and its eyes go up toward the third.
        let medium = try #require(transform(clips[1]))
        let x = medium.number("x", at: nil, default: 0), y = medium.number("y", at: nil, default: 0)
        #expect(close(x, 0.03, 0.001) && close(y, -0.005, 0.001))
        // Never past the edge: at 1.15 the picture can move 0.075 either way.
        #expect(abs(x) <= 0.075 && abs(y) <= 0.075)
        #expect(r.operations[0].summary.hasPrefix("Punched in on the cuts"))
        // Again over the second half only: it carries on from the shot before, so 2–4 isn't repeated at 1.
        let again = try run(TimelineCut(project: p, context: c.context), [try move(#"{"op":"punchIn","range":{"start":2,"end":4},"scales":[1,1.15]}"#)]).0
        #expect(transform(story(again)[1])?.params["scale"]?.double == 1.15)
    }

    @Test func aShotThatAlreadyMovesIsLeftAlone() throws {
        var c = try cut()
        c.project = try run(c, [try move(#"{"op":"slowPush","range":{"start":4,"end":9},"longerThan":4}"#)]).0
        let pushed = try #require(story(c.project).first { $0.assetID == "b" })
        #expect(transform(pushed)?.keys?["scale"]?.map(\.v) == [1, 1.05] && transform(pushed)?.keys?["scale"]?.first?.t == pushed.sourceRange.start.seconds)
        let (p, r) = try run(c, [try move(#"{"op":"punchIn","range":{"start":0,"end":9}}"#)])
        #expect(transform(story(p).first { $0.assetID == "b" }!)?.keys?["scale"] != nil && r.warnings.contains { $0.contains("already move") })
        // And no slow push on a shot too short, or punched in already.
        expectFailure("bad_argument", index: 0) { _ = try run(c, [try move(#"{"op":"slowPush","range":{"start":0,"end":4}}"#)]) }
    }

    @Test func emphasisPunchCutsInOnOneLineAndBackOut() throws {
        let c = try cut()
        let (p, _) = try run(c, [try move(#"{"op":"emphasisPunch","range":{"start":0.5,"end":1.5},"scale":1.32}"#)])
        let a = story(p).filter { $0.start.seconds < 2 }
        #expect(a.count == 3 && a.map { transform($0)?.params["scale"]?.double ?? 1 } == [1, 1.32, 1])
        #expect(close(a[1].start.seconds, 0.5, 0.001) && close(a[1].end.seconds, 1.5, 0.001))
        // The rest of the cut doesn't move.
        #expect(close(p.sequences[0].duration.seconds, c.project.sequences[0].duration.seconds, 0.001))
        expectFailure("bad_argument", index: 0) { _ = try run(c, [try move(#"{"op":"emphasisPunch","range":{"start":1.5,"end":2.5}}"#)]) }
        expectFailure("bad_argument", index: 0) { _ = try run(c, [try move(#"{"op":"punchIn","range":{"start":0,"end":4},"scales":[1]}"#)]) }
        #expect(["punchIn", "emphasisPunch", "slowPush"].allSatisfy { name in EditCatalog.operations.contains { $0.op == name } } && EditCatalog.effect("place") != nil)
    }
}
