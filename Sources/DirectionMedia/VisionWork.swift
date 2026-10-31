import Foundation
import CoreGraphics

/// Vision's requests block the thread they run on while Vision waits for work of its own, and some
/// of that work needs Swift's shared threads. Run on those threads, a few at once can leave none
/// free for it and everything waits for good: footage stuck at "Finding shots · 0 of 1", a test run
/// hung inside text recognition. Vision runs on threads of its own instead.
enum VisionWork {
    private static let queue = DispatchQueue(label: "dev.direction.vision", qos: .utility, attributes: .concurrent)

    static func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { done in queue.async { done.resume(with: Result(catching: body)) } }
    }
}

/// A frame handed to Vision on its own thread. A CGImage never changes once made.
struct VisionImage: @unchecked Sendable {
    let image: CGImage
}
