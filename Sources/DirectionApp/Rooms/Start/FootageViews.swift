import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers
import DirectionCore

/// Which files Direction brings in. Originals stay where they are; Settings › Storage can ask for copies.
enum FootageFiles {
    static let video: Set<String> = ["mov", "mp4", "m4v", "mxf", "braw", "r3d"]
    static let sound: Set<String> = ["wav", "aif", "aiff", "m4a", "mp3"]
    static let still: Set<String> = ["jpg", "jpeg", "png"]
    static let script: Set<String> = ["pdf", "fdx", "fountain", "md", "markdown", "txt"]

    /// Files and folders → the footage and sound inside them, sorted by name, and where the director filed
    /// each in scene and setup folders, by path (FootageFolders).
    static func expand(_ urls: [URL]) -> (footage: [URL], scripts: [URL], places: [String: FootagePlace]) {
        var files: [URL] = [], found: [(file: URL, root: URL)] = []
        for url in urls {
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue, url.pathExtension != "direction" {
                let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])?.allObjects as? [URL] ?? []
                files += items; found += items.map { ($0, url) }
            } else { files.append(url) }
        }
        let ext = { (u: URL) in u.pathExtension.lowercased() }
        let footage = files.filter { video.contains(ext($0)) || sound.contains(ext($0)) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let kept = Set(footage.map(\.path))
        // A script is a file dropped on its own: notes and PDFs inside a footage folder aren't one.
        let inFolders = Set(found.map(\.file.path))
        return (footage, files.filter { script.contains(ext($0)) && !inFolders.contains($0.path) }, FootageFolders.places(found.filter { kept.contains($0.file.path) }))
    }

    /// What a drop on a film's window brings: a film to open, footage and sound (folders opened), and scripts.
    /// A still comes in only when it's dropped itself, never from inside a folder (a camera card's thumbnails).
    static func route(_ urls: [URL]) -> FootageDrop {
        let (footage, scripts, places) = expand(urls)
        return FootageDrop(film: urls.first { $0.pathExtension == "direction" }, footage: footage + urls.filter { still.contains($0.pathExtension.lowercased()) }, scripts: scripts, places: places)
    }

    /// Copies a file into a film's Footage folder under its own name, or "Name 2.mov" when that's taken,
    /// never over another file. It's written to `temp` first, so a copy cut short never looks finished.
    /// A copy of the same file already there (same name, size and date) is used instead of a second one.
    static func copy(_ url: URL, into folder: URL, via temp: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        let named = { (n: Int) in n == 1 ? folder.appendingPathComponent(url.lastPathComponent) : folder.appendingPathComponent("\(base) \(n)\(ext)") }
        let source = try fm.attributesOfItem(atPath: url.path)
        var n = 1
        while let there = try? fm.attributesOfItem(atPath: named(n).path) {
            if there[.size] as? NSNumber == source[.size] as? NSNumber, there[.modificationDate] as? Date == source[.modificationDate] as? Date { return named(n) }
            n += 1
        }
        do { try fm.copyItem(at: url, to: temp) } catch { try? fm.removeItem(at: temp); throw error }
        while true {
            do { try fm.moveItem(at: temp, to: named(n)); return named(n) }
            // Taken since it was checked: the next name.
            catch where fm.fileExists(atPath: named(n).path) { n += 1 }
            catch { try? fm.removeItem(at: temp); throw error }
        }
    }

    /// Mounted camera cards and other removable volumes.
    static var cards: [URL] {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []).filter { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return url.path != "/" && (v?.volumeIsRemovable == true || v?.volumeIsEjectable == true)
        }
    }

    @MainActor static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var out: [URL] = []
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { c in _ = p.loadObject(ofClass: URL.self) { url, _ in c.resume(returning: url) } }
            if let url { out.append(url) }
        }
        return out
    }
}

/// A drop on a film's window, sorted by what each file is.
struct FootageDrop: Equatable {
    var film: URL?
    var footage: [URL] = []
    var scripts: [URL] = []
    /// Where the director filed each file in scene and setup folders, by path.
    var places: [String: FootagePlace] = [:]
}

/// Footage on its way into the film's Footage folder: files copied, of how many, and how far the one being copied is.
struct FootageCopying: Equatable {
    var done = 0
    var total = 0
    var current = 0.0
    var fraction: Double { min(1, (Double(done) + current) / Double(max(1, total))) }
}

// MARK: 04 · Bring footage

