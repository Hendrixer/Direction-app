import AVFoundation
import DirectionCore

/// Reading media that can't wait forever (hang recovery). AVAssetReader's copyNextSampleBuffer blocks until a sample
/// comes; under load it has been seen to wait forever (17 reads at once in the tests, 2026-11-05). Past `limit` seconds
/// without a sample, the reader is cancelled from another thread, so the copy returns nil, and `check` turns that into
/// an error saying which file stopped answering instead of a read that never ends.
public enum ReadStall {
    /// No single sample takes this long to decode, even 4K from a slow drive.
    nonisolated(unsafe) public static var limit: Double = 30
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stalled = Set<ObjectIdentifier>()

    static func next(_ output: AVAssetReaderOutput, of reader: AVAssetReader) -> CMSampleBuffer? {
        let box = ReaderBox(reader)
        let watchdog = DispatchWorkItem {
            lock.withLock { _ = stalled.insert(ObjectIdentifier(box.reader)) }
            box.reader.cancelReading()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit, execute: watchdog)
        defer { watchdog.cancel() }
        return output.copyNextSampleBuffer()
    }

    /// After a read loop: throws when the reader was stopped for stalling (and forgets it).
    static func check(_ reader: AVAssetReader, _ what: @autoclosure () -> String) throws {
        let was = lock.withLock { stalled.remove(ObjectIdentifier(reader)) != nil }
        guard was else { return }
        let name = what()
        DirectionLog.error("Reading \(name) gave no frame or sound for \(Int(limit)) s and was stopped", "media")
        throw DirectionError("media_stalled", "Reading \(name) stopped answering for \(Int(limit)) seconds and was stopped. Try again; if it keeps happening, the file or the drive it's on may be the trouble.")
    }

    private final class ReaderBox: @unchecked Sendable { let reader: AVAssetReader; init(_ r: AVAssetReader) { reader = r } }
}

extension AVAssetReaderOutput {
    /// copyNextSampleBuffer that gives up after `ReadStall.limit` seconds (then `ReadStall.check` throws).
    func nextSample(of reader: AVAssetReader) -> CMSampleBuffer? { ReadStall.next(self, of: reader) }
}
