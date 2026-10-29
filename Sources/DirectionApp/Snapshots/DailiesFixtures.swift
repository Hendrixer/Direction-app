import SwiftUI
import DirectionCore

// Owner: Start agent (07–09). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum DailiesFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
