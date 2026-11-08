import AVFoundation
import DirectionCore

/// Reading media without holding Swift's shared threads, and without waiting forever.
///
/// AVAssetReader's copyNextSampleBuffer blocks until a sample comes, and on macOS 26 the work that brings
/// it needs one of Swift's shared threads to be free. A copy made on one of those threads holds it while it
/// waits, so once every shared thread waits on a copy (16 at once on a 16-core Mac, 8 on an 8-core one),
/// nothing is left to bring a sample and every read in the process stops for good (the test suite hung,
/// 2026-11-05 and 2026-11-07; repeated in a small program, 2026-11-08: 16 readers stop at their first
/// sample, 15 never do, and 48 on threads of their own never wait past 0.1 s). GCD's threads won't do either:
/// it lends about 64 to work like this, Apple's media code needs some of them too, and 60 copies blocking on a
/// GCD queue stop every read the same way (the suite, 2026-11-08). So every copy is made on a thread of
/// Direction's own (`OwnThreads`), and a reader on a shared thread awaits it instead.
///
/// One limit is Apple's own and can't be read around: each reader reading keeps one of its threads busy
/// fetching ahead, and past about a hundred at once in a process they run out and every read stops, on any
/// threads (120 readers on plain threads stopped, 80 never did; capping the copies at 24 didn't help, as the
/// readers fetch ahead anyway). Direction never has near that many open: its work in parallel runs four at
/// a time. Tests keep under it too (ReadStallTests).
///
/// Past `limit` seconds without a sample, the copy is given up on: the read gets nil, and `check` turns that
/// into an error saying which file stopped answering. The copy itself is left to finish on its thread. It
/// is never cancelled under it: cancelling a reader while a copy waits on it frees what the copy is waiting
/// on and crashes the app (the suite, 2026-11-08). A reader given up on or stopped answers nil from then on,
/// and `cancel` stops it once its copy is back.
///
/// One watchdog looks after every copy that's waiting, ticking once a second while any is.
public enum ReadStall {
    /// No single sample takes this long to decode, even 4K from a slow drive.
    nonisolated(unsafe) public static var limit: Double = 30

    /// Where copies wait.
    private static let copies = OwnThreads(name: "dev.direction.media-read", qos: .userInitiated)
    private static let lock = NSLock()
    /// The copies waiting on a sample now, by number.
    nonisolated(unsafe) private static var waiting: [UInt64: Copy] = [:]
    nonisolated(unsafe) private static var lastCopy: UInt64 = 0
    /// Readers with a copy out, given up on, or to stop once their copy is back. Held weakly, so a reader
    /// that's gone is never taken for a later one at the same address.
    nonisolated(unsafe) private static var readers: [ObjectIdentifier: Reading] = [:]
    nonisolated(unsafe) private static var watchdog: DispatchSourceTimer?

    /// The next sample, copied on a thread of its own while the caller waits without holding one.
    static func next(_ output: AVAssetReaderOutput, of reader: AVAssetReader) async -> CMSampleBuffer? {
        let work = Work(output: output)
        return await take(reader, limit: limit) { work.output.copyNextSampleBuffer() }
    }

    /// A copy made by `copy` on a thread of its own, given up on after `limit` seconds (tests make their own).
    static func take(_ reader: AVAssetReader, limit: Double, copy: @escaping @Sendable () -> CMSampleBuffer?) async -> CMSampleBuffer? {
        await withCheckedContinuation { (done: CheckedContinuation<Sample, Never>) in
            start(reader, limit: limit, copy: copy) { done.resume(returning: $0) }
        }.buffer
    }

    /// The same for code already on a thread of its own (VisionWork's, or a serial queue's), never on Swift's shared threads.
    static func nextWaiting(_ output: AVAssetReaderOutput, of reader: AVAssetReader) -> CMSampleBuffer? {
        let done = DispatchSemaphore(value: 0)
        let got = Got(), work = Work(output: output)
        start(reader, limit: limit, copy: { work.output.copyNextSampleBuffer() }) { got.sample = $0; done.signal() }
        done.wait()
        return got.sample.buffer
    }

    /// Stops a reader; one whose copy is still out (given up on, or answering) stops once it's back. Either
    /// way no copy starts on it again, so none can be waiting while it stops.
    static func cancel(_ reader: AVAssetReader) {
        let now: Bool = lock.withLock {
            let r = reading(reader)
            r.stopped = true
            guard r.out > 0 else { return true }
            r.cancel = true
            return false
        }
        if now, reader.status == .reading { reader.cancelReading() }
    }

    /// Under the lock: what's known of a reader, made when nothing is.
    private static func reading(_ reader: AVAssetReader) -> Reading {
        let key = ObjectIdentifier(reader)
        if let known = readers[key], known.reader === reader { return known }
        // Readers stopped or given up on stay known while they live; forget the ones that are gone now and then.
        if readers.count >= 256 { readers = readers.filter { $0.value.reader != nil } }
        let r = Reading(reader)
        readers[key] = r
        return r
    }

    /// After a read loop: throws when the reader was given up on for stalling.
    static func check(_ reader: AVAssetReader, _ what: @autoclosure () -> String) throws {
        let was = lock.withLock {
            guard let r = readers[ObjectIdentifier(reader)], r.reader === reader, r.gaveUp, !r.told else { return nil as Double? }
            r.told = true
            return r.limit
        }
        guard let after = was else { return }
        let name = what(), seconds = Int(after.rounded())
        DirectionLog.error("Reading \(name) gave no frame or sound for \(seconds) s and was stopped", "media")
        throw DirectionError("media_stalled", "Reading \(name) stopped answering for \(seconds) seconds and was stopped. Try again; if it keeps happening, the file or the drive it's on may be the trouble.")
    }

