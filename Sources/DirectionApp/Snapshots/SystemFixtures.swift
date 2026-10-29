import SwiftUI
import DirectionCore

// Owner: System agent (39–53). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum SystemFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
