import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DirectionCore
import DirectionMedia

// Learn a technique (techniques.md › Learning one): the director gives a link or a video file and says what
// to take from it; Direction gets the video ready (downloaded, its words, a contact sheet every two seconds)
// in the film's editor folder, and the editor learns it into the Techniques folder.

extension FilmModel {
    func learnTechnique(link: String, file: URL?, ask: String) {
        guard !isPreview, let store, let runtime else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = store.url.appendingPathComponent("Editor/Learn").appendingPathComponent(stamp, isDirectory: true)
        learning = file == nil ? "Downloading the video" : "Reading the video"
        toast = Toast(title: "Getting the video ready", detail: file == nil ? "Downloading it and reading its words. The editor starts when it\u{2019}s ready." : "Reading its words and frames. The editor starts when it\u{2019}s ready.", editor: true)
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let video: URL
                if let file {
                    // A copy beside what Direction reads from it, so the editor can look at any moment.
                    video = folder.appendingPathComponent("video." + (file.pathExtension.isEmpty ? "mov" : file.pathExtension))
                    try FileManager.default.copyItem(at: file, to: video)
                } else {
                    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw DirectionError("bad_link", "That isn\u{2019}t a link to a video.") }
                    video = try await TutorialStudy.download(url, to: folder)
                }
                learning = "Reading the video"
                _ = try await TutorialStudy.prepare(video: video, folder: folder, cacheDirectory: runtime.cacheDirectory)
                learning = nil
                if runs.learnTechnique(self, request: ask, folder: folder, video: video) {
                    toast = Toast(title: "Learning a technique", detail: "The editor is watching the video now. It goes in your techniques when it\u{2019}s done.", editor: true)
                } else {
                    error = "Direction doesn\u{2019}t start the editor here. Ask your own session to learn the technique in \(folder.path) (the learn-technique skill)."
                }
            } catch {
                learning = nil
                self.error = (error as? DirectionError)?.message ?? error.localizedDescription
            }
        }
    }
}

/// A link or a file, and what to take from it.
struct LearnTechniqueSheet: View {
    @Bindable var model: FilmModel
    @State private var link = ""
    @State private var file: URL?
    @State private var ask = ""

    private var ready: Bool { (file != nil || link.lowercased().hasPrefix("http")) && !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Learn a technique").font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                Text("Give the editor a video that teaches a transition, an effect or a move, in any editing app. It learns how it\u{2019}s done, rebuilds it in Direction, and keeps it in your techniques for every film.")
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("The video").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    HStack(spacing: 8) {
                        if let file {
                            Label(file.lastPathComponent, systemImage: "film").font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: Gate.Size.control, alignment: .leading).background(GateFieldBackground())
                            Button("Remove") { self.file = nil }.buttonStyle(.gate(.ghost, .small))
                        } else {
                            TextField("", text: $link).gateField(focused: false).startPlaceholder("https://www.youtube.com/watch?v=\u{2026}", shown: link.isEmpty)
                            Button("Choose File\u{2026}") { choose() }.buttonStyle(.gate)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to take from it").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    GateTextArea(text: $ask, placeholder: "The grid transition it opens with, and the clicks under it.", minHeight: 64)
                }
                Text(file == nil ? "Direction downloads the video to learn from it. It stays in this film\u{2019}s editor folder; nothing from it goes into your films." : "It stays in this film\u{2019}s editor folder; nothing from it goes into your films.")
                    .font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.sheet = nil }.buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button("Learn") {
                    model.learnTechnique(link: link, file: file, ask: ask.trimmingCharacters(in: .whitespacesAndNewlines))
                    model.sheet = nil
                }
                .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command).disabled(!ready)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { SystemHairline() }
        }
        .frame(width: 520)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
    }

    private func choose() {
        let panel = NSOpenPanel(); panel.title = "Choose a video to learn from"; panel.prompt = "Choose"
        panel.allowedContentTypes = [.movie]; panel.canChooseDirectories = false
        if panel.runModal() == .OK { file = panel.url }
    }
}

/// Settings › Styles › Techniques: what's in the library and where it came from.
struct TechniquesGroup: View {
    var preview = false
    @State private var techniques: [Technique] = []

    var body: some View {
        SettingsGroup(label: "Techniques", note: AnyView(SettingsNote("Ways of doing one thing the same way every time, often learned from a tutorial: Film \u{203A} Learn a Technique\u{2026} gives the editor a video to learn from. A style can name them for its moments, and so can a note."))) {
            if techniques.isEmpty {
                SettingsRow(label: "No techniques yet", detail: "Learn one from a video with Film \u{203A} Learn a Technique\u{2026}.", first: true) { EmptyView() }
            }
            ForEach(Array(techniques.enumerated()), id: \.element.id) { i, t in
                SettingsRow(label: t.name, detail: [t.summary, Self.line(t)].filter { !$0.isEmpty }.joined(separator: "\n"), first: i == 0, minHeight: 56) {
                    Button { if !preview { NSWorkspace.shared.activateFileViewerSelecting([t.url]) } } label: { Image(systemName: "folder") }
                        .buttonStyle(.gate(.normal, .regular, icon: true)).help("Show in Finder")
                }
            }
        }
        .task { techniques = preview ? TechniqueSamples.techniques : TechniqueLibrary.list(in: SharedSettings.techniquesFolder) }
    }

    /// "Transition · 10 variants · from “GRID TRANSITION PLUGIN” by Ryan Nangle".
    static func line(_ t: Technique) -> String {
        let n = t.variants.count
        return [t.kind.capitalized, n == 0 ? nil : "\(n) variant\(n == 1 ? "" : "s")", t.source["title"].string.map { "from \u{201C}\($0)\u{201D}" + (t.source["author"].string.map { " by \($0)" } ?? "") }].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

/// Samples for snapshots and previews, so nothing reads the director's own folder there.
enum TechniqueSamples {
    static var techniques: [Technique] {
        let folder = URL(fileURLWithPath: "/tmp/direction-sample-techniques", isDirectory: true)
        return [
            Technique(id: "grid-flash", url: folder.appendingPathComponent("grid-flash"), tokens: .object([
                "name": .string("Grid flash"), "kind": .string("transition"), "summary": .string("The frame splits into squares and each one flips to the next shot under a flash of light."),
                "variants": .array((["Big", "Large", "Medium", "Small", "Fine"]).map { .object(["name": .string($0)]) }),
                "source": .object(["title": .string("Grid Transition Plugin"), "author": .string("Ryan Nangle")]),
            ])),
            Technique(id: "pixel-grid", url: folder.appendingPathComponent("pixel-grid"), tokens: .object([
                "name": .string("Pixel grid"), "kind": .string("effect"), "summary": .string("A second shot shows only in the squares its subject fills, over the first."),
                "variants": .array((["Big squares", "Fine squares", "No lines"]).map { .object(["name": .string($0)]) }),
                "source": .object(["title": .string("Pixel Grid Effect Tutorial"), "author": .string("Ryan Nangle")]),
            ])),
        ]
    }
}
