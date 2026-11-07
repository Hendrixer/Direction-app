import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import DirectionCore
import DirectionTools
@testable import DirectionApp

/// Direction's own finishing steps before the editor starts: each runs when there's something to do, so
/// Finish again never lays captions over the editor's or rolls the same credits twice.
@Suite("Finishing pass", .serialized)
@MainActor
struct FinishingPassTests {
    @Test func aSecondPassChangesNothingAndNewCreditsRollAgain() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pass-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("picture.mov")
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "No frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let c = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            c.setFillColor(CGColor(gray: Double(i) / 90, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished(); await writer.finishWriting()
        // A quiet tone under it, so there's a mix to bring to the target.
        let tone = dir.appendingPathComponent("tone.wav"), format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 144_000)!
        buffer.frameLength = 144_000
        for i in 0..<144_000 { buffer.floatChannelData![0][i] = Float(0.05 * sin(2 * Double.pi * 440 * Double(i) / 48_000)) }
        do { let file = try AVAudioFile(forWriting: tone, settings: format.settings); try file.write(from: buffer) }
        let composition = AVMutableComposition(), length = CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 48_000))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: 1)!.insertTimeRange(length, of: try await AVURLAsset(url: movie).loadTracks(withMediaType: .video)[0], at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 2)!.insertTimeRange(length, of: try await AVURLAsset(url: tone).loadTracks(withMediaType: .audio)[0], at: .zero)
        let source = dir.appendingPathComponent("take.mov")
        try await AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!.export(to: source, as: .mov)
        let store = try ProjectStore.create(at: dir.appendingPathComponent("Pass.direction"), name: "Pass")
        let runtime = try ToolRuntime(store: store)
        let asset = try await runtime.invoke("direction_import", arguments: .object(["path": .string(source.path), "append": .bool(true)])).value["asset"]
        try store.saveTranscript(.init(assetID: asset["id"].string ?? "", audioTrackID: Int32(asset["audio"].array?.first?["id"].int ?? 0), provider: "test", words: [
            TranscriptWord(id: "a", text: "We", range: .init(start: 0.2, end: 0.4)), TranscriptWord(id: "b", text: "made", range: .init(start: 0.45, end: 0.7)), TranscriptWord(id: "c", text: "it.", range: .init(start: 0.75, end: 1.0)),
        ]))
        try store.saveCredits("Camera\nSam Ortiz")
        try store.lockPicture(cutID: nil, locked: true)
        func placed() throws -> [String] {
            let p = try store.read()
            return p.sequences[0].clips.filter { $0.layer > 0 }.compactMap { c in c.assetID.flatMap { id in p.assets.first { $0.id == id }?.graphic } }.sorted()
        }

        await FinishingPass.run(store: store, runID: "run-1")
        let first = try placed(), revision = try store.revision()
        #expect(first.contains { $0.hasPrefix("captions-") } && first.contains { $0.hasPrefix("credits-") }, "\(first)")
        #expect(try store.read().sequences[0].mixGainDB != nil, "the quiet mix was brought up")
        // Finish again: the captions and credits are there, so nothing is laid again.
        await FinishingPass.run(store: store, runID: "run-2")
        #expect(try placed() == first && store.revision() == revision)
        // The director changed their credits: those roll again, the captions stay.
        try store.saveCredits("Camera\nSam Ortiz\n\nSound\nLee Park")
        await FinishingPass.run(store: store, runID: "run-3")
        let third = try placed()
        #expect(third.filter { $0.hasPrefix("captions-") } == first.filter { $0.hasPrefix("captions-") } && third.filter { $0.hasPrefix("credits-") } != first.filter { $0.hasPrefix("credits-") }, "\(third)")
        let titles = try store.directingState().finishing?.first { $0.id == "titles" }?.detail ?? ""
        #expect(titles.components(separatedBy: "Direction rolled").count == 2, "\(titles)")
    }
}
