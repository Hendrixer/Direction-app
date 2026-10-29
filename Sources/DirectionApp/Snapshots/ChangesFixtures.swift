import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent (29–33). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum ChangesFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
