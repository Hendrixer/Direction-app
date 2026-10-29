import SwiftUI
import DirectionCore

/// Graphics in the film and their words (specs/graphics.md).
@MainActor @Observable final class GraphicsModel {
    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {}
}
