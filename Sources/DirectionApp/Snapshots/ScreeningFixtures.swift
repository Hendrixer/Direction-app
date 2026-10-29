import SwiftUI
import DirectionCore

// Owner: Script and Screening agent (13–16). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum ScreeningFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
