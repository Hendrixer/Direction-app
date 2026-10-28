import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreText
import DirectionCore

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

public final class CompiledSequence: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let sequence: Sequence
    public let revision: Int
    private let access: MediaAccess
    init(composition: AVMutableComposition, video: AVMutableVideoComposition, audio: AVMutableAudioMix, sequence: Sequence, revision: Int, access: MediaAccess) { self.composition = composition; videoComposition = video; audioMix = audio; self.sequence = sequence; self.revision = revision; self.access = access }
    @MainActor public func playerItem() -> AVPlayerItem { let item = AVPlayerItem(asset: composition); item.videoComposition = videoComposition; item.audioMix = audioMix; return item }
}

public enum SequenceRenderer {
    public static func compile(project: Project, sequenceID: String? = nil, cacheDirectory: URL, previewMaxDimension: Int? = nil) async throws -> CompiledSequence {
        try EditReducer.validate(project)
        let sequence = try project.sequence(sequenceID)
        guard sequence.duration > .zero else { throw DirectionError("empty_sequence", "Add footage to the sequence before playing or rendering.") }
        guard GPUCompositor.deviceName != nil else { throw DirectionError("metal_unavailable", "Direction requires a Metal-capable Mac.") }
        let usedIDs = Set(sequence.clips.compactMap(\.assetID))
        let assets = project.assets.filter { usedIDs.contains($0.id) }
        let access = try MediaAccess(assets: assets)
        let composition = AVMutableComposition()
        // A tiny timing track spans the whole cut, including gaps and still-only sections.
        // AVFoundation otherwise has no video samples to drive the custom compositor there.
        let clock = AVURLAsset(url: try await timingVideo(in: cacheDirectory.appendingPathComponent("Render")))
        guard let clockSource = try await clock.loadTracks(withMediaType: .video).first,
              let clockTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw DirectionError("track_allocation", "Cannot allocate the composition clock.") }
        let clockRange = try await clockSource.load(.timeRange)
        try clockTrack.insertTimeRange(clockRange, of: clockSource, at: .zero)
        clockTrack.scaleTimeRange(.init(start: .zero, duration: clockRange.duration), toDuration: sequence.duration.cmTime)
        var layers: [(Clip, RenderLayer)] = [], audioParameters: [AVMutableAudioMixInputParameters] = []
        for clip in sequence.clips.sorted(by: { ($0.layer, $0.start.seconds, $0.id) < ($1.layer, $1.start.seconds, $1.id) }) {
            try Task.checkCancellation()
            if clip.kind == .title {
                let image = try titleImage(clip.title ?? clip.name, width: sequence.width, height: sequence.height)
                layers.append((clip, .init(trackID: nil, image: image, transform: .identity, grade: clip.grade, framing: clip.framing)))
                continue
            }
            guard let asset = assets.first(where: { $0.id == clip.assetID }) else { throw DirectionError("missing_asset", "Missing source for \(clip.name).") }
            let url = try MediaInspector.checkedURL(asset)
            if asset.isImage {
                guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw DirectionError("image_decode_failed", "Cannot load \(asset.name).") }
                layers.append((clip, .init(trackID: nil, image: image, transform: .identity, grade: clip.grade, framing: clip.framing)))
                continue
            }
            let source = AVURLAsset(url: url)
            if clip.kind == .video, let sourceTrack = try await source.loadTracks(withMediaType: .video).first {
                guard let destination = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw DirectionError("track_allocation", "Cannot allocate video layer.") }
                try destination.insertTimeRange(clip.sourceRange.cmRange, of: sourceTrack, at: clip.start.cmTime)
                if clip.speed != 1 { destination.scaleTimeRange(CMTimeRange(start: clip.start.cmTime, duration: clip.sourceRange.duration.cmTime), toDuration: clip.duration.cmTime) }
                layers.append((clip, .init(trackID: destination.trackID, image: nil, transform: try await sourceTrack.load(.preferredTransform), grade: clip.grade, framing: clip.framing)))
            }
            let sourceAudio = try await source.loadTracks(withMediaType: .audio)
            for stream in asset.audio {
                let settings = clip.audioOverrides[String(stream.id)] ?? stream.settings
                guard !settings.muted else { continue }
                let inputTrack: AVAssetTrack?
                if settings.effects.isActive {
                    let processed = try await AudioProcessor.processed(asset: asset, trackID: stream.id, effects: settings.effects, directory: cacheDirectory.appendingPathComponent("Audio"))
                    inputTrack = try await AVURLAsset(url: processed).loadTracks(withMediaType: .audio).first
                } else { inputTrack = sourceAudio.first { $0.trackID == stream.id } }
                guard let inputTrack, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw DirectionError("audio_track_failed", "Cannot load source audio track \(stream.id).") }
                let available = try await inputTrack.load(.timeRange)
                let requested = CMTimeRangeGetIntersection(clip.sourceRange.cmRange, otherRange: available)
                if requested.duration.seconds > 0 {
                    let offset = CMTimeSubtract(requested.start, clip.sourceRange.start.cmTime)
                    let insertAt = CMTimeAdd(clip.start.cmTime, CMTimeMultiplyByFloat64(offset, multiplier: 1 / clip.speed))
                    try track.insertTimeRange(requested, of: inputTrack, at: insertAt)
                    let duration = CMTimeMultiplyByFloat64(requested.duration, multiplier: 1 / clip.speed)
                    if clip.speed != 1 { track.scaleTimeRange(CMTimeRange(start: insertAt, duration: requested.duration), toDuration: duration) }
                    let mix = AVMutableAudioMixInputParameters(track: track)
                    mix.audioTimePitchAlgorithm = .timeDomain
                    let gain = Float(pow(10, settings.gainDB / 20)), d = duration.seconds
                    let fadeIn = min(settings.fadeIn, d / 2), fadeOut = min(settings.fadeOut, d / 2)
                    mix.setVolume(gain, at: insertAt)
                    if fadeIn > 0 { mix.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain, timeRange: .init(start: insertAt, duration: CMTime(seconds: fadeIn, preferredTimescale: 48_000))) }
                    if fadeOut > 0 { mix.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0, timeRange: .init(start: CMTimeAdd(insertAt, CMTime(seconds: d - fadeOut, preferredTimescale: 48_000)), duration: CMTime(seconds: fadeOut, preferredTimescale: 48_000))) }
                    audioParameters.append(mix)
                }
            }
        }
        if composition.duration < sequence.duration.cmTime { composition.insertEmptyTimeRange(.init(start: composition.duration, duration: CMTimeSubtract(sequence.duration.cmTime, composition.duration))) }
        let points = Set([MediaTime.zero, sequence.duration] + layers.flatMap { [$0.0.start, $0.0.end] }).sorted()
        var instructions: [RenderInstruction] = []
        for i in points.indices.dropLast() {
            let t = points[i]
            let active = layers.filter { $0.0.range.contains(t) }.map(\.1)
            instructions.append(.init(range: .init(start: t.cmTime, duration: (points[i + 1] - t).cmTime), layers: active, timingTrackID: clockTrack.trackID))
        }
        let video = AVMutableVideoComposition(); video.customVideoCompositorClass = GPUCompositor.self; video.instructions = instructions; video.frameDuration = sequence.frameRate.frameDuration
        let ratio = previewMaxDimension.map { min(1, Double($0) / Double(max(sequence.width, sequence.height))) } ?? 1
        video.renderSize = .init(width: max(2, Int(Double(sequence.width) * ratio) / 2 * 2), height: max(2, Int(Double(sequence.height) * ratio) / 2 * 2))
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2; video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2; video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let audio = AVMutableAudioMix(); audio.inputParameters = audioParameters
        return .init(composition: composition, video: video, audio: audio, sequence: sequence, revision: project.editRevision, access: access)
    }

    private static func timingVideo(in directory: URL) async throws -> URL {
        let target = directory.appendingPathComponent("clock-v1.mov")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        do {
            guard writer.startWriting() else { throw writer.error ?? DirectionError("render_clock_failed", "Cannot prepare the render clock.") }
            writer.startSession(atSourceTime: .zero)
            for index in 0..<30 {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error ?? DirectionError("render_clock_failed", "Cannot write the render clock.") }
                    try await Task.sleep(for: .milliseconds(2))
                }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw DirectionError("render_clock_failed", "Cannot allocate the render clock.") }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let bytes = CVPixelBufferGetBaseAddress(buffer) { memset(bytes, 0, CVPixelBufferGetBytesPerRow(buffer) * 16) }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw writer.error ?? DirectionError("render_clock_failed", "Cannot write the render clock.") }
            }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? DirectionError("render_clock_failed", "Cannot finish the render clock.") }
            do { try FileManager.default.moveItem(at: temporary, to: target) }
            catch { if FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.removeItem(at: temporary) } else { throw error } }
            return target
        } catch { writer.cancelWriting(); try? FileManager.default.removeItem(at: temporary); throw error }
    }

    public static func frame(_ compiled: CompiledSequence, at time: MediaTime, to output: URL, maxDimension: Int = 1280) async throws -> JSONValue {
        guard time.isValid && time >= .zero && time < compiled.sequence.duration else { throw DirectionError("invalid_time", "Frame time must fall inside the cut.") }
        let generator = AVAssetImageGenerator(asset: compiled.composition)
        generator.videoComposition = compiled.videoComposition; generator.maximumSize = .init(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let result = try await generator.image(at: time.cmTime)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MediaInspector.writePNG(result.image, to: output)
        return .object(["path": .string(output.path), "mimeType": .string("image/png"), "width": .number(Double(result.image.width)), "height": .number(Double(result.image.height)), "editRevision": .number(Double(compiled.revision)), "requestedTime": try .wrapping(time), "actualTime": try .wrapping(MediaTime(result.actualTime))])
    }

    public static func export(_ compiled: CompiledSequence, to destination: URL, preset: String = "h264", range: MediaRange? = nil) async throws -> JSONValue {
        let presetName: String, type: AVFileType
        switch preset { case "h264": presetName = AVAssetExportPresetHighestQuality; type = .mp4
        case "hevc": presetName = AVAssetExportPresetHEVCHighestQuality; type = .mp4
        case "prores": presetName = AVAssetExportPresetAppleProRes422LPCM; type = .mov
        default: throw DirectionError("unsupported_preset", "Use h264, hevc, or prores.") }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw DirectionError("destination_exists", "Choose a new output path; Direction does not overwrite existing media.") }
        guard let session = AVAssetExportSession(asset: compiled.composition, presetName: presetName) else { throw DirectionError("export_unavailable", "This export preset is unavailable for the sequence.") }
        session.videoComposition = compiled.videoComposition; session.audioMix = compiled.audioMix
        if let range { guard range.isValid && range.end <= compiled.sequence.duration else { throw DirectionError("invalid_range", "Preview range must lie inside the cut.") }; session.timeRange = range.cmRange }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".direction-" + UUID().uuidString + (type == .mov ? ".mov" : ".mp4"))
        let started = Date()
        let exportSession = ExportSessionBox(session)
        do {
            try await withTaskCancellationHandler { @Sendable in try await exportSession.session.export(to: temp, as: type) } onCancel: { exportSession.session.cancelExport() }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temp, to: destination)
            let output = AVURLAsset(url: destination)
            let actual = try await output.load(.duration)
            return .object(["path": .string(destination.path), "editRevision": .number(Double(compiled.revision)), "sequenceID": .string(compiled.sequence.id), "preset": .string(preset), "duration": try .wrapping(MediaTime(actual)), "elapsedSeconds": .number(Date().timeIntervalSince(started)), "videoRenderer": .string("Metal/Core Image"), "gpu": .string(GPUCompositor.deviceName ?? "unavailable")])
        } catch { session.cancelExport(); try? FileManager.default.removeItem(at: temp); throw error }
    }

    private static func titleImage(_ text: String, width: Int, height: Int) throws -> CIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DirectionError("title_failed", "Cannot allocate title canvas.") }
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, CGFloat(width) * 0.043, nil)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: CGRect(x: CGFloat(width) * 0.1, y: CGFloat(height) * 0.12, width: CGFloat(width) * 0.8, height: CGFloat(height) * 0.2), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
        guard let image = context.makeImage() else { throw DirectionError("title_failed", "Cannot draw title.") }
        return CIImage(cgImage: image)
    }

    public static func audioPreview(_ compiled: CompiledSequence, range: MediaRange, to output: URL) async throws -> JSONValue {
        guard range.isValid, range.end <= compiled.sequence.duration, range.duration.seconds <= 30 else { throw DirectionError("invalid_range", "Audio samples need a valid range of up to 30 seconds.") }
        let tracks = try await compiled.composition.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw DirectionError("no_audio", "The cut has no enabled audio.") }
        let reader = try AVAssetReader(asset: compiled.composition)
        reader.timeRange = range.cmRange
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let mix = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings); mix.audioMix = compiled.audioMix
        reader.add(mix)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        guard reader.startReading() else { throw reader.error ?? DirectionError("audio_preview_failed", "Cannot render audio preview.") }
        do {
            while let sample = mix.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let data = CMSampleBufferGetDataBuffer(sample), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))), let pointer = buffer.mutableAudioBufferList.pointee.mBuffers.mData else { continue }
                buffer.frameLength = buffer.frameCapacity
                guard CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: Int(buffer.frameLength) * 2, destination: pointer) == kCMBlockBufferNoErr else { throw DirectionError("audio_preview_failed", "Invalid audio preview samples.") }
                try file.write(from: buffer)
            }
            guard reader.status == .completed else { throw reader.error ?? DirectionError("audio_preview_failed", "Audio preview failed.") }
            return .object(["path": .string(output.path), "mimeType": .string("audio/wav"), "editRevision": .number(Double(compiled.revision)), "range": try .wrapping(range)])
        } catch { reader.cancelReading(); try? FileManager.default.removeItem(at: output); throw error }
    }
}