    private static func start(_ reader: AVAssetReader, limit: Double, copy make: @escaping @Sendable () -> CMSampleBuffer?, answer: @escaping @Sendable (Sample) -> Void) {
        let copy: Copy? = lock.withLock {
            let r = reading(reader)
            // A reader given up on answers nothing more: its last copy may still be waiting, and a new one would
            // wait behind it. Nor does one that's stopped or being stopped: a copy must never wait while it stops.
            guard !r.gaveUp, !r.stopped else { return nil }
            r.out += 1
            lastCopy &+= 1
            let copy = Copy(number: lastCopy, reading: r, limit: limit, answer: answer)
            waiting[lastCopy] = copy
            if watchdog == nil { watch() }
            return copy
        }
        guard let copy else { return answer(Sample(nil)) }
        // The copy holds its reader until it's back, so a reader given up on is never freed under it.
        let held = Held(reader: reader)
        copies.run { back(copy, Sample(make()), held.reader) }
    }

    /// A copy came back: its answer goes to the reader unless the reader was already given up on, and a
    /// reader stopped meanwhile is stopped now that nothing waits on it.
    private static func back(_ copy: Copy, _ sample: Sample, _ reader: AVAssetReader) {
        let (answer, stop): ((@Sendable (Sample) -> Void)?, Bool) = lock.withLock {
            waiting[copy.number] = nil
            let answer = copy.answer
            copy.answer = nil
            let r = copy.reading
            r.out -= 1
            let stop = r.out == 0 && r.cancel
            if stop { r.cancel = false }
            // Done with: nothing out and nothing still to say.
            if r.out == 0, !r.gaveUp, !r.stopped, readers[ObjectIdentifier(reader)] === r { readers[ObjectIdentifier(reader)] = nil }
            return (answer, stop)
        }
        // Stopped before the sample goes back, so nothing reading on can start a copy under it.
        if stop, reader.status == .reading { reader.cancelReading() }
        answer?(sample)
    }

    /// The watchdog's own queue. A private serial queue gets a thread even when every shared one is blocked,
    /// which is exactly when it has to run (the suite hung with its watchdog on the shared utility queue, 2026-11-07).
    private static let queue = DispatchQueue(label: "dev.direction.read-stall", qos: .userInitiated)

    /// Under the lock: the one watchdog, which stops once nothing is waiting.
    private static func watch() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { sweep() }
        watchdog = timer
        timer.resume()
    }

    /// Gives up on the copies that have waited past the limit: their readers get nil now, and the copies are
    /// left to come back when they do.
    private static func sweep() {
        let now = DispatchTime.now()
        let late: [(answer: @Sendable (Sample) -> Void, limit: Double)] = lock.withLock {
            var late: [(answer: @Sendable (Sample) -> Void, limit: Double)] = []
            for (number, copy) in waiting where copy.deadline <= now {
                waiting[number] = nil
                copy.reading.gaveUp = true
                copy.reading.limit = copy.limit
                if let answer = copy.answer { late.append((answer, copy.limit)); copy.answer = nil }
            }
            readers = readers.filter { $0.value.reader != nil }
            if waiting.isEmpty { watchdog?.cancel(); watchdog = nil }
            return late
        }
        guard !late.isEmpty else { return }
        let seconds = Int((late.map(\.limit).min() ?? limit).rounded())
        DirectionLog.error("\(late.count == 1 ? "A read" : "\(late.count) reads") waited \(seconds) s or more for a sample; giving up on \(late.count == 1 ? "it" : "them")", "media")
        for late in late { late.answer(Sample(nil)) }
    }

    /// For tests: copies out now, given up on or not.
    static var copiesOut: Int { lock.withLock { readers.values.reduce(0) { $0 + $1.out } } }

    private final class Reading: @unchecked Sendable {
        weak var reader: AVAssetReader?
        var out = 0, gaveUp = false, told = false, cancel = false, stopped = false
        /// The time it was given up after.
        var limit = 0.0
        init(_ reader: AVAssetReader) { self.reader = reader }
    }

    private final class Copy: @unchecked Sendable {
        let number: UInt64, reading: Reading, limit: Double, deadline: DispatchTime
        var answer: (@Sendable (Sample) -> Void)?
        init(number: UInt64, reading: Reading, limit: Double, answer: @escaping @Sendable (Sample) -> Void) {
            self.number = number; self.reading = reading; self.limit = limit; self.deadline = .now() + limit; self.answer = answer
        }
    }

    /// A sample handed from the copy's thread to its reader, which owns it from then on.
    private struct Sample: @unchecked Sendable { let buffer: CMSampleBuffer?; init(_ b: CMSampleBuffer?) { buffer = b } }
    private final class Got: @unchecked Sendable { var sample = Sample(nil) }
    /// An output handed to the copy's thread; its reader waits meanwhile.
    private struct Work: @unchecked Sendable { let output: AVAssetReaderOutput }
    private struct Held: @unchecked Sendable { let reader: AVAssetReader }
}

extension AVAssetReaderOutput {
    /// copyNextSampleBuffer, made on a thread of its own while the caller awaits it, and given up on after
    /// `ReadStall.limit` seconds (then `ReadStall.check` throws).
    public func nextSample(of reader: AVAssetReader) async -> CMSampleBuffer? { await ReadStall.next(self, of: reader) }

    /// The same, for code already on a thread of its own (VisionWork's, or a serial queue's): it blocks that thread.
    public func nextSampleWaiting(of reader: AVAssetReader) -> CMSampleBuffer? { ReadStall.nextWaiting(self, of: reader) }
}
