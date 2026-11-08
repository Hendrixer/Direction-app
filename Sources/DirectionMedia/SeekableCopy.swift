import Foundation
@preconcurrency import AVFoundation
import Synchronization
import DirectionCore

/// Some encoders (FFmpeg's x265) write open keyframes: the few frames shown just before one are decoded
/// after it, from the group before, yet the file says decoding can start at it. Asked for one of those
/// frames, the player starts at the keyframe and can't decode it, so screening stalls where a cut starts on
/// one, and so do frames and scrubbing there. Such a file comes into a film as a copy in its Footage folder,
/// written without re-encoding: the same picture, sound, timing and track IDs, with those keyframes marked
/// partial so the player starts a group earlier. The original stays as it is.
public enum SeekableCopy {
    /// True when the frame shown just before a keyframe can't be decoded but the keyframe can. Apple's
    /// encoders write the same kinds of frames decodable from their keyframe, so the decoder is asked.
    public static func isNeeded(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first, (try? await track.load(.canProvideSampleCursors)) == true,
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder(), let segments = try? await track.load(.segments) else { return false }
        // The first keyframe after the start with a frame decoded after it but shown before it.
        var found: (keyframe: CMTime, leading: CMTime)?, steps = 0
        while found == nil, steps < 3_000, cursor.stepInDecodeOrder(byCount: 1) == 1 {
            steps += 1
            guard cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue, let next = cursor.copy() as? AVSampleCursor, next.stepInDecodeOrder(byCount: 1) == 1,
                  next.presentationTimeStamp < cursor.presentationTimeStamp else { continue }
            found = (cursor.presentationTimeStamp, next.presentationTimeStamp)
        }
        // The cursor counts in the media's own time; an edit list (FFmpeg's B-frame delay) shifts what plays.
        func played(_ t: CMTime) -> CMTime? { segments.first { !$0.isEmpty && $0.timeMapping.source.containsTime(t) }.map { CMTimeMapTimeFromRangeToRange(t, fromRange: $0.timeMapping.source, toRange: $0.timeMapping.target) } }
        guard let found, let keyframe = played(found.keyframe), let leading = played(found.leading) else { return false }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 64, height: 64)
        do { _ = try await generator.image(at: leading); return false } catch { return (try? await generator.image(at: keyframe)) != nil }
    }

    /// Writes the copy into `folder` under the original's name as a .mov (QuickTime keeps partial keyframes),
    /// or "Name 2.mov" when that's taken. It's written to a hidden file first, so a copy cut short never looks finished.
    public static func make(_ url: URL, in folder: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        // In track order, so each track keeps its ID and a take's sound settings, kept by track, still find theirs.
        let tracks = try await asset.load(.tracks).filter { $0.mediaType == .video || $0.mediaType == .audio }.sorted { $0.trackID < $1.trackID }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).copying.mov")
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mov)
        var streams: [Stream] = []
        func failed() -> Error { writer.error ?? streams.lazy.compactMap(\.reader.error).first ?? DirectionError("seekable_copy_failed", "Direction couldn\u{2019}t copy \(url.lastPathComponent).") }
        do {
            for track in tracks {
                // A reader of its own: one reader's tracks wait on each other, and the writer can hold one back.
                let reader = try AVAssetReader(asset: asset), output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                output.alwaysCopiesSampleData = false
                let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: try await track.load(.formatDescriptions).first)
                input.expectsMediaDataInRealTime = false
                if track.mediaType == .video { input.transform = try await track.load(.preferredTransform); input.mediaTimeScale = try await track.load(.naturalTimeScale) }
                if let tag = try await track.load(.extendedLanguageTag) { input.extendedLanguageTag = tag }
                if let code = try await track.load(.languageCode) { input.languageCode = code }
                guard reader.canAdd(output), writer.canAdd(input) else { throw failed() }
                reader.add(output); writer.add(input)
                streams.append(Stream(reader: reader, output: output, input: input, video: track.mediaType == .video))
            }
            guard streams.allSatisfy({ $0.reader.startReading() }), writer.startWriting() else { throw failed() }
            writer.startSession(atSourceTime: .zero)
            let copying = Copying(writer: writer, streams: streams)
            try await withTaskCancellationHandler { try await copying.run() } onCancel: { copying.cancel() }
            try Task.checkCancellation()
            for stream in streams { try ReadStall.check(stream.reader, "the footage") }
            guard streams.allSatisfy({ $0.reader.status == .completed }) else { throw failed() }
            await writer.finishWriting()
            guard writer.status == .completed else { throw failed() }
            return try SDRCopy.place(temp, as: url, in: folder)
        } catch {
            for stream in streams { ReadStall.cancel(stream.reader) }
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Takes brought in before Direction made these copies, still on such a file, get theirs in place: the
    /// same take, so its cuts, notes and sound settings carry on. Each file is asked once; `checked` keeps
    /// which, so opening the film again costs nothing. Returns the takes it copied.
    public static func copyTakes(in store: ProjectStore, checked: URL) async -> [MediaAsset] {
        func key(_ a: MediaAsset) -> String { "\(a.id) \(a.fileSize) \(a.modifiedAt) \(a.path)" }
        var seen = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: checked))) ?? [])
        let takes = ((try? store.read())?.footage(film: store.url) ?? []).filter { !$0.isImage && !$0.video.isEmpty && $0.sdrCopyOf == nil && $0.seekableCopyOf == nil && !seen.contains(key($0)) }
        var copied: [MediaAsset] = []
        for take in takes where !Task.isCancelled {
            // A take that's offline is asked when it's back.
            guard let url = try? MediaInspector.checkedURL(take) else { continue }
            if await isNeeded(url) {
                do { copied.append(try await copy(take, from: url, in: store)) }
                catch { DirectionLog.warning("Couldn\u{2019}t copy \(take.name) so it plays from any frame: \(error.localizedDescription)", "footage"); continue }
            }
            seen.insert(key(take))
        }
        if !takes.isEmpty { try? JSONEncoder().encode(seen.sorted()).write(to: checked, options: .atomic) }
        return copied
    }

    private static func copy(_ take: MediaAsset, from url: URL, in store: ProjectStore) async throws -> MediaAsset {
        let file = try await make(url, in: MediaAsset.copies(in: store.url))
        do {
            let copy = try await MediaInspector.inspect(url: file)
            guard copy.video.map(\.id) == take.video.map(\.id), copy.audio.map(\.id) == take.audio.map(\.id) else { throw DirectionError("seekable_copy_failed", "The copy of \(take.name) doesn\u{2019}t have its tracks.") }
            return try store.useSeekableCopy(AssetRelink(assetID: take.id, path: copy.path, fileSize: copy.fileSize, modifiedAt: copy.modifiedAt, duration: copy.duration, bookmark: copy.bookmark)).asset(take.id)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}

/// The samples moving into the copy, on a thread of its own: reading blocks until the file's data is in, and
/// Swift's shared threads mustn't wait on it (when they all do, nothing is left to read the file). A track at
/// a time while it takes more; the writer holds back one that's ahead of the others.
private final class Copying: @unchecked Sendable {
    private let writer: AVAssetWriter, streams: [Stream]
    private let cancelled = Mutex(false)
    init(writer: AVAssetWriter, streams: [Stream]) { self.writer = writer; self.streams = streams }
    func cancel() { cancelled.withLock { $0 = true } }

    func run() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            DispatchQueue(label: "dev.direction.seekable-copy", qos: .userInitiated).async { [self] in done.resume(with: Result { try pump() }) }
        }
    }

    private func pump() throws {
        while streams.contains(where: { !$0.finished }) {
            guard !cancelled.withLock({ $0 }) else { throw CancellationError() }
            guard writer.status == .writing, !streams.contains(where: { $0.reader.status == .failed }) else { throw writer.error ?? DirectionError("seekable_copy_failed", "The copy stopped.") }
            var moved = false
            for stream in streams where !stream.finished && stream.input.isReadyForMoreMediaData {
                moved = true
                guard let sample = stream.next() else { stream.input.markAsFinished(); stream.finished = true; continue }
                guard stream.input.append(sample) else { throw writer.error ?? DirectionError("seekable_copy_failed", "The copy stopped.") }
            }
            if !moved { usleep(2_000) }
        }
    }
}

