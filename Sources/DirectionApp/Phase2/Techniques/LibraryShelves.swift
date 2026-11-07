import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import DirectionCore
import DirectionMedia

// The director's sounds and images in the Library window (library.md): brought in by dropping or choosing
// files, measured in the background, played and read here, and kept for every film.

extension LibraryModel {
    func shelf(_ item: ShelfItem) -> MediaLibrary { item.kind == .image ? .images : .sounds }

    /// Listens to and looks at what hasn't been measured since it changed, one at a time, in the background.
    func measure() {
        guard !preview, !measuring else { return }
        let waiting = MediaLibrary.shelves.flatMap { shelf in shelf.items().filter(shelf.needsMeasuring).map { (shelf, $0) } }
        guard !waiting.isEmpty else { return }
        measuring = true
        Task {
            defer { measuring = false }
            for (shelf, item) in waiting {
                do { replace(try await LibraryMeasuring.measure(item, in: shelf, cacheDirectory: DirectionPaths.caches.appendingPathComponent("Library"))) }
                catch { DirectionLog.warning("\(item.file) wasn\u{2019}t measured: \(error.localizedDescription)", "library") }
            }
            // Heard for their lengths, a song's stems and full mix are put together (library.md › Songs in parts), and
            // the song's beats, bars and changes are heard once for all its parts.
            do { if try !MediaLibrary.sounds.groupStems().isEmpty { load() } }
            catch { DirectionLog.warning("Songs in parts weren\u{2019}t put together: \(error.localizedDescription)", "library") }
            if !(await LibraryMeasuring.shareSongGrids(cacheDirectory: DirectionPaths.caches.appendingPathComponent("Library"))).isEmpty { load() }
        }
    }

    /// The entry the Library shows for one: a song for any of its parts.
    func whole(_ e: LibraryEntry) -> LibraryEntry { e.partOf.flatMap { song in entries.first { $0.id == "song:" + song } } ?? e }

    /// Files dropped or chosen go on their shelf, sounds to Sounds and pictures to Images; anything else is
    /// named in `problem`. A folder (a song's stems, unzipped) brings the sounds and pictures in it. Returns
    /// the first one's entry, to show it.
    @discardableResult
    func add(_ urls: [URL]) -> String? {
        var first: String?, refused: [String] = []
        for url in urls.flatMap(Self.inside) {
            guard let kind = MediaLibrary.shelf(for: url) else { refused.append(url.lastPathComponent); continue }
            do {
                let item = try (kind == .sounds ? MediaLibrary.sounds : MediaLibrary.images).add(url)
                first = first ?? LibraryCatalog.entry(item).id
            } catch { problem = "\(url.lastPathComponent): \(error.localizedDescription)" }
        }
        if !refused.isEmpty { problem = "\(refused.joined(separator: ", ")) \(refused.count == 1 ? "isn\u{2019}t" : "aren\u{2019}t") a sound or an image." }
        load(); measure()
        return first
    }

