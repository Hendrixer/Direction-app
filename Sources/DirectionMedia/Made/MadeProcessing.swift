import Foundation
@preconcurrency import AVFoundation
import VideoToolbox
import CoreImage
import Metal
import DirectionCore

/// Picture work around made shots (made-media.md › What the editor can make, Finishing a made shot):
/// a take's range as a small file to send to a service, and the steps that bring a made shot up to the
/// cut (trims, Apple's super resolution, slow motion), written as 10-bit HEVC.
public enum MadeProcessing {
    // MARK: Sending a range

    /// A range of a take as a small H.264 .mp4 (no sound) to send to a service. Longest side ≤ maxDimension,
    /// even dimensions, keeps aspect, rotation baked in. If the file is over maxBytes, it's written again at a
    /// lower bitrate (and then a smaller size) until it fits. The range is clamped to the take.
    public static func exportRange(_ path: String, start: Double, end: Double, maxDimension: Int = 1280, maxBytes: Int = 16_000_000, to output: URL) async throws {
        guard start.isFinite, end.isFinite, end - start > 0 else { throw DirectionError("invalid_range", "The range has to end after it starts.") }
        guard maxDimension >= 16, maxBytes > 0 else { throw DirectionError("invalid_size", "The size limits are too small to send anything.") }
        let source = try await Source(URL(fileURLWithPath: path))
        let frames = try source.frames(in: start...end)
        let seconds = (frames.last!.end - frames[0].time).seconds, fps = source.frameRate
        var longest = min(maxDimension, max(source.display.width, source.display.height))
        var size = fit(source.display, inside: .init(width: longest, height: longest))
        var bitrate = min(Int(Double(size.width * size.height) * fps * 0.15), 12_000_000, Int(Double(maxBytes) * 8 * 0.85 / max(seconds, 0.1)))
        for _ in 0..<6 {
            try Task.checkCancellation()
            try await writeProxy(source, frames, size: size, bitrate: max(bitrate, 20_000), to: output)
            // Not URL.resourceValues: it caches the first size it reads.
            let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? .max
            if bytes <= maxBytes { return }
            bitrate = Int(Double(bitrate) * Double(maxBytes) / Double(bytes) * 0.85)
            // Below about 0.03 bits a pixel the picture falls apart; a smaller one reads better.
            if Double(bitrate) < Double(size.width * size.height) * fps * 0.03 {
                longest = max(16, longest * 7 / 10)
                size = fit(source.display, inside: .init(width: longest, height: longest))
            }
        }
        try? FileManager.default.removeItem(at: output)
        throw DirectionError("range_too_large", "That range won't fit in \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)), even small. Try a shorter range.")
    }

