import SwiftUI
import AppKit
import DirectionCore

// Styles with rules, layouts and moves (styles.md), Keep as a rule, and the Layout picker with a style's
// layouts, from real views and sample state.
@MainActor
enum StyleFixtures {
    static var frames: [String: () -> SnapshotScene] {
        [
            "style-edit": { page(StyleSamples.styles[0], height: 1480) },
            "settings-library-entry": { SettingsKey.register(); LibraryModel.shared.preview = false; LibraryModel.shared.load()
                let entry = LibraryModel.shared.entries.first { $0.name == "Grid flash" } ?? LibraryModel.shared.entries.first
                return settingsPage(SettingsPage(id: "library:" + (entry?.id ?? ""), title: entry?.name ?? "") { LibraryEntryPage(id: entry?.id ?? "") }, tab: .library, height: 789) },
            "style-house": { page(StyleSamples.house, height: 640) },
            "style-new": { SnapshotScene(size: CGSize(width: 640, height: 560), StyleEditSheet(draft: .new, folder: StyleSamples.folder) {}.frame(maxHeight: .infinity, alignment: .top).background(Gate.Surface.ground)) },
            "settings-library-page": { SettingsKey.register(); return settingsPage(SettingsPage(id: "library", title: "Library") { LibraryPage(preview: true) }, tab: .library, height: 789) },
            "keep-rule": { keep() },
            "changes-keep-rule": { .film(answered()) },
            "layout-picker-style": { picker() },
            "library": { library() },
            "library-sounds": { library(kind: "sounds") },
            "library-images": { library(kind: "images") },
            "mention-list": { mentions() },
            "mention-note": { mentionNote() },
            "learn-technique": { SnapshotScene(size: CGSize(width: 520, height: 400), LearnTechniqueSheet(model: ChangesFixtures.cut4()).frame(maxHeight: .infinity, alignment: .top).background(Gate.Surface.ground)) },
            "style-from-video": { SnapshotScene(size: CGSize(width: 540, height: 470), StyleFromVideoSheet(model: ChangesFixtures.cut4(), videos: [
                StyleVideo(link: "https://www.youtube.com/watch?v=k3Jx9fQ2mPo"), StyleVideo(file: URL(fileURLWithPath: "/Users/you/Movies/Their best one.mp4")),
            ], ask: "How fast it moves, the yellow captions three words at a time, the punch-in on every joke.") {}.frame(maxHeight: .infinity, alignment: .top).background(Gate.Surface.ground)) },
            "style-learned": { learned() },
        ]
    }

