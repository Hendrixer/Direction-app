import SwiftUI
import AppKit
import AVFoundation
import DirectionCore

/// Frame 52: Find missing footage. Choose a folder; Direction looks inside it for each missing
/// take by file name, checks the length within one frame, and relinks the matches in one step.
/// Missing footage never deletes notes, circles or cuts.
struct RelinkSheet: View {
    @Bindable var model: FilmModel
    /// Snapshots: a search already under way.
    var previewState: RelinkSearch.Snapshot? = nil
    @State private var search = RelinkSearch()

    private var missing: [MediaAsset] { model.isPreview ? MissingFootage.previewAssets(model) : MissingFootage.assets(in: model) }
    private var top: CGFloat { Gate.Size.titlebar + (model.offline ? 36 : 0) + (missing.isEmpty ? 0 : 36) }

    var body: some View {
        SystemSheet(width: 620, top: top, label: "Find missing footage", onDismiss: cancel) {
            SystemSheetHead(title: "Find missing footage", subtitle: "Point to the folder or drive with the original files. Direction matches them by name and length, and looks through every folder inside.")
            VStack(alignment: .leading, spacing: 14) {
                folderRow
                if search.folder != nil { progressRow }
                list
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            SystemSheetFoot {
                Text("Unmatched takes stay offline. Notes on them are kept.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                Spacer(minLength: 8)
                Button("Cancel", action: cancel).buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button(search.found.count == 1 ? "Relink 1 take" : "Relink \(search.found.count) takes", action: relink)
                    .buttonStyle(.steel).keyboardShortcut(.defaultAction).disabled(search.found.isEmpty)
            }
        }
        .onAppear {
            if let state = previewState ?? SystemPreview.relink[ObjectIdentifier(model)] { search.load(state) } else { search.reset(missing, dailies: model.dailies) }
        }
        .onDisappear { search.cancel() }
    }

    private var folderRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                Text(search.folder?.path ?? "Choose the folder or drive with the originals")
                    .font(Gate.Font.body).foregroundStyle(search.folder == nil ? Gate.Text.disabled : Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: Gate.Size.control).background(GateFieldBackground())
            Button("Choose\u{2026}", action: choose).buttonStyle(.gate)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            if search.running { RingSpinner() } else { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Gate.Text.tertiary) }
            Text(progressText).lineLimit(1)
            Spacer(minLength: 8)
            GateProgress(value: search.total == 0 ? 0 : Double(search.found.count) / Double(search.total)).frame(width: 160)
        }
        .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
        .accessibilityElement(children: .combine)
    }

    private var progressText: String {
        let counts = "\(search.found.count) of \(search.total) found"
        if search.running { return "Searching \(search.current ?? search.folder?.lastPathComponent ?? "")\u{2026} \(counts)" }
        return counts
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(search.rows.enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 10) {
                        icon(row.status).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary)
                            Text(row.displayPath).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Gate.Text.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        chip(row.status)
                    }
                    .padding(.vertical, 6).frame(minHeight: 36)
                    .overlay(alignment: .top) { if i > 0 { SystemHairline() } }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.label), \(row.status.word)")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
        }
        .frame(maxHeight: 290)
        .fixedSize(horizontal: false, vertical: true)
        .background(SystemCardBackground(fill: Gate.Surface.sunken))
    }

    @ViewBuilder private func icon(_ s: RelinkSearch.Status) -> some View {
        switch s {
        case .found: Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Gate.State.approve)
        case .searching: RingSpinner(size: 12)
        case .waiting: Image(systemName: "externaldrive").font(.system(size: 11)).foregroundStyle(Gate.Text.disabled)
        case .notFound, .wrongLength: Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Gate.State.alert)
        }
    }

    @ViewBuilder private func chip(_ s: RelinkSearch.Status) -> some View {
        switch s {
        case .found: Chip("Found", style: .ok, mono: false)
        case .searching: Chip("Searching", mono: false)
        case .waiting: Chip("Offline", mono: false)
        case .notFound: Chip("Not in this folder", style: .bad, mono: false)
        case .wrongLength: Chip("Different length", style: .bad, mono: false)
        }
    }

    private func choose() {
        let panel = NSOpenPanel(); panel.title = "Find missing footage"; panel.prompt = "Search Here"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if let first = missing.first, let volume = MissingFootage.volumeName(first.path) { panel.directoryURL = URL(fileURLWithPath: "/Volumes/\(volume)") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        search.start(folder: url, missing: missing, dailies: model.dailies)
    }

    private func cancel() { search.cancel(); model.sheet = nil }

    private func relink() {
        let links = search.found
        guard !links.isEmpty else { return }
        if model.isPreview { model.sheet = nil; return }
        model.perform { try $0.relink(links) }
        if model.error == nil {
            let total = search.total
            model.toast = Toast(title: links.count == 1 ? "1 take relinked." : "\(links.count) takes relinked.", detail: links.count < total ? "\(total - links.count) still missing." : nil)
            model.loadDisplayed(force: true)
            model.sheet = nil
        }
    }
}

