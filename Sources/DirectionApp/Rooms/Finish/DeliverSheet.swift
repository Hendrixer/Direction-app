import SwiftUI
import AppKit
import ObjectiveC
import UserNotifications
import DirectionCore
import DirectionTools

// Owner: Changes and Finish agent. Deliver (37) and the delivery that runs after it (36, 38).
// Files are written by direction_export jobs, captions straight from the cut; nothing is ever overwritten.

/// An output the engine can write today.
struct DeliveryOutput: Identifiable, Hashable {
    var id: String
    var name: String
    var preset: String
    var ext: String
    var codec: String
    var note: String
    var defaultOn: Bool
    /// Rough data rate at 1920 × 1080, 24 fps, for the size estimate.
    var mbps: Double
    var art: FootageArt

    static let all: [DeliveryOutput] = [
        .init(id: "master", name: "Master", preset: "prores", ext: "mov", codec: "ProRes 422", note: "with audio", defaultOn: true, mbps: 125, art: .day),
        .init(id: "web", name: "Web", preset: "h264", ext: "mp4", codec: "H.264", note: "for sharing and upload", defaultOn: true, mbps: 7, art: .room),
        .init(id: "hevc", name: "HEVC", preset: "hevc", ext: "mp4", codec: "HEVC", note: "smaller, same quality", defaultOn: false, mbps: 4.5, art: .dusk),
        // The captions the cut shows, as SRT with a WebVTT beside it (finish.md › 37).
        .init(id: "captions", name: "Captions", preset: "captions", ext: "srt", codec: "SRT and WebVTT", note: "", defaultOn: true, mbps: 0, art: .night),
        // A folder for another editing app (issue #4): the cut as FCPXML, renders, each sound track and the look.
        .init(id: "timeline", name: "Timeline", preset: "timeline", ext: "", codec: "For Final Cut Pro or DaVinci Resolve", note: "sound by track", defaultOn: false, mbps: 0, art: .dusk),
    ]
    static func matching(_ url: URL) -> DeliveryOutput? { all.first { ($0.ext.isEmpty ? url : url.deletingPathExtension()).lastPathComponent.hasSuffix("\u{2013} \($0.name)") } }
    /// "Name.ext", or "Name" for a folder.
    func file(_ name: String) -> String { ext.isEmpty ? name : "\(name).\(ext)" }
}

/// A delivery in progress or done. Lives with the film so it keeps running when the sheet closes.
@MainActor @Observable
final class Delivery {
    enum State: Equatable { case queued, writing, done, failed(String) }
    struct Item: Identifiable, Equatable {
        var id: String
        var output: DeliveryOutput
        var url: URL
        var state: State = .queued
    }
    var items: [Item] = []
    var folder: URL?
    /// Another size of the cut's shape, such as the footage's; nil delivers at the cut's own size.
    var size: (width: Int, height: Int)?
    /// After delivering, the director can go back to the checklist (38's more menu).
    var showChecklist = false
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { items.contains { $0.state == .queued || $0.state == .writing } }
    var doneCount: Int { items.filter { $0.state == .done }.count }
    var failed: [Item] { items.filter { if case .failed = $0.state { true } else { false } } }