/// Frame 04: one big drop zone. Choosing starts logging at once; dropping waits a second for more.
struct OnboardingFootageDrop: View {
    @Bindable var model: FilmModel
    @State private var targeted = false
    @State private var dragCount: Int?
    @State private var rejected = false
    @State private var shake: CGFloat = 0

    private var session: OnboardingSession { .of(model) }

    @State private var scriptTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            Text("What are you starting from?").font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary).padding(.top, 6)
            HStack(spacing: 18) {
                scriptZone
                zone
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(28)
        .background(Gate.Surface.ground)
        .onExitCommand { model.sheet = .brief }
    }

    /// A dashed zone that takes a drop, like the rest of the start flow.
    private func dropZone<Content: View>(targeted: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(targeted ? AnyShapeStyle(Gate.Steel.ramp[3]) : AnyShapeStyle(EllipticalGradient(colors: [Gate.Steel.ramp[3], Gate.Surface.sunken], center: UnitPoint(x: 0.5, y: 0.45), startRadiusFraction: 0, endRadiusFraction: 0.6)))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(targeted ? Gate.Text.primary : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: targeted ? [] : [4, 4]))
            content().padding(32)
        }
    }

    /// Before the shoot: a script or a story becomes the A/V script, and footage comes after (specs/script.md).
    /// A dropped file could be either, so Direction asks which before bringing it in.
    private var scriptZone: some View {
        dropZone(targeted: scriptTargeted) {
            VStack(spacing: 18) {
                boards
                Text(scriptTargeted ? "Drop to bring it in" : "A script or a story").font(Gate.Font.brandXL).foregroundStyle(Gate.Text.primary)
                Text("A script is said as written; a story is what happens, with the talking found on the day. The editor lays out what we see and hear, beat by beat, and you plan the shoot from it.")
                    .font(.system(size: 13.5)).foregroundStyle(Gate.Text.tertiary)
                    .multilineTextAlignment(.center).lineSpacing(3.5).frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { model.chooseScript(.script) } label: { HStack(spacing: 6) { Image(systemName: "doc.text"); Text("Choose a script\u{2026}") } }
                        .buttonStyle(.gate(.normal, .large))
                    Button { model.chooseScript(.story) } label: { HStack(spacing: 6) { Image(systemName: "text.book.closed"); Text("Choose a story\u{2026}") } }
                        .buttonStyle(.gate(.normal, .large))
                }
                format("doc.text", "Markdown, text, Fountain, Final Draft, PDF")
            }
        }
        .onDrop(of: [.fileURL], delegate: ScriptDropDelegate(targeted: $scriptTargeted) { urls in bring(urls, wait: true) })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop a script or a story here")
    }

    /// Three drawn boards, fanned like the footage frames: drawings, so the grain stays on them.
    private var boards: some View {
        let spread: CGFloat = scriptTargeted ? 6 : 0
        return ZStack(alignment: .topLeading) {
            board(.wide).rotationEffect(.degrees(-8)).offset(x: -spread, y: 22)
            board(.detail).rotationEffect(.degrees(7)).offset(x: 118 + spread, y: 26)
            board(.close).offset(x: 60, y: 0)
        }
        .frame(width: 210, height: 120, alignment: .topLeading)
        .transformPreference(GrainHolesKey.self) { $0 = [] }
        .animation(gateAnimation(Gate.Motion.settle), value: scriptTargeted)
        .accessibilityHidden(true)
    }
    private func board(_ kind: BoardKind) -> some View {
        BoardView(kind: kind).frame(width: 150, height: 84.375)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.strong, lineWidth: 1))
            .shadow(color: .black.opacity(0.9), radius: 20, y: 10)
    }

    private var zone: some View {
        dropZone(targeted: targeted) {
            VStack(spacing: 18) {
                fan
                Text(title).font(Gate.Font.brandXL).foregroundStyle(Gate.Text.primary)
                Text(message).font(.system(size: 13.5)).foregroundStyle(rejected ? Gate.State.alert : Gate.Text.tertiary)
                    .multilineTextAlignment(.center).lineSpacing(3.5).frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(action: choose) { HStack(spacing: 6) { Image(systemName: "folder"); Text("Choose folder\u{2026}"); KeyHint("\u{21E7}\u{2318}I") } }
                        .buttonStyle(.gate(.normal, .large)).keyboardShortcut("i", modifiers: [.command, .shift])
                    cardMenu
                }
                HStack(spacing: 18) {
                    format("film", "MOV, MP4, MXF, BRAW, R3D")
                    format("waveform", "WAV, synced by its sound")
                }
                .accessibilityElement(children: .combine)
            }
            .offset(x: shake)
        }
        .onDrop(of: [.fileURL], delegate: FootageDropDelegate(targeted: $targeted, count: $dragCount, drop: received))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop footage here")
    }

    private var title: String {
        if targeted { return dragCount.map { "Drop to add \(DailiesFormat.count($0, "file"))" } ?? "Drop to add footage" }
        if !session.pending.isEmpty { return "Adding \(DailiesFormat.count(session.pending.count, "file"))" }
        return "Footage"
    }
    private var message: String {
        if rejected { return "Those aren't video, sound or script files." }
        if !session.pending.isEmpty {
            let scenes = Set(session.pendingPlaces.values.map(\.scene)).count
            return "Logging starts in a moment.\(scenes > 0 ? " Your folders give \(DailiesFormat.count(scenes, "scene"))." : "") Drop more to add them too."
        }
        return "Drop a folder, a camera card or loose files. The editor logs every take, transcribes the dialogue and sorts it into scenes, or keeps the scene folders you made. Your files stay where they are."
    }

    /// Three fanned frames: they spread a little while something is dragged over.
    private var fan: some View {
        let spread: CGFloat = targeted ? 6 : 0
        return ZStack(alignment: .topLeading) {
            card(.night).rotationEffect(.degrees(-8)).offset(x: -spread, y: 22)
            card(.room).rotationEffect(.degrees(7)).offset(x: 118 + spread, y: 26)
            card(.dusk).offset(x: 60, y: 0)
        }
        .frame(width: 210, height: 120, alignment: .topLeading)
        // Pictures cut themselves out of the grain as straight boxes; these tilt, and they're only art.
        .transformPreference(GrainHolesKey.self) { $0 = [] }
        .animation(gateAnimation(Gate.Motion.settle), value: targeted)
        .accessibilityHidden(true)
    }
    private func card(_ art: FootageArt) -> some View {
        FootageArtView(art: art).frame(width: 150, height: 84.375).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.strong, lineWidth: 1))
            .shadow(color: .black.opacity(0.9), radius: 20, y: 10)
    }

    private var cardMenu: some View {
        let cards = FootageFiles.cards
        return Menu {
            ForEach(cards, id: \.self) { url in Button(FileManager.default.displayName(atPath: url.path)) { bring([url], wait: false) } }
        } label: {
            HStack(spacing: 6) { Image(systemName: "externaldrive"); Text("From a camera card") }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                .padding(.horizontal, 16).frame(height: Gate.Size.controlLarge).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .disabled(cards.isEmpty).opacity(cards.isEmpty && !model.isPreview ? 0.4 : 1)
        .help(cards.isEmpty ? "No camera card connected" : "Bring footage from a camera card")
    }

    private func format(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 10)); Text(text) }.font(Gate.Font.small).foregroundStyle(Gate.Text.disabled)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.plaintext").font(.system(size: 12)).foregroundStyle(Gate.Text.disabled)
            Text("Brief saved. \u{201C}\(Self.firstSentences(model.brief.feeling))\u{201D}").lineLimit(1)
            Button("Edit brief") { model.sheet = .brief }.buttonStyle(.gate(.ghost, .small))
            Spacer(minLength: 12)
            Text(UserDefaults.standard.string(forKey: SettingsKey.footageImport) == "copy" ? "Copies go in the film. Your originals stay where they are." : "Nothing is moved or copied.").lineLimit(1)
        }
        .font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
        .frame(height: 22)
    }

    /// "Tired, then proud. Quiet, not triumphant." from a longer feeling.
    static func firstSentences(_ text: String, _ n: Int = 2) -> String {
        var out = "", count = 0
        for c in text { out.append(c); if ".?!".contains(c) { count += 1; if count == n { break } } }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private func choose() {
        let panel = NSOpenPanel(); panel.title = "Bring footage"; panel.prompt = "Bring"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        bring(panel.urls, wait: false)
    }

    private func received(_ urls: [URL]) { bring(urls, wait: true) }

    /// A script or a story dropped on either zone comes in as whichever the director says it is; footage
    /// dropped on the script zone is footage.
    private func bring(_ urls: [URL], wait: Bool) {
        let (footage, scripts, places) = FootageFiles.expand(urls)
        guard !footage.isEmpty else {
            rejected = scripts.isEmpty
            if let script = scripts.first { if !model.isPreview, let kind = FilmModel.askKind(script) { model.bringScript(script, as: kind) } } else { shakeOnce() }
            return
        }
        rejected = false
        session.add(footage, places: places, wait: wait)
    }

    private func shakeOnce() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        Task {
            for x in [4.0, -4, 4, -4, 0] { withAnimation(Gate.Motion.snap) { shake = x }; try? await Task.sleep(for: .milliseconds(60)) }
        }
    }
}