    private static func writeProxy(_ source: Source, _ frames: [Frame], size: Steps.Size, bitrate: Int, to output: URL) async throws {
        // VideoToolbox does both color conversions, with the take's tags; Core Image only scales and turns.
        let renderer = try Renderer(), drawn = try pool(rgba(size))
        let reader = try source.pictureReader(frames, format: kCVPixelFormatType_64RGBAHalf)
        let keys = Set(frames.map { source.ticks($0.time) })
        var writer: Writer?
        do {
            while let sample = reader.output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let decoded = sample.imageBuffer, keys.contains(source.ticks(sample.presentationTimeStamp)) else { continue }
                if writer == nil {
                    writer = try Writer(output, type: .mp4, codec: .h264, profile: AVVideoProfileLevelH264HighAutoLevel, size: size, bitrate: bitrate, fps: source.frameRate,
                                        colors: Colors(decoded), format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, transform: .identity, timescale: source.timescale)
                    try writer!.start()
                }
                let frame = try buffer(drawn)
                try renderer.draw(Renderer.image(decoded).oriented(source.orientation), into: frame)
                CVBufferPropagateAttachments(decoded, frame)
                try await writer!.append(try writer!.converted(frame), at: sample.presentationTimeStamp - frames[0].time)
            }
            try reader.check()
            guard let writer else { throw DirectionError("empty_range", "There are no frames in that range.") }
            try await writer.finish(at: frames.last!.end - frames[0].time)
        } catch { writer?.cancel(); throw error }
    }

    // MARK: Sharpening

    public enum Sharpening: Sendable, Equatable { case unsupported, needsDownload, downloading(Double), ready }

    /// Whether Apple's super resolution (4×, for video) can run for this input size on this Mac. Portrait
    /// frames are turned on their side for it, so either orientation of a size answers the same.
    public static func sharpeningStatus(width: Int, height: Int) -> Sharpening {
        guard let configuration = superResolution(width: width, height: height)?.0 else { return .unsupported }
        switch configuration.configurationModelStatus {
        case .ready: return .ready
        case .downloading: return .downloading(Double(configuration.configurationModelPercentageAvailable))
        default: return .needsDownload
        }
    }

    /// Downloads Apple's super-resolution model once. progress 0…1, called from any thread.
    public static func prepareSharpening(width: Int, height: Int, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let configuration = superResolution(width: width, height: height)?.0 else { throw DirectionError("sharpening_unsupported", "This Mac can't sharpen footage at \(width) × \(height).") }
        guard configuration.configurationModelStatus != .ready else { progress(1); return }
        let watch = Task {
            while !Task.isCancelled { progress(Double(configuration.configurationModelPercentageAvailable)); try? await Task.sleep(for: .milliseconds(250)) }
        }
        defer { watch.cancel() }
        do { try await configuration.downloadConfigurationModel() } catch { throw DirectionError("sharpening_download_failed", "Couldn't download Apple's sharpening model: \(error.localizedDescription)") }
        guard configuration.configurationModelStatus == .ready else { throw DirectionError("sharpening_download_failed", "Apple's sharpening model didn't finish downloading. Try again.") }
        progress(1)
    }

    /// A configuration for frames of this size, and whether they have to be turned on their side to fit
    /// (video input is at most 1920 wide and 1080 tall).
    static func superResolution(width: Int, height: Int) -> (VTSuperResolutionScalerConfiguration, transposed: Bool)? {
        guard VTSuperResolutionScalerConfiguration.isSupported, VTSuperResolutionScalerConfiguration.supportedScaleFactors.contains(4), width > 0, height > 0 else { return nil }
        for (w, h, transposed) in width >= height ? [(width, height, false), (height, width, true)] : [(height, width, true), (width, height, false)] {
            if let configuration = VTSuperResolutionScalerConfiguration(frameWidth: w, frameHeight: h, scaleFactor: 4, inputType: .video, usePrecomputedFlow: false, qualityPrioritization: .normal, revision: VTSuperResolutionScalerConfiguration.defaultRevision) { return (configuration, transposed) }
        }
        return nil
    }

    // MARK: Finishing

    public struct Steps: Sendable, Equatable {
        /// Source seconds; nil is the whole file.
        public var range: ClosedRange<Double>?
        /// An extended shot's repeated join frame, at its start (a tail extension).
        public var dropFirstFrame = false
        /// An extended shot's repeated join frame, at its end (a head extension).
        public var dropLastFrame = false
        /// Fit inside this size: super resolution 4× when the shot is smaller, then a Lanczos scale to fit. Aspect kept, even sizes.
        public var sharpenTo: Size?
        /// 2, 3 or 4: factor − 1 made frames between each pair, written at the source rate so it plays that much slower. Sound is dropped.
        public var slowMotion: Int?
        /// Carry the sound, trimmed to the range, unless slowMotion.
        public var keepSound = true

        public struct Size: Sendable, Equatable {
            public var width: Int
            public var height: Int
            public init(width: Int, height: Int) { self.width = width; self.height = height }
        }

        public init(range: ClosedRange<Double>? = nil, dropFirstFrame: Bool = false, dropLastFrame: Bool = false, sharpenTo: Size? = nil, slowMotion: Int? = nil, keepSound: Bool = true) {
            self.range = range; self.dropFirstFrame = dropFirstFrame; self.dropLastFrame = dropLastFrame; self.sharpenTo = sharpenTo; self.slowMotion = slowMotion; self.keepSound = keepSound
        }
    }

    public struct Result: Sendable, Equatable {
        public var width: Int
        public var height: Int
        public var frames: Int
        public var duration: Double
        /// Whether super resolution ran; false when sharpening fell back to a plain fit.
        public var sharpened: Bool
        /// The shot's size before super resolution, when it ran.
        public var sharpenedFrom: Steps.Size?
        public init(width: Int, height: Int, frames: Int, duration: Double, sharpened: Bool, sharpenedFrom: Steps.Size? = nil) {
            self.width = width; self.height = height; self.frames = frames; self.duration = duration; self.sharpened = sharpened; self.sharpenedFrom = sharpenedFrom
        }
    }

    /// Reads input, applies the steps in order (range → super resolution/fit → slow motion → frame drops) and
    /// writes 10-bit HEVC (Main10) .mov at `output`. If sharpenTo is set but super resolution can't run here or its
    /// model isn't downloaded, it's a plain Lanczos fit and `sharpened` is false; this never downloads.
    /// progress 0…1, called from any thread.
    public static func process(_ input: URL, _ steps: Steps, to output: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Result {
        if let factor = steps.slowMotion, !(2...4).contains(factor) { throw DirectionError("invalid_slow_motion", "Slow motion is 2, 3 or 4 times slower.") }
        if let size = steps.sharpenTo, size.width < 2 || size.height < 2 { throw DirectionError("invalid_size", "The size to sharpen to is too small.") }
        let source = try await Source(input)
        let frames = try source.frames(in: steps.range ?? 0...source.duration.seconds)
        let factor = steps.slowMotion ?? 1
        let total = (frames.count - 1) * factor + 1 - (steps.dropFirstFrame ? 1 : 0) - (steps.dropLastFrame ? 1 : 0)
        guard total > 0 else { throw DirectionError("empty_range", "Dropping the join frame leaves nothing of this shot.") }

        let target = steps.sharpenTo.map { fit(source.display, inside: $0) }
        let sharpener = target.flatMap { $0.width > source.display.width || $0.height > source.display.height ? SuperResolution(source.natural) : nil }
        // A fit renders the picture upright; otherwise frames keep their stored orientation and the track its transform.
        let size = target ?? source.natural
        let interpolation = factor > 1 ? try Interpolation(size, factor: factor) : nil
        let processing = target != nil || interpolation != nil
        let renderer = processing ? try Renderer() : nil
        let fitted = try target.map { try pool(rgba($0)) }
        // Ticks: the track's timescale × factor, so made frames between two source frames land on exact times.
        let timescale = source.timescale * Int32(factor)
        func ticks(_ time: CMTime) -> Int64 { time.convertScale(timescale, method: .roundHalfAwayFromZero).value }
        let keys = Set(frames.map { ticks($0.time) })
        let kept = frames[(steps.dropFirstFrame && factor == 1 ? 1 : 0)...].dropLast(steps.dropLastFrame && factor == 1 ? 1 : 0)
        let sound = steps.keepSound && factor == 1 && !kept.isEmpty ? CMTimeRange(start: kept.first!.time, end: kept.last!.end) : nil

        let reader = try source.pictureReader(frames, format: processing ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mov")
        try FileManager.default.createDirectory(at: temporary.deletingLastPathComponent(), withIntermediateDirectories: true)
        var writer: Writer?
        var skipFirst = steps.dropFirstFrame, pending: (buffer: CVPixelBuffer, ticks: Int64, duration: Int64)?
        var base: Int64?, written = 0, end = CMTime.zero
        func write(_ frame: (buffer: CVPixelBuffer, ticks: Int64, duration: Int64)) async throws {
            guard let writer else { return }
            let first = base ?? frame.ticks; base = first
            let at = CMTime(value: (frame.ticks - first) * Int64(factor), timescale: timescale)
            let ready = processing ? try writer.converted(frame.buffer) : frame.buffer
            try await writer.append(ready, at: at)
            written += 1; end = at + CMTime(value: frame.duration, timescale: timescale)
            progress(min(1, Double(written) / Double(total)))
        }
        func emit(_ buffer: CVPixelBuffer, _ ticks: Int64, _ duration: Int64) async throws {
            if skipFirst { skipFirst = false; return }
            if let pending { try await write(pending) }
            pending = (buffer, ticks, duration)
        }
        do {
            var previous: (buffer: CVPixelBuffer, ticks: Int64)?
            while let sample = reader.output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let decoded = sample.imageBuffer else { continue }
                let time = sample.presentationTimeStamp, t = ticks(time)
                guard keys.contains(t) else { continue }
                if writer == nil {
                    let colors = Colors(decoded)
                    writer = try Writer(temporary, type: .mov, codec: .hevc, profile: kVTProfileLevel_HEVC_Main10_AutoLevel as String, size: size, bitrate: finishingBitrate(size, fps: source.frameRate),
                                        fps: source.frameRate, colors: colors, format: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, transform: target == nil ? source.transform : .identity, timescale: timescale)
                    if let sound { for track in source.audio { try await writer!.addSound(source.asset, track, range: sound) } }
                    try writer!.start()
                }
                var frame = decoded
                if let renderer, let fitted {
                    let image = try await sharpener?.scale(decoded, at: time, renderer: renderer) ?? Renderer.image(decoded)
                    frame = try buffer(fitted)
                    try renderer.draw(image.oriented(source.orientation), into: frame)
                    CVBufferPropagateAttachments(decoded, frame)
                }
                let duration = sample.duration.isNumeric && sample.duration > .zero ? ticks(sample.duration) : ticks(source.frameDuration)
                if let interpolation, let previous {
                    let step = (t - previous.ticks) / Int64(factor)
                    for (j, made) in try await interpolation.frames(between: previous.buffer, at: CMTime(value: previous.ticks, timescale: timescale), and: frame, at: time).enumerated() {
                        CVBufferPropagateAttachments(frame, made)
                        try await emit(made, previous.ticks + Int64(j + 1) * step, step * Int64(factor))
                    }
                }
                try await emit(frame, t, duration)
                previous = (frame, t)
            }
            try reader.check()
            if let pending, !steps.dropLastFrame { try await write(pending) }
            guard let writer, written > 0 else { throw DirectionError("empty_range", "There are no frames to write in that range.") }
            try await writer.finish(at: end)
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.moveItem(at: temporary, to: output)
        } catch {
            writer?.cancel(); try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        progress(1)
        let shown = target ?? source.display
        return Result(width: shown.width, height: shown.height, frames: written, duration: end.seconds, sharpened: sharpener != nil, sharpenedFrom: sharpener != nil ? source.display : nil)
    }

    // MARK: Sizes

    /// The largest size inside `box` with `size`'s aspect, in even pixels.
    static func fit(_ size: Steps.Size, inside box: Steps.Size) -> Steps.Size {
        let scale = min(Double(box.width) / Double(size.width), Double(box.height) / Double(size.height))
        func even(_ value: Double, _ limit: Int) -> Int { max(2, min(Int((value / 2).rounded()) * 2, limit / 2 * 2)) }
        return .init(width: even(Double(size.width) * scale, box.width), height: even(Double(size.height) * scale, box.height))
    }

    /// About 90 Mbps at 4K30, scaled with pixels and a little with frame rate (68–120 Mbps at 4K).
    static func finishingBitrate(_ size: Steps.Size, fps: Double) -> Int {
        max(8_000_000, Int(90_000_000 * Double(size.width * size.height) / (3840 * 2160) * min(max(fps / 30, 0.75), 4.0 / 3)))
    }

    private static func rgba(_ size: Steps.Size) -> [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_64RGBAHalf, kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
         kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](), kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    fileprivate static func pool(_ attributes: [String: Any]) throws -> CVPixelBufferPool {
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess, let pool else { throw DirectionError("frame_allocation", "Couldn't set aside memory for the frames.") }
        return pool
    }

    fileprivate static func buffer(_ pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("frame_allocation", "Couldn't set aside memory for a frame.") }
        return buffer
    }
}

