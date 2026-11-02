import SwiftUI
import AppKit
import DirectionCore

/// Settings › Library: the director's sounds, songs, images and techniques, kept for every film, and where each
/// lives. The Library window shows and plays them.
struct LibraryPane: View {
    var preview = false
    @Environment(\.openWindow) private var openWindow
    @State private var counts = (songs: 0, sounds: 0, images: 0)

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Library", note: AnyView(SettingsNote("Kept outside any film, for every film. A note names one with @ and the editor brings that film its own copy, so a film keeps playing whatever happens here."))) {
                SettingsRow(label: "Library", detail: summary, first: true, minHeight: 56) {
                    Button("Open Library") { if !preview { openWindow(id: "library") } }.buttonStyle(.gate)
                }
            }
            TechniquesGroup(preview: preview)
            SettingsGroup(label: "Where they live") {
                folder("Sounds folder", detail: "Music, songs in parts, stings and sound effects. Put files in from the Finder, or drop them on the Library.", url: MediaLibrary.sounds.folder, sample: "Sounds", first: true)
                folder("Images folder", detail: "Logos, stills and overlays.", url: MediaLibrary.images.folder, sample: "Images")
                folder("Techniques folder", detail: "One folder for each technique. Copy one to share it; drop one in to use it.", url: SharedSettings.techniquesFolder, sample: "Techniques")
            }
        }
        .task { load() }
    }

    /// "3 songs · 12 sounds · 4 images, and every transition, move and effect."
    private var summary: String {
        let parts = [(counts.songs, "song"), (counts.sounds, "sound"), (counts.images, "image")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        let held = parts.isEmpty ? "No sounds or images yet" : parts.joined(separator: " \u{00B7} ")
        return held + ", and every transition, move and effect, with a preview of each."
    }

    private func load() {
        if preview { counts = (2, 9, 3); return }
        let sounds = MediaLibrary.sounds
        counts = (sounds.songs().count, sounds.items().filter { !$0.isPart }.count, MediaLibrary.images.items().count)
    }

    private func folder(_ label: String, detail: String, url: URL, sample: String, first: Bool = false) -> some View {
        let shown = preview ? "~/Movies/Direction/\(sample)" : (url.path as NSString).abbreviatingWithTildeInPath
        return SettingsRow(label: label, detail: detail, first: first, minHeight: 56) {
            Text(shown).font(.system(size: 12)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 10).frame(width: 230, height: Gate.Size.control, alignment: .leading).background(GateFieldBackground()).help(url.path)
            Button("Show in Finder") {
                guard !preview else { return }
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.gate)
        }
    }
}
