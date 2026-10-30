import Testing
import Foundation
import CoreGraphics
import CoreText
import DirectionCore
import DirectionMedia

/// Text on screen (footage-index.md › Text on screen): reading frames, stretches over time, and
/// finding a moment by what was on screen.
struct ScreenTextTests {
    /// A dark 1920 × 1080 screen with a menu bar, a big title and body text, drawn with Core Text.
    static func screen() -> CGImage {
        let w = 1920, h = 1080
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        func draw(_ text: String, size: CGFloat, x: CGFloat, top: CGFloat) {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.92, alpha: 1)])
            ctx.textPosition = CGPoint(x: x, y: CGFloat(h) - top - size)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), ctx)
        }
        draw("File   Edit   View   Window   Help", size: 18, x: 40, top: 14)
        draw("Navier\u{2013}Stokes existence and smoothness", size: 64, x: 160, top: 180)
        draw("The equations describe how fluids move.", size: 30, x: 160, top: 320)
        draw("Al could solve it before we do.", size: 30, x: 160, top: 380)
        return ctx.makeImage()!
    }

    @Test func readsAFrameLargestTextFirst() async throws {
        let lines = try await ScreenReader.lines(Self.screen())
        #expect(lines.first?.contains("Navier") == true && lines.first?.contains("smoothness") == true, "\(lines)")
        #expect(lines.contains("The equations describe how fluids move."), "\(lines)")
        // "AI" in Helvetica reads as "Al"; the word alone is put back.
        #expect(lines.contains("AI could solve it before we do."), "\(lines)")
        // The menu bar's small text comes after the body, though it's above it.
        let menu = try #require(lines.firstIndex { $0.contains("Edit") }, "\(lines)")
        #expect(menu > (lines.firstIndex(of: "The equations describe how fluids move.") ?? .max))
    }

    @Test func linesAreCleanedOfIconsAndNoise() {
        #expect(ScreenReader.clean("\u{2022} All videos") == "All videos")
        #expect(ScreenReader.clean("+ New video") == "New video")
        #expect(ScreenReader.clean("\u{00A9}") == nil && ScreenReader.clean("+ #") == nil && ScreenReader.clean("8\u{2022}") == nil)
        #expect(ScreenReader.clean("Al is the last thing") == "AI is the last thing")
        #expect(ScreenReader.clean("Allen and Alice") == "Allen and Alice")
    }

    @Test func samplesBecomeStretchesOfWhatStaysAndWhatChanges() {
        let shot = Shot(id: "s1", assetID: "a", number: 1, start: 0, end: 20)
        // Every 2 s from 1 s: the window title stays; slide one until 7 s, slide two from 9 s.
        let samples = stride(from: 1.0, to: 20, by: 2).enumerated().map { i, t in
            ScreenReader.Sample(time: t, lines: ["Keynote \u{2014} Talk"] + (i < 4 ? ["Slide one: pricing", "Plans start at $9"] : ["Slide two: roadmap"]))
        }
        let stretches = ScreenReader.stretches(samples, shot: shot)
        #expect(stretches.map(\.lines) == [["Keynote \u{2014} Talk"], ["Slide one: pricing", "Plans start at $9"], ["Slide two: roadmap"]])
        // The title spans the shot; the slides change halfway between the samples either side.
        #expect(stretches.map(\.start) == [0, 0, 8] && stretches.map(\.end) == [20, 8, 20])

        // A page scrolling a line at a time stays one stretch, gathering the lines it shows, until
        // most of what the stretch began with is gone; then the next begins, so a hit says about when.
        let page = (0..<10).map { "Line \($0) of the page" }
        let scrolled = (0..<6).map { i in ScreenReader.Sample(time: Double(i) * 2 + 1, lines: Array(page[i..<(i + 4)])) }
        let two = ScreenReader.stretches(scrolled, shot: Shot(id: "s2", assetID: "a", number: 2, start: 0, end: 12))
        #expect(two.map(\.lines) == [Array(page[0..<6]), Array(page[3..<9])])
        #expect(two.map(\.start) == [0, 6] && two.map(\.end) == [6, 12])

        // Fewer than three samples: everything read stands for the whole shot.
        let short = ScreenReader.stretches([.init(time: 1, lines: ["EXIT"]), .init(time: 3, lines: ["EXIT", "Stairs"])], shot: Shot(id: "s3", assetID: "a", number: 3, start: 0, end: 4))
        #expect(short.map(\.lines) == [["EXIT", "Stairs"]])
        #expect(ScreenReader.stretches([], shot: shot).isEmpty)
    }

    @Test func searchFindsAMomentByWhatWasOnScreen() throws {
        let folder = try IndexTests.temp("screen"); defer { try? FileManager.default.removeItem(at: folder) }
        let store = try IndexTests.searchable(folder)
        let shots = try store.shots(assetID: "take-b")
        try store.replaceScreenText(assetID: "take-b", [
            ScreenText(assetID: "take-b", shotID: "take-b-shot-1", start: 0, end: 10, lines: ["Terminal \u{2014} zsh"]),
            ScreenText(assetID: "take-b", shotID: "take-b-shot-1", start: 4.5, end: 8.5, lines: ["Navier\u{2013}Stokes existence and smoothness", "A Millennium Prize problem"]),
        ])
        try store.replaceSearchRows(assetID: "take-b", FootageIndexer.searchRows(shots: shots, transcripts: try store.transcripts().filter { $0.assetID == "take-b" }, screen: try store.screenText(assetID: "take-b")))
        let hit = try #require(try FootageSearch.search("Navier Stokes", store: store).first)
        // When it's on screen, not the whole shot, and only the lines that matched.
        #expect(hit.why == .screen && hit.start == 4.5 && hit.end == 8.5)
        #expect(hit.text == "Navier\u{2013}Stokes existence and smoothness" && hit.matched == ["Navier", "Stokes"])
        #expect(try FootageSearch.search("millennium prize", store: store).first?.why == .screen)
        // Every word on screen beats a description that holds one of them.
        #expect(try FootageSearch.search("hands prize problem", store: store).first { $0.assetID == "take-b" }?.why == .screen)
        #expect(try FootageSearch.search("Navier Stokes", store: store, options: .init(wordsOnly: true)).isEmpty)
        // A spoken line still wins on words.
        #expect(try FootageSearch.search("laughing at that bug", store: store).first?.why == .words)
        #expect(FootageSearch.Why.screen.label == "on screen")
    }

    @Test func takesLookedAtBeforeTheReaderAreReadOnce() throws {
        let folder = try IndexTests.temp("unread"); defer { try? FileManager.default.removeItem(at: folder) }
        let (store, _) = try IndexTests.project(folder)
        let asset = MediaAsset(id: "screen", name: "screen.mov", path: "/screen.mov", duration: .init(seconds: 30), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)])
        _ = try store.addAsset(asset, append: false, expectedRevision: try store.revision())
        var t = TakeIndex(assetID: "screen", state: .done, fingerprint: TakeIndex.fingerprint(try store.read().asset("screen")))
        t.firstPassDone = true; t.shotCount = 1; t.described = 1
        try store.saveTakeIndex(t)
        #expect(try FootageIndexer.pending(store: store, assetIDs: nil, force: false, engine: nil).map(\.id) == ["screen"])
        t.screenTextVersion = ScreenReader.version
        try store.saveTakeIndex(t)
        #expect(try FootageIndexer.pending(store: store, assetIDs: nil, force: false, engine: nil).isEmpty)
        // New shots drop the old text with them.
        try store.replaceScreenText(assetID: "screen", [ScreenText(assetID: "screen", shotID: "old", start: 0, end: 30, lines: ["Old"])])
        try store.replaceShots(assetID: "screen", [Shot(assetID: "screen", number: 1, start: 0, end: 30)])
        #expect(try store.screenText(assetID: "screen").isEmpty)
    }
}
