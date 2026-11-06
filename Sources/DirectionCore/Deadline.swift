import Foundation
import os

/// Work that mustn't wait forever (hang recovery, system.md › Crash reports). Past its time, `onTimeout` cancels what it
/// can and the caller gets `error` at once, so whoever is waiting (the editor, a tool call) carries on. Work that ignores
/// cancellation is left to finish on its own; nobody waits for it any more.
public enum Deadline {
    public static func run<T: Sendable>(seconds: Double, error: @escaping @Sendable () -> Error, onTimeout: @escaping @Sendable () -> Void = {},
                                        _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let claimed = OSAllocatedUnfairLock(initialState: false)
        let claim: @Sendable () -> Bool = { claimed.withLock { done in if done { return false }; done = true; return true } }
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<T, Error>) in
                let task = Task {
                    do { let value = try await work(); if claim() { done.resume(returning: value) } }
                    catch { if claim() { done.resume(throwing: error) } }
                }
                box.set(task)
                Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    guard claim() else { return }
                    onTimeout(); task.cancel()
                    done.resume(throwing: error())
                }
            }
        } onCancel: { box.cancel() }
    }

    /// The work's task, so a caller's cancellation reaches it.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<Void, Never>?
        private var cancelled = false
        func set(_ t: Task<Void, Never>) { lock.withLock { task = t; if cancelled { t.cancel() } } }
        func cancel() { lock.withLock { cancelled = true; task?.cancel() } }
    }
}
