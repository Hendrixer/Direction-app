import Foundation

/// Threads of Direction's own for work that blocks while Apple's frameworks finish something of theirs: a
/// media read waiting on its sample (ReadStall), a Vision request waiting on its model (VisionWork). That
/// work needs threads from both pools a process shares, Swift's (one per core) and GCD's (about 64 for work
/// like this), so blocking either pool while it waits can leave none for it, and everything waits for good.
/// Here, each job waiting has a thread: one is made when none is free, and gone after a minute with nothing
/// to do. 120 media reads at once on threads like these never waited past 0.2 s (2026-11-08).
final class OwnThreads: @unchecked Sendable {
    private let name: String, qos: QualityOfService
    private let condition = NSCondition()
    private var jobs: [@Sendable () -> Void] = []
    /// Threads waiting for a job.
    private var idle = 0

    init(name: String, qos: QualityOfService) { self.name = name; self.qos = qos }

    func run(_ job: @escaping @Sendable () -> Void) {
        condition.lock()
        jobs.append(job)
        // A thread waiting for each job not yet taken, or a new one.
        if idle >= jobs.count { condition.signal() } else { start() }
        condition.unlock()
    }

    /// `body` on one of these threads, awaited without holding a thread of Swift's.
    func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { done in run { done.resume(with: Result(catching: body)) } }
    }

    private func start() {
        let thread = Thread { [self] in work() }
        thread.name = name
        thread.qualityOfService = qos
        thread.start()
    }

    private func work() {
        condition.lock()
        while true {
            while jobs.isEmpty {
                idle += 1
                let woken = condition.wait(until: Date().addingTimeInterval(60))
                idle -= 1
                if !woken, jobs.isEmpty { condition.unlock(); return }
            }
            let job = jobs.removeFirst()
            condition.unlock()
            autoreleasepool { job() }
            condition.lock()
        }
    }
}
