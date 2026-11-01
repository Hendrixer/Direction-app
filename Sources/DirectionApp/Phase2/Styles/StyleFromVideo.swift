import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DirectionCore
import DirectionMedia

// Styles from a video (styles.md › From a video): the director gives a video or a few they like and says what
// they like about them; Direction fetches each, measures what it can count, and the editor makes the style
// from that, the words and the contact sheets. The downloads go once the style is saved. A video dropped in
// the brief is studied the same way, as inspiration for that film (styles.md › In the brief).

/// A video for a style: a link to fetch, or a file on this Mac.
struct StyleVideo: Hashable, Identifiable {
    var id = UUID()
    var link = ""
    var file: URL?
    var ready: Bool { file != nil || ReferenceVideo.isLink(link) }
    var name: String { file?.deletingPathExtension().lastPathComponent ?? link.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum ReferenceVideo {
    /// Sites yt-dlp fetches videos from that people send as inspiration.
    static let sites = ["youtube.com", "youtu.be", "vimeo.com", "tiktok.com", "instagram.com", "loom.com", "x.com", "twitter.com"]

    static func isLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil else { return false }
        return true
    }
    /// A reference Direction can study: a movie on this Mac, or a link to a video site.
    static func isVideo(_ path: String) -> Bool {
        if path.contains("://") {
            guard let host = URL(string: path)?.host()?.lowercased() else { return false }
            return sites.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        return UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)?.conforms(to: .movie) == true
    }
    /// Where a brief reference's study is kept: in the film, beside what the editor writes.
    static func folder(_ id: String, film: URL) -> URL { VideoStudy.referenceFolder(id, film: film) }
    static func study(_ r: BriefReference, film: URL) -> VideoStudy? { VideoStudy.read(in: folder(r.id, film: film)) }

    /// What the page said about a downloaded video: its title and who made it.
    static func about(_ folder: URL) -> (title: String?, by: String?) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("video.info.json")), let info = try? JSONDecoder().decode(JSONValue.self, from: data) else { return (nil, nil) }
        return (info["title"].string, info["channel"].string ?? info["uploader"].string)
    }

    /// Fetches a link into `folder`, or puts a file there by a link to it (the original stays where it is),
    /// so the editor can look at any moment of either. True when it was downloaded.
    static func fetch(_ video: StyleVideo, into folder: URL) async throws -> (URL, downloaded: Bool) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let file = video.file {
            let here = folder.appendingPathComponent("video." + (file.pathExtension.isEmpty ? "mov" : file.pathExtension))
            try FileManager.default.createSymbolicLink(at: here, withDestinationURL: file)
            return (here, false)
        }
        guard let url = URL(string: video.link.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw DirectionError("bad_link", "That isn\u{2019}t a link to a video.") }
        return (try await TutorialStudy.download(url, to: folder), true)
    }

    /// The video and the frames taken from it; what was read from it stays.
    static func removeVideo(in folder: URL) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where (name.hasPrefix("video.") && name != "video.info.json") || name == "frames" || name.hasSuffix(".part") {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Studies of references the brief no longer has.
    static func cleanUp(_ brief: Brief, film: URL) {
        let root = film.appendingPathComponent("Editor/References", isDirectory: true), keep = Set(brief.references.map(\.id))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }
}

