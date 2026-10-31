import SwiftUI
import DirectionCore

// The Layout picker (layouts.md), from real views and sample state.
@MainActor
enum LayoutFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "layout-picker": { picker() },
            "layout-notes": { notes() },
        ]
    }

    /// The picker open on Screen and you, bottom right, with a selection on the strip.
    private static func picker() -> SnapshotScene {
        let m = ChangesFixtures.cut4()
        m.rangeSelection = 40...52; m.anchorMode = .range
        m.layouts.draft = .standard; m.layouts.scope = .selection
        return SnapshotScene(size: CGSize(width: 400, height: 380), ZStack {
            Gate.Surface.ground
            LayoutPicker(model: m).background(SystemPopBackground())
        })
    }

    /// Notes with the Layout button after Mark under the picture.
    private static func notes() -> SnapshotScene { .film(NotesFixtures.readBack()) }
}
