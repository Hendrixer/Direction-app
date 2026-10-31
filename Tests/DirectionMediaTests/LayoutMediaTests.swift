import Testing
import Foundation
import CoreImage
import DirectionCore
@testable import DirectionMedia
import DirectionTools

/// Layouts on real footage (layouts.md): the card drawn by the renderer, telling the camera from the
/// screen, and the director's layout going into the latest cut.
@Suite(.serialized) struct LayoutMediaTests {
    /// One pixel of an image, as 0–1 RGBA.
    private func pixel(_ image: CIImage, _ x: Int, _ y: Int) -> [Double] {
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return px.map { Double($0) / 255 }
    }

    @Test func aCardRoundsThePictureAndShadowsItOverItsBackground() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 100, y: 150, width: 200, height: 200))
        // A circle with a shadow, nothing behind it.
        let circle = ClipRendering.card(red, ClipEffect(name: "card", params: ["radius": .number(0.5), "shadow": .number(0.6)]), bounds: bounds)
        #expect(pixel(circle, 200, 250)[0] > 0.95 && pixel(circle, 200, 250)[3] > 0.95)
        // The square's corner is outside the circle: only a little shadow there.
        #expect(pixel(circle, 103, 347)[3] < 0.3)
        // Below the picture (y goes up in Core Image), the shadow.
        #expect(pixel(circle, 200, 140)[3] > 0.05 && pixel(circle, 200, 140)[0] < 0.1)
        // A framed screen: rounded a little, over the background, which fills the frame.
        let framed = ClipRendering.card(red, ClipEffect(name: "card", params: ["radius": .number(0.03), "background": .string("#16171A")]), bounds: bounds)
        let corner = pixel(framed, 5, 5)
        #expect(abs(corner[0] - 0x16 / 255.0) < 0.02 && abs(corner[2] - 0x1A / 255.0) < 0.02 && corner[3] > 0.99)
        #expect(pixel(framed, 102, 152)[0] > 0.9)
        #expect(ClipRendering.color("#FF8000") == CIColor(red: 1, green: 128 / 255, blue: 0) && ClipRendering.color("orange") == nil)
    }

    @Test func theDirectorLaysOutTheCutWithTheScreenAndTheCameraInSync() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        // The fixture shows no face, so the name decides: a screen recording and the take on V1 as the camera.
        let copy = f.directory.appendingPathComponent("Screen Recording 2026-10-31.mov")
        try FileManager.default.copyItem(at: f.source, to: copy)
        _ = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(copy.path)]))
        let p = try f.store.read()
        let story = try #require(p.assets.first { $0.path == f.source.path }), screen = try #require(p.assets.first { $0.path == copy.path })
        try f.store.saveSync([SyncGroup(id: "sync-1", soundAssetID: story.id, takes: [SyncedTake(assetID: story.id, offset: 0, match: 1), SyncedTake(assetID: screen.id, offset: 0, match: 1)], method: "sound", createdAt: 0)], checked: [story.id, screen.id])
        let measured = try await LayoutAnalysis.measure(project: p, sequence: p.sequences[0], dailies: try f.store.dailies(), range: nil, cacheDirectory: f.runtime.cacheDirectory)
        #expect(measured.cameras == [story.id] && measured.screens == [screen.id] && measured.faces[story.id]?.samples.isEmpty == true)
        // Faces found once are kept: the second look reads the cache.
        #expect(FileManager.default.fileExists(atPath: LayoutAnalysis.cache(story, "faces", f.runtime.cacheDirectory).path))

        // No cut yet: nothing to lay out.
        await #expect(throws: DirectionError.self) { _ = try await f.runtime.setLayout(.standard, range: nil) }
        let cut = try f.store.createCut(name: "Cut 1", sequenceID: nil, revision: nil)
        let made = try await f.runtime.setLayout(FrameLayout(kind: .screenAndYou, corner: .topRight, shape: .rounded), range: nil)
        #expect(made.byDirector == true && made.operations.first?.op == "layout")
        let after = try f.store.read()
        #expect(try f.store.cuts().first { $0.id == cut.id }?.editRevision == after.editRevision)
        let laid = after.sequences[0].clips.filter { $0.layout != nil }
        #expect(laid.compactMap(\.assetID).sorted() == [story.id, screen.id].sorted() && laid.allSatisfy { $0.layout?.byDirector == true })
        // It renders: the frame at 1 s has the bubble in the top right over the screen.
        let frame = try await f.runtime.invoke("direction_frame", arguments: .object(["time": .number(1)]))
        #expect(frame.value["path"].string != nil || frame.value["image"] != .null)
    }
}
