import SwiftUI

// Snapshot frames for phase 2. Each area returns its own frames (design/spec/frames.js 54–64).
@MainActor
enum Phase2Fixtures {
    static var frames: [String: () -> SnapshotScene] {
        var all: [String: () -> SnapshotScene] = [:]
        for group in [RunsFixtures.frames, IndexFixtures.frames, LooksFixtures.frames, GraphicsFixtures.frames, MadeFixtures.frames] { all.merge(group) { a, _ in a } }
        return all
    }
}
