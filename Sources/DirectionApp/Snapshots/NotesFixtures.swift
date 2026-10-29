import SwiftUI
import DirectionCore

// Owner: Notes agent (17–28). Register a SnapshotScene per frame ID from design/spec/frames.js.
@MainActor
enum NotesFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [:]
    }
}