    /// "<Film title> – <Output>.<ext>", with " 2", " 3"… when a file is already there.
    static func uniqueURL(in folder: URL, film: String, output: DeliveryOutput, taken: Set<String>) -> URL {
        let safe = film.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var url = folder.appendingPathComponent(output.file("\(safe) \u{2013} \(output.name)")), n = 2
        // Captions write a .vtt beside the .srt, so that name has to be free too.
        func used(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path) || taken.contains(url.path)
                || (output.id == "captions" && FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("vtt").path))
        }
        while used(url) {
            url = folder.appendingPathComponent(output.file("\(safe) \u{2013} \(output.name) \(n)")); n += 1
        }
        return url
    }

    func start(model: FilmModel, outputs: [DeliveryOutput], folder: URL, size: (width: Int, height: Int)? = nil, finderAlias: Bool) {
        guard !isRunning, let cut = model.deliveryCut else { return }
        self.folder = folder
        self.size = size
        showChecklist = true
        var taken: Set<String> = []
        items = outputs.map { o in
            let url = Self.uniqueURL(in: folder, film: model.filmName, output: o, taken: taken)
            taken.insert(url.path)
            return Item(id: o.id, output: o, url: url)
        }
        run(model: model, cut: cut, finderAlias: finderAlias)
    }

    func retry(model: FilmModel, _ id: String) {
        guard !isRunning, let i = items.firstIndex(where: { $0.id == id }), let cut = model.deliveryCut else { return }
        items[i].url = Self.uniqueURL(in: items[i].url.deletingLastPathComponent(), film: model.filmName, output: items[i].output, taken: Set(items.map(\.url.path)))
        items[i].state = .queued
        run(model: model, cut: cut, finderAlias: false)
    }

    func cancel() { task?.cancel() }

    private func run(model: FilmModel, cut: ReviewCut, finderAlias: Bool) {
        guard let runtime = model.runtime else { for i in items.indices where items[i].state == .queued { items[i].state = .failed("This film isn't open from disk.") }; return }
        task = Task { [weak self, weak model] in
            guard let self else { return }
            if let folder = self.folder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            // The locked cut with everything finished since (color, mix), every file the same.
            let revision = model?.revision(of: cut) ?? cut.editRevision
            for i in self.items.indices where self.items[i].state == .queued {
                if Task.isCancelled { self.items[i].state = .failed("Stopped"); continue }
                self.items[i].state = .writing
                let item = self.items[i]
                do {
                    if item.output.id == "captions" {
                        _ = try await runtime.writeCaptionFiles(revision: revision, sequenceID: cut.sequenceID, to: item.url)
                        self.items[i].state = .done
                        continue
                    }
                    var args: [String: JSONValue] = [
                        "path": .string(item.url.path), "preset": .string(item.output.preset),
                        "revision": .number(Double(revision)), "sequenceID": .string(cut.sequenceID),
                    ]
                    if let size = self.size { args["width"] = .number(Double(size.width)); args["height"] = .number(Double(size.height)) }
                    let response = try await runtime.invoke("direction_export", arguments: .object(args))
                    let job = try response.value.decode(JobRecord.self)
                    do { _ = try await runtime.waitForJob(job.id) } catch is CancellationError {
                        // Stop stops the writing too, not only the waiting: a stopped timeline never lands later.
                        Task { _ = try? await runtime.invoke("direction_cancel_job", arguments: .object(["jobID": .string(job.id)])) }
                        throw CancellationError()
                    }
                    self.items[i].state = .done
                } catch {
                    self.items[i].state = .failed(error is CancellationError ? "Stopped" : error.localizedDescription)
                }
            }
            guard let model else { return }
            self.finish(model: model, cut: cut, finderAlias: finderAlias)
        }
    }

    private func finish(model: FilmModel, cut: ReviewCut, finderAlias: Bool) {
        let done = items.filter { $0.state == .done }.map(\.url.path)
        guard !done.isEmpty else { return }
        model.perform { store in
            _ = try store.updateDirectingState(summary: "Delivered \(cut.name)") { s in s.deliveredAt = Date().timeIntervalSince1970; s.deliveredPaths = done }
            if self.failed.isEmpty, var item = (model.directing.finishing ?? FinishingItem.defaults).first(where: { $0.id == "deliver" }) {
                item.state = "done"; item.progress = nil
                _ = try store.updateFinishing([item])
            }
        }
        showChecklist = false
        if finderAlias, let folder { Self.makeDesktopAlias(to: folder, named: "\(model.filmName) Delivery") }
        let title = failed.isEmpty ? "\(model.filmName) is delivered" : "\(done.count) of \(items.count) delivered"
        AccessibilityNotification.Announcement("\(title), \(done.count) files").post()
        // Notifications need an app bundle; a delivery finishing in the background posts one.
        if Bundle.main.bundleIdentifier != nil, NSApp?.isActive == false, UserDefaults.standard.object(forKey: "notifyDelivered") as? Bool ?? true {
            let content = UNMutableNotificationContent(); content.title = title; content.body = "\(cut.name) \u{00B7} \(done.count) files in \(folder?.lastPathComponent ?? "Delivery")"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// A Finder alias, never replacing anything already on the Desktop.
    static func makeDesktopAlias(to target: URL, named name: String) {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
              let data = try? target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var url = desktop.appendingPathComponent(name), n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = desktop.appendingPathComponent("\(name) \(n)"); n += 1 }
        try? URL.writeBookmarkData(data, to: url)
    }
}