    /// A folder's sounds and pictures, in name order; a file is itself.
    static func inside(_ url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return [url] }
        let all = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])?.allObjects as? [URL] ?? []
        return all.filter { MediaLibrary.shelf(for: $0) != nil }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func chooseAndAdd() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Add Sounds or Images"; panel.prompt = "Add"
        panel.allowedContentTypes = [.audio, .image]; panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return add(panel.urls)
    }

    /// Changes one item and shows it changed, without reading the whole library again.
    func update(_ item: ShelfItem, _ change: @escaping (inout ShelfItem) -> Void) {
        do { replace(try shelf(item).update(item.file, change)) } catch { problem = error.localizedDescription }
    }

    /// Returns the renamed item's entry id, or nil when it kept its name.
    func rename(_ item: ShelfItem, to name: String) -> String? {
        do {
            let renamed = try shelf(item).rename(item, to: name)
            guard renamed.file != item.file else { return nil }
            if playing == item.file { stop() }
            load()
            return LibraryCatalog.entry(renamed).id
        } catch { problem = error.localizedDescription; return nil }
    }

    func remove(_ item: ShelfItem) {
        if playing == item.file { stop() }
        do { try shelf(item).remove(item); images[item.file] = nil; load() } catch { problem = error.localizedDescription }
    }

    private func replace(_ item: ShelfItem) {
        if let song = item.song, !song.isEmpty { return replace(song: song) }
        let entry = LibraryCatalog.entry(item)
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { replaceEntry(at: i, with: entry) } else { load() }
    }
    /// A song and its parts as they are now on the shelf, without reading the whole library again.
    private func replace(song name: String) {
        guard let song = MediaLibrary.sounds.songs().first(where: { $0.name == name }) else { return load() }
        for e in [LibraryCatalog.entry(song)] + song.parts.map({ LibraryCatalog.entry($0, of: song) }) {
            guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return load() }
            replaceEntry(at: i, with: e)
        }
    }

    // MARK: Songs in parts

    /// Changes every part of a song: what the director wrote about it is the song's.
    func update(_ song: Song, _ change: @escaping (inout ShelfItem) -> Void) {
        do { for p in song.parts { try MediaLibrary.sounds.update(p.file, change) }; replace(song: song.name) } catch { problem = error.localizedDescription }
    }
    /// Returns the renamed song's entry id, or nil when it kept its name.
    func rename(_ song: Song, to name: String) -> String? {
        do {
            try MediaLibrary.sounds.renameSong(song, to: name)
            load()
            return entries.first { $0.parts != nil && $0.name.lowercased() == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }?.id
        } catch { problem = error.localizedDescription; return nil }
    }
    /// Takes a song apart into sounds on their own. Returns the first's entry id.
    func takeApart(_ song: Song) -> String? {
        do { try MediaLibrary.sounds.partSong(song); load(); return "sound:" + song.lead.file } catch { problem = error.localizedDescription; return nil }
    }
    /// Makes a sound a part of a song. Returns the song's entry id.
    func join(_ item: ShelfItem, song: String, part: String) -> String? {
        do {
            let joined = try MediaLibrary.sounds.setSong(item.file, song: song, part: part)
            load()
            return joined.song.map { "song:" + $0 }
        } catch { problem = error.localizedDescription; return nil }
    }
    func remove(_ song: Song) {
        if song.parts.contains(where: { $0.file == playing }) { stop() }
        do { for p in song.parts { try MediaLibrary.sounds.remove(p) }; load() } catch { problem = error.localizedDescription }
    }

    // MARK: Hearing and seeing

    func play(_ item: ShelfItem) {
        stop()
        do {
            player = try LibraryPlayer(url: shelf(item).url(item)) { [weak self] in Task { @MainActor in self?.playing = nil; self?.player = nil } }
            player?.audio.play(); playing = item.file
        } catch { problem = "\(item.name) can\u{2019}t be played: \(error.localizedDescription)" }
    }
    func stop() { player?.audio.stop(); player = nil; playing = nil }
    /// How far through the playing sound is, 0–1.
    func progress(_ item: ShelfItem) -> Double? {
        guard playing == item.file, let a = player?.audio, a.duration > 0 else { return nil }
        return a.currentTime / a.duration
    }

    func image(_ item: ShelfItem) -> NSImage? {
        let key = "\(item.file) \(item.modifiedAt)"
        if let had = images[key] { return had }
        guard let image = NSImage(contentsOf: shelf(item).url(item)) else { return nil }
        images[key] = image
        return image
    }
}

/// A sound playing in the library, saying when it's done.
final class LibraryPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let audio: AVAudioPlayer
    private let done: @Sendable () -> Void
    init(url: URL, done: @escaping @Sendable () -> Void) throws {
        audio = try AVAudioPlayer(contentsOf: url); self.done = done
        super.init()
        audio.delegate = self
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { done() }
}

