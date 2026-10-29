import SwiftUI
import DirectionCore

// Owner: Script and Screening agent (10–12). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum ScriptFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
