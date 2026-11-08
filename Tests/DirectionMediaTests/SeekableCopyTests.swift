import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
import DirectionMedia
import DirectionTools

/// A file with open keyframes comes in as a copy that plays from any frame (architecture.md › Color), checked
/// on a clip x265 writes that way through FFmpeg, as the one that stalled screening was.
struct SeekableCopyTests {
    /// Four seconds at 30 fps with an open keyframe each second, muxed by FFmpeg as an .mp4 that calls each
    /// one a place to start, with two sound tracks. Nil without FFmpeg's x265.
    static func openKeyframes(in folder: URL, name: String = "Take 1.mp4") async throws -> URL? {
        guard let ffmpeg = WhisperTranscriber.ffmpeg() else { return nil }
        let out = folder.appendingPathComponent(name)
        let p = Process(); p.executableURL = ffmpeg; p.standardError = FileHandle.nullDevice
        p.arguments = ["-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30:duration=4",
                       "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=4", "-f", "lavfi", "-i", "sine=frequency=660:sample_rate=48000:duration=4",
                       "-map", "0:v", "-map", "1:a", "-map", "2:a", "-c:v", "libx265", "-preset", "ultrafast", "-x265-params", "keyint=30:min-keyint=30:open-gop=1:bframes=3:log-level=error",
                       "-pix_fmt", "yuv420p", "-tag:v", "hvc1", "-c:a", "aac", out.path]
        // Waited for without holding one of Swift's shared threads, which the media tests need for reading.
        let status: Int32 = try await withCheckedThrowingContinuation { done in
            p.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { p.terminationHandler = nil; done.resume(throwing: error) }
        }
        return status == 0 ? out : nil
    }

