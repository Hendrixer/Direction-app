import SwiftUI
import AppKit
import AVFoundation
import DirectionCore
import DirectionMedia
import DirectionTools

// The library (techniques.md › The library): every transition, move and effect the director can name, each
// with its own icon and a preview made on this Mac, the director's techniques learned from tutorials, and
// their sounds and images (library.md, LibraryShelves.swift). The same list answers "@" in a note or the brief.

@MainActor @Observable final class LibraryModel {
    static let shared = LibraryModel()
    private(set) var entries: [LibraryEntry] = []
    /// Entries whose preview is on disk.
    private(set) var ready: Set<String> = []
    /// Snapshots and previews: samples, nothing read from disk or made.
    var preview = false
    @ObservationIgnored private var making = false
    /// The sound playing, by its file, and what went wrong bringing something in.
    var playing: String?
    var problem: String?
    @ObservationIgnored var measuring = false
    @ObservationIgnored var player: LibraryPlayer?
    @ObservationIgnored var images: [String: NSImage] = [:]

    func load() {
        entries = preview ? LibrarySamples.entries : LibraryCatalog.all()
        guard !preview else { ready = []; return }
        ready = Set(entries.filter { FileManager.default.fileExists(atPath: ToolRuntime.previewURL(for: $0).path) }.map(\.id))
    }

    func replaceEntry(at i: Int, with e: LibraryEntry) { entries[i] = e }

    func previewURL(_ e: LibraryEntry) -> URL? { ready.contains(e.id) ? ToolRuntime.previewURL(for: e) : nil }
    func poster(_ e: LibraryEntry) -> NSImage? { previewURL(e).flatMap { NSImage(contentsOf: $0.deletingPathExtension().appendingPathExtension("jpg")) } }

    /// Makes the previews that aren't there yet, one at a time, in the background.
    func makePreviews() {
        guard !preview, !making else { return }
        let missing = entries.filter { !ready.contains($0.id) }
        guard !missing.isEmpty else { return }
        making = true
        Task {
            defer { making = false }
            for e in missing {
                guard let subject = LibraryPreviews.subject(for: e) else { continue }
                let url = ToolRuntime.previewURL(for: e)
                do { try await LibraryPreviews.render(subject, to: url, cacheDirectory: DirectionPaths.caches); ready.insert(e.id) }
                catch { DirectionLog.warning("Preview of \(e.name) wasn't made: \(error.localizedDescription)", "library") }
            }
        }
    }

    /// Entries whose name or sentence holds every word typed, names that start with it first. A note's "@" also
    /// looks through the film's `footage`: after the library while nothing's typed, among it after that.
    func search(_ query: String, kind: String? = nil, footage: [FootageName] = []) -> [LibraryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let words = q.split(separator: " ").map(String.init)
        let pool = footage.map(\.entry) + entries.filter { Self.shown($0, kind: kind) }
        guard !words.isEmpty else { return entries.filter { Self.shown($0, kind: kind) } + footage.map(\.entry) }
        let hits = pool.filter { e in words.allSatisfy { w in "\(e.name) \(e.summary) \(e.kind)".lowercased().contains(w) } }
        return hits.sorted { a, b in
            let pa = a.name.lowercased().hasPrefix(q), pb = b.name.lowercased().hasPrefix(q)
            return pa != pb ? pa : false
        }
    }

    /// The window's kinds: Direction's transitions, moves and effects; the director's sounds, images and learned techniques.
    static func shown(_ e: LibraryEntry, kind: String?) -> Bool {
        switch kind {
        case nil: true
        case "yours": e.technique != nil
        case "sounds": e.item?.isSound == true
        case "images": e.item?.kind == .image
        case let k?: e.item == nil && e.kind == k
        }
    }
}

extension FootageName {
    /// As the "@" list shows it: a scene with the film icon, a setup with a camera, a take with a frame.
    var entry: LibraryEntry {
        LibraryEntry(id: id, name: name, kind: kind.rawValue, summary: summary.isEmpty ? kind.rawValue.capitalized : summary,
                     icon: kind == .scene ? "film" : kind == .setup ? "video" : "play.rectangle", use: "")
    }
}