private nonisolated(unsafe) var deliveryKey: UInt8 = 0

extension FilmModel {
    var delivery: Delivery {
        if let d = objc_getAssociatedObject(self, &deliveryKey) as? Delivery { return d }
        let d = Delivery()
        objc_setAssociatedObject(self, &deliveryKey, d, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return d
    }
    /// True while files are being written. Quit should ask first.
    var isDelivering: Bool { delivery.isRunning }
    /// The cut picture was locked on; the latest cut before that.
    var deliveryCut: ReviewCut? { cuts.first { $0.id == directing.pictureLockedCutID } ?? latestCut }
    var deliveredFiles: [URL] { (directing.deliveredPaths ?? []).map { URL(fileURLWithPath: $0) } }

    /// The size the cut's footage holds at the cut's shape, when that's bigger than the cut:
    /// 3840 × 2160 for 4K footage in a 1920 × 1080 cut.
    func footageSize(_ s: DirectionCore.Sequence?) -> (width: Int, height: Int)? {
        guard let s, s.width > 0, s.height > 0, let assets = project?.assets else { return nil }
        let used = Set(s.clips.filter { $0.kind == .video }.compactMap(\.assetID))
        let scale = assets.filter { used.contains($0.id) && !$0.isImage }.compactMap(\.video.first)
            .map { min(Double($0.width) / Double(s.width), Double($0.height) / Double(s.height)) }.max() ?? 1
        guard scale > 1.05 else { return nil }
        let width = Int((Double(s.width) * min(scale, 4)).rounded()) / 2 * 2
        return (width, Int((Double(width) * Double(s.height) / Double(s.width)).rounded()) / 2 * 2)
    }
}

// MARK: Formatting

enum DeliveryFormat {
    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: n)
    }
    /// "Movies › Launch film › Delivery".
    static func folderLabel(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var path = url.standardizedFileURL.path
        if path.hasPrefix(home) { path = String(path.dropFirst(home.count)) }
        let parts = path.split(separator: "/").map(String.init)
        return parts.suffix(3).joined(separator: " \u{203A} ")
    }
    static func defaultFolder(film: String) -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent(film).appendingPathComponent("Delivery")
    }
    /// Free space on the volume the folder would live on, and that volume's name.
    static func freeSpace(at url: URL) -> (Int64, String)? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) && probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        guard let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]), let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return (free, v.volumeName ?? "this disk")
    }
    /// A file's size, or everything in a folder.
    static func fileSize(_ url: URL) -> Int64? {
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &folder) else { return nil }
        guard folder.boolValue else { return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value }
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

// MARK: Sheet

struct DeliverSheet: View {
    @Bindable var model: FilmModel
    @State private var chosen: Set<String> = Set(DeliveryOutput.all.filter(\.defaultOn).map(\.id))
    @State private var folder: URL?
    @State private var finderAlias = false
    /// "footage" or "cut": which size to deliver at, when the footage is bigger than the cut.
    @State private var sizeChoice = "footage"
    /// The delivery check (finish.md › Checks): the sound against the target, and the framing. Warnings only.
    @State private var check: JSONValue?
    @State private var checking = false
    @State private var leveling = false
    /// The captions the cut shows: how many, in what language, and the files' size. nil until read.
    @State private var captions: (count: Int, language: String?, bytes: Int64)?
    @AppStorage("deliveryRecentFolders") private var recentFolders = ""