// MARK: - Reading

private struct Frame { var time: CMTime; var duration: CMTime; var end: CMTime { time + duration } }

private struct Source {
    let asset: AVURLAsset, video: AVAssetTrack, audio: [AVAssetTrack]
    let natural: MadeProcessing.Steps.Size, transform: CGAffineTransform, orientation: CGImagePropertyOrientation
    let duration: CMTime, frameDuration: CMTime, timescale: CMTimeScale
    var frameRate: Double { 1 / frameDuration.seconds }
    var display: MadeProcessing.Steps.Size { [.left, .right, .leftMirrored, .rightMirrored].contains(orientation) ? .init(width: natural.height, height: natural.width) : natural }

    init(_ url: URL) async throws {
        asset = AVURLAsset(url: url)
        guard FileManager.default.fileExists(atPath: url.path) else { throw DirectionError("missing_media", "\(url.lastPathComponent) isn't there anymore.") }
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw DirectionError("no_picture", "\(url.lastPathComponent) has no picture.") }
        self.video = video
        audio = try await asset.loadTracks(withMediaType: .audio)
        let (size, transform, rate, minimum, scale) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration, .naturalTimeScale)
        natural = .init(width: Int(size.width.rounded()), height: Int(size.height.rounded()))
        guard natural.width > 0, natural.height > 0 else { throw DirectionError("no_picture", "\(url.lastPathComponent) has no picture.") }
        self.transform = transform
        orientation = switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        case (-1, 0, 0, 1): .upMirrored
        case (1, 0, 0, -1): .downMirrored
        case (0, 1, 1, 0): .leftMirrored
        case (0, -1, -1, 0): .rightMirrored
        default: .up
        }
        duration = try await asset.load(.duration)
        frameDuration = minimum.isNumeric && minimum > .zero ? minimum : rate > 0 ? CMTime(seconds: 1 / Double(rate), preferredTimescale: 600_000) : CMTime(value: 1, timescale: 24)
        timescale = scale > 0 ? scale : 600
    }

    func ticks(_ time: CMTime) -> Int64 { time.convertScale(timescale, method: .roundHalfAwayFromZero).value }

    /// The frames shown in a range of source seconds, in order: each one whose time on screen overlaps the
    /// range by more than a quarter of a frame, or else the one on screen at its start.
    func frames(in range: ClosedRange<Double>) throws -> [Frame] {
        let lower = max(0, range.lowerBound), upper = min(duration.seconds, range.upperBound)
        guard upper > lower else { throw DirectionError("invalid_range", "That range is outside the take, which is \(String(format: "%.2f", duration.seconds)) s long.") }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: lower, preferredTimescale: 600_000), end: CMTime(seconds: upper, preferredTimescale: 600_000))
        // Stored samples, not decoded: only their times are needed.
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { throw DirectionError("media_unreadable", "Couldn't read \(asset.url.lastPathComponent): \(reader.error?.localizedDescription ?? "unknown error").") }
        var all: [Frame] = []
        while let sample = output.copyNextSampleBuffer() {
            for timing in (try? sample.sampleTimingInfos()) ?? [] where timing.presentationTimeStamp.isNumeric {
                all.append(.init(time: timing.presentationTimeStamp, duration: timing.duration.isNumeric && timing.duration > .zero ? timing.duration : frameDuration))
            }
        }
        guard reader.status == .completed else { throw DirectionError("media_unreadable", "Couldn't read \(asset.url.lastPathComponent): \(reader.error?.localizedDescription ?? "unknown error").") }
        all.sort { $0.time < $1.time }
        let slack = frameDuration.seconds / 4
        let shown = all.filter { $0.end.seconds > lower + slack && $0.time.seconds < upper - slack }
        if !shown.isEmpty { return shown }
        guard let at = all.last(where: { $0.time.seconds <= lower }) ?? all.first else { throw DirectionError("empty_range", "There are no frames in that range.") }
        return [at]
    }

    /// Decoded frames covering `frames`, as IOSurface-backed buffers in `format`.
    func pictureReader(_ frames: [Frame], format: OSType) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput, check: () throws -> Void) {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: frames[0].time, end: frames.last!.end)
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: format, kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](), kCVPixelBufferMetalCompatibilityKey as String: true])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        let name = asset.url.lastPathComponent
        guard reader.startReading() else { throw DirectionError("media_unreadable", "Couldn't read \(name): \(reader.error?.localizedDescription ?? "unknown error").") }
        return (reader, output, { guard reader.status == .completed else { throw DirectionError("media_unreadable", "Couldn't read all of \(name): \(reader.error?.localizedDescription ?? "unknown error").") } })
    }
}