/// Counts what's being dragged (folders included) so the title can say how many files will come in.
private struct FootageDropDelegate: DropDelegate {
    @Binding var targeted: Bool
    @Binding var count: Int?
    var drop: ([URL]) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) {
        targeted = true; count = nil
        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in
            let urls = await FootageFiles.urls(from: providers)
            if targeted { count = FootageFiles.expand(urls).footage.count }
        }
    }
    func dropExited(info: DropInfo) { targeted = false }
    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in drop(await FootageFiles.urls(from: providers)) }
        return true
    }
}

/// A drop on the script zone.
private struct ScriptDropDelegate: DropDelegate {
    @Binding var targeted: Bool
    var drop: ([URL]) -> Void
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false }
    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in drop(await FootageFiles.urls(from: providers)) }
        return true
    }
}

// MARK: 05 · Logging footage

/// One file in the logging table.
struct LoggingRow: Identifiable {
    enum Status { case needsYou(String, sound: Bool), working(String, Double?), done(String), queued }
    var asset: MediaAsset
    var info: TakeInfo?
    var status: Status
    /// A dropped file not in the film yet: listed from the moment it's dropped, with nothing to do to it.
    var arriving = false
    var id: String { asset.id }
    var rank: Int { switch status { case .needsYou: 0; case .working: 1; case .done: 2; case .queued: 3 } }
}