    private var cut: ReviewCut? { model.deliveryCut }
    private var sequence: DirectionCore.Sequence? { model.cutSequence(cut) ?? model.sequence }
    /// Where this film delivered last, or its own folder: another film's folder is in the menu, never the default.
    private var target: URL { folder ?? lastHere ?? DeliveryFormat.defaultFolder(film: model.filmName) }
    private var recent: [URL] { recentFolders.split(separator: "\n").map { URL(fileURLWithPath: String($0)) } }
    private var filmKey: String { "deliveryFolder." + (model.url?.path ?? model.filmName) }
    private var lastHere: URL? { UserDefaults.standard.string(forKey: filmKey).map { URL(fileURLWithPath: $0) } }
    private var outputs: [DeliveryOutput] { DeliveryOutput.all.filter { chosen.contains($0.id) } }
    private var total: Int64 { outputs.map(estimate).reduce(0, +) }
    private var free: (Int64, String)? { model.isPreview ? (312_000_000_000, "Macintosh HD") : DeliveryFormat.freeSpace(at: target) }
    private var tooBig: Bool { free.map { total > $0.0 } ?? false }
    private var footage: (width: Int, height: Int)? { model.footageSize(sequence) }
    /// What the files come out at: the footage's size when chosen, else the cut's.
    private var size: (width: Int, height: Int)? { sizeChoice == "footage" ? footage : nil }
    private var dimensions: (width: Int, height: Int)? { size ?? sequence.map { ($0.width, $0.height) } }

