import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
@testable import DirectionMedia

/// Reading media never holds Swift's shared threads, and a copy that never answers is given up on without
/// stopping its reader under it (ReadStall).
struct ReadStallTests {
    /// More readers at once than Swift has shared threads. A copy made on a shared thread holds it while it
    /// waits, and the work that brings its sample needs one free: with a reader on every shared thread, every
    /// read stopped at its first sample (the suite, 2026-11-05 to 2026-11-08). Well under the hundred or so
    /// readers at once where Apple's media code runs out of threads of its own (ReadStall), whatever runs them.
    @Test func readsAtOnceOnEveryThreadAllFinish() async throws {
        let folder = try MadeProcessingTests.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await MadeProcessingTests.clip(in: folder, frames: 72, sound: true)
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)[0], sound = try await asset.loadTracks(withMediaType: .audio)[0]
        let readers = ProcessInfo.processInfo.activeProcessorCount + 8
        let started = ContinuousClock.now
        let counts = try await withThrowingTaskGroup(of: (picture: Bool, count: Int).self) { group in
            for k in 0..<readers {
                group.addTask {
                    let picture = k % 2 == 0
                    let reader = try AVAssetReader(asset: asset)
                    let output = picture
                        // As stored, not decoded: a crowd of decoders crowds out other tests' encoders.
                        ? AVAssetReaderTrackOutput(track: video, outputSettings: nil)
                        : AVAssetReaderTrackOutput(track: sound, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
                    output.alwaysCopiesSampleData = false
                    reader.add(output)
                    guard reader.startReading() else { throw reader.error ?? DirectionError("test", "The reader didn\u{2019}t start.") }
                    var count = 0
                    while let sample = await output.nextSample(of: reader) { count += CMSampleBufferGetNumSamples(sample) }
                    try ReadStall.check(reader, "the clip")
                    #expect(reader.status == .completed)
                    return (picture, count)
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts.count == readers)
        #expect(counts.filter(\.picture).allSatisfy { $0.count == 72 })
        // Every reader of the sound got all of it.
        let sounds = Set(counts.filter { !$0.picture }.map(\.count))
        #expect(sounds.count == 1 && sounds.first! > 0)
        // Well inside the give-up time: nothing waited on a sample.
        #expect(ContinuousClock.now - started < .seconds(Int(ReadStall.limit)))
    }

    /// A copy that never answers: the read gets nil once the time's up and `check` says the file stopped
    /// answering, once. Stopping the reader then waits until the copy is back; stopping it under the copy
    /// crashed the suite (2026-11-08).
    @Test func aStuckCopyIsGivenUpOnAndItsReaderStoppedOnlyOnceItsBack() async throws {
        let folder = try MadeProcessingTests.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await MadeProcessingTests.clip(in: folder)
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .video)[0], outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())

        let release = DispatchSemaphore(value: 0)
        let started = ContinuousClock.now
        let got = await ReadStall.take(reader, limit: 1) { release.wait(); return nil }
        #expect(got == nil)
        // The watchdog looks once a second.
        #expect(ContinuousClock.now - started < .seconds(4))
        do { try ReadStall.check(reader, "the stuck clip"); Issue.record("A stuck read wasn\u{2019}t reported") }
        catch let e as DirectionError { #expect(e.code == "media_stalled"); #expect(e.message.contains("Reading the stuck clip stopped answering for 1 seconds")) }
        try ReadStall.check(reader, "the stuck clip")

        // Given up on, the reader answers nil at once: a new copy would only wait behind the stuck one.
        #expect(await output.nextSample(of: reader) == nil)
        ReadStall.cancel(reader)
        #expect(reader.status == .reading)

        // Back at last: now nothing waits on the reader, it's stopped.
        release.signal()
        let deadline = ContinuousClock.now + .seconds(5)
        while reader.status == .reading, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(reader.status == .cancelled)
    }

    /// A reader read to its end through ReadStall is stopped at once when asked, with nothing out.
    @Test func aFinishedReaderStopsAtOnce() async throws {
        let folder = try MadeProcessingTests.temp(); defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await MadeProcessingTests.clip(in: folder)
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .video)[0], outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let sample = await output.nextSample(of: reader) { frames += CMSampleBufferGetNumSamples(sample); if frames == 10 { break } }
        #expect(frames == 10)
        ReadStall.cancel(reader)
        #expect(reader.status == .cancelled)
    }
}
