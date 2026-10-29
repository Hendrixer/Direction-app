import SwiftUI
import DirectionCore

/// The editor's runs: activity, state, control (specs/editor.md).
@MainActor @Observable final class EditorRunsModel {
    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {}
}
