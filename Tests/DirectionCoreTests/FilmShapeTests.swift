import Testing
import Foundation
@testable import DirectionCore

/// The film's shape (start.md › 03 · Shape, cut.md › Changing the shape): set in the brief, it sizes the cut from
/// the footage; changed once there's a cut, it's the director's own edit with black bars, and the moves and the
/// editor's outline work from the frame it fills.
struct FilmShapeTests {
    private func take(_ id: String, _ width: Int, _ height: Int) -> MediaAsset {
        MediaAsset(id: id, name: id + ".mov", path: "/\(id).mov", duration: .init(seconds: 10), video: [.init(id: 1, width: width, height: height, frameRate: 30)])
    }

    @Test func aShapeKeepsTheFootagesShortSide() {
        let hd = (width: 1920, height: 1080)
        #expect(FilmShape.tall.size(footage: hd) == (1080, 1920) && FilmShape.feed.size(footage: hd) == (1080, 1350))
        #expect(FilmShape.square.size(footage: hd) == (1080, 1080) && FilmShape.wide.size(footage: hd) == (1920, 1080))
        #expect(FilmShape.tall.size(footage: (3840, 2160)) == (2160, 3840) && FilmShape.wide.size(footage: (1080, 1920)) == (1920, 1080))
        #expect(FilmShape.label(width: 1920, height: 1080) == "16:9" && FilmShape.label(width: 1080, height: 1920) == "9:16")
        #expect(FilmShape.label(width: 2048, height: 858) == "2.39:1" && FilmShape.label(width: 1440, height: 1080) == "4:3" && FilmShape.label(width: 1080, height: 1350) == "4:5")
        #expect(FilmShape.of(width: 1080, height: 1920) == .tall && FilmShape.of(width: 1440, height: 1080) == nil)
        // 16:9 footage fills a 9:16 frame at 3.16×; 1080p stays sharp to 1.78×, 4K to 3.56×.
        #expect(abs(FrameFill.cover(source: hd, frame: (1080, 1920)) - 3.16) < 0.01 && FrameFill.cover(source: hd, frame: hd) == 1)
        #expect(abs(FrameFill.sharp(source: hd, frame: (1080, 1920)) - 1.78) < 0.01 && abs(FrameFill.sharp(source: (3840, 2160), frame: (1080, 1920)) - 3.56) < 0.01)
    }

    @Test func theFirstFootageCutsAtTheBriefsShape() throws {
        let store = try temporaryStore(); defer { try? FileManager.default.removeItem(at: store.url) }
        var brief = Brief(); brief.shape = .tall
        try store.saveBrief(brief)
        let p = try store.addAsset(take("a", 1920, 1080), append: false, expectedRevision: 0)
        #expect(p.sequences[0].width == 1080 && p.sequences[0].height == 1920)
        let asShot = try #require(try store.cutSize(for: nil)), square = try #require(try store.cutSize(for: .square))
        #expect(asShot == (1920, 1080) && square == (1080, 1080))
    }

    @Test func beforeAnythingsCutTheShapeChangesAtOnce() throws {
        let store = try temporaryStore(); defer { try? FileManager.default.removeItem(at: store.url) }
        // No footage yet: nothing to size, so the first footage takes it (above).
        #expect(try store.reshape(.tall) == nil)
        _ = try store.addAsset(take("a", 1920, 1080), append: false, expectedRevision: 0)
        #expect(try store.reshape(.feed) == nil)
        #expect(try store.read().sequences.allSatisfy { $0.width == 1080 && $0.height == 1350 })
        #expect(try store.cuts().isEmpty)
    }

    @Test func onceTheresACutTheDirectorsBarsChangeIt() throws {
        let store = try seededStore(); defer { try? FileManager.default.removeItem(at: store.url) }
        var p = try store.read()
        let wide = (width: p.sequences[0].width, height: p.sequences[0].height)
        let cut = try store.createCut(name: "Cut 1", sequenceID: nil, revision: nil)
        let made = try #require(try store.reshape(.tall))
        p = try store.read()
        #expect(made.byDirector == true && made.summary == "Shape: 9:16")
        #expect(FilmShape.label(width: p.sequences[0].width, height: p.sequences[0].height) == "9:16" && p.sequences[0].clips.count == 1)
        // The latest cut plays it, and the events say what happened.
        #expect(try store.cuts().first { $0.id == cut.id }?.editRevision == made.editRevision)
        #expect(try store.events().contains { $0.kind == "edit.committed" && $0.summary == "Shape: 9:16" })
        // The same shape again changes nothing; undo puts it back.
        #expect(try store.reshape(.tall) == nil)
        try store.undoDirectorEdit(revision: made.editRevision)
        #expect(try store.read().sequences[0].width == wide.width)
        // Picture locked: the frame can't change.
        try store.lockPicture(cutID: nil, locked: true)
        expectError("picture_locked") { _ = try store.reshape(.square) }
    }