/// Finds missing takes in a folder: by file name, then length within one frame.
@MainActor @Observable
final class RelinkSearch {
    enum Status: Equatable {
        case waiting, searching, found(AssetRelink), notFound, wrongLength(String)
        var word: String {
            switch self { case .waiting: "offline"; case .searching: "searching"; case .found: "found"; case .notFound: "not in this folder"; case .wrongLength: "different length" }
        }
    }
    struct Row: Identifiable, Equatable {
        var id: String
        var label: String
        var originalPath: String
        var status: Status
        var displayPath: String {
            if case .found(let link) = status { return RelinkSearch.shortPath(link.path) }
            if case .wrongLength(let path) = status { return RelinkSearch.shortPath(path) }
            return RelinkSearch.shortPath(originalPath)
        }
    }
    /// Snapshot state for frame 52.
    struct Snapshot { var folder: String; var current: String?; var rows: [Row] }

    private(set) var rows: [Row] = []
    private(set) var folder: URL?
    private(set) var current: String?
    private(set) var running = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var assets: [MediaAsset] = []

    var total: Int { rows.count }
    var found: [AssetRelink] { rows.compactMap { if case .found(let l) = $0.status { l } else { nil } } }

    func reset(_ missing: [MediaAsset], dailies: Dailies = Dailies()) {
        assets = missing
        rows = missing.map { Row(id: $0.id, label: MissingFootage.label($0, dailies: dailies), originalPath: $0.path, status: .waiting) }
    }
    func load(_ s: Snapshot) { folder = URL(fileURLWithPath: s.folder); current = s.current; rows = s.rows; running = s.current != nil }

    func start(folder: URL, missing: [MediaAsset], dailies: Dailies) {
        cancel()
        reset(missing, dailies: dailies)
        self.folder = folder
        for i in rows.indices { rows[i].status = .searching }
        running = true
        let wanted = Set(missing.map { URL(fileURLWithPath: $0.path).lastPathComponent.lowercased() })
        let assets = missing
        task = Task {
            // The chosen folder first, then the rest of its drive when it's an external one.
            var roots = [folder]
            let parts = folder.standardizedFileURL.pathComponents
            if parts.count > 3, parts[1] == "Volumes" { roots.append(URL(fileURLWithPath: "/Volumes/\(parts[2])")) }
            var searched: Set<String> = []
            for root in roots {
                if found.count == total { break }
                current = root.lastPathComponent
                let skip = searched
                let files = await Task.detached(priority: .userInitiated) { Self.files(named: wanted, under: root, skipping: skip) }.value
                searched.insert(root.standardizedFileURL.path)
                if Task.isCancelled { return }
                let candidates = FootageMatch.candidates(for: assets.filter { a in !found.contains { $0.assetID == a.id } }, in: files)
                for asset in assets {
                    guard let urls = candidates[asset.id], let i = rows.firstIndex(where: { $0.id == asset.id }) else { continue }
                    current = urls.first?.deletingLastPathComponent().lastPathComponent
                    var mismatch: String?
                    for url in urls {
                        if let link = await Self.measure(url, for: asset) { rows[i].status = .found(link); mismatch = nil; break }
                        mismatch = url.path
                    }
                    if let mismatch, case .searching = rows[i].status { rows[i].status = .wrongLength(mismatch) }
                    if Task.isCancelled { return }
                }
            }
            for i in rows.indices where rows[i].status == .searching { rows[i].status = .notFound }
            running = false; current = nil
        }
    }

    func cancel() { task?.cancel(); task = nil; running = false }

    nonisolated static func files(named wanted: Set<String>, under root: URL, skipping: Set<String>) -> [URL] {
        var out: [URL] = []
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = e?.nextObject() as? URL {
            if skipping.contains(url.standardizedFileURL.path) { e?.skipDescendants(); continue }
            if wanted.contains(url.lastPathComponent.lowercased()) { out.append(url) }
        }
        return out
    }

    /// The file's details if its length matches the take within one frame.
    nonisolated static func measure(_ url: URL, for asset: MediaAsset) async -> AssetRelink? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let duration: MediaTime
        if asset.isImage { duration = asset.duration }
        else {
            guard let d = try? await AVURLAsset(url: url).load(.duration), d.isNumeric else { return nil }
            duration = MediaTime(d)
        }
        guard FootageMatch.durationMatches(asset, duration) else { return nil }
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? (try? url.bookmarkData())
        return AssetRelink(assetID: asset.id, path: url.path, fileSize: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0, duration: duration, bookmark: bookmark)
    }

    /// "Shoot SSD/Day 1/A001_C002.mov" for files on a drive; "~/…" for the home folder.
    nonisolated static func shortPath(_ path: String) -> String {
        if path.hasPrefix("/Volumes/") { return String(path.dropFirst("/Volumes/".count)) }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