/// The color a take's frames were decoded with, carried to the file written from them.
private struct Colors {
    var primaries = AVVideoColorPrimaries_ITU_R_709_2, transfer = AVVideoTransferFunction_ITU_R_709_2, matrix = AVVideoYCbCrMatrix_ITU_R_709_2
    init() {}
    init(_ buffer: CVPixelBuffer) {
        let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any] ?? [:]
        if let value = attachments[kCVImageBufferColorPrimariesKey as String] as? String { primaries = value }
        if let value = attachments[kCVImageBufferTransferFunctionKey as String] as? String { transfer = value }
        if let value = attachments[kCVImageBufferYCbCrMatrixKey as String] as? String { matrix = value }
    }
    var settings: [String: Any] { [AVVideoColorPrimariesKey: primaries, AVVideoTransferFunctionKey: transfer, AVVideoYCbCrMatrixKey: matrix] }
}

// MARK: - Picture

/// Core Image with color management off: frames keep the values they were decoded with.
private final class Renderer {
    let context: CIContext
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw DirectionError("metal_unavailable", "Direction requires a Metal-capable Mac.") }
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false, .name: "MadeProcessing"])
    }

    static func image(_ buffer: CVPixelBuffer) -> CIImage { CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()]) }

    /// Draws `image` into `buffer`, scaled with Lanczos to fill it exactly.
    func draw(_ image: CIImage, into buffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var image = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
        if Int(image.extent.width.rounded()) != width || Int(image.extent.height.rounded()) != height {
            let scale = Double(height) / image.extent.height, aspect = Double(width) / image.extent.width / scale
            image = image.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: aspect])
        }
        let destination = CIRenderDestination(pixelBuffer: buffer)
        destination.colorSpace = nil
        try context.startTask(toRender: image.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)), to: destination).waitUntilCompleted()
    }
}

