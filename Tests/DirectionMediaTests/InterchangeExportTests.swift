import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import DirectionCore
@testable import DirectionMedia
import DirectionTools

/// The timeline folder for other editing apps (issue #4), end to end: renders, sound, the FCPXML, and the
/// timecode other apps match frames by.
@Suite("Timeline for other editing apps", .serialized)
struct InterchangeExportTests {
    @Test func aCutGoesOutAsAFolderOtherAppsOpen() async throws {
        let f = try await MediaFixture.make()
        defer { f.cleanup() }
        let asset = try #require(try f.store.read().assets.first)
        // The take, then again from half a second in, a dissolve between, and a freeze: the freeze is rendered, the rest isn't.
        let first = try #require(try f.store.read().sequences[0].clips.first)
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Cut"), "operations": .array([
            .object(["op": .string("removeRange"), "range": .object(["start": .number(2.5), "end": .number(3)])]),
            .object(["op": .string("insert"), "assetID": .string(asset.id), "sourceRange": .object(["start": .number(0.5), "end": .number(2.5)]), "at": .number(2.5)]),
        ])]))
        let second = try #require(try f.store.read().sequences[0].clips.first { $0.id != first.id && $0.layer == 0 })
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("Dissolve and freeze"), "operations": .array([
            .object(["op": .string("transition"), "editPoint": .string("\(first.id)|\(second.id)"), "type": .string("dissolve"), "frames": .number(10)]),
            .object(["op": .string("freeze"), "clipID": .string(second.id), "at": .number(3.5), "seconds": .number(0.5)]),
        ])]))
        // The take's own camera LUT: copied, and named for it in the read-me.
        let cube = f.directory.appendingPathComponent("Slog to 709.cube")
        try CubeLUT.identity(size: 2).text.write(to: cube, atomically: true, encoding: .utf8)
        _ = try await f.runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try f.store.revision())), "idempotencyKey": .string(UUID().uuidString), "summary": .string("LUT"), "operations": .array([
            .object(["op": .string("cameraLUT"), "assetID": .string(asset.id), "lut": .string(cube.path)]),
        ])]))
        let folder = f.directory.appendingPathComponent("Export/Integration fixture \u{2013} Timeline")
        let response = try await f.runtime.invoke("direction_export", arguments: .object(["preset": .string("timeline"), "path": .string(folder.path)]))
        let job = try await f.runtime.waitForJob(try response.value.decode(JobRecord.self).id)
        let result = try #require(job.result)
        #expect(result["renders"].array?.count == 1 && result["renders"].array?.first?["why"].string == "a freeze", "\(result)")
        #expect(result["sound"].array?.compactMap(\.string) == ["Mix", "A1 Dialogue"])

        // The render is the freeze's frames, the sound files are the cut's length.
        let s = try f.store.read().sequences[0]
        let renders = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("Renders"), includingPropertiesForKeys: nil)
        let render = try #require(renders.first)
        #expect(abs(try await AVURLAsset(url: render).load(.duration).seconds - 0.5) < 0.04)
        for name in ["Mix", "A1 Dialogue"] {
            let file = try AVAudioFile(forReading: folder.appendingPathComponent("Sound/Integration fixture \u{2013} \(name).wav"))
            #expect(file.length == AVAudioFramePosition((s.duration.seconds * 48_000).rounded()) && file.fileFormat.channelCount == 2)
        }
        let readMe = try String(contentsOf: folder.appendingPathComponent("Read Me.txt"), encoding: .utf8)
        #expect(readMe.contains("a freeze") && readMe.contains("Final Cut Pro") && readMe.contains("Slog to 709.cube for two-track.mov"), "\(readMe)")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Camera LUTs/Slog to 709.cube").path))

        // The timeline: a dissolve, the take twice, and the render where the freeze is, pointing at the files here.
        let timeline = try #require(result["timeline"].string)
        let xml = try String(contentsOfFile: timeline, encoding: .utf8)
        let doc = try XMLDocument(xmlString: xml)
        #expect(try doc.nodes(forXPath: "//spine/transition").count == 1)
        let srcs = try doc.nodes(forXPath: "//media-rep/@src").compactMap(\.stringValue)
        #expect(srcs.contains { $0.hasSuffix("two-track.mov") } && srcs.contains { $0.contains("/Renders/") && $0.hasPrefix(folder.absoluteString) })
        // Final Cut's DTD, when it's at hand (it isn't kept in the repository).
        if let dtd = ProcessInfo.processInfo.environment["DIRECTION_FCPXML_DTD"] {
            let lint = Process()
            lint.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint"); lint.arguments = ["--noout", "--dtdvalid", dtd, timeline]
            try lint.run(); lint.waitUntilExit()
            #expect(lint.terminationStatus == 0)
        }
        // Never over what's there.
        let again = try await f.runtime.invoke("direction_export", arguments: .object(["preset": .string("timeline"), "path": .string(folder.path)]))
        await #expect(throws: DirectionError.self) { _ = try await f.runtime.waitForJob(try again.value.decode(JobRecord.self).id) }
    }

    @Test func timecodeIsReadFromTheFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("timecode.mov")
        try await Self.writeMovie(url, timecodeFrame: 108_000)
        let start = await InterchangeExport.timecodeStart(url)
        let kinds = try await AVURLAsset(url: url).load(.tracks).map(\.mediaType.rawValue)
        #expect(start == 3600, "\(String(describing: start)) \(kinds)")
        let plain = dir.appendingPathComponent("plain.mov")
        try await Self.writeMovie(plain, timecodeFrame: nil)
        #expect(await InterchangeExport.timecodeStart(plain) == nil)
    }

    @Test func aSoundRecordersTimeReferenceIsItsStart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bwf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 48 kHz, a bext chunk saying 01:00:00:00 (172,800,000 samples since midnight), a moment of silence.
        var d = Data()
        func text(_ s: String) { d.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        var bext = Data(count: 602)
        withUnsafeBytes(of: UInt32(172_800_000).littleEndian) { bext.replaceSubrange(338..<342, with: $0) }
        let riffSize: UInt32 = 10_254
        text("RIFF"); u32(riffSize); text("WAVE")
        text("bext"); u32(602); d.append(bext)
        text("fmt "); u32(16); u16(1); u16(1); u32(48_000); u32(96_000); u16(2); u16(16)
        text("data"); u32(9600); d.append(Data(count: 9600))
        let url = dir.appendingPathComponent("Sound 1.wav")
        try d.write(to: url)
        #expect(InterchangeExport.broadcastWaveStart(url) == 3600)
        let plain = dir.appendingPathComponent("tone.wav")
        try MediaFixture.writeTone(to: plain, frequency: 440, seconds: 0.2)
        #expect(InterchangeExport.broadcastWaveStart(plain) == nil)
    }

    /// One second of 30 fps picture, with a timecode track starting at `timecodeFrame` when given.
    static func writeMovie(_ url: URL, timecodeFrame: Int32?) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 36])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 36])
        writer.add(input)
        var tcInput: AVAssetWriterInput?
        var format: CMTimeCodeFormatDescription?
        if timecodeFrame != nil {
            CMTimeCodeFormatDescriptionCreate(allocator: nil, timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32, frameDuration: CMTime(value: 1, timescale: 30), frameQuanta: 30, flags: 0, extensions: nil, formatDescriptionOut: &format)
            let tc = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: format)
            writer.add(tc); input.addTrackAssociation(withTrackOf: tc, type: AVAssetTrack.AssociationType.timecode.rawValue)
            tcInput = tc
        }
        writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished()
        if let tcInput, let format, let frame = timecodeFrame {
            var value = frame.bigEndian
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 4, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 4, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
            CMBlockBufferReplaceDataBytes(with: &value, blockBuffer: block!, offsetIntoDestination: 0, dataLength: 4)
            var timing = CMSampleTimingInfo(duration: CMTime(value: 30, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            var size = 4
            var sample: CMSampleBuffer?
            CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
            while !tcInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            tcInput.append(sample!)
            tcInput.markAsFinished()
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write the movie.") }
    }
}
