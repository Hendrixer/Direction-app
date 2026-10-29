import SwiftUI
import DirectionCore

/// Shots, sounds and search for Dailies (specs/footage-index.md).
@MainActor @Observable final class FootageIndexModel {
    /// Takes looked at so far, while the index is working; nil when idle. The pill reads it.
    var looking: IndexProgress?
    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {}
}

struct IndexProgress: Equatable { var done: Int; var total: Int }