/// Apple's super resolution, 4×, for one shot's frames in order. Only when its model is already here.
private final class SuperResolution {
    private let processor = VTFrameProcessor()
    private let transposed: Bool
    private let sources: CVPixelBufferPool?, destinations: CVPixelBufferPool
    private var previous: (source: VTFrameProcessorFrame, output: VTFrameProcessorFrame)?

    init?(_ size: MadeProcessing.Steps.Size) {
        guard let (configuration, transposed) = MadeProcessing.superResolution(width: size.width, height: size.height).map({ ($0.0, $0.transposed) }), configuration.configurationModelStatus == .ready,
              let destinations = try? MadeProcessing.pool(configuration.destinationPixelBufferAttributes) else { return nil }
        self.transposed = transposed; self.destinations = destinations
        sources = transposed ? try? MadeProcessing.pool(configuration.sourcePixelBufferAttributes) : nil
        guard !transposed || sources != nil, (try? processor.startSession(configuration: configuration)) != nil else { return nil }
    }

    deinit { processor.endSession() }

    /// The frame at 4×, in its stored orientation.
    func scale(_ buffer: CVPixelBuffer, at time: CMTime, renderer: Renderer) async throws -> CIImage {
        var input = buffer
        if transposed, let sources {
            input = try MadeProcessing.buffer(sources)
            try renderer.draw(Renderer.image(buffer).oriented(.right), into: input)
        }
        let output = try MadeProcessing.buffer(destinations)
        guard let source = VTFrameProcessorFrame(buffer: input, presentationTimeStamp: time), let destination = VTFrameProcessorFrame(buffer: output, presentationTimeStamp: time),
              let parameters = VTSuperResolutionScalerParameters(sourceFrame: source, previousFrame: previous?.source, previousOutputFrame: previous?.output, opticalFlow: nil, submissionMode: .sequential, destinationFrame: destination)
        else { throw DirectionError("sharpening_failed", "Couldn't prepare a frame for sharpening.") }
        do { _ = try await processor.process(parameters: parameters) } catch { throw DirectionError("sharpening_failed", "Sharpening stopped partway: \(error.localizedDescription)") }
        previous = (source, destination)
        let image = Renderer.image(output)
        return transposed ? image.oriented(.left) : image
    }
}