/// One track on its way into the copy. A video keyframe waits for the frame after it: when that frame is
/// shown before it, decoding can't start at the keyframe, so it's marked partial. The first frame starts the
/// file whatever follows it.
private final class Stream {
    let reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, video: Bool
    var finished = false
    private var held: CMSampleBuffer?, waiting: [CMSampleBuffer] = [], started = false
    init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, video: Bool) { self.reader = reader; self.output = output; self.input = input; self.video = video }

    func next() -> CMSampleBuffer? {
        while waiting.isEmpty, let sample = output.nextSampleWaiting(of: reader) {
            guard video else { return sample }
            if let keyframe = held {
                if sample.presentationTimeStamp < keyframe.presentationTimeStamp { Self.markPartial(keyframe) }
                waiting.append(keyframe); held = nil
            }
            if started, Self.isFullSync(sample) { held = sample } else { waiting.append(sample) }
            started = true
        }
        if waiting.isEmpty, let keyframe = held { held = nil; return keyframe }
        return waiting.isEmpty ? nil : waiting.removeFirst()
    }

    private static func isFullSync(_ sample: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        return attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
    }

    private static func markPartial(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary], let first = attachments.first else { return }
        first[kCMSampleAttachmentKey_NotSync] = kCFBooleanTrue
        first[kCMSampleAttachmentKey_PartialSync] = kCFBooleanTrue
    }
}
