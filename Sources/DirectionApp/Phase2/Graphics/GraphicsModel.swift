import SwiftUI
import DirectionCore
import DirectionMedia

/// Graphics in the film and their words (specs/graphics.md). Words are the director's to fix
/// directly, without a turnover (open-questions.md › 14): Change Words re-renders the graphic,
/// records "You changed the words of the title" in History and undoes with ⌘Z. No new cut.
@MainActor @Observable final class GraphicsModel {
    var graphics: [Graphic] = []
    /// Graphics rendering after a words change; their picture shows "Preparing picture".
    var rendering: Set<String> = []
    /// The answer whose Words popover is open.
    var wordsNoteID: String?
    /// What the director is typing, by word key.
    var draft: [String: String] = [:]

    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {
        guard let store = film.store, let all = try? store.graphics() else { return }
        if all != graphics { graphics = all }
    }

    /// The graphic an answer delivered, if it's a graphic answer.
    func graphic(for note: ReviewComment) -> Graphic? { graphics.first { $0.noteID == note.id } }
    func isRendering(_ g: Graphic) -> Bool { rendering.contains(g.name) }

    // MARK: The Words popover (frame 64)

    func openWords(_ g: Graphic, for note: ReviewComment) {
        draft = g.resolvedWords
        wordsNoteID = note.id
    }
    func cancelWords() { wordsNoteID = nil; draft = [:] }

    /// Words longer than their max can't be typed: the field keeps only what fits.
    static func limited(_ text: String, max: Int?) -> String {
        guard let max, text.count > max else { return text }
        return String(text.prefix(max))
    }
    func type(_ text: String, into word: GraphicWord) { draft[word.key] = Self.limited(text, max: word.maxLength) }

    /// Change Words: renders with the new words, then saves them as the director's.
    func changeWords(_ film: FilmModel, _ g: Graphic) {
        let words = draft.filter { key, text in g.text(key) != text }
        cancelWords()
        guard !words.isEmpty else { return }
        if film.isPreview {
            guard let i = graphics.firstIndex(where: { $0.name == g.name }) else { return }
            let before = graphics[i]
            for (k, v) in words { graphics[i].directorWords[k] = v }
            film.registerUndo("Change Words") { m in m.graphics.put(m, before, summary: "Put back") }
            return
        }
        guard let store = film.store else { return }
        rendering.insert(g.name)
        Task {
            defer { rendering.remove(g.name) }
            do {
                let (before, _) = try await GraphicMaker.changeWords(store: store, name: g.name, words: words)
                film.registerUndo("Change Words") { m in m.graphics.put(m, before, summary: "Put back") }
                reload(film)
            } catch { film.error = error.localizedDescription }
        }
    }

    /// Undo and redo: puts a graphic's words back to `state`, registering the way back first so ⌘⇧Z works.
    func put(_ film: FilmModel, _ state: Graphic, summary: String) {
        guard let current = graphics.first(where: { $0.name == state.name }) else { return }
        film.registerUndo("Change Words") { m in m.graphics.put(m, current, summary: summary == "Put back" ? "You changed" : "Put back") }
        if film.isPreview { if let i = graphics.firstIndex(where: { $0.name == state.name }) { graphics[i] = state }; return }
        guard let store = film.store else { return }
        rendering.insert(state.name)
        Task {
            defer { rendering.remove(state.name) }
            do { try await GraphicMaker.restoreWords(store: store, state, summary: "\(summary) the words of \(state.spokenName)"); reload(film) }
            catch { film.error = error.localizedDescription }
        }
    }

    /// Every revision plays the current render, so the cut on screen is compiled again.
    private func reload(_ film: FilmModel) {
        film.refresh(force: true)
        film.loadDisplayed(force: true)
        film.preparePlayback(force: true)
    }
}

extension FilmModel {
    /// The titlebar's steel button stands down while a sheet or the Words popover is open: one steel button per window state.
    var primaryIsInert: Bool { sheet != nil || graphics.wordsNoteID != nil }
}