/// Samples for snapshots, so nothing reads the director's own folders there.
enum LibrarySamples {
    static var entries: [LibraryEntry] { LibraryCatalog.entries(techniques: TechniqueSamples.techniques.map { t in var t = t; if case .object(var o) = t.tokens { o["icon"] = .string(t.id == "grid-flash" ? "square.grid.3x3.fill" : "squareshape.split.3x3"); o["when"] = .string("A punchy change of scene or chapter."); t.tokens = .object(o) }; return t }) }
}

// MARK: The window

/// The window as a snapshot draws it, with an entry chosen.
struct LibraryWindowPreview: View {
    var chosen: String?
    var kind: String? = nil
    var body: some View { LibraryWindow(app: nil, preview: false, initial: chosen, kind: kind) }
}

struct LibraryWindow: View {
    var app: AppModel?
    var preview = false
    var initial: String? = nil
    /// A page in Settings: the page says Library, and the grid and the detail fit its width.
    var embedded = false
    @State private var library = LibraryModel.shared
    @State private var query = ""
    @State private var kind: String?
    @State private var chosen: String?
    @State private var dropping = false
    @Environment(\.settingsPages) private var pages
    init(app: AppModel?, preview: Bool = false, initial: String? = nil, kind: String? = nil, embedded: Bool = false) {
        self.app = app; self.preview = preview; self.initial = initial; self.embedded = embedded; _kind = State(initialValue: kind)
    }

    var body: some View {
        // A song's parts are in its song here, though a note can name each.
        let shown = library.search(query, kind: kind).filter { $0.partOf == nil }
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // In Settings the page's bar says Library, and search leads the row.
                    if !embedded { Text("Library").font(Gate.Font.title).foregroundStyle(Gate.Text.primary); Spacer(minLength: 8) }
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                        TextField("", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary)
                            .startPlaceholder("Search", shown: query.isEmpty).frame(width: 150)
                    }
                    .padding(.horizontal, 10).frame(height: 28).background(GateFieldBackground())
                    Button("Add Sounds or Images\u{2026}") { if let id = library.chooseAndAdd() { open(id) } }.buttonStyle(.gate(.normal, .small))
                        .help("Music, sound effects, logos and stills, kept for every film.")
                    Button("Learn a Technique\u{2026}") { app?.film?.sheet = .learnTechnique; NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil) }
                        .buttonStyle(.gate(.normal, .small)).disabled(app?.film == nil).help(app?.film == nil ? "Open a film to learn a technique into it." : "Give the editor a video to learn from.")
                    if embedded { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 20).frame(height: 56)
                // Kinds on a row of their own: Direction's, then the director's.
                HStack {
                    GateSegmented(options: [(nil, "All"), ("transition", "Transitions"), ("move", "Moves"), ("effect", "Effects"), ("sounds", "Sounds"), ("images", "Images"), ("yours", "Learned")], selection: $kind)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
                .overlay(alignment: .bottom) { SystemHairline() }
                if let problem = library.problem {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Gate.State.alert)
                        Text(problem).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary)
                        Spacer(minLength: 0)
                        Button { library.problem = nil } label: { Image(systemName: "xmark") }.buttonStyle(.gate(.ghost, .small, icon: true)).help("Dismiss")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8).background(Gate.State.alertWash)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 196, maximum: 260), spacing: 14)], spacing: 16) {
                        ForEach(shown) { e in LibraryCard(entry: e, library: library, chosen: !embedded && (chosen ?? initial) == e.id) { open(e.id) } }
                    }
                    .padding(20)
                    if shown.isEmpty {
                        if query.isEmpty && (kind == "sounds" || kind == "images") {
                            VStack(spacing: 6) {
                                Text(kind == "sounds" ? "No sounds yet" : "No images yet").font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary)
                                Text(kind == "sounds" ? "Drop music and sound effects here. They\u{2019}re kept for every film, and a note names one with @." : "Drop logos and stills here. They\u{2019}re kept for every film, and a note names one with @.")
                                    .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).multilineTextAlignment(.center).frame(maxWidth: 360)
                            }
                            .padding(.top, 60)
                        } else {
                            Text("Nothing in the library matches \u{201C}\(query)\u{201D}.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).padding(.top, 40)
                        }
                    }
                }
                .overlay {
                    if dropping {
                        RoundedRectangle(cornerRadius: Gate.Radius.panel, style: .continuous).strokeBorder(Gate.Line.strong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .background(RoundedRectangle(cornerRadius: Gate.Radius.panel, style: .continuous).fill(Gate.Surface.hover.opacity(0.4)))
                            .overlay(Text("Add to the library").font(Gate.Font.title).foregroundStyle(Gate.Text.primary))
                            .padding(10).allowsHitTesting(false)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let id = library.add(urls) else { return false }
                    open(id); return true
                } isTargeted: { dropping = $0 }
            }
            // In Settings an entry opens as its own page; the window shows it beside the grid.
            if !embedded, let e = library.entries.first(where: { $0.id == (chosen ?? initial) }).map(library.whole) ?? shown.first {
                LibraryEntryDetail(entry: e, library: library) { chosen = $0 }
                    .frame(width: 340).overlay(alignment: .leading) { Rectangle().fill(Gate.Line.subtle).frame(width: 1) }
            }
        }
        .frame(minWidth: embedded ? nil : 960, minHeight: embedded ? nil : 540)
        .background(Gate.Surface.ground)
        .preferredColorScheme(.dark)
        .task {
            if preview { library.preview = true }
            library.load()
            library.makePreviews()
            library.measure()
        }
        // Files put in the Sounds or Images folder in the Finder show up when you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !preview else { return }
            library.load(); library.measure()
        }
        .onDisappear { library.stop() }
    }
}