    @Test func aNewShapeSaysWhatWasPlacedForTheOldOne() throws {
        var c = TimelineCut.make()
        let plain = try c.run([#"{"op":"format","width":1080,"height":1920}"#]).1
        #expect(plain.warnings.isEmpty)
        try c.apply(#"{"op":"title","text":"Two years.","at":1}"#)
        let r = try c.run([#"{"op":"format","width":1080,"height":1920}"#]).1
        #expect(r.warnings == ["1 title was placed for 16:9. Look at it in the new shape."])
        // Only a new shape: another size of the same one says nothing.
        #expect(try c.run([#"{"op":"format","width":3840,"height":2160}"#]).1.warnings.isEmpty)
    }

    @Test func movesStartFromFillingTheFrame() throws {
        var c = TimelineCut.make()
        try c.apply(#"{"op":"format","width":1080,"height":1920}"#, #"{"op":"split","clipID":"c1","at":2}"#)
        var o = try op(#"{"op":"punchIn","range":{"start":0,"end":4},"scales":[1,1.15]}"#)
        o.resolved = .init(faces: ["a": FaceTrack(samples: (0...20).map { FaceTrack.Sample(t: Double($0), x: 0.5, y: 0.4, h: 0.25) })])
        let (p, _) = try EditReducer.run(EditBatch(baseEditRevision: 0, notes: [1], operations: [o]), on: c.project, context: c.context)
        let scales = p.sequences[0].clips.filter { $0.layer == 0 && $0.kind == .video && $0.assetID == "a" }.sorted { $0.start < $1.start }
            .map { $0.effects?.first { $0.name == "transform" }?.params["scale"]?.double ?? 0 }
        let cover = FrameFill.cover(source: (1920, 1080), frame: (1080, 1920))
        #expect(scales.count == 2 && abs(scales[0] - cover) < 0.001 && abs(scales[1] - 1.15 * cover) < 0.001)
        // A shot kept whole on its backdrop punches in from whole.
        try c.apply(#"{"op":"addEffect","target":"c2","effect":"backdrop","params":{"blur":0.5,"dim":0.3}}"#)
        #expect(c.project.sequences[0].clips.first { $0.id == "c2" }?.effects?.contains { $0.name == "backdrop" } == true)
        expectFailure("bad_argument", index: 0) { _ = try c.run([#"{"op":"addEffect","target":"m1","effect":"backdrop"}"#]) }
    }

    @Test func sideBySideStacksInATallFrame() {
        let l = FrameLayout(kind: .sideBySide), tall = LayoutGeometry.Size(1080, 1920), wide = LayoutGeometry.Size(1920, 1080)
        let screen = LayoutGeometry.screenRect(l, frame: tall, screen: .init(1920, 1080)), camera = LayoutGeometry.cameraRect(l, frame: tall)
        // The screen across the top at full width inside the margins, you under it.
        #expect(screen.y < camera.y && screen.y + screen.h <= camera.y && abs(screen.w - camera.w) < 0.001 && camera.y + camera.h <= 1)
        #expect(camera.h * 1920 > 1000 && FrameLayout.Kind.sideBySide.label(tall: true) == "Stacked")
        // Wide frames keep it side by side.
        #expect(LayoutGeometry.cameraRect(l, frame: wide).x > 0.5 && FrameLayout.Kind.sideBySide.label(tall: false) == "Side by side")
    }

    @Test func theOutlineSaysWhatFillsTheFrame() throws {
        var c = TimelineCut.make()
        try c.apply(#"{"op":"format","width":1080,"height":1920}"#)
        let doc = TimelineExport.document(.init(project: c.project, sequence: c.project.sequences[0], cutName: "Cut 1", dailies: c.context.dailies))
        #expect(doc.outline.contains("1080×1920") && doc.outline.contains("16:9 footage, fills at 3.16×, sharp to 1.78×"))
    }
}
