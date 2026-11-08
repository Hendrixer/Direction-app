import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import DirectionCore
import DirectionMedia

private final class Reports: @unchecked Sendable {
    private let lock = NSLock(); private var list: [Double] = []
    func add(_ value: Double) { lock.withLock { list.append(value) } }
    var values: [Double] { lock.withLock { list } }
}

/// Sending a take's range and finishing a made shot (made-media.md). Every file lives in a temp folder.
/// Super resolution only runs when Apple's model is already on this Mac; nothing here downloads it.
struct MadeProcessingTests {
    // MARK: Fixtures

    static func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("direction-made-processing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 24 fps H.264: a red top-left quarter over dark blue, and a yellow box moving 1/80 of the width a frame
    /// along the bottom. Optionally a 440 Hz tone, a track transform, or noise that doesn't compress.
    static func clip(in folder: URL, width: Int = 640, height: Int = 360, frames: Int = 48, sound: Bool = false, transform: CGAffineTransform = .identity, noise: Bool = false) async throws -> URL {
        let picture = folder.appendingPathComponent("picture-\(UUID().uuidString.prefix(6)).mov")
        let writer = try AVAssetWriter(outputURL: picture, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)); if writer.status == .failed { throw writer.error! } }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("fixture_failed", "Cannot allocate fixture frame.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!, stride = CVPixelBufferGetBytesPerRow(buffer)
            if noise {
                let words = base.bindMemory(to: UInt64.self, capacity: stride * height / 8)
                for w in 0..<(stride * height / 8) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; words[w] = seed | 0xFF00_0000_FF00_0000 }
            } else {
                let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
                context.setFillColor(CGColor(red: 0.1, green: 0.15, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
                let side = Double(height) / 6
                context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)); context.fill(CGRect(x: Double(width) / 40 + Double(i * width) / 80, y: Double(height) / 10, width: side, height: side))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 24)) else { throw writer.error ?? DirectionError("fixture_failed", "Cannot write fixture video.") }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DirectionError("fixture_failed", "Cannot finish fixture video.") }
        guard sound else { return picture }
        let tone = folder.appendingPathComponent("tone-\(UUID().uuidString.prefix(6)).wav")
        try MediaFixture.writeTone(to: tone, frequency: 440, seconds: Double(frames) / 24)
        let composition = AVMutableComposition(), length = CMTimeRange(start: .zero, duration: CMTime(value: Int64(frames), timescale: 24))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: 1)!.insertTimeRange(length, of: try await AVURLAsset(url: picture).loadTracks(withMediaType: .video)[0], at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: 2)!.insertTimeRange(length, of: try await AVURLAsset(url: tone).loadTracks(withMediaType: .audio)[0], at: .zero)
        let out = folder.appendingPathComponent("with-sound-\(UUID().uuidString.prefix(6)).mov")
        try await AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!.export(to: out, as: .mov)
        return out
    }

    static func frameCount(_ url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url), reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .video)[0], outputSettings: nil)
        reader.add(output); reader.startReading()
        var n = 0
        while let sample = await output.nextSample(of: reader) { n += CMSampleBufferGetNumSamples(sample) }
        return n
    }

    /// Where the yellow box is in each frame, as a fraction of the width.
    static func boxCenters(_ url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url), reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .video)[0], outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); reader.startReading()
        var centers: [Double] = []
        while let sample = await output.nextSample(of: reader), let buffer = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            var sum = 0.0, count = 0.0
            // Weighted by how yellow each pixel is, so soft edges place it between pixels.
            for y in (h / 2)..<h { for x in 0..<w { let p = bytes + y * stride + x * 4, weight = max(0, Double(p[1]) - Double(p[0]) - 40); sum += weight * (Double(x) + 0.5); count += weight } }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            centers.append(count > 0 ? sum / count / Double(w) : -1)
        }
        return centers
    }

    /// The mean color of each quarter of the upright picture (0 top-left, 1 top-right, 2 bottom-left,
    /// 3 bottom-right), 0–255, from the middle of each so soft edges don't count.
    static func quarters(_ url: URL) async throws -> [[Double]] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(value: 1, timescale: 24)).image
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let context = CGContext(data: &pixels, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.itur_709)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        var sums = [[Double]](repeating: [0, 0, 0], count: 4)
        for y in 0..<64 where (8..<24).contains(y % 32) { for x in 0..<64 where (8..<24).contains(x % 32) { let i = (y * 64 + x) * 4; for c in 0..<3 { sums[(y / 32) * 2 + x / 32][c] += Double(pixels[i + c]) / 256 } } }
        return sums
    }

    /// Which quarter of the upright picture is the red one.
    static func redQuarter(_ url: URL) async throws -> Int {
        let quarters = try await quarters(url)
        return quarters.indices.max { quarters[$0][0] - quarters[$0][2] < quarters[$1][0] - quarters[$1][2] }!
    }

    /// The red quarter's color came through within a few levels.
    static func sameColor(_ a: URL, _ b: URL) async throws -> Bool {
        let x = try await quarters(a)[try await redQuarter(a)], y = try await quarters(b)[try await redQuarter(b)]
        return zip(x, y).allSatisfy { abs($0 - $1) < 4 }
    }

    static func isTenBitHEVC(_ track: AVAssetTrack) async throws -> Bool {
        guard let description = try await track.load(.formatDescriptions).first else { return false }
        let bits = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent) as? Int
        return CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_HEVC && bits == 10
    }

    static func loudness(_ track: AVAssetTrack, in asset: AVAsset) async throws -> Double {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
        reader.add(output); reader.startReading()
        var sum = 0.0, n = 0
        while let sample = await output.nextSample(of: reader), let block = CMSampleBufferGetDataBuffer(sample) {
            var length = 0, pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            pointer!.withMemoryRebound(to: Float.self, capacity: length / 4) { for i in 0..<(length / 4) { sum += Double($0[i] * $0[i]) } }
            n += length / 4
        }
        return n > 0 ? sqrt(sum / Double(n)) : 0
    }

    // MARK: Sending a range

    @Test func exportRangeMakesASmallSilentMP4() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, sound: true)
        let out = folder.appendingPathComponent("range.mp4")
        try await MadeProcessing.exportRange(source.path, start: 0.5, end: 1.5, maxDimension: 320, to: out)
        let asset = AVURLAsset(url: out)
        let video = try await asset.loadTracks(withMediaType: .video)
        #expect(video.count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await video[0].load(.naturalSize) == CGSize(width: 320, height: 180))
        let subtype = try await video[0].load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        #expect(subtype == kCMVideoCodecType_H264)
        #expect(abs(try await asset.load(.duration).seconds - 1.0) < 0.5 / 24)
        #expect(try await Self.frameCount(out) == 24)
        #expect(try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int ?? .max <= 16_000_000)
        // Clamped to the take: the clip is 2 s long.
        try await MadeProcessing.exportRange(source.path, start: 1.5, end: 9, maxDimension: 320, to: out)
        #expect(try await Self.frameCount(out) == 12)
    }

    @Test func exportRangeShrinksUntilItFits() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, frames: 48, noise: true)
        let out = folder.appendingPathComponent("range.mp4")
        try await MadeProcessing.exportRange(source.path, start: 0, end: 2, maxDimension: 640, maxBytes: 120_000, to: out)
        let bytes = try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int ?? .max
        #expect(bytes <= 120_000)
        let size = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0].load(.naturalSize)
        #expect(Int(size.width) % 2 == 0 && Int(size.height) % 2 == 0 && size.width <= 640)
        #expect(abs(size.width / size.height - 16.0 / 9) < 0.03)
        // Nothing fits in a kilobyte.
        await #expect(throws: DirectionError.self) { try await MadeProcessing.exportRange(source.path, start: 0, end: 2, maxBytes: 1_000, to: out) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func exportRangeBakesInRotation() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        // Stored landscape, shown portrait (a phone held upright).
        let source = try await Self.clip(in: folder, frames: 12, transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0))
        let out = folder.appendingPathComponent("range.mp4")
        try await MadeProcessing.exportRange(source.path, start: 0, end: 0.5, maxDimension: 320, to: out)
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0]
        #expect(try await track.load(.naturalSize) == CGSize(width: 180, height: 320))
        #expect(try await track.load(.preferredTransform) == .identity)
        let red = try await Self.redQuarter(source)
        #expect(red == 1)
        #expect(try await Self.redQuarter(out) == red)
        #expect(try await Self.sameColor(source, out))
    }

    // MARK: Finishing

    @Test func rangeAndDropFirstFrame() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, sound: true)
        let out = folder.appendingPathComponent("tail.mov")
        let result = try await MadeProcessing.process(source, .init(range: 0.5...1.5, dropFirstFrame: true), to: out)
        #expect(result == .init(width: 640, height: 360, frames: 23, duration: result.duration, sharpened: false))
        #expect(abs(result.duration - 23.0 / 24) < 1e-6)
        #expect(try await Self.frameCount(out) == 23)
        let asset = AVURLAsset(url: out)
        let video = try await asset.loadTracks(withMediaType: .video)[0]
        #expect(try await Self.isTenBitHEVC(video))
        #expect(try await Self.sameColor(source, out))
        #expect(abs(try await asset.load(.duration).seconds - 23.0 / 24) < 1e-3)
        // The box was at frame 13 when the shot now starts.
        let centers = try await Self.boxCenters(out)
        #expect(abs(centers[0] - (1.0 / 40 + 13.0 / 80 + 1.0 / 12 / 1.0 * 9 / 16)) < 0.01)
        // Sound comes along, trimmed to the same frames.
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        if let sound = audio.first {
            #expect(abs(try await sound.load(.timeRange).duration.seconds - 23.0 / 24) < 0.005)
            #expect(try await Self.loudness(sound, in: asset) > 0.05)
        }
    }

    @Test func dropLastFrameWithoutSound() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, sound: true)
        let out = folder.appendingPathComponent("head.mov")
        let result = try await MadeProcessing.process(source, .init(dropLastFrame: true, keepSound: false), to: out)
        #expect(result.frames == 47)
        #expect(try await Self.frameCount(out) == 47)
        #expect(try await AVURLAsset(url: out).loadTracks(withMediaType: .audio).isEmpty)
        let centers = try await Self.boxCenters(out)
        #expect(abs(centers.last! - (1.0 / 40 + 46.0 / 80 + 9.0 / 16 / 12)) < 0.01)
    }

    @Test func keepSoundCarriesAudio() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, sound: true)
        let out = folder.appendingPathComponent("whole.mov")
        let progress = Reports()
        let result = try await MadeProcessing.process(source, .init(), to: out) { progress.add($0) }
        #expect(result == .init(width: 640, height: 360, frames: 48, duration: 2, sharpened: false))
        let asset = AVURLAsset(url: out)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        if let sound = audio.first {
            #expect(abs(try await sound.load(.timeRange).duration.seconds - 2) < 0.005)
            #expect(try await Self.loudness(sound, in: asset) > 0.05)
        }
        let reports = progress.values
        #expect(reports.last == 1)
        #expect(zip(reports, reports.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func slowMotionMakesFramesBetween() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, sound: true)
        let out = folder.appendingPathComponent("slow.mov")
        let result = try await MadeProcessing.process(source, .init(slowMotion: 2), to: out)
        #expect(result.frames == 95)
        #expect(try await Self.frameCount(out) == 95)
        #expect(abs(result.duration - 95.0 / 24) < 1e-6)
        #expect(abs(result.duration - 2 * 2) <= 1.0 / 24 + 1e-6)
        #expect(try await AVURLAsset(url: out).loadTracks(withMediaType: .audio).isEmpty)
        // Made frames sit halfway: the box moves half as far each frame.
        let centers = try await Self.boxCenters(out)
        let steps = zip(centers, centers.dropFirst()).map { $1 - $0 }
        #expect(steps.allSatisfy { abs($0 - 1.0 / 160) < 0.002 })
    }

    @Test func slowMotionAfterAFit() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder)
        let out = folder.appendingPathComponent("slow-small.mov")
        // 12 frames, three times slower: 34, less the join frame.
        let result = try await MadeProcessing.process(source, .init(range: 0...0.5, dropFirstFrame: true, sharpenTo: .init(width: 320, height: 320), slowMotion: 3), to: out)
        #expect(result == .init(width: 320, height: 180, frames: 33, duration: 33.0 / 24, sharpened: false))
        #expect(try await Self.frameCount(out) == 33)
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0]
        #expect(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
        #expect(try await Self.isTenBitHEVC(track))
        let centers = try await Self.boxCenters(out)
        let steps = zip(centers, centers.dropFirst()).map { $1 - $0 }
        #expect(steps.allSatisfy { abs($0 - 1.0 / 240) < 0.003 })
    }

    @Test func rotatedTakesStayUpright() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let turned = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        let source = try await Self.clip(in: folder, frames: 6, transform: turned)
        let out = folder.appendingPathComponent("turned.mov")
        // Frames that aren't fitted keep the take's transform.
        let kept = try await MadeProcessing.process(source, .init(slowMotion: 2), to: out)
        #expect(kept == .init(width: 360, height: 640, frames: 11, duration: 11.0 / 24, sharpened: false))
        #expect(try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0].load(.preferredTransform) == turned)
        #expect(try await Self.redQuarter(out) == 1)
        // A fit draws them upright.
        let fit = try await MadeProcessing.process(source, .init(sharpenTo: .init(width: 180, height: 180)), to: out)
        #expect(fit == .init(width: 102, height: 180, frames: 6, duration: 0.25, sharpened: false))
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0]
        #expect(try await track.load(.naturalSize) == CGSize(width: 102, height: 180))
        #expect(try await track.load(.preferredTransform) == .identity)
        #expect(try await Self.redQuarter(out) == 1)
        #expect(try await Self.sameColor(source, out))
    }

    @Test func sharpenFallsBackToAPlainFit() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        // Wider than super resolution takes, either way up.
        #expect(MadeProcessing.sharpeningStatus(width: 2048, height: 1152) == .unsupported)
        let big = try await Self.clip(in: folder, width: 2048, height: 1152, frames: 6)
        let out = folder.appendingPathComponent("fit.mov")
        let result = try await MadeProcessing.process(big, .init(sharpenTo: .init(width: 2500, height: 1500)), to: out)
        #expect(result == .init(width: 2500, height: 1406, frames: 6, duration: 0.25, sharpened: false, sharpenedFrom: nil))
        #expect(try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0].load(.naturalSize) == CGSize(width: 2500, height: 1406))
        #expect(try await Self.redQuarter(out) == 0)
        #expect(try await Self.sameColor(big, out))
        // Smaller than the shot: nothing to sharpen, just a fit, to even sizes inside an odd box.
        let small = try await Self.clip(in: folder, frames: 6)
        let fit = try await MadeProcessing.process(small, .init(sharpenTo: .init(width: 501, height: 501)), to: out)
        #expect(fit == .init(width: 500, height: 282, frames: 6, duration: 0.25, sharpened: false))
        // Without the model, a bigger size is still a fit.
        if MadeProcessing.sharpeningStatus(width: 640, height: 360) != .ready {
            let up = try await MadeProcessing.process(small, .init(sharpenTo: .init(width: 1920, height: 1080)), to: out)
            #expect(up == .init(width: 1920, height: 1080, frames: 6, duration: 0.25, sharpened: false))
        }
    }

    @Test(.enabled(if: MadeProcessing.sharpeningStatus(width: 640, height: 360) == .ready, "Apple's super-resolution model isn't on this Mac"))
    func sharpenWithSuperResolution() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, frames: 12)
        let out = folder.appendingPathComponent("sharp.mov")
        let result = try await MadeProcessing.process(source, .init(sharpenTo: .init(width: 1920, height: 1080)), to: out)
        #expect(result == .init(width: 1920, height: 1080, frames: 12, duration: 0.5, sharpened: true, sharpenedFrom: .init(width: 640, height: 360)))
        let track = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)[0]
        #expect(try await track.load(.naturalSize) == CGSize(width: 1920, height: 1080))
        #expect(try await Self.isTenBitHEVC(track))
        #expect(try await Self.redQuarter(out) == 0)
        #expect(try await Self.sameColor(source, out))
        let centers = try await Self.boxCenters(out)
        #expect(centers.count == 12)
        #expect(zip(centers, centers.dropFirst()).allSatisfy { abs($1 - $0 - 1.0 / 80) < 0.003 })
    }

    @Test(.enabled(if: MadeProcessing.sharpeningStatus(width: 608, height: 1088) == .ready, "Apple's super-resolution model isn't on this Mac"))
    func sharpenTurnsTallFramesOnTheirSide() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        // Taller than the 1080 super resolution takes: it runs on the frame turned sideways.
        let source = try await Self.clip(in: folder, width: 608, height: 1088, frames: 6)
        let out = folder.appendingPathComponent("tall.mov")
        let result = try await MadeProcessing.process(source, .init(sharpenTo: .init(width: 1216, height: 2176)), to: out)
        #expect(result == .init(width: 1216, height: 2176, frames: 6, duration: 0.25, sharpened: true, sharpenedFrom: .init(width: 608, height: 1088)))
        #expect(try await Self.redQuarter(out) == 0)
        #expect(try await Self.sameColor(source, out))
    }

    @Test func sharpeningStatusAnswersBySize() {
        #expect(MadeProcessing.sharpeningStatus(width: 8000, height: 8000) == .unsupported)
        #expect(MadeProcessing.sharpeningStatus(width: 640, height: 360) == MadeProcessing.sharpeningStatus(width: 360, height: 640))
        #expect(MadeProcessing.sharpeningStatus(width: 1280, height: 720) == MadeProcessing.sharpeningStatus(width: 720, height: 1280))
    }

    @Test func rejectsStepsItCantDo() async throws {
        let folder = try Self.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let source = try await Self.clip(in: folder, frames: 6)
        let out = folder.appendingPathComponent("bad.mov")
        await #expect(throws: DirectionError.self) { try await MadeProcessing.process(source, .init(slowMotion: 5), to: out) }
        await #expect(throws: DirectionError.self) { try await MadeProcessing.process(source, .init(range: 10...12), to: out) }
        await #expect(throws: DirectionError.self) { try await MadeProcessing.exportRange(source.path, start: 0.2, end: 0.2, to: out) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }
}