extension LibraryWindow {
    /// Shows an entry: beside the grid in the window, as its own page in Settings.
    fileprivate func open(_ id: String) {
        guard embedded else { chosen = id; return }
        let name = library.entries.first { $0.id == id }?.name ?? "Library"
        pages?.open(SettingsPage(id: "library:" + id, title: name) { LibraryEntryPage(id: id) })
    }
}

/// What the library knows about one entry: a song with its parts, a sound or image, or a transition, move or effect.
struct LibraryEntryDetail: View {
    var entry: LibraryEntry
    var library: LibraryModel
    var chose: (String) -> Void
    var body: some View {
        if let parts = entry.parts { LibrarySongDetail(entry: entry, song: Song(name: entry.name, parts: parts), library: library, chose: chose) }
        else if let item = entry.item { LibraryItemDetail(entry: entry, item: item, library: library, chose: chose) } else { LibraryDetail(entry: entry, library: library) }
    }
}

/// An icon in its tile: the same everywhere an entry shows.
struct LibraryIcon: View {
    var name: String
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? "square.dashed" : name)
            .font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Gate.Surface.hover))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(Gate.Line.subtle, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// One entry: its preview (plays while the pointer is on it), icon, name and sentence.
struct LibraryCard: View {
    var entry: LibraryEntry
    var library: LibraryModel
    var chosen: Bool
    var choose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 8) {
                if let item = entry.item { LibraryItemPreview(item: item, library: library) } else { LibraryPreview(entry: entry, library: library, playing: hovering) }
                HStack(spacing: 8) {
                    LibraryIcon(name: entry.icon)
                    Text(entry.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).lineLimit(1)
                    Spacer(minLength: 0)
                    if entry.technique != nil { Text("Learned").font(Gate.Font.caption).foregroundStyle(Gate.Voice.director) }
                }
                Text(entry.summary).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(chosen || hovering ? Gate.Surface.raised : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(chosen ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(entry.name). \(entry.summary)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A preview at 16:9: its poster, and the video looping while it plays; a quiet wait while it's being made.
struct LibraryPreview: View {
    var entry: LibraryEntry
    var library: LibraryModel
    var playing: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Gate.Surface.sunken)
            if let url = library.previewURL(entry) {
                // The poster under the video, so nothing goes blank while it starts.
                if let poster = library.poster(entry) { Image(nsImage: poster).resizable().aspectRatio(contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) }
                if playing { LoopingVideo(url: url).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) }
            } else {
                VStack(spacing: 6) {
                    LibraryIcon(name: entry.icon, size: 30)
                    if !library.preview { Text("Making its preview").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled) }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }
}

/// What an entry does, at length: its preview playing, when to use it, its variants, where it was learned.
struct LibraryDetail: View {
    var entry: LibraryEntry
    var library: LibraryModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LibraryPreview(entry: entry, library: library, playing: true)
                HStack(spacing: 10) {
                    LibraryIcon(name: entry.icon, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(Gate.Font.title).foregroundStyle(Gate.Text.primary)
                        Text(entry.isBuiltIn ? "Direction\u{2019}s own \(entry.kind)" : "A \(entry.kind) you taught it").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    }
                }
                Text(entry.summary).font(.system(size: 13)).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
                if let t = entry.technique {
                    if !t.when.isEmpty { section("When to use it", t.when) }
                    if !t.needs.isEmpty { section("What it needs", t.needs) }
                    if !t.variants.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Variants").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                            FlowChips(items: t.variants.map(\.name))
                        }
                    }
                    if let title = t.source["title"].string {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Learned from").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                            if let link = t.source["url"].string.flatMap(URL.init(string:)) {
                                Link(destination: link) { Text("\u{201C}\(title)\u{201D}" + (t.source["author"].string.map { " by \($0)" } ?? "")).font(Gate.Font.small).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                            } else { Text(title).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("In a note or the brief, type @ and pick it, or write").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                    Text("@\(entry.name)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Voice.director).textSelection(.enabled)
                }
            }
            .padding(18)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            Text(text).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Small chips that wrap.
struct FlowChips: View {
    var items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { Chip($0, mono: false) }
        }
    }
}

/// A short video playing over and over, silent.
struct LoopingVideo: NSViewRepresentable {
    var url: URL
    func makeNSView(context: Context) -> LoopingPlayerView { let v = LoopingPlayerView(); v.play(url); return v }
    func updateNSView(_ v: LoopingPlayerView, context: Context) { v.play(url) }
    static func dismantleNSView(_ v: LoopingPlayerView, coordinator: ()) { v.stop() }
}

final class LoopingPlayerView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var current: URL?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let layer = AVPlayerLayer(player: player); layer.videoGravity = .resizeAspectFill
        self.layer = layer
        player.isMuted = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func play(_ url: URL) {
        guard url != current else { return }
        current = url
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }
    func stop() { player.pause(); looper = nil }
}

