import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import DirectionCore
@testable import DirectionMedia
import DirectionTools

/// Six seconds of a made-up screen recording at 640×360: "Settings" in the top right all through; a cursor
/// circling near the top left from 1 to 3 s; a new page at 3.2 s; typing growing a line near the bottom
/// right from 4 to 5.5 s.
func writeScreenMovie(to url: URL) async throws {
    let w = 640, h = 360
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 34, nil)
    let words = CTLineCreateWithAttributedString(NSAttributedString(string: "Settings", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)]))
    for i in 0..<180 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate a frame.") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let c = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        let t = Double(i) / 30
        // Core Graphics counts y up from the bottom; the comments count it down from the top.
        c.setFillColor(CGColor(gray: t < 3.2 ? 0.93 : 0.78, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.textPosition = CGPoint(x: 470, y: h - 50); CTLineDraw(words, c)
        c.setFillColor(CGColor(gray: 0.05, alpha: 1))
        if t >= 1, t < 3 { c.fill(CGRect(x: 110 + 24 * sin(t * 4), y: Double(h) - 90 - 14 * cos(t * 4), width: 12, height: 16)) }
        if t >= 4, t < 5.5 { c.fill(CGRect(x: 380, y: Double(h) - 262, width: 12 + (t - 4) * 120, height: 16)) }
        if t >= 5.5 { c.fill(CGRect(x: 380, y: Double(h) - 262, width: 192, height: 16)) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write a frame.") }
    }
    input.markAsFinished(); await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish the movie.") }
}

@Suite(.serialized) struct ScreenZoomTests {
    private func film() async throws -> (URL, ProjectStore, ToolRuntime, MediaAsset) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("direction-zoom-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let movie = root.appendingPathComponent("Screen Recording 2026-10-31.mov")
        try await writeScreenMovie(to: movie)
        let store = try ProjectStore.create(at: root.appendingPathComponent("Demo.direction"), name: "Demo")
        let runtime = try ToolRuntime(store: store)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(movie.path), "append": .bool(true)]))
        return (root, store, runtime, try #require(try store.read().assets.first))
    }

    @Test func theActivityShowsTheCursorTheNewPageAndTheTyping() async throws {
        let (root, _, runtime, screen) = try await film(); defer { try? FileManager.default.removeItem(at: root) }
        let samples = try await ScreenActivity.measure(screen, from: 0, to: 6, cacheDirectory: runtime.cacheDirectory)
        #expect(samples.count >= 23)
        let cursor = samples.filter { $0.t > 1.2 && $0.t < 2.9 && $0.amount > 0 }, typing = samples.filter { $0.t > 4.2 && $0.t < 5.4 && $0.amount > 0 }
        #expect(!cursor.isEmpty && cursor.allSatisfy { $0.cx < 0.3 && $0.cy < 0.35 && $0.w < 0.2 })
        #expect(!typing.isEmpty && typing.allSatisfy { $0.cx > 0.55 && $0.cy > 0.65 })
        // At the change, or the look after it when a busy Mac dropped that frame.
        #expect(samples.contains { abs($0.t - 3.25) < 0.3 && $0.amount >= ZoomPlanner.pageChange })
        // The still opening shows nothing. (The end isn't still for long: a look can land an eighth of a
        // second early, so the one at 5.75 may still see the typing that stops at 5.5.)
        #expect(samples.filter { $0.t < 0.9 }.allSatisfy { $0.amount == 0 })
        // Looked at once: the second time is read back.
        let again = try await ScreenActivity.measure(screen, from: 0, to: 6, cacheDirectory: runtime.cacheDirectory)
        #expect(again == samples)
    }

    @Test func autoZoomGoesToTheCursorThenTheTyping() async throws {
        let (root, store, runtime, _) = try await film(); defer { try? FileManager.default.removeItem(at: root) }
        let p = try store.read()
        _ = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "summary": .string("Zooms"), "operations": .array([.object(["op": .string("autoZoom"), "range": .object(["start": .number(0), "end": .number(6)])])])]))
        let clip = try #require(try store.read().sequences[0].clips.first)
        let t = try #require(clip.effects?.first { $0.name == "transform" })
        let scale = try #require(t.keys?["scale"]), x = try #require(t.keys?["x"]), y = try #require(t.keys?["y"])
        // Two zooms, all the way in on the small cursor and less on the wider typing, back out at the new page
        // between them, each toward its corner of the screen.
        // A busy Mac can sample the screen a beat late and leave a hold too short to see between the zoom out and the
        // next zoom in (1.0 at 3.5, 1.0 at 3.65): keys of one value under a quarter second apart count as one. The zoom
        // out is at the new page (3.2 s), or the look after it (3.5 s) when that frame was dropped.
        let keys = scale.enumerated().filter { i, k in i == 0 || !(k.v == scale[i - 1].v && k.t - scale[i - 1].t < 0.25) }.map(\.element)
        let v = keys.map(\.v)
        #expect(v.count == 7 && v[0] == 1 && v[3] == 1 && v[6] == 1 && v[1] == 2 && v[2] == 2 && (1.6...1.95).contains(v[4]) && v[4] == v[5] && keys[3].t <= 3.55,
                "scale \(scale.map { "\($0.v)@\($0.t)" })")
        #expect(x.contains { $0.v > 0.1 } && y.contains { $0.v > 0.1 } && x.contains { $0.v < -0.1 } && y.contains { $0.v < -0.1 })
    }

    @Test func zoomToFindsWordsOnScreen() async throws {
        let (root, store, runtime, _) = try await film(); defer { try? FileManager.default.removeItem(at: root) }
        let p = try store.read()
        _ = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(p.editRevision)), "summary": .string("Zoom"), "operations": .array([
            .object(["op": .string("zoomTo"), "range": .object(["start": .number(0.2), "end": .number(2.6)]), "focus": .object(["text": .string("settings")])]),
        ])]))
        let t = try #require(try store.read().sequences[0].clips.first?.effects?.first { $0.name == "transform" })
        // "Settings" is top right: the picture moves left and down to bring it toward the middle.
        let zoomed = try #require(t.keys?["x"]?[1].v), lowered = try #require(t.keys?["y"]?[1].v)
        #expect(zoomed < -0.2 && lowered > 0.2)
        do {
            _ = try await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.read().editRevision)), "summary": .string("Zoom"), "operations": .array([
                .object(["op": .string("zoomTo"), "range": .object(["start": .number(0.2), "end": .number(2.6)]), "focus": .object(["text": .string("Billing")])]),
            ])]))
            Issue.record("Billing isn't on screen")
        } catch let e as DirectionError { #expect(e.code == "bad_argument" && e.message.contains("isn\u{2019}t on screen")) }
    }
}