/// A sound's level over its length, a bar to a stretch; what's been played is brighter.
struct LibraryWaveform: View {
    var levels: [Float]
    var progress: Double?
    var body: some View {
        Canvas { context, size in
            let n = max(1, levels.count), step = size.width / CGFloat(n)
            for (i, level) in levels.enumerated() {
                let h = max(2, CGFloat(level) * size.height)
                let bar = CGRect(x: CGFloat(i) * step + step * 0.2, y: (size.height - h) / 2, width: max(1, step * 0.6), height: h)
                let played = progress.map { Double(i) / Double(n) < $0 } ?? false
                context.fill(Path(roundedRect: bar, cornerRadius: min(1.5, step * 0.3)), with: .color(played ? Gate.Text.primary : Gate.Text.tertiary))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A sound or image at 16:9: the picture, or the waveform with a play button; a quiet wait while it's being listened to.
struct LibraryItemPreview: View {
    var item: ShelfItem
    var library: LibraryModel
    var large = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Gate.Surface.sunken)
            if item.kind == .image {
                if let image = library.image(item) { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).clearOfGrain().padding(large ? 18 : 12) }
                else { LibraryIcon(name: "photo", size: 30) }
            } else if let levels = item.measured?.levels {
                TimelineView(.animation(paused: library.playing != item.file)) { _ in
                    LibraryWaveform(levels: levels, progress: library.progress(item))
                }
                .padding(.horizontal, 14).padding(.vertical, large ? 26 : 20)
            } else {
                VStack(spacing: 6) {
                    LibraryIcon(name: item.kind == .music ? "music.note" : "waveform", size: 30)
                    if !library.preview { Text("Listening").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled) }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if item.isSound {
                let on = library.playing == item.file
                Button { on ? library.stop() : library.play(item) } label: { Image(systemName: on ? "pause.fill" : "play.fill") }
                    .buttonStyle(.gate(.normal, .small, icon: true)).padding(8)
                    .help(on ? "Stop" : "Play").accessibilityLabel(on ? "Stop \(item.name)" : "Play \(item.name)")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }
}

/// A sound or image at length: hear or see it, what Direction measured, its kind, the director's words about
/// when to use it and where it's from, and its name for "@".
struct LibraryItemDetail: View {
    var entry: LibraryEntry
    var item: ShelfItem
    var library: LibraryModel
    /// The entry to show after a rename.
    var chose: (String) -> Void
    @State private var name = ""
    @State private var note = ""
    @State private var source = ""
    @State private var song = ""
    @State private var part = ""
    @State private var trashing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LibraryItemPreview(item: item, library: library, large: true)
                HStack(spacing: 10) {
                    LibraryIcon(name: entry.icon, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: $name).textFieldStyle(.plain).font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                            .onSubmit(rename).accessibilityLabel("Name")
                        Text(item.kind == .image ? "An image you keep" : "A sound you keep").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    }
                }
                if item.isSound {
                    GateSegmented(options: [(ShelfItem.Kind.music, "Music"), (.effect, "Sound effect")], selection: Binding(get: { item.kind }, set: { k in library.update(item) { $0.kind = k } }))
                }
                Text(item.summary).font(.system(size: 13)).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                field("When to use it") {
                    GateTextArea(text: $note, placeholder: item.kind == .image ? "In the corner from the first chapter on" : "Under the opening, out on the first cut", minHeight: 56)
                }
                field("Where it\u{2019}s from") {
                    TextField("", text: $source).textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                        .startPlaceholder(item.kind == .image ? "Who made it, its license, a link" : "A music library and its license, a link", shown: source.isEmpty, inset: .init())
                        .padding(.horizontal, 11).frame(height: 28).background(GateFieldBackground())
                }
                if item.kind == .music {
                    // Stems Direction didn't put together by their names: the director names the song and the part.
                    field("Part of a song") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                TextField("", text: $song).textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                                    .startPlaceholder("Song", shown: song.isEmpty, inset: .init())
                                    .padding(.horizontal, 11).frame(height: 28).background(GateFieldBackground()).accessibilityLabel("Song")
                                TextField("", text: $part).textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                                    .startPlaceholder("Drums", shown: part.isEmpty, inset: .init())
                                    .padding(.horizontal, 11).frame(width: 104, height: 28).background(GateFieldBackground()).accessibilityLabel("Part")
                            }
                            .onSubmit(join)
                            Text("Give each stem the song\u{2019}s name and its part, and they play in time together.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("In a note or the brief, type @ and pick it, or write").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    Text("@\(item.name)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Voice.director).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.shelf(item).url(item)]) }.buttonStyle(.gate(.ghost, .small))
                    Spacer(minLength: 0)
                    Button("Move to Trash\u{2026}") { trashing = true }.buttonStyle(.gate(.ghostDanger, .small))
                }
            }
            .padding(18)
        }
        .onAppear(perform: fill)
        .onChange(of: item.file) { _, _ in fill() }
        .onChange(of: note) { _, v in if v != (item.note ?? "") { library.update(item) { $0.note = v.isEmpty ? nil : v } } }
        .onChange(of: source) { _, v in if v != (item.source ?? "") { library.update(item) { $0.source = v.isEmpty ? nil : v } } }
        .alert("Move \(item.name) to the Trash?", isPresented: $trashing) {
            Button("Move to Trash", role: .destructive) { library.remove(item) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Films that use it keep their own copy.") }
    }

    private func fill() { name = item.name; note = item.note ?? ""; source = item.source ?? ""; song = ""; part = "" }
    private func rename() {
        if let id = library.rename(item, to: name) { chose(id) } else { name = item.name }
    }
    private func join() {
        guard !song.trimmingCharacters(in: .whitespaces).isEmpty, !part.trimmingCharacters(in: .whitespaces).isEmpty, let id = library.join(item, song: song, part: part) else { return }
        chose(id)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            content()
        }
    }
}