/// Apple's frame rate conversion: the made frames between two neighbors, for slow motion.
private final class Interpolation {
    private let processor = VTFrameProcessor()
    private let destinations: CVPixelBufferPool
    private let phases: [Float]
    private var started = false

    init(_ size: MadeProcessing.Steps.Size, factor: Int) throws {
        guard VTFrameRateConversionConfiguration.isSupported,
              let configuration = VTFrameRateConversionConfiguration(frameWidth: size.width, frameHeight: size.height, usePrecomputedFlow: false, qualityPrioritization: .quality, revision: VTFrameRateConversionConfiguration.defaultRevision)
        else { throw DirectionError("slow_motion_unsupported", "This Mac can't make slow motion at \(size.width) × \(size.height).") }
        destinations = try MadeProcessing.pool(configuration.destinationPixelBufferAttributes)
        phases = (1..<factor).map { Float($0) / Float(factor) }
        do { try processor.startSession(configuration: configuration) } catch { throw DirectionError("slow_motion_unsupported", "Couldn't start slow motion: \(error.localizedDescription)") }
    }

    deinit { processor.endSession() }

    func frames(between first: CVPixelBuffer, at start: CMTime, and next: CVPixelBuffer, at end: CMTime) async throws -> [CVPixelBuffer] {
        let made = try phases.map { _ in try MadeProcessing.buffer(destinations) }
        let destinations = zip(made, phases).compactMap { VTFrameProcessorFrame(buffer: $0, presentationTimeStamp: start + CMTimeMultiplyByFloat64(end - start, multiplier: Double($1))) }
        guard let source = VTFrameProcessorFrame(buffer: first, presentationTimeStamp: start), let following = VTFrameProcessorFrame(buffer: next, presentationTimeStamp: end), destinations.count == made.count,
              let parameters = VTFrameRateConversionParameters(sourceFrame: source, nextFrame: following, opticalFlow: nil, interpolationPhase: phases, submissionMode: started ? .sequential : .random, destinationFrames: destinations)
        else { throw DirectionError("slow_motion_failed", "Couldn't prepare frames for slow motion.") }
        do { _ = try await processor.process(parameters: parameters) } catch { throw DirectionError("slow_motion_failed", "Slow motion stopped partway: \(error.localizedDescription)") }
        started = true
        return made
    }
}

