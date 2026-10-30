import SwiftUI
import DirectionCore
import DirectionMedia

/// Settings › Footage › Looking at footage (frame 54, specs/settings.md › 54). Stored in the
/// shared suite, so the editor's tools index the way the director chose.
struct FootageLookingGroup: View {
    var preview = false
    @AppStorage(SharedSettings.IndexKey.engine, store: SharedSettings.defaults) private var engine = SharedSettings.LookEngine.thisMac.rawValue
    @AppStorage(SharedSettings.IndexKey.detail, store: SharedSettings.defaults) private var detail = "standard"
    @AppStorage(SharedSettings.IndexKey.openRouterVersion, store: SharedSettings.defaults) private var version = SharedSettings.lookOpenRouterVersions[0].id
    @AppStorage(SharedSettings.IndexKey.automatic, store: SharedSettings.defaults) private var automatic = true
    @State private var setup: Setup = .checking
    @State private var status: VisionHelper.Status?
    @State private var room = true
    @State private var hasKey = false
    private var downloads = VisionDownloads.shared

    enum Setup: Equatable { case checking, noMLX, ready }

    private var onMac: Bool { (preview ? SharedSettings.LookEngine.thisMac.rawValue : engine) == SharedSettings.LookEngine.thisMac.rawValue }
    private var chosen: SharedSettings.LookDetail { SharedSettings.lookDetails.first { $0.id == (preview ? "standard" : detail) } ?? SharedSettings.lookDetails[1] }

    var body: some View {
        SettingsGroup(label: "Looking at footage", note: AnyView(SettingsNote("The editor reads what\u{2019}s found here to log takes, and you can search it in Dailies with \u{2318}F."))) {
            SettingsRow(label: "Look with", detail: onMac ? "Private and free. Footage never leaves this Mac." : "Sends three small frames of each shot to a vision version through OpenRouter. Needs your key in Services.", first: true) {
                GateSegmented(options: [(SharedSettings.LookEngine.thisMac.rawValue, "This Mac"), (SharedSettings.LookEngine.openRouter.rawValue, "OpenRouter")], selection: preview ? .constant(SharedSettings.LookEngine.thisMac.rawValue) : $engine)
            }
            if onMac { localRow } else { openRouterRow }
            SettingsRow(label: "Look at new footage automatically") { GateSwitch(isOn: preview ? .constant(true) : $automatic) }
        }
        .task(id: "\(engine)|\(detail)|\(downloads.progress[chosen.id] == nil)") { await check() }
        // The index may download a version on first use while Settings is open; look again on return.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await check() } }
    }

    // MARK: This Mac

    @ViewBuilder private var localRow: some View {
        if setup == .noMLX {
            SettingsRow(label: "mlx-vlm isn\u{2019}t installed", detail: "Install it in Terminal with uv tool install mlx-vlm. Until then, nothing is described; shots and sounds are still found.") {
                Button("Copy Command") { SystemSupport.copy("uv tool install mlx-vlm") }.buttonStyle(.gate(.normal))
            }
        } else {
            SettingsRow(label: "Detail", detail: localDetail) {
                if !preview, case .notDownloaded = localState {
                    Button("Download") { downloads.start(chosen) }.buttonStyle(.gate(.normal)).help("Download \(chosen.name) now instead of the first time footage is looked at")
                }
                if !preview, case .noRoom = localState, chosen.id != "quick" {
                    Button("Use Quick") { detail = "quick" }.buttonStyle(.gate(.normal))
                }
                GateSelect(options: SharedSettings.lookDetails.map { ($0.id, $0.label) }, selection: preview ? .constant("standard") : $detail)
            }
            .contextMenu {
                if downloads.progress[chosen.id] != nil { Button("Cancel Download") { downloads.cancel(chosen) } }
            }
        }
    }

    enum LocalState { case checking, downloaded, notDownloaded, downloading(Double), noRoom, needsMemory }
    private var localState: LocalState {
        if preview { return .downloaded }
        if let p = downloads.progress[chosen.id] { return .downloading(p) }
        switch status {
        case .needsMemory?: return .needsMemory
        case .downloaded?: return .downloaded
        case nil: return .checking
        case .noPython?, .notDownloaded?: return room ? .notDownloaded : .noRoom
        }
    }
    private var localDetail: String {
        switch localState {
        case .checking: return "\(chosen.name)."
        case .downloaded: return "\(chosen.name). Downloaded."
        case .notDownloaded: return "\(chosen.name). Downloads \(sizeWord) the first time it\u{2019}s used."
        case .downloading(let p): return "\(chosen.name). Downloading \u{00B7} \(Int(p * 100))%."
        case .noRoom: return "Only \(ByteCountFormatter.string(fromByteCount: VisionHelper.freeBytes(), countStyle: .file)) free on \(VisionHelper.volumeName()). \(chosenTitle) needs \(sizeWord)."
        case .needsMemory: return "\(chosen.name) needs \(chosen.minimumMemory >> 30) GB of memory or more."
        }
    }
    /// "5.8 GB" from the select's own label, so the row and the menu agree.
    private var sizeWord: String { chosen.label.components(separatedBy: " \u{00B7} ").last ?? "" }
    private var chosenTitle: String { chosen.label.components(separatedBy: " \u{00B7} ").first ?? chosen.name }

    // MARK: OpenRouter

    private var openRouterRow: some View {
        let name = SharedSettings.lookOpenRouterVersions.first { $0.id == version }?.name ?? version
        return SettingsRow(label: "Detail", detail: hasKey ? "\(name) through OpenRouter." : "\(name) through OpenRouter. Add your key in Services first.") {
            GateSelect(options: SharedSettings.lookOpenRouterVersions.map { ($0.id, $0.name) }, selection: $version)
        }
    }

    private func check() async {
        if preview { setup = .ready; return }
        let detail = chosen
        let (python, key, state, fits) = await Task.detached {
            VisionHelper.forget()
            return (VisionHelper.python() != nil, OpenRouter.Key.read() != nil, VisionHelper.status(detail), VisionHelper.hasRoom(for: detail))
        }.value
        setup = python ? .ready : .noMLX
        hasKey = key; status = state; room = fits
    }
}

/// Weight downloads started from Settings, with their progress, cancellable from the row.
@MainActor @Observable final class VisionDownloads {
    static let shared = VisionDownloads()
    var progress: [String: Double] = [:]
    var failure: [String: String] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    func start(_ detail: SharedSettings.LookDetail) {
        guard tasks[detail.id] == nil else { return }
        progress[detail.id] = 0; failure[detail.id] = nil
        tasks[detail.id] = Task {
            do {
                try await VisionHelper.download(detail) { p in Task { @MainActor in if VisionDownloads.shared.progress[detail.id] != nil { VisionDownloads.shared.progress[detail.id] = p } } }
            } catch is CancellationError {} catch { failure[detail.id] = error.localizedDescription }
            progress[detail.id] = nil; tasks[detail.id] = nil
        }
    }
    func cancel(_ detail: SharedSettings.LookDetail) { tasks[detail.id]?.cancel() }
}