    var body: some View {
        AttachedSheet(width: 640, onDismiss: { model.sheet = nil }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Deliver \(cut?.name ?? "the cut")").font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary)
                Text(formatLine).font(.system(size: 13)).foregroundStyle(Gate.Text.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 14) {
                outputsCard
                if let footage, let s = sequence {
                    HStack(alignment: .center, spacing: 16) {
                        Text("Size").font(.system(size: 13, weight: .medium)).frame(width: 120, alignment: .leading)
                        GateSegmented(options: [("footage", "\(footage.width) \u{00D7} \(footage.height) \u{00B7} your footage"), ("cut", "\(s.width) \u{00D7} \(s.height) \u{00B7} the cut")], selection: $sizeChoice)
                        Spacer(minLength: 0)
                    }
                }
                HStack(alignment: .center, spacing: 16) {
                    Text("Save to").font(.system(size: 13, weight: .medium)).frame(width: 120, alignment: .leading)
                    folderMenu
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top, spacing: 16) {
                    Text("Also").font(.system(size: 13, weight: .medium)).frame(width: 120, alignment: .leading).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 8) {
                        CheckRow(on: false, enabled: false, title: "Update the screening link to the final cut", detail: "Sharing isn\u{2019}t set up on this Mac.") {}
                        CheckRow(on: finderAlias, title: "Make a Finder alias on the Desktop") { finderAlias.toggle() }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 10).hairlineBorder(.top)
                warnings
            }
            .padding(.horizontal, 22).padding(.vertical, 14)

            SheetFooter {
                Text(footLine).font(Gate.Font.small).foregroundStyle(tooBig ? Gate.State.alert : Gate.Text.tertiary).lineLimit(1)
            } trailing: {
                Button { model.sheet = nil } label: { HStack(spacing: 6) { Text("Cancel"); KeyHint("esc") } }
                    .buttonStyle(.gate(.normal)).keyboardShortcut(.cancelAction)
                Button(confirmTitle) { deliver() }
                    .buttonStyle(.steel).keyboardShortcut(.defaultAction)
                    .disabled(outputs.isEmpty || tooBig || model.delivery.isRunning)
                    .help(model.delivery.isRunning ? "A delivery is already running" : "")
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Deliver \(cut?.name ?? "")")
        .task { await readCaptions(); await runCheck() }
    }

    private func readCaptions() async {
        if model.isPreview { captions = (41, "en-US", 8_200); return }
        guard let runtime = model.runtime, let read = try? await runtime.captionLines(revision: cut.map { model.revision(of: $0) }, sequenceID: cut?.sequenceID) else { return }
        captions = (read.lines.count, read.language, Int64(Captions.srt(read.lines).utf8.count + Captions.webVTT(read.lines).utf8.count))
        if read.lines.isEmpty { chosen.remove("captions") }
    }

    private func runCheck() async {
        if model.isPreview { check = DeliveredPreview.check; return }
        guard let runtime = model.runtime else { return }
        checking = true; defer { checking = false }
        check = try? await runtime.deliveryCheck(revision: cut.map { model.revision(of: $0) })
    }

    /// The loudness step, from here: the same edit the editor would make.
    private func level() {
        guard let runtime = model.runtime, let store = model.store else { return }
        leveling = true
        Task {
            defer { leveling = false }
            _ = try? await runtime.invoke("direction_edit", arguments: .object(["baseEditRevision": .number(Double(try store.revision())), "idempotencyKey": .string(UUID().uuidString),
                                                                             "summary": .string("Set the mix to the loudness target"), "operations": .array([.object(["op": .string("loudness")])])]))
            model.refresh(force: true)
            await runCheck()
        }
    }

    private var formatLine: String {
        var parts = [Timecode.duration(model.cutDuration(cut) ?? model.duration)]
        if let s = sequence {
            parts.append("\(s.width) \u{00D7} \(s.height)")
            let fps = s.frameRate.value
            parts.append((fps.rounded() == fps ? String(Int(fps)) : String(format: "%.3f", fps)) + " fps")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func estimate(_ o: DeliveryOutput) -> Int64 {
        if o.id == "captions" { return captions?.bytes ?? 0 }
        let seconds = model.cutDuration(cut) ?? model.duration
        // The sound files: the mix and each track, 48 kHz 24-bit stereo. Renders are extra, and only where needed.
        if o.id == "timeline" { return Int64(288_000 * seconds * Double(1 + Set((sequence?.clips ?? []).filter { $0.kind == .audio }.map(\.layer)).union([0]).count)) }
        let d = dimensions
        let scale = Double((d?.width ?? 1920) * (d?.height ?? 1080)) / (1920 * 1080) * ((sequence?.frameRate.value ?? 24) / 24)
        return Int64(o.mbps * 1_000_000 / 8 * seconds * max(0.1, scale))
    }

    // MARK: Outputs

    private var outputsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(DeliveryOutput.all.enumerated()), id: \.element.id) { i, o in
                outputRow(o).hairlineBorder(i == 0 ? [] : .top)
            }
        }
        .gatePanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outputs")
    }

    private func outputRow(_ o: DeliveryOutput) -> some View {
        let on = chosen.contains(o.id)
        // No words in the cut: nothing to caption.
        let empty = o.id == "captions" && captions?.count == 0
        return Button { if on { chosen.remove(o.id) } else { chosen.insert(o.id) } } label: {
            HStack(spacing: 12) {
                CheckMark(on: on)
                thumb(o.art).opacity(on ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(o.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                    Text(spec(o)).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).monospacedDigit()
                }
                .opacity(on ? 1 : 0.5)
                Spacer(minLength: 8)
                Text("~" + DeliveryFormat.bytes(estimate(o))).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(empty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(o.name), \(spec(o)), about \(DeliveryFormat.bytes(estimate(o)))")
        .accessibilityValue(on ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
    private func spec(_ o: DeliveryOutput) -> String {
        if o.id == "captions" {
            guard let captions else { return o.codec }
            guard captions.count > 0 else { return "No words to caption: the takes have no transcript" }
            let language = captions.language.flatMap { Locale(identifier: $0).language.languageCode?.identifier }.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
            return [o.codec, language, captions.count == 1 ? "1 line" : "\(captions.count) lines"].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        if o.id == "timeline" { return [o.codec, o.note].joined(separator: " \u{00B7} ") }
        return [o.codec, dimensions.map { "\($0.width) \u{00D7} \($0.height)" }, o.note].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func thumb(_ art: FootageArt) -> some View {
        Thumbnail(path: model.stripScenes.last?.thumbnail, art: art).frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.subtle, lineWidth: 1))
    }

    // MARK: Folder

    private var folderMenu: some View {
        Menu {
            ForEach(([DeliveryFormat.defaultFolder(film: model.filmName)] + recent).reduce(into: [URL]()) { if !$0.contains($1) { $0.append($1) } }, id: \.self) { url in
                Button(DeliveryFormat.folderLabel(url)) { folder = url }
            }
            Divider()
            Button("Choose\u{2026}") { choose() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").font(.system(size: 12, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                Text(DeliveryFormat.folderLabel(target)).font(.system(size: 12.5)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Gate.Text.tertiary)
            }
            .foregroundStyle(Gate.Text.primary).padding(.leading, 10).padding(.trailing, 8).frame(height: Gate.Size.control)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.control).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(target.path)
        .accessibilityLabel("Save to \(DeliveryFormat.folderLabel(target))")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Deliver to"; panel.prompt = "Choose"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = target.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
    }

    // MARK: Warnings and foot

    private var openItems: [FinishingItem] { (model.directing.finishing ?? []).filter { $0.id != "deliver" && $0.state != "done" } }

    @ViewBuilder private var warnings: some View {
        let blocked = openItems.filter { $0.state == "blocked" }
        let working = openItems.filter { $0.state == "working" }
        if !blocked.isEmpty {
            HStack(spacing: 10) {
                Text(Image(systemName: "exclamationmark.triangle")).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.State.alert)
                Text("Still open: \(blocked.map(\.title).joined(separator: ", ")). You can deliver, but don\u{2019}t publish yet.").font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.card).fill(Gate.Surface.panel).overlay(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.State.alert.opacity(0.45), lineWidth: 1)))
            .accessibilityElement(children: .combine)
        }
        if !working.isEmpty {
            Text("The editor is still on \(working.map { $0.title.lowercased() }.joined(separator: " and ")). These files use it as it is now.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
        }
        if let check, check["loudness"]["ready"].bool == false {
            HStack(spacing: 10) {
                Text(Image(systemName: "speaker.wave.2")).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.State.alert)
                Text(soundWords(check["loudness"])).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Set to \(LoudnessCheck.lufsText(check["loudness"]["target"].double ?? SharedSettings.loudnessTarget))") { level() }
                    .buttonStyle(.gate(.normal)).disabled(leveling || checking)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.card).fill(Gate.Surface.panel).overlay(RoundedRectangle(cornerRadius: Gate.Radius.card).strokeBorder(Gate.State.alert.opacity(0.45), lineWidth: 1)))
            .accessibilityElement(children: .combine)
        }
        if let problems = check?["framing"].array, !problems.isEmpty {
            let said = problems.prefix(2).compactMap { $0["says"].string }.joined(separator: " ")
            Text("Look before you publish: \(said)\(problems.count > 2 ? " And \(problems.count - 2) more." : "")")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if checking || leveling {
            Text(leveling ? "Setting the mix\u{2026}" : "Checking the sound and the framing\u{2026}").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
        }
    }

    /// The sound against the target the director chose in Settings, in their words: quieter or louder, or a
    /// moment loud enough to crackle.
    private func soundWords(_ l: JSONValue) -> String {
        let target = l["target"].double ?? SharedSettings.loudnessTarget
        if let peak = l["truePeakDBTP"].double, peak > (l["ceiling"].double ?? SharedSettings.truePeakCeiling) + 0.1 {
            return "The loudest moment is too loud and can crackle on some players. You can deliver, but don\u{2019}t publish yet."
        }
        guard let measured = l["integratedLUFS"].double else { return l["says"].string ?? "" }
        return "The sound is \(measured < target ? "quieter" : "louder") than your \(LoudnessCheck.lufsText(target)) target (it\u{2019}s \(LoudnessCheck.lufsText(measured)) now). You can deliver, but it won\u{2019}t play at the level you chose."
    }

    private var footLine: String {
        let n = outputs.count
        var s = "\(n == 1 ? "1 file" : "\(n) files") \u{00B7} about \(DeliveryFormat.bytes(total))"
        if let free { s += tooBig ? " \u{00B7} Not enough space on \(free.1)" : " \u{00B7} \(DeliveryFormat.bytes(free.0)) free" }
        return s
    }
    private var confirmTitle: String { outputs.count == 1 ? "Deliver 1 file" : "Deliver \(outputs.count) files" }

    private func deliver() {
        guard !outputs.isEmpty, !tooBig else { return }
        let path = target.path
        recentFolders = ([path] + recent.map(\.path).filter { $0 != path }).prefix(5).joined(separator: "\n")
        UserDefaults.standard.set(path, forKey: filmKey)
        model.delivery.start(model: model, outputs: outputs, folder: target, size: size, finderAlias: finderAlias)
        model.sheet = nil
    }
}

/// The Gate checkbox, drawn inside a larger clickable row.
struct CheckMark: View {
    var on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(on ? Gate.Steel.ramp[9] : Gate.Surface.sunken)
            .overlay { if !on { RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.strong, lineWidth: 1) } }
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Gate.Steel.ramp[1]) } }
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }
}

struct CheckRow: View {
    var on: Bool
    var enabled = true
    var title: String
    var detail: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CheckMark(on: on).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                    if let detail { Text(detail).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "on" : "off")
    }
}