// MARK: - Writing

private final class Writer {
    private let writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor, colors: Colors
    private var sounds: [(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, offset: CMTime, done: Bool)] = []
    private var transfer: VTPixelTransferSession?

    init(_ url: URL, type: AVFileType, codec: AVVideoCodecType, profile: String, size: MadeProcessing.Steps.Size, bitrate: Int, fps: Double, colors: Colors, format: OSType, transform: CGAffineTransform, timescale: CMTimeScale) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        writer.shouldOptimizeForNetworkUse = type == .mp4
        writer.movieTimeScale = timescale
        func settings(_ colors: Colors) -> [String: Any] {
            [AVVideoCodecKey: codec, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height, AVVideoColorPropertiesKey: colors.settings,
             AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: profile, AVVideoAverageBitRateKey: bitrate, AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()), AVVideoMaxKeyFrameIntervalKey: max(1, Int(fps.rounded()))]]
        }
        // Tags AVFoundation can't write (an unusual transfer, say) become Rec. 709.
        let colors = writer.canApply(outputSettings: settings(colors), forMediaType: .video) ? colors : Colors()
        guard writer.canApply(outputSettings: settings(colors), forMediaType: .video) else { throw DirectionError("encoder_unavailable", "This Mac can't write \(codec == .hevc ? "10-bit HEVC" : "H.264") at \(size.width) × \(size.height).") }
        self.writer = writer; self.colors = colors
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings(colors))
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        input.mediaTimeScale = timescale
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: format, kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](), kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        writer.add(input)
    }

    /// Carries one sound track, as 24-bit PCM, for `range` of the source; it starts at the movie's zero.
    func addSound(_ asset: AVAsset, _ track: AVAssetTrack, range: CMTimeRange) async throws {
        guard let description = try await track.load(.formatDescriptions).first, let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee, basic.mChannelsPerFrame > 0 else { return }
        var settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: basic.mSampleRate > 0 ? basic.mSampleRate : 48_000, AVNumberOfChannelsKey: Int(basic.mChannelsPerFrame),
                                       AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        var layoutSize = 0
        if let layout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: &layoutSize), layoutSize > 0 { settings[AVChannelLayoutKey] = Data(bytes: layout, count: layoutSize) }
        else if basic.mChannelsPerFrame > 2 {
            var layout = AudioChannelLayout(); layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | basic.mChannelsPerFrame
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        guard writer.canApply(outputSettings: settings, forMediaType: .audio) else { return }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return }
        writer.add(input)
        sounds.append((reader, output, input, range.start, false))
    }

    func start() throws {
        for sound in sounds where !sound.reader.startReading() { throw DirectionError("media_unreadable", "Couldn't read the sound: \(sound.reader.error?.localizedDescription ?? "unknown error").") }
        guard writer.startWriting() else { throw writer.error ?? DirectionError("write_failed", "Couldn't start writing the shot.") }
        writer.startSession(atSourceTime: .zero)
    }

    func buffer() throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? DirectionError("frame_allocation", "Couldn't set aside memory for a frame.") }
        return try MadeProcessing.buffer(pool)
    }

    /// A processed frame in the encoder's format and the file's color.
    func converted(_ frame: CVPixelBuffer) throws -> CVPixelBuffer {
        if transfer == nil {
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer)
            guard let transfer else { throw DirectionError("frame_conversion", "Couldn't prepare frames for the encoder.") }
            VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries, value: colors.primaries as CFString)
            VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: colors.transfer as CFString)
            VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, value: colors.matrix as CFString)
        }
        let output = try buffer()
        guard VTPixelTransferSessionTransferImage(transfer!, from: frame, to: output) == noErr else { throw DirectionError("frame_conversion", "Couldn't convert a frame for the encoder.") }
        return output
    }

    func append(_ buffer: CVPixelBuffer, at time: CMTime) async throws {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw failure }
            if try !pumpSound() { try await Task.sleep(for: .milliseconds(1)) }
        }
        guard adaptor.append(buffer, withPresentationTime: time) else { throw failure }
        _ = try pumpSound()
    }

    func finish(at end: CMTime) async throws {
        input.markAsFinished()
        while sounds.contains(where: { !$0.done }) {
            if writer.status == .failed { throw failure }
            if try !pumpSound() { try await Task.sleep(for: .milliseconds(1)) }
        }
        writer.endSession(atSourceTime: end)
        await writer.finishWriting()
        guard writer.status == .completed else { throw failure }
    }

    func cancel() {
        for sound in sounds { sound.reader.cancelReading() }
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: writer.outputURL)
    }

    private var failure: Error { writer.error.map { DirectionError("write_failed", "Couldn't write the shot: \($0.localizedDescription)") } ?? DirectionError("write_failed", "Couldn't write the shot.") }

    /// Feeds the sound while the writer wants it, so picture and sound interleave. True if anything moved.
    private func pumpSound() throws -> Bool {
        var moved = false
        for i in sounds.indices where !sounds[i].done {
            while sounds[i].input.isReadyForMoreMediaData {
                guard let sample = sounds[i].output.copyNextSampleBuffer() else {
                    if sounds[i].reader.status == .failed { throw DirectionError("media_unreadable", "Couldn't read the sound: \(sounds[i].reader.error?.localizedDescription ?? "unknown error").") }
                    sounds[i].input.markAsFinished(); sounds[i].done = true; break
                }
                let timing = try sample.sampleTimingInfos().map { CMSampleTimingInfo(duration: $0.duration, presentationTimeStamp: $0.presentationTimeStamp - sounds[i].offset, decodeTimeStamp: .invalid) }
                guard sounds[i].input.append(try CMSampleBuffer(copying: sample, withNewTiming: timing)) else { throw failure }
                moved = true
            }
        }
        return moved
    }
}