extension FilmModel {
    /// Every file with where the editor is on it: problems first, then in progress, done, queued.
    /// Progress is real where it's known (shots described, an estimate from how fast Whisper has run
    /// on this Mac); elsewhere the row says how long it's been, never a bar that only loops.
    var loggingRows: [LoggingRow] {
        let assets = footage
        let byAsset = Dictionary(grouping: transcripts, by: \.assetID)
        let transcribed = Set(transcripts.filter { !$0.words.isEmpty }.map(\.assetID))
        let running = jobs.filter { !$0.isTerminal && $0.kind == "transcription" }
        let editorActive = editorStatus.map { Date().timeIntervalSince1970 - $0.updatedAt < 120 } ?? false
        let now = Date().timeIntervalSince1970, rate = transcriptionRate
        let logging = runs.runs.last { $0.job == .logFootage && $0.state.isActive }
        var rows: [LoggingRow] = []
        for a in assets {
            let info = dailies.takes[a.id]
            let flags = info?.flags.map { $0.lowercased() } ?? []
            if flags.contains(where: { $0.contains("unreadable") || $0.contains("damaged") }), info?.unusable != true {
                rows.append(.init(asset: a, info: info, status: .needsYou("Can't read this file. It may be damaged.", sound: false))); continue
            }
            if !a.video.isEmpty && a.audio.isEmpty && (info == nil || flags.contains { $0.contains("no audio") }) && info?.unusable != true {
                rows.append(.init(asset: a, info: info, status: .needsYou("No audio. Separate sound file?", sound: true))); continue
            }
            if let job = running.first(where: { $0.assetID == a.id }) {
                if job.phase.hasPrefix("Downloading") { rows.append(.init(asset: a, info: info, status: .working("Downloading the Whisper model \u{00B7} " + Self.clock(now - job.createdAt), nil))); continue }
                let expected = max(2, a.duration.seconds / rate), elapsed = now - job.createdAt
                let left = expected - elapsed
                rows.append(.init(asset: a, info: info, status: .working(left > 1 ? "Transcribing \u{00B7} about \(Self.clock(left)) left" : "Transcribing \u{00B7} almost done", min(0.97, elapsed / expected)))); continue
            }
            if let info, info.isLogged {
                let line = Self.dailiesLines(byAsset[a.id] ?? []).first { !$0.direction }
                let done = line.map { "\u{201C}\(Self.clip($0.text))\u{201D}" } ?? (["No dialogue"] + info.flags.prefix(1).map { $0.lowercased() }).joined(separator: " \u{00B7} ")
                rows.append(.init(asset: a, info: info, status: .done(done))); continue
            }
            if let t = index.takes[a.id], t.state == .looking {
                if t.step == "describing", t.shotCount > 0 {
                    rows.append(.init(asset: a, info: nil, status: .working("Describing \(min(t.described, t.shotCount)) of \(DailiesFormat.count(t.shotCount, "shot"))", Double(t.described) / Double(t.shotCount)))); continue
                }
                rows.append(.init(asset: a, info: nil, status: .working(t.step == "shots" ? "Finding shots" : t.step == "text" ? "Reading the screen" : "Looking", nil))); continue
            }
            if let run = logging, run.assetIDs?.contains(a.id) ?? true {
                rows.append(.init(asset: a, info: nil, status: .working("Logging \u{00B7} " + Self.clock(now - (run.startedAt ?? run.createdAt)), nil))); continue
            }
            if transcribed.contains(a.id) || index.readyToLog(a) { rows.append(.init(asset: a, info: nil, status: .working("Ready to log", nil))); continue }
            rows.append(.init(asset: a, info: nil, status: .queued))
        }
        // Files still coming in, in the order they come: the first is being brought in (or copied), the rest wait.
        for (i, url) in arrivingFootage.enumerated() {
            let file = MediaAsset(id: "arriving:" + url.path, name: url.lastPathComponent, path: url.path, duration: .zero)
            let status: LoggingRow.Status = i > 0 ? .queued : copyingFootage.map { .working("Copying into the film", $0.current) } ?? .working("Bringing in", nil)
            rows.append(.init(asset: file, info: nil, status: status, arriving: true))
        }
        // With the editor active but nothing visibly running, the first queued file is the one it's on.
        if editorActive, !rows.contains(where: { if case .working = $0.status { true } else { false } }), let i = rows.firstIndex(where: { if case .queued = $0.status { !$0.arriving } else { false } }) {
            rows[i].status = .working("Logging", nil)
        }
        return rows.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
    }

