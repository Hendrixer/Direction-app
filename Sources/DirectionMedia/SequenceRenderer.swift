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
    public let videoComposition: AVVideoComposition
    public let audioMix: AVMutableAudioMix
    public let sequence: Sequence
    public let revision: Int
    private let access: MediaAccess
    init(composition: AVMutableComposition, video: AVVideoComposition, audio: AVMutableAudioMix, sequence: Sequence, revision: Int, access: MediaAccess) { self.composition = composition; videoComposition = video; audioMix = audio; self.sequence = sequence; self.revision = revision; self.access = access }
    @MainActor public func playerItem() -> AVPlayerItem { let item = AVPlayerItem(asset: composition); item.videoComposition = videoComposition; item.audioMix = audioMix; return item }
}

public enum SequenceRenderer {
    /// - looks: the director's look (`try? store.lookContext()`), applied over every layer that isn't above it.
    public static func compile(project: Project, sequenceID: String? = nil, cacheDirectory: URL, previewMaxDimension: Int? = nil, looks: LookContext? = nil) async throws -> CompiledSequence {
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
        let fps = sequence.frameRate.value
        func cm(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600_000) }
        // The transition into the next clip on the same track: a dissolve plays this clip's tail past its end.
        let picture = Dictionary(grouping: sequence.clips.filter { $0.kind != .audio }, by: \.layer)
        func outgoing(_ c: Clip) -> ClipTransition? { picture[c.layer]?.first { $0.id != c.id && abs($0.start.seconds - c.end.seconds) < 0.5 / fps }?.transition }
        func trackSettings(_ c: Clip) -> [ClipEffect] { sequence.tracks?[c.trackName]?.effects ?? [] }
        func above(_ c: Clip) -> Bool { c.aboveLook ?? sequence.tracks?[c.trackName]?.aboveLook ?? false }
        var layers: [RenderLayer] = [], audioParameters: [AVMutableAudioMixInputParameters] = []
        for clip in sequence.clips.sorted(by: { ($0.layer, $0.start.seconds, $0.id) < ($1.layer, $1.start.seconds, $1.id) }) {
            try Task.checkCancellation()
            let head = clip.transition?.type == "dissolve" ? clip.transition!.before : 0
            let next = outgoing(clip), tail = next?.type == "dissolve" ? next!.after : 0
            func layer(_ track: CMPersistentTrackID?, _ image: CIImage?, _ transform: CGAffineTransform, _ lut: CameraLUTFile?) -> RenderLayer {
                .init(trackID: track, image: image, transform: transform, grade: clip.grade, framing: clip.framing, clip: clip, start: clip.start.seconds - head, end: clip.end.seconds + tail, outgoing: next, trackEffects: trackSettings(clip), aboveLook: above(clip), lut: lut)
            }
            if clip.kind == .title {
                layers.append(layer(nil, try titleImage(clip.title ?? clip.name, width: sequence.width, height: sequence.height), .identity, nil))
                continue
            }
            guard let asset = assets.first(where: { $0.id == clip.assetID }) else { throw DirectionError("missing_asset", "Missing source for \(clip.name).") }
            let url = try MediaInspector.checkedURL(asset)
            let lut = asset.cameraLUT.flatMap { $0.hasSuffix(".cube") ? CameraLUTFile.load($0) : nil }
            if asset.isImage {
                guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw DirectionError("image_decode_failed", "Cannot load \(asset.name).") }
                layers.append(layer(nil, image, .identity, lut))
                continue
            }
            let source = AVURLAsset(url: url)
            if clip.kind == .video, let sourceTrack = try await source.loadTracks(withMediaType: .video).first {
                if clip.hold != nil {
                    // A freeze is the one frame, held as a still.
                    let generator = AVAssetImageGenerator(asset: source)
                    generator.appliesPreferredTrackTransform = true; generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                    layers.append(layer(nil, CIImage(cgImage: try await generator.image(at: clip.sourceRange.start.cmTime).image), .identity, lut))
                } else {
                    guard let destination = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw DirectionError("track_allocation", "Cannot allocate video layer.") }
                    // Dissolve handles come along so both sides of the cut have picture.
                    let start = CMTimeMaximum(.zero, CMTimeSubtract(clip.sourceRange.start.cmTime, cm(head * clip.speed)))
                    let duration = CMTimeAdd(CMTimeSubtract(clip.sourceRange.end.cmTime, start), cm(tail * clip.speed))
                    let at = CMTimeSubtract(clip.start.cmTime, cm(head))
                    try destination.insertTimeRange(CMTimeRange(start: start, duration: duration), of: sourceTrack, at: at)
                    if clip.speed != 1 { destination.scaleTimeRange(CMTimeRange(start: at, duration: duration), toDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1 / clip.speed)) }
                    layers.append(layer(destination.trackID, nil, try await sourceTrack.load(.preferredTransform), lut))
                }
            }
            guard clip.hold == nil else { continue }
            let sourceAudio = try await source.loadTracks(withMediaType: .audio)
            // J- and L-cuts move where the sound starts and ends against the picture.
            let lead = clip.soundLead ?? 0, carry = clip.soundTail ?? 0
            let soundStart = CMTimeSubtract(clip.sourceRange.start.cmTime, cm(lead * clip.speed))
            let soundRange = CMTimeRange(start: soundStart, duration: CMTimeAdd(clip.sourceRange.duration.cmTime, cm((lead + carry) * clip.speed)))
            let soundAt = CMTimeSubtract(clip.start.cmTime, cm(lead))
            let soundTrack = clip.kind == .audio ? clip.trackName : clip.layer == 0 ? "A1" : nil
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
                let requested = CMTimeRangeGetIntersection(soundRange, otherRange: available)
                guard requested.duration.seconds > 0 else { continue }
                let offset = CMTimeSubtract(requested.start, soundStart)
                let insertAt = CMTimeMaximum(.zero, CMTimeAdd(soundAt, CMTimeMultiplyByFloat64(offset, multiplier: 1 / clip.speed)))
                try track.insertTimeRange(requested, of: inputTrack, at: insertAt)
                let duration = CMTimeMultiplyByFloat64(requested.duration, multiplier: 1 / clip.speed)
                if clip.speed != 1 { track.scaleTimeRange(CMTimeRange(start: insertAt, duration: requested.duration), toDuration: duration) }
                let mix = AVMutableAudioMixInputParameters(track: track)
                mix.audioTimePitchAlgorithm = .timeDomain
                let points = AudioEnvelope.points(clip: clip, streamDB: settings.gainDB, streamFadeIn: settings.fadeIn, streamFadeOut: settings.fadeOut, track: soundTrack.flatMap { sequence.tracks?[$0] }, from: insertAt.seconds, to: CMTimeAdd(insertAt, duration).seconds)
                // A volume holds until the next ramp, so only changes need one.
                if let first = points.first { mix.setVolume(first.gain, at: insertAt) }
                for (a, b) in zip(points, points.dropFirst()) where b.t - a.t > 1e-6 && a.gain != b.gain { mix.setVolumeRamp(fromStartVolume: a.gain, toEndVolume: b.gain, timeRange: CMTimeRange(start: cm(a.t), end: cm(b.t))) }
                audioParameters.append(mix)
            }
        }
        if composition.duration < sequence.duration.cmTime { composition.insertEmptyTimeRange(.init(start: composition.duration, duration: CMTimeSubtract(sequence.duration.cmTime, composition.duration))) }
        let settings = RenderSettings(looks: looks, fps: fps, size: CGSize(width: sequence.width, height: sequence.height))
        // Instructions tile the cut exactly, so marks closer than a microsecond merge rather than leave a gap.
        let total = sequence.duration.seconds
        var marks: [Double] = []
        for m in Set(layers.flatMap { [$0.start, $0.end] }).filter({ $0 > 1e-6 && $0 < total - 1e-6 }).sorted() where m - (marks.last ?? 0) > 1e-6 { marks.append(m) }
        marks = [0] + marks + [total]
        var instructions: [RenderInstruction] = []
        for (a, b) in zip(marks, marks.dropFirst()) {
            let active = layers.filter { $0.start < b - 1e-9 && $0.end > a + 1e-9 }
            instructions.append(.init(range: CMTimeRange(start: a == 0 ? .zero : cm(a), end: b == sequence.duration.seconds ? sequence.duration.cmTime : cm(b)), layers: active, timingTrackID: clockTrack.trackID, settings: settings))
        }
        let ratio = previewMaxDimension.map { min(1, Double($0) / Double(max(sequence.width, sequence.height))) } ?? 1
        var configuration = AVVideoComposition.Configuration()
        configuration.customVideoCompositorClass = GPUCompositor.self
        configuration.instructions = instructions
        configuration.frameDuration = sequence.frameRate.frameDuration
        configuration.renderSize = .init(width: max(2, Int(Double(sequence.width) * ratio) / 2 * 2), height: max(2, Int(Double(sequence.height) * ratio) / 2 * 2))
        configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2; configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2; configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let audio = AVMutableAudioMix(); audio.inputParameters = audioParameters
        return .init(composition: composition, video: AVVideoComposition(configuration: configuration), audio: audio, sequence: sequence, revision: project.editRevision, access: access)
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
