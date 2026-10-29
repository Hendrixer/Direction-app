import SwiftUI
import DirectionCore

/// Made media, services and spend (specs/made-media.md).
@MainActor @Observable final class MadeModel {
    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {}
}