    /// A style made from two videos: where it came from, its examples (stills drawn for the snapshot) and how one runs.
    private static func learned() -> SnapshotScene {
        let url = StyleSamples.folder.appendingPathComponent("fast-talk")
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("stills"), withIntermediateDirectories: true)
        let stills: [(String, NSColor)] = [("captions", .systemYellow), ("punch", .systemOrange), ("screen", .systemTeal), ("hook", .systemPink)]
        for (name, color) in stills {
            let image = NSImage(size: NSSize(width: 320, height: 180), flipped: false) { r in color.withAlphaComponent(0.55).setFill(); r.fill(); return true }
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let jpg = rep.representation(using: .jpeg, properties: [:]) { try? jpg.write(to: url.appendingPathComponent("stills/\(name).jpg")) }
        }
        let study = VideoStudy(title: "How I edit talking videos", by: "Ali Example", link: "https://www.youtube.com/watch?v=k3Jx9fQ2mPo", seconds: 742,
                               pace: .init(shots: 241, cutsPerMinute: 19.5, averageShot: 3.1, medianShot: 2.6, longestShot: 11, firstCut: 1.4, cutsByMinute: [31, 22, 18]),
                               words: .init(count: 2078, perMinute: 168, medianPause: 0.11, longestPause: 1.2, pausesOverHalfSecond: 0.08), sound: .init(loudness: -14.2, truePeak: -1.1, music: 0.86, musicUnderSpeech: 0.8),
                               picture: .init(close: 0.62, medium: 0.28, wide: 0.02, noFace: 0.08, punchIns: 0.55, brightness: 0.52, contrast: 0.21, saturation: 0.38, warmth: 0.06),
                               onScreen: .init(captions: 0.84, otherText: 0.12, wordsPerCaption: 3, captionHeight: 0.72, upperCase: 1), shots: [])
        var second = study; second.title = "My desk setup, cut fast"; second.pace.shots = 188; second.pace.averageShot = 3.4; second.pace.cutsPerMinute = 17.6
        let style = Style(id: "fast-talk", url: url, name: "Fast Talk", summary: "Close, fast and captioned: a cut every three seconds, a punch-in on every joke.", updatedAt: 0, tokens: .object([
            "format": .number(2),
            "rules": StyleSamples.rules([("captions", "Bold yellow captions, three words at a time, upper case, in the lower third.")]),
            "sources": (try? JSONValue.wrapping([StyleSource(study), StyleSource(second)])) ?? .array([]),
            "examples": .array([
                .object(["still": .string("stills/captions.jpg"), "area": .string("captions"), "text": .string("Three words at a time, yellow, in the lower third."), "source": .number(0), "at": .number(14)]),
                .object(["still": .string("stills/punch.jpg"), "area": .string("picture"), "text": .string("A punch-in on the joke, out on the next cut."), "source": .number(0), "at": .number(62)]),
                .object(["still": .string("stills/screen.jpg"), "area": .string("layouts"), "text": .string("The screen full, the face in a round corner."), "source": .number(1), "at": .number(130)]),
                .object(["still": .string("stills/hook.jpg"), "area": .string("pace"), "text": .string("The result in the first second, before a word."), "source": .number(1), "at": .number(0.5)]),
            ]),
            "structure": .array([
                .object(["name": .string("Hook"), "at": .number(0), "length": .number(8), "what": .string("The result first, then the question it answers.")]),
                .object(["name": .string("Sections"), "length": .number(90), "what": .string("One idea each, a title card between them.")]),
                .object(["name": .string("Ending"), "what": .string("A one-line takeaway, then straight out. No outro.")]),
            ]),
        ]), contents: { var c = StyleContents(); c.stills = stills.map { $0.0 + ".jpg" }; return c }())
        return page(style, height: 1500)
    }

    /// The library as it is on this Mac (DIRECTION_TECHNIQUES_PATH, DIRECTION_SOUNDS_PATH, DIRECTION_IMAGES_PATH
    /// and DIRECTION_CACHE_DIR point it at scratch copies in a snapshot run): Grid flash chosen, or the first sound or image.
    private static func library(kind: String? = nil) -> SnapshotScene {
        let library = LibraryModel.shared
        library.preview = false; library.load()
        let chosen = kind == nil ? library.entries.first { $0.name == "Grid flash" } : library.entries.first { LibraryModel.shown($0, kind: kind) }
        return SnapshotScene(size: CGSize(width: 1180, height: 760), LibraryWindowPreview(chosen: chosen?.id, kind: kind))
    }

    /// A note that names a sound, an image, a take, a scene and a transition: in the field as it's written, as the
    /// note reads after, and as chips under a brief field. The library as on this Mac (scratch folders in a snapshot run).
    private static func mentionNote() -> SnapshotScene {
        let library = LibraryModel.shared
        library.preview = false; library.load()
        let footage = [FootageName(id: "scene:s2", name: "Scene 2", kind: .scene, summary: "The desk", sceneID: "s2"),
                       FootageName(id: "take:a", name: "2A Take 3", kind: .take, summary: "Circled", sceneID: "s2", setupCode: "2A", assetID: "a")]
        let words = "Put @Felt piano bed under the open, out on @2A Take 3. @Channel mark in the corner from @Scene 2 on, and a @Whip into the talking head."
        return SnapshotScene(size: CGSize(width: 460, height: 330), VStack(alignment: .leading, spacing: 14) {
            NoteField(text: .constant(words), placeholder: "", label: "Note", footage: footage, minHeight: 90)
            Mentions.text(words, footage: footage).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).lineHeight(13, 1.45).fixedSize(horizontal: false, vertical: true)
            MentionChips(text: words, footage: footage)
        }
        .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Gate.Surface.ground))
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

    /// Settings › Styles with the style open as its page, drawn whole.
    private static func page(_ s: Style, height: CGFloat) -> SnapshotScene {
        SettingsKey.register()
        return settingsPage(SettingsPage(id: "style:" + s.id, title: s.name) { StylePage(draft: .init(s), folder: StyleSamples.folder) }, tab: .styles, height: height)
    }

    private static func settingsPage(_ page: SettingsPage, tab: SettingsTab, height: CGFloat) -> SnapshotScene {
        SnapshotScene(size: CGSize(width: Gate.Size.settingsWidth, height: height),
                      SettingsView(initialTab: tab, preview: true, page: page).frame(width: Gate.Size.settingsWidth, height: height, alignment: .top).clipped().background(Gate.Surface.ground))
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
