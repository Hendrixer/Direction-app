import SwiftUI
import DirectionCore

/// The film's look and the Look sheet (specs/looks.md).
@MainActor @Observable final class LooksModel {
    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {}
}