    /// Dropped files that aren't takes in the film yet.
    var arrivingFootage: [URL] {
        let paths = Set(project?.assets.map(\.path) ?? [])
        return incomingFootage.filter { !paths.contains($0.path) }
    }

    /// Seconds of audio Whisper gets through per second on this Mac, from this film's finished jobs.
    var transcriptionRate: Double {
        let rates = jobs.filter { $0.kind == "transcription" && $0.status == "completed" }.compactMap { j -> Double? in
            guard let id = j.assetID, let a = asset(id), j.updatedAt > j.createdAt else { return nil }
            return a.duration.seconds / (j.updatedAt - j.createdAt)
        }.sorted()
        return rates.isEmpty ? 15 : rates[rates.count / 2]
    }

    /// When this footage started coming in, and when logging finished, for "3:35 so far".
    var loggingStartedAt: Double? { jobs.filter { ["index", "transcription", "sync"].contains($0.kind) }.map(\.createdAt).min() }
    var loggingFinishedAt: Double? { isLogging ? nil : runs.runs.filter { $0.job == .logFootage }.compactMap(\.endedAt).max() }

    static func clock(_ seconds: Double) -> String { let s = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", s / 60, s % 60) }

    /// The stage line under the progress (footage-index.md › 05): the latest of Reading → Finding
    /// shots → Looking at footage → Listening → Sorting into scenes to have started. Counts in SF Mono.
    var loggingStage: (text: Text, spoken: String)? {
        func line(_ words: String, _ n: Int? = nil, _ of: Int? = nil) -> (Text, String) {
            guard let n, let of else { return (Text(words), words) }
            let mono = { (v: Int) in Text(String(v)).font(.system(size: 11.5, design: .monospaced)) }
            return (Text("\(words) \u{00B7} ") + mono(n) + Text(" of ") + mono(of), "\(words), \(n) of \(of)")
        }
        if let c = copyingFootage { return line("Copying into the film", min(c.total, c.done + 1), c.total) }
        let assets = footage.filter { !$0.isImage }
        guard !assets.isEmpty else { return nil }
        if loggedCount > 0 || !dailies.scenes.isEmpty { return line("Sorting into scenes") }
        let speaking = assets.filter { !$0.audio.isEmpty }
        let transcribed = Set(transcripts.filter { !$0.words.isEmpty }.map(\.assetID))
        if !transcribed.isEmpty || jobs.contains(where: { $0.kind == "transcription" && !$0.isTerminal }) { return line("Listening", speaking.filter { transcribed.contains($0.id) }.count, speaking.count) }
        let takes = index.takes.values
        if takes.contains(where: { $0.step == "describing" || $0.described > 0 }) { return line("Looking at footage", index.states.values.filter { $0 == .done }.count, assets.count) }
        if index.job != nil || takes.contains(where: { $0.shotCount > 0 }) { return line("Finding shots") }
        return line("Reading \(DailiesFormat.count(assets.count, "take"))")
    }

    static func clip(_ s: String, _ n: Int = 48) -> String { s.count > n ? String(s.prefix(n)).trimmingCharacters(in: .whitespaces) + "\u{2026}" : s }

    /// "About 6 minutes left." from how fast the editor has logged so far.
    var loggingEstimate: String? {
        let total = footage.count, logged = loggedCount
        guard logged > 0, logged < total else { return nil }
        let logEvents = events.filter { $0.kind == "dailies.updated" && $0.summary.contains("logged") }
        guard let first = logEvents.map(\.createdAt).min() else { return nil }
        let elapsed = Date().timeIntervalSince1970 - first
        guard elapsed > 10 else { return nil }
        let minutes = Int((Double(total - logged) * elapsed / Double(logged) / 60).rounded())
        return minutes < 1 ? "Almost done." : minutes == 1 ? "About a minute left." : "About \(minutes) minutes left."
    }
}

/// Frame 05: the editor logs, transcribes and sorts every take. You can start circling once a scene exists.
struct OnboardingLoggingView: View {
    @Bindable var model: FilmModel
    @Environment(\.dailiesPreview) private var preview
    @State private var selection: String?
    @State private var quickLook: URL?
    @FocusState private var focused: Bool