// MARK: "@" in what the director writes

/// The list "@" opens: icon, name and sentence; the chosen one lit. The caller handles the keys.
struct MentionList: View {
    var items: [LibraryEntry]
    var selected: Int
    var pick: (LibraryEntry) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                Button { pick(e) } label: {
                    HStack(spacing: 9) {
                        LibraryIcon(name: e.icon, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Gate.Text.primary).lineLimit(1)
                            Text(e.summary).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(i == selected ? Gate.Surface.hover : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("\u{2191}\u{2193} to move, \u{21A9} to choose").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled)
                Spacer()
                Text("Window \u{203A} Library").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled)
            }
            .padding(.horizontal, 8).padding(.top, 5)
        }
        .padding(6)
        .frame(width: 340)
        .background(Gate.Surface.panel)
    }
}

/// Where "@" is being typed: the "@word" before the caret, when it starts a word and the words could still
/// be one of the library's names.
enum MentionToken {
    /// The caret's place in `text`, in UTF-16 units, or nil when it isn't a place in this text. A field's
    /// selection can still point into what the field held before (another film's brief, the text a keystroke
    /// ago), and measuring that against this text stops the app.
    static func caret(_ i: String.Index, in text: String) -> Int? {
        var n = 0
        for j in text.utf16.indices { if j == i { return n }; n += 1 }
        return i == text.endIndex ? n : nil
    }

