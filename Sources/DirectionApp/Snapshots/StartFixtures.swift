import SwiftUI
import DirectionCore

// Owner: Start agent (01–06). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum StartFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