    var body: some View {
        let rows = model.loggingRows
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                summary(rows)
                GeometryReader { g in
                    let widths = columns(g.size.width)
                    VStack(spacing: 0) {
                        header(widths)
                        ScrollView {
                            // Elapsed times and estimates move once a second.
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                LazyVStack(spacing: 0) { ForEach(model.loggingRows) { row($0, widths) } }
                            }
                        }
                        .scrollIndicators(.automatic)
                    }
                }
            }
            .background(Gate.Surface.ground)
            aside.frame(width: 360)
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onMoveCommand { d in
            guard d == .up || d == .down, !rows.isEmpty else { return }
            let i = selection.flatMap { id in rows.firstIndex { $0.id == id } } ?? -1
            selection = rows[max(0, min(rows.count - 1, i + (d == .down ? 1 : -1)))].id
        }
        .onKeyPress(.space) {
            guard !TextInput.hasFocus, let id = selection, let a = model.asset(id) else { return .ignored }
            quickLook = URL(fileURLWithPath: a.path); return .handled
        }
        .quickLookPreview($quickLook)
        .onDisappear {
            // Logging finished while it was on screen: say so once, on the way to Dailies.
            guard model.hasFootage, !model.isLogging, !model.onboardingDismissed, !model.isPreview else { return }
            model.toast = Toast(title: "\(DailiesFormat.count(model.footage.count, "take")) logged.", detail: "\(DailiesFormat.count(model.dailies.scenes.count, "scene")), \(model.dailiesUnsorted.count) unsorted.", editor: true)
        }
    }

    // MARK: Summary

    private func summary(_ rows: [LoggingRow]) -> some View {
        // Not finished while files are still coming in: a copy can take minutes before its take exists.
        let total = model.footage.count + model.arrivingFootage.count, logged = model.loggedCount, finished = !model.isLogging && model.importingFootage == 0
        let seconds = model.dailiesTotalSeconds
        let loggedSeconds = model.footage.filter { model.dailies.isLogged($0.id) }.reduce(0) { $0 + $1.duration.seconds }
        let problems = rows.filter { if case .needsYou = $0.status { true } else { false } }.count
        let fraction = total > 0 ? Double(logged) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(finished ? "Footage logged" : "Logging footage").font(Gate.Font.brand(size: 28, width: 122)).foregroundStyle(Gate.Text.primary)
                if let start = model.loggingStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let end = model.loggingFinishedAt ?? context.date.timeIntervalSince1970
                        Text(finished ? "in \(FilmModel.clock(end - start))" : "\(FilmModel.clock(end - start)) so far")
                            .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.secondary)
                    }
                    .accessibilityLabel(finished ? "Took \(FilmModel.clock((model.loggingFinishedAt ?? 0) - start))" : "Elapsed")
                }
                Text(finished ? "Every take is in Dailies." : ([model.loggingEstimate, model.dailies.scenes.isEmpty ? nil : "You can start circling takes now."].compactMap { $0 }.joined(separator: " "))).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            if !finished { LoggingBar(value: fraction).frame(height: 5).accessibilityLabel("Logged").accessibilityValue("\(Int(fraction * 100)) percent") }
            if !finished, let stage = model.loggingStage { stage.text.font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).padding(.top, -6).accessibilityLabel(stage.spoken) }
            HStack(alignment: .top, spacing: 28) {
                stat("\(logged) / \(total)", "takes logged")
                stat(DailiesFormat.hoursMinutes(loggedSeconds), "of \(DailiesFormat.hoursMinutes(seconds))")
                stat(String(Set(model.transcripts.filter { !$0.words.isEmpty }.map(\.assetID)).count), "transcribed")
                stat(String(model.dailies.scenes.count), "scenes found")
                stat(String(problems), "need you", alert: problems > 0)
            }
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBorder(.bottom)
    }

    private func stat(_ value: String, _ label: String, alert: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(alert ? Gate.State.alert : Gate.Text.primary)
            Text(label).font(.system(size: 12.5)).foregroundStyle(alert ? Gate.State.alert : Gate.Text.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Table

    private struct Widths { var file: CGFloat; var status: CGFloat }
    /// 22 · 72 · file · 64 · 150 · status, 14 pt gaps; file and status share what's left 1 : 1.5.
    private func columns(_ width: CGFloat) -> Widths {
        let flex = max(200, width - 48 - (22 + 72 + 64 + 150) - 5 * 14)
        return Widths(file: flex / 2.5, status: flex * 1.5 / 2.5)
    }

    private func header(_ w: Widths) -> some View {
        HStack(spacing: 14) {
            Color.clear.frame(width: 22)
            SectionLabel("Take").frame(width: 72, alignment: .leading)
            SectionLabel("File").frame(width: w.file, alignment: .leading)
            SectionLabel("Duration").frame(width: 64, alignment: .leading)
            SectionLabel("Scene").frame(width: 150, alignment: .leading)
            SectionLabel("Status").frame(width: w.status, alignment: .leading)
        }
        .padding(.horizontal, 24).frame(height: 32, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairlineBorder(.bottom)
        .accessibilityHidden(true)
    }

    private func row(_ r: LoggingRow, _ w: Widths) -> some View {
        let queued: Bool = { if case .queued = r.status { true } else { false } }()
        let scene = model.scene(r.info?.sceneID)
        let setup = scene?.setups.first { $0.code == r.info?.setupCode }
        let sub: String = {
            if let info = r.info, info.code != nil || info.setupCode != nil { return ([model.dailiesLabel(info)] + [setup?.description].compactMap { $0 }).joined(separator: " \u{00B7} ") }
            if case .needsYou(_, false) = r.status { return "Unreadable" }
            if r.arriving { return queued ? "Coming in" : "Coming in now" }
            return queued ? "Waiting" : "Logging"
        }()
        return HStack(spacing: 14) {
            Group {
                switch r.status {
                case .needsYou: Image(systemName: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(Gate.State.alert)
                case .working: GateSpinner()
                case .done: Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gate.State.approve)
                case .queued: Color.clear
                }
            }
            .frame(width: 22)
            DailiesTakeThumb(asset: r.asset, art: preview.art[r.id] ?? model.dailiesArt(r.id), preview: model.isPreview)
                .frame(width: 72, height: 40).clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle, lineWidth: 1))
                .opacity(queued ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.asset.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled).lineLimit(1)
            }
            .frame(width: w.file, alignment: .leading)
            Text(r.asset.duration.seconds > 0 ? Timecode.duration(r.asset.duration.seconds) : "\u{2014}").font(.system(size: 12.5, design: .monospaced)).frame(width: 64, alignment: .leading)
            Text(scene?.label ?? "\u{2014}").font(Gate.Font.small).foregroundStyle(queued ? Gate.Text.disabled : Gate.Text.tertiary).lineLimit(1).frame(width: 150, alignment: .leading)
            status(r).frame(width: w.status, alignment: .leading)
        }
        .foregroundStyle(queued ? Gate.Text.disabled : Gate.Text.primary)
        .padding(.horizontal, 24).frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selection == r.id ? Gate.Surface.panel : .clear)
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .onTapGesture { selection = r.id; focused = true }
        .contextMenu {
            if r.arriving {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.asset.path)]) }
                Button("Preview") { quickLook = URL(fileURLWithPath: r.asset.path) }
            } else {
                Button("Show in Finder") { model.revealTakes([r.id]) }
                Button("Preview") { quickLook = URL(fileURLWithPath: r.asset.path) }
                Divider()
                Button("Skip") { model.setUnusable(r.id, true) }
                Button(r.info?.unusable == true ? "Mark Usable" : "Mark Not Usable") { model.setUnusable(r.id, !(r.info?.unusable ?? false)) }
                Menu("Assign to Scene") { ForEach(model.scenes) { s in Button(s.label) { model.moveTake(r.id, to: s.id) } } }.disabled(model.scenes.isEmpty)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selection == r.id ? .isSelected : [])
    }

    @ViewBuilder private func status(_ r: LoggingRow) -> some View {
        switch r.status {
        case .needsYou(let text, let sound):
            HStack(spacing: 8) {
                Text(text).foregroundStyle(Gate.State.alert).lineLimit(1)
                if sound { Button("Find sound\u{2026}") { findSound() }.buttonStyle(.gate(.normal, .small)).padding(.leading, 4) }
                else { Button("Skip") { model.setUnusable(r.id, true) }.buttonStyle(.gate(.ghost, .small)).padding(.leading, 4) }
            }
            .font(.system(size: 12.5))
        case .working(let step, let progress):
            HStack(spacing: 8) {
                // A bar only when there's real progress to show; the spinner on the left says it's working.
                if let progress { GateProgress(value: progress, agent: true).frame(width: 80) }
                Text(step).foregroundStyle(Gate.Text.tertiary).monospacedDigit()
            }
            .font(.system(size: 12.5))
            .accessibilityLabel(progress.map { "\(step), \(Int($0 * 100)) percent" } ?? step)
        case .done(let text): Text(text).font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
        case .queued: Text("Queued").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
        }
    }

    private func findSound() {
        let panel = NSOpenPanel(); panel.title = "Find sound"; panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        model.importFootage(panel.urls)
    }

    // MARK: Aside

    private var aside: some View {
        let scenes = model.scenes
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DailiesEditorLabel(text: "What the editor is finding")
                DailiesSayLine(text: findingLine(scenes.count))
                ForEach(scenes) { s in sceneRow(s) }
                Hairline()
                DailiesSayLine(text: "No script found. I'll build one from the transcript for the Script room.")
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
        }
        .frame(maxHeight: .infinity)
        .background(Gate.Surface.sunken)
        .hairlineBorder(.leading)
    }

    /// The editor's own words when it has posted them; otherwise a plain count.
    private func findingLine(_ count: Int) -> String {
        if let detail = model.editorStatus?.detail, !detail.isEmpty { return detail }
        guard count > 0 else { return "Nothing placed yet. I'm reading the footage first." }
        let words = NumberFormatter.localizedString(from: NSNumber(value: count), number: .spellOut).capitalized
        return "\(words) \(count == 1 ? "scene" : "scenes") so far. Rename or merge them in Dailies."
    }

    private func sceneRow(_ s: DailiesScene) -> some View {
        let takes = model.dailiesTakes(inScene: s.id)
        let setups = Set(takes.compactMap(\.setupCode)).count
        let speaking = takes.filter { !(model.asset($0.assetID)?.audio.isEmpty ?? true) }
        let transcribed = !speaking.isEmpty && speaking.allSatisfy { model.dailiesIsTranscribed($0.assetID) }
        let meta = takes.isEmpty ? "Still logging" : ([DailiesFormat.count(setups, "setup"), DailiesFormat.count(takes.count, "take")] + (transcribed ? ["transcribed"] : [])).joined(separator: " \u{00B7} ")
        return Button { model.openDailiesFromLogging(scene: s.id) } label: {
            HStack(spacing: 12) {
                DailiesTakeThumb(asset: takes.first.flatMap { model.asset($0.assetID) }, art: FootageArt.forScene(s.number), preview: model.isPreview)
                    .frame(width: 52, height: 30).clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.label).font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.primary)
                    Text(meta).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(takes.isEmpty ? 0.45 : 1)
        .disabled(takes.isEmpty)
        .help("Open \(s.label) in Dailies")
    }
}

/// The 5 pt prism progress line. A highlight passes along it while the editor works.
private struct LoggingBar: View {
    var value: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width * max(0, min(1, value))
            ZStack(alignment: .leading) {
                Capsule().fill(Gate.Surface.hover)
                Capsule().fill(Gate.Voice.prism).frame(width: w)
                    .overlay {
                        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Gate.Motion.shimmerPeriod) / Gate.Motion.shimmerPeriod
                                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 120).offset(x: (w + 120) * t - 120)
                            }
                            .frame(width: w, alignment: .leading).clipShape(Capsule())
                        }
                    }
            }
        }
    }
}