    static func find(_ text: String, caret: Int) -> (range: NSRange, query: String)? {
        let s = text as NSString
        guard caret <= s.length else { return nil }
        var i = caret - 1
        while i >= 0, caret - i <= 32 {
            let ch = s.character(at: i)
            if ch == 10 { return nil }
            if ch == 64 {
                if i > 0, let scalar = Unicode.Scalar(s.character(at: i - 1)), CharacterSet.alphanumerics.contains(scalar) { return nil }
                return (NSRange(location: i, length: caret - i), s.substring(with: NSRange(location: i + 1, length: caret - i - 1)))
            }
            i -= 1
        }
        return nil
    }

    /// What the list offers while a name is typed after "@". The library finds words anywhere in a name or what
    /// it is, which is right for the first word; past it a name is being spelled out, so only names that start
    /// with what's typed stay. A whole name with a space after it is finished, and so is the list: what follows
    /// is the note.
    static func offer(_ query: String, from found: [LibraryEntry]) -> [LibraryEntry] {
        let q = query.lowercased(), typed = q.trimmingCharacters(in: .whitespaces)
        if q.hasSuffix(" "), found.contains(where: { $0.name.lowercased() == typed }) { return [] }
        guard typed.contains(" ") || q.hasSuffix(" ") else { return Array(found.prefix(6)) }
        return Array(found.filter { $0.name.lowercased().hasPrefix(q) }.prefix(6))
    }
}

/// "@" on a SwiftUI field (the brief): the list under the field while a name is being typed.
struct MentionsModifier: ViewModifier {
    @Binding var text: String
    @Binding var selection: TextSelection?
    @State private var selected = 0
    @State private var dismissed: String?
    private var library: LibraryModel { LibraryModel.shared }

    private var token: (range: NSRange, query: String)? {
        guard let sel = selection, case .selection(let r) = sel.indices, r.isEmpty, let caret = MentionToken.caret(r.lowerBound, in: text) else { return nil }
        return MentionToken.find(text, caret: caret)
    }
    private var items: [LibraryEntry] {
        guard let t = token, dismissed != text else { return [] }
        return MentionToken.offer(t.query, from: library.search(t.query))
    }

    func body(content: Content) -> some View {
        let items = self.items
        content
            .overlay(alignment: .bottomLeading) {
                if !items.isEmpty {
                    MentionList(items: items, selected: min(selected, items.count - 1)) { pick($0) }
                        .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.strong, lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                        .alignmentGuide(.bottom) { $0[.top] - 6 }
                        .zIndex(10)
                }
            }
            .zIndex(items.isEmpty ? 0 : 10)
            .onKeyPress(.downArrow) { guard !items.isEmpty else { return .ignored }; selected = min(items.count - 1, selected + 1); return .handled }
            .onKeyPress(.upArrow) { guard !items.isEmpty else { return .ignored }; selected = max(0, selected - 1); return .handled }
            .onKeyPress(.return) { guard !items.isEmpty else { return .ignored }; pick(items[min(selected, items.count - 1)]); return .handled }
            .onKeyPress(.tab) { guard !items.isEmpty else { return .ignored }; pick(items[min(selected, items.count - 1)]); return .handled }
            .onKeyPress(.escape) { guard !items.isEmpty else { return .ignored }; dismissed = text; return .handled }
            .onChange(of: text) { _, _ in selected = 0 }
            .task { if library.entries.isEmpty { library.load() } }
    }

    private func pick(_ e: LibraryEntry) {
        guard let t = token else { return }
        let ns = text as NSString
        let replaced = ns.replacingCharacters(in: t.range, with: "@\(e.name) ")
        text = replaced
        let caret = replaced.index(replaced.startIndex, offsetBy: min(replaced.count, (ns.substring(to: t.range.location) as String).count + e.name.count + 2))
        selection = TextSelection(insertionPoint: caret)
        selected = 0
    }
}

extension View {
    /// "@" opens the library under this field while a name is typed (the brief's fields).
    func libraryMentions(text: Binding<String>, selection: Binding<TextSelection?>) -> some View { modifier(MentionsModifier(text: text, selection: selection)) }
}
