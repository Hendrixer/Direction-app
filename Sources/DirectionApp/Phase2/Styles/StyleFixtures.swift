import SwiftUI
import DirectionCore

// Styles with rules, layouts and moves (styles.md), Keep as a rule, and the Layout picker with a style's
// layouts, from real views and sample state.
@MainActor
enum StyleFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "style-edit": { sheet(StyleSamples.styles[0]) },
            "style-house": { sheet(StyleSamples.house) },
            "keep-rule": { keep() },
            "changes-keep-rule": { .film(answered()) },
            "layout-picker-style": { picker() },
            "library": { library() },
            "mention-list": { mentions() },
            "learn-technique": { SnapshotScene(size: CGSize(width: 520, height: 400), LearnTechniqueSheet(model: ChangesFixtures.cut4()).frame(maxHeight: .infinity, alignment: .top).background(Gate.Surface.ground)) },
        ]
    }

    /// The library as it is on this Mac (DIRECTION_TECHNIQUES_PATH and DIRECTION_CACHE_DIR point it at a scratch
    /// copy in a snapshot run), Grid flash chosen.
    private static func library() -> SnapshotScene {
        let library = LibraryModel.shared
        library.preview = false; library.load()
        return SnapshotScene(size: CGSize(width: 1180, height: 760), LibraryWindowPreview(chosen: library.entries.first { $0.name == "Grid flash" }?.id))
    }

    /// "@gr" typed in a note: the list under it.
    private static func mentions() -> SnapshotScene {
        let library = LibraryModel.shared
        if library.entries.isEmpty { library.preview = true; library.load() }
        return SnapshotScene(size: CGSize(width: 360, height: 230), ZStack(alignment: .top) {
            Gate.Surface.ground
            MentionList(items: Array(library.search("gr").prefix(5)), selected: 0) { _ in }.background(SystemPopBackground())
        })
    }

    private static func sheet(_ s: Style) -> SnapshotScene {
        SnapshotScene(size: CGSize(width: 620, height: 640), StyleEditSheet(draft: .init(s), folder: StyleSamples.folder) {}.frame(maxHeight: .infinity, alignment: .top).background(Gate.Surface.ground))
    }

    /// Cut 4 in Desk + Screen, answer 1 accepted with a rule the editor read in its note.
    private static func answered() -> FilmModel {
        let m = ChangesFixtures.cut4()
        m.brief.style = "desk-screen"
        ChangesFixtures.accept(m, 1)
        if let i = m.notes.firstIndex(where: { $0.number == 1 }), var a = m.notes[i].answers?.last {
            a.rule = RuleSuggestion(text: "Text never covers my face.", area: "graphics", scope: "house")
            m.notes[i].answers = [a]
        }
        m.changes.chosenTab = .accepted
        return m
    }

    private static func keep() -> SnapshotScene {
        let m = answered()
        let note = m.notes.first { $0.number == 1 }!
        return SnapshotScene(size: CGSize(width: 380, height: 260), ZStack(alignment: .top) {
            Gate.Surface.ground
            KeepRulePopover(model: m, note: note, suggestion: note.answers?.last?.rule) {}.background(SystemPopBackground())
        })
    }

    /// The picker in a Desk + Screen film: its layouts by name.
    private static func picker() -> SnapshotScene {
        let m = ChangesFixtures.cut4()
        m.brief.style = "desk-screen"
        m.layouts.draft = m.appliedStyle.layouts[1]; m.layouts.scope = .scene
        return SnapshotScene(size: CGSize(width: 400, height: 360), ZStack {
            Gate.Surface.ground
            LayoutPicker(model: m).background(SystemPopBackground())
        })
    }
}
