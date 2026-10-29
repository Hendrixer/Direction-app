import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent (34–38). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum FinishFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
