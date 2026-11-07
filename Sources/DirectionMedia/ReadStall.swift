import AVFoundation
import DirectionCore

/// Reading media that can't wait forever (hang recovery). AVAssetReader's copyNextSampleBuffer blocks until a sample
/// comes; under load it has been seen to wait forever (17 reads at once in the tests, 2026-11-05). Past `limit` seconds
/// without a sample, the reader is cancelled from another thread, so the copy returns nil, and `check` turns that into
/// an error saying which file stopped answering instead of a read that never ends.
///
/// One watchdog looks after every copy that's waiting, ticking once a second while any is: a sample costs a note of
/// its reader and deadline, never a timer of its own, and no reader is held once its copy returns.
public enum ReadStall {
    /// No single sample takes this long to decode, even 4K from a slow drive.
    nonisolated(unsafe) public static var limit: Double = 30
    private static let lock = NSLock()
    /// The copies waiting on a sample now: their reader, and when they give up.
    nonisolated(unsafe) private static var waiting: [UInt64: (reader: AVAssetReader, deadline: DispatchTime)] = [:]
    nonisolated(unsafe) private static var lastCopy: UInt64 = 0
    nonisolated(unsafe) private static var watchdog: DispatchSourceTimer?
    /// Readers stopped for stalling, until `check` hears of it. Held weakly, so a reader that's gone is never taken
    /// for a later one at the same address.
    nonisolated(unsafe) private static var stalled: [ObjectIdentifier: Stalled] = [:]

    static func next(_ output: AVAssetReaderOutput, of reader: AVAssetReader) -> CMSampleBuffer? {
        let copy: UInt64 = lock.withLock {
            lastCopy &+= 1
            waiting[lastCopy] = (reader, .now() + limit)
            if watchdog == nil { watch() }
            return lastCopy
        }
        defer { lock.withLock { _ = waiting.removeValue(forKey: copy) } }
        return output.copyNextSampleBuffer()
    }

    /// The watchdog's own queue. A private serial queue gets a thread even when every shared one is blocked in a
    /// read, which is exactly when it has to run (the full suite hung with all 16 cooperative threads in
    /// copyNextSampleBuffer, 2026-11-07, and the watchdog on the shared utility queue never fired).
    private static let queue = DispatchQueue(label: "dev.direction.read-stall", qos: .userInitiated)

    /// Under the lock: the one watchdog, which stops once nothing is waiting.
    private static func watch() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { sweep() }
        watchdog = timer
        timer.resume()
    }

    /// Cancels the readers whose copy has waited past the limit (outside the lock: cancelling can take a moment).
    private static func sweep() {
        let now = DispatchTime.now()
        let late: [AVAssetReader] = lock.withLock {
            var late: [AVAssetReader] = []
            for (copy, w) in waiting where w.deadline <= now {
                waiting[copy] = nil
                stalled[ObjectIdentifier(w.reader)] = Stalled(w.reader)
                late.append(w.reader)
            }
            stalled = stalled.filter { $0.value.reader != nil }
            if waiting.isEmpty { watchdog?.cancel(); watchdog = nil }
            return late
        }
        if !late.isEmpty { DirectionLog.error("\(late.count == 1 ? "A read" : "\(late.count) reads") waited \(Int(limit)) s for a sample; stopping \(late.count == 1 ? "it" : "them")", "media") }
        for reader in late { reader.cancelReading() }
    }

    /// After a read loop: throws when the reader was stopped for stalling (and forgets it).
    static func check(_ reader: AVAssetReader, _ what: @autoclosure () -> String) throws {
        let was = lock.withLock { stalled.removeValue(forKey: ObjectIdentifier(reader))?.reader === reader }
        guard was else { return }
        let name = what()
        DirectionLog.error("Reading \(name) gave no frame or sound for \(Int(limit)) s and was stopped", "media")
        throw DirectionError("media_stalled", "Reading \(name) stopped answering for \(Int(limit)) seconds and was stopped. Try again; if it keeps happening, the file or the drive it's on may be the trouble.")
    }

    private final class Stalled: @unchecked Sendable { weak var reader: AVAssetReader?; init(_ r: AVAssetReader) { reader = r } }
}

extension AVAssetReaderOutput {
    /// copyNextSampleBuffer that gives up after `ReadStall.limit` seconds (then `ReadStall.check` throws).
    func nextSample(of reader: AVAssetReader) -> CMSampleBuffer? { ReadStall.next(self, of: reader) }
}