/// A song kept in parts (library.md › Songs in parts): hear it whole or a part at a time, what Direction measured,
/// the director's words about when to use it and where it's from, and its names for "@".
struct LibrarySongDetail: View {
    var entry: LibraryEntry
    var song: Song
    var library: LibraryModel
    /// The entry to show after a rename, or after it's taken apart.
    var chose: (String) -> Void
    @State private var name = ""
    @State private var note = ""
    @State private var source = ""
    @State private var trashing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LibraryItemPreview(item: song.lead, library: library, large: true)
                HStack(spacing: 10) {
                    LibraryIcon(name: entry.icon, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: $name).textFieldStyle(.plain).font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                            .onSubmit(rename).accessibilityLabel("Name")
                        Text("A song you keep in parts").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    }
                }
                Text(song.summary).font(.system(size: 13)).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                field("Parts") {
                    VStack(spacing: 2) { ForEach(song.parts) { p in LibraryPartRow(item: p, song: song, library: library) } }
                        .padding(4).background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Gate.Surface.sunken))
                }
                field("When to use it") {
                    GateTextArea(text: $note, placeholder: "0:00 soft intro \u{00B7} 0:32 drums come in \u{00B7} 1:04 the big part", minHeight: 56)
                }
                field("Where it\u{2019}s from") {
                    TextField("", text: $source).textFieldStyle(.plain).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                        .startPlaceholder("A music library and its license, a link", shown: source.isEmpty, inset: .init())
                        .padding(.horizontal, 11).frame(height: 28).background(GateFieldBackground())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("In a note or the brief, type @ and pick it, or write").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    Text("@\(song.name)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Voice.director).textSelection(.enabled)
                    if let stem = song.parts.first(where: { $0.part != Stems.fullMix })?.part {
                        Text("or one part, like @\(Song.name(song.name, part: stem))").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).textSelection(.enabled)
                    }
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(song.parts.map { MediaLibrary.sounds.url($0) }) }.buttonStyle(.gate(.ghost, .small))
                    Button("Take Apart") { if let id = library.takeApart(song) { chose(id) } }.buttonStyle(.gate(.ghost, .small))
                        .help("Keep each part as a sound on its own.")
                    Spacer(minLength: 0)
                    Button("Move to Trash\u{2026}") { trashing = true }.buttonStyle(.gate(.ghostDanger, .small))
                }
            }
            .padding(18)
        }
        .onAppear(perform: fill)
        .onChange(of: song.name) { _, _ in fill() }
        .onChange(of: note) { _, v in if v != (song.note ?? "") { library.update(song) { $0.note = v.isEmpty ? nil : v } } }
        .onChange(of: source) { _, v in if v != (song.source ?? "") { library.update(song) { $0.source = v.isEmpty ? nil : v } } }
        .alert("Move \(song.name) to the Trash?", isPresented: $trashing) {
            Button("Move to Trash", role: .destructive) { library.remove(song) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All \(song.parts.count) parts go. Films that use it keep their own copies.") }
    }

    private func fill() { name = song.name; note = song.note ?? ""; source = song.source ?? "" }
    private func rename() {
        if let id = library.rename(song, to: name) { chose(id) } else { name = song.name }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            content()
        }
    }
}

/// One part of a song: play it on its own, and see where in the song it plays.
struct LibraryPartRow: View {
    var item: ShelfItem
    var song: Song
    var library: LibraryModel
    var body: some View {
        let on = library.playing == item.file, what = item.part ?? item.name
        HStack(spacing: 8) {
            Button { on ? library.stop() : library.play(item) } label: { Image(systemName: on ? "pause.fill" : "play.fill") }
                .buttonStyle(.gate(.ghost, .small, icon: true))
                .help(on ? "Stop" : "Play the \(what.lowercased())").accessibilityLabel(on ? "Stop \(what)" : "Play \(what)")
            Text(what).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.primary).lineLimit(1).frame(width: 84, alignment: .leading)
            if let levels = item.measured?.levels {
                TimelineView(.animation(paused: !on)) { _ in LibraryWaveform(levels: levels, progress: library.progress(item)) }.frame(height: 16)
            } else { Spacer(minLength: 0) }
            if let seconds = item.measured?.seconds {
                Text(PlainTime.text(seconds.rounded())).font(Gate.Font.caption).monospacedDigit().foregroundStyle(Gate.Text.tertiary)
            }
        }
        .padding(.horizontal, 4).frame(height: 30)
        .help("@\(Song.name(song.name, part: what)) \u{00B7} \(item.file)")
    }
}