extension FilmModel {
    /// A video in the brief is studied once, in the background; a downloaded one keeps what was read from it, not the video.
    func studyReference(_ r: BriefReference) {
        guard !isPreview, let store, let runtime, let path = r.path, ReferenceVideo.isVideo(path), !studyingReferences.contains(r.id) else { return }
        let folder = ReferenceVideo.folder(r.id, film: store.url)
        guard VideoStudy.read(in: folder) == nil else { return }
        studyingReferences.insert(r.id); referenceProblems[r.id] = nil
        let video = path.contains("://") ? StyleVideo(link: path) : StyleVideo(file: URL(fileURLWithPath: path))
        Task { @MainActor in
            defer { studyingReferences.remove(r.id) }
            do {
                let (file, downloaded) = try await ReferenceVideo.fetch(video, into: folder)
                let about = ReferenceVideo.about(folder)
                _ = try await VideoStudying.study(video: file, folder: folder, cacheDirectory: runtime.cacheDirectory, title: about.title ?? r.title, by: about.by, link: downloaded ? path : URL(fileURLWithPath: path).lastPathComponent)
                ReferenceVideo.removeVideo(in: folder)
            } catch {
                ReferenceVideo.removeVideo(in: folder)
                referenceProblems[r.id] = (error as? DirectionError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Fetches and studies each video in its own folder, then starts the editor on the style. Nothing half
    /// done stays if a video can't be had; once the style is saved, the folders go (EditorRunsModel).
    func makeStyle(from videos: [StyleVideo], ask: String) {
        guard !isPreview, let store, let runtime, !videos.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let one = videos.count == 1
        learning = one ? "Getting the video ready" : "Getting the videos ready"
        toast = Toast(title: learning!, detail: "Direction is fetching \(one ? "it" : "them") and studying \(one ? "it" : "each one") on this Mac. The editor starts when \(one ? "it\u{2019}s" : "they\u{2019}re") ready.", editor: true)
        Task { @MainActor in
            var folders: [URL] = []
            do {
                for (i, v) in videos.enumerated() {
                    let folder = store.url.appendingPathComponent("Editor/Learn/\(stamp)-\(i + 1)", isDirectory: true)
                    folders.append(folder)
                    learning = v.file == nil ? (one ? "Downloading the video" : "Downloading video \(i + 1) of \(videos.count)") : (one ? "Studying the video" : "Studying video \(i + 1) of \(videos.count)")
                    let (file, downloaded) = try await ReferenceVideo.fetch(v, into: folder)
                    learning = one ? "Studying the video" : "Studying video \(i + 1) of \(videos.count)"
                    let about = ReferenceVideo.about(folder)
                    _ = try await VideoStudying.study(video: file, folder: folder, cacheDirectory: runtime.cacheDirectory, title: about.title ?? v.name, by: about.by, link: downloaded ? v.link.trimmingCharacters(in: .whitespacesAndNewlines) : v.file?.lastPathComponent)
                }
                learning = nil
                let request = ask.isEmpty ? "Make a style from \(one ? "this video" : "these videos"): how \(one ? "it\u{2019}s" : "they\u{2019}re") paced, framed, captioned and how \(one ? "it sounds" : "they sound")." : ask
                if runs.makeStyle(self, request: request, fromFilm: false, studies: folders) {
                    toast = Toast(title: "Making a style", detail: "The editor is watching \(one ? "the video" : "the videos") now. The style goes in your styles when it\u{2019}s done, and the downloads go.", editor: true)
                } else {
                    error = "Direction doesn\u{2019}t start the editor here. Ask your own session to make a style from the studies in \(folders.map(\.path).joined(separator: ", ")) (the make-style skill)."
                }
            } catch {
                learning = nil
                for f in folders { try? FileManager.default.removeItem(at: f) }
                self.error = (error as? DirectionError)?.message ?? error.localizedDescription
            }
        }
    }
}

/// New Style from a Video: up to three videos (a link or a file each) and what you like about them.
struct StyleFromVideoSheet: View {
    var model: FilmModel
    var done: () -> Void
    @State private var videos: [StyleVideo]
    @State private var ask: String

    init(model: FilmModel, videos: [StyleVideo] = [], ask: String = "", done: @escaping () -> Void) {
        self.model = model; self.done = done
        _videos = State(initialValue: videos.isEmpty ? [StyleVideo()] : videos)
        _ask = State(initialValue: ask)
    }

    private var chosen: [StyleVideo] { videos.filter(\.ready) }
    private var ready: Bool { !chosen.isEmpty && videos.allSatisfy { $0.ready || ($0.link.isEmpty && $0.file == nil) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Make a style from a video").font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                Text("Give the editor a video you\u{2019}d like yours to feel like. Direction measures how it\u{2019}s cut, framed, captioned and mixed; the editor turns that into a style you can use on every film like it. Two or three videos by the same person make a truer style.")
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(videos.count == 1 ? "The video" : "The videos").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    ForEach($videos) { $v in row($v) }
                    if videos.count < 3 {
                        Button { videos.append(StyleVideo()) } label: { Label("Add Another Video", systemImage: "plus") }.buttonStyle(.gate(.ghost, .small))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What you like about it").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    GateTextArea(text: $ask, placeholder: "How fast it moves, the yellow captions three words at a time, the punch-in on every joke.", minHeight: 64)
                }
                Text("Videos from links are downloaded to study them. Everything fetched is removed once the style is saved; the style keeps the link, what was measured and a few stills.")
                    .font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: done).buttonStyle(.gate).keyboardShortcut(.cancelAction)
                Button("Make Style") {
                    model.makeStyle(from: chosen, ask: ask.trimmingCharacters(in: .whitespacesAndNewlines))
                    done()
                }
                .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command).disabled(!ready || model.learning != nil)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(alignment: .top) { SystemHairline() }
        }
        .frame(width: 540)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func row(_ v: Binding<StyleVideo>) -> some View {
        HStack(spacing: 8) {
            if let file = v.wrappedValue.file {
                Label(file.lastPathComponent, systemImage: "film").font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: Gate.Size.control, alignment: .leading).background(GateFieldBackground())
            } else {
                TextField("", text: v.link).gateField(focused: false).startPlaceholder("https://www.youtube.com/watch?v=\u{2026}", shown: v.wrappedValue.link.isEmpty)
                Button("Choose File\u{2026}") { choose(v) }.buttonStyle(.gate)
            }
            if videos.count > 1 || v.wrappedValue.file != nil {
                Button { remove(v.wrappedValue.id) } label: { Image(systemName: "xmark") }.buttonStyle(.gate(.ghost, .small, icon: true)).help("Remove")
            }
        }
    }

    private func remove(_ id: UUID) {
        if videos.count > 1 { videos.removeAll { $0.id == id } } else { videos = [StyleVideo()] }
    }

    private func choose(_ v: Binding<StyleVideo>) {
        let panel = NSOpenPanel(); panel.title = "Choose a video to learn from"; panel.prompt = "Choose"
        panel.allowedContentTypes = [.movie]; panel.canChooseDirectories = false
        if panel.runModal() == .OK { v.wrappedValue.file = panel.url }
    }
}