    /// Three seconds of HEVC from Apple's encoder, a keyframe each second and frames reordered around it, as an iPhone writes.
    static func appleHEVC(in folder: URL) async throws -> URL {
        let url = folder.appendingPathComponent("IMG_0001.MOV")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // The hardware encoder, as an iPhone's: it reorders frames around each keyframe.
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 180, AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 30, AVVideoAllowFrameReorderingKey: true],
                                                                          AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180, kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<90 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate a frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: Double(i) / 90, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            context.setFillColor(CGColor(gray: 1, alpha: 0.6)); context.fill(CGRect(x: 10 + 3 * i, y: 60, width: 40, height: 40))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write a frame.") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish the clip.") }
        return url
    }

    /// From the sample table: keyframes after the first with a frame shown before them next, and partial keyframes.
    static func keyframes(_ url: URL) async throws -> (open: Int, partial: Int) {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let cursor = try #require(track.makeSampleCursorAtFirstSampleInDecodeOrder())
        var open = 0, partial = 0
        while cursor.stepInDecodeOrder(byCount: 1) == 1 {
            let sync = cursor.currentSampleSyncInfo
            if sync.sampleIsPartialSync.boolValue { partial += 1 }
            guard sync.sampleIsFullSync.boolValue, let next = cursor.copy() as? AVSampleCursor, next.stepInDecodeOrder(byCount: 1) == 1, next.presentationTimeStamp < cursor.presentationTimeStamp else { continue }
            open += 1
        }
        return (open, partial)
    }

    /// The frame shown at `frame` (30 fps), asked for on its own as screening and scrubbing ask.
    static func decodes(_ url: URL, frame: Int) async -> Bool {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        return (try? await generator.image(at: CMTime(value: Int64(frame), timescale: 30))) != nil
    }

    /// Every sample's time on each track, in the order it's stored. Sound packets come several to a buffer.
    /// Each track has a reader of its own, read off Swift's shared threads, as the copy reads.
    static func timings(_ url: URL) async throws -> [[CMTime]] {
        let asset = AVURLAsset(url: url)
        var all: [[CMTime]] = []
        for track in try await asset.load(.tracks).sorted(by: { $0.trackID < $1.trackID }) {
            let reader = try AVAssetReader(asset: asset), output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output); reader.startReading()
            nonisolated(unsafe) let read = output, from = reader
            all.append(await withCheckedContinuation { done in
                DispatchQueue(label: "seekable-copy-tests").async {
                    var times: [CMTime] = []
                    while let sample = read.nextSampleWaiting(of: from) {
                        let n = CMSampleBufferGetNumSamples(sample), each = CMTimeMultiplyByRatio(sample.duration, multiplier: 1, divisor: Int32(max(1, n)))
                        for k in 0..<n { times.append(sample.presentationTimeStamp + CMTimeMultiply(each, multiplier: Int32(k))) }
                    }
                    done.resume(returning: times)
                }
            })
        }
        return all
    }

    @Test func aFileWithOpenKeyframesIsCopiedSoEveryFrameDecodes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-seekable-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        guard let original = try await Self.openKeyframes(in: folder) else { return }
        let before = try FileManager.default.attributesOfItem(atPath: original.path)
        // The frame just before each keyframe stalls, though the keyframe itself is fine.
        for frame in [29, 59, 89] { #expect(await !Self.decodes(original, frame: frame), "\(frame)") }
        #expect(await Self.decodes(original, frame: 30))
        #expect(await SeekableCopy.isNeeded(original))

        let footage = folder.appendingPathComponent("Footage")
        let copy = try await SeekableCopy.make(original, in: footage)
        #expect(copy.lastPathComponent == "Take 1.mov")
        #expect(await !SeekableCopy.isNeeded(copy))
        for frame in [0, 15, 28, 29, 30, 58, 59, 60, 88, 89, 90, 119] { #expect(await Self.decodes(copy, frame: frame), "\(frame)") }
        let marks = try await Self.keyframes(copy)
        #expect(marks.open == 0 && marks.partial == 3, "\(marks)")
        // Not re-encoded: every sample at its time, on tracks with the same IDs, so a take's sound settings carry over.
        #expect(try await Self.timings(copy) == Self.timings(original))
        let a = try await MediaInspector.inspect(url: original), b = try await MediaInspector.inspect(url: copy)
        #expect(a.video.map(\.id) == b.video.map(\.id) && a.audio.map(\.id) == b.audio.map(\.id) && b.audio.count == 2)
        #expect(FootageMatch.durationMatches(a, b.duration), "\(a.duration.seconds) \(b.duration.seconds)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: footage.path).filter { $0.hasPrefix(".") }.isEmpty)
        let after = try FileManager.default.attributesOfItem(atPath: original.path)
        #expect(after[.size] as? NSNumber == before[.size] as? NSNumber && after[.modificationDate] as? Date == before[.modificationDate] as? Date)
    }

    /// Apple's encoders reorder frames around a keyframe too, but those decode from it: an iPhone's clips come in as they are.
    @Test func applesFramesAroundAKeyframeAreLeftAlone() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-seekable-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: folder) }
        let clip = try await Self.appleHEVC(in: folder)
        // Busy, the encoder sometimes writes this clip without reordering: then there's nothing here to leave alone.
        guard try await Self.keyframes(clip).open > 0 else { return }
        #expect(await !SeekableCopy.isNeeded(clip))
    }

    @Test func importingItBringsInTheCopyOnce() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        guard let original = try await Self.openKeyframes(in: f.directory) else { return }
        let imported = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(original.path)]))
        let path = try #require(imported.value["asset"]["path"].string)
        #expect(URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path == MediaAsset.copies(in: f.store.url).standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(imported.value["asset"]["seekableCopyOf"].string == original.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(imported.value["asset"]["sdrCopyOf"].string == nil)
        // The same clip again is already in, and no second copy is made.
        await #expect(throws: DirectionError.self) { _ = try await f.runtime.invoke("direction_import", arguments: .object(["path": .string(original.path)])) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: MediaAsset.copies(in: f.store.url).path).filter { $0.hasSuffix(".mov") } == ["Take 1.mov"])
    }

    /// A take brought in before these copies stalls the cut where it's asked for a frame before a keyframe;
    /// it gets its copy in place, once, and the cut plays there.
    @Test func aTakeAlreadyInGetsItsCopyInPlace() async throws {
        let f = try await MediaFixture.make(); defer { f.cleanup() }
        guard let original = try await Self.openKeyframes(in: f.directory) else { return }
        let take = try await MediaInspector.inspect(url: original)
        let clip = try #require(try f.store.addAsset(take, append: true, expectedRevision: f.store.read().editRevision).sequence(nil).clips.first { $0.assetID == take.id && $0.kind == .video })
        let frame = MediaTime(seconds: clip.start.seconds + 29.0 / 30), still = f.directory.appendingPathComponent("frame.png")
        await #expect(throws: (any Error).self) { _ = try await SequenceRenderer.frame(try await SequenceRenderer.compile(project: f.store.read(), cacheDirectory: f.runtime.cacheDirectory), at: frame, to: still) }

        let checked = f.directory.appendingPathComponent("checked.json")
        let copied = try #require(await SeekableCopy.copyTakes(in: f.store, checked: checked).first)
        #expect(copied.id == take.id && copied.name == take.name)
        #expect(copied.seekableCopyOf == original.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(URL(fileURLWithPath: copied.path).deletingLastPathComponent().standardizedFileURL.path == MediaAsset.copies(in: f.store.url).standardizedFileURL.resolvingSymlinksInPath().path)
        _ = try await SequenceRenderer.frame(try await SequenceRenderer.compile(project: f.store.read(), cacheDirectory: f.runtime.cacheDirectory), at: frame, to: still)
        // Asked again, nothing more: the copy plays from any frame, and the fixture's own picture was checked once.
        #expect(await SeekableCopy.copyTakes(in: f.store, checked: checked).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: MediaAsset.copies(in: f.store.url).path).filter { $0.hasSuffix(".mov") } == ["Take 1.mov"])
    }
}
