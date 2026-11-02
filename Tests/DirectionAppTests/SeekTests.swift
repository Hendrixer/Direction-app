import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// The scene strip on a real player: a click lands where you click and stays there.
@Suite("Seeking", .serialized)
@MainActor
struct SeekTests {
    /// Six seconds of 320×180 picture, imported into a new film.
    private func film() async throws -> (FilmModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seek-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let movie = dir.appendingPathComponent("picture.mov")
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<180 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "No frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let c = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            c.setFillColor(CGColor(gray: Double(i) / 180, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished(); await writer.finishWriting()
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Seek.direction"), name: "Seek")
        let runtime = try ToolRuntime(store: store)
        _ = try await runtime.invoke("direction_import", arguments: .object(["path": .string(movie.path), "append": .bool(true)]))
        let m = FilmModel()
        m.runtime = runtime
        m.refresh(force: true)
        m.loadDisplayed(force: true)
        for _ in 0..<200 where m.isPreparing || m.player.currentItem?.status != .readyToPlay { try await Task.sleep(for: .milliseconds(25)) }
        #expect(m.player.currentItem?.status == .readyToPlay)
        return (m, dir)
    }

    /// What the strip does on a click while the cut plays: pause, then seek. The player still
    /// reports where it was for a moment; the playhead mustn't jump back there.
    @Test func aClickWhilePlayingStaysWhereItLands() async throws {
        let (m, dir) = try await film(); defer { m.close(); try? FileManager.default.removeItem(at: dir) }
        for target in [4.5, 1.2, 3.3] {
            m.togglePlayback()
            try await Task.sleep(for: .milliseconds(300))
            m.pause(); m.seek(target)
            var lowest = m.position
            for _ in 0..<30 { try await Task.sleep(for: .milliseconds(10)); lowest = min(lowest, abs(m.position - target) < 0.05 ? m.position : -1) }
            #expect(lowest >= 0, "the playhead left \(target) after the click")
            #expect(abs(m.position - target) < 0.05)
        }
    }

    /// A take in Dailies, the same way: clicking a shot while the take plays lands on the shot's start and stays,
    /// so the shot clicked is the one lit, not the one the take was in.
    @Test func aShotClickedInATakeStaysWhereItLands() async throws {
        let (m, dir) = try await film(); defer { m.close(); try? FileManager.default.removeItem(at: dir) }
        let p = DailiesTakePlayer(); defer { p.stop() }
        p.load(try #require(m.project?.assets.first), at: 0, autoplay: false)
        for _ in 0..<200 where p.player.currentItem?.status != .readyToPlay { try await Task.sleep(for: .milliseconds(25)) }
        for target in [4.5, 1.2, 3.3] {
            p.toggle()
            try await Task.sleep(for: .milliseconds(300))
            p.toggle(); p.seek(target)
            var lowest = p.position
            for _ in 0..<30 { try await Task.sleep(for: .milliseconds(10)); lowest = min(lowest, abs(p.position - target) < 0.05 ? p.position : -1) }
            #expect(lowest >= 0, "the playhead left \(target) after the click")
            #expect(abs(p.position - target) < 0.05)
        }
    }

    /// A drag sends a seek for every move; the playhead follows the pointer and the picture ends
    /// up where the drag stops.
    @Test func aDragEndsWhereThePointerStops() async throws {
        let (m, dir) = try await film(); defer { m.close(); try? FileManager.default.removeItem(at: dir) }
        for i in 0...50 { m.seek(Double(i) * 0.1); #expect(abs(m.position - Double(i) * 0.1) < 0.001) }
        for _ in 0..<100 where m.seeking { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!m.seeking)
        #expect(abs(m.player.currentTime().seconds - 5.0) < 0.05 && abs(m.position - 5.0) < 0.05)
    }
}
