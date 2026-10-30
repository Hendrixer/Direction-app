import SwiftUI
import DirectionCore
import DirectionMedia

/// Settings › Engines (specs/settings.md › 54): everything that does the thinking in one place.
/// What this Mac can run and what to use on it, then the editor, transcription, looking at
/// footage, and OpenRouter for what's made and for looking at footage elsewhere.
struct EnginesPane: View {
    var app: AppModel?
    var preview = false
    var body: some View {
        SettingsPane {
            ThisMacGroup(app: app, preview: preview)
            EditorWhoEditsGroup(app: app, preview: preview)
            TranscriptionGroup(preview: preview)
            FootageLookingGroup(preview: preview)
            ServicesGroups(preview: preview)
        }
    }
}

// MARK: This Mac

/// What Settings › Engines knows about this Mac.
struct MacFacts: Equatable, Sendable {
    var chip: String
    var memory: UInt64
    var appleSilicon: Bool
    var freeBytes: Int64
    var volume: String
    var mlxVLM: Bool
    /// Looking-at-footage versions already downloaded, by id.
    var downloaded: Set<String>
    var hasOpenRouterKey: Bool

    static func read() async -> MacFacts {
        await Task.detached(priority: .utility) {
            func sysctl(_ name: String) -> String? {
                var size = 0
                guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
                var buffer = [CChar](repeating: 0, count: size)
                guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
                return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            var arm: Int32 = 0, size = MemoryLayout<Int32>.size
            let appleSilicon = sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1
            return MacFacts(chip: sysctl("machdep.cpu.brand_string") ?? "This Mac", memory: ProcessInfo.processInfo.physicalMemory, appleSilicon: appleSilicon,
                            freeBytes: VisionHelper.freeBytes(), volume: VisionHelper.volumeName(), mlxVLM: VisionHelper.python() != nil,
                            downloaded: Set(SharedSettings.lookDetails.filter { VisionHelper.isDownloaded($0.repo) }.map(\.id)), hasOpenRouterKey: OpenRouter.Key.read() != nil)
        }.value
    }

    /// The snapshots' Mac: the director's.
    static let preview = MacFacts(chip: "Apple M4 Max", memory: 64 << 30, appleSilicon: true, freeBytes: 521_000_000_000, volume: "Macintosh HD", mlxVLM: true, downloaded: ["standard"], hasOpenRouterKey: true)
}

/// What Settings › Engines recommends for a Mac. Pure, so it can be checked for any Mac.
struct EngineAdvice: Equatable {
    var lookEngine: SharedSettings.LookEngine
    /// The local version, when looking happens on this Mac.
    var lookDetail: String?
    var transcription: SharedSettings.TranscriptionEngine
    /// nil keeps what's chosen: your own session, or nothing to run yet.
    var editor: EditorRunsOn?
    /// What the advice needs that isn't on this Mac: name and install command.
    var missing: [Missing]

    struct Missing: Equatable { var name: String; var why: String; var command: String }

    /// Looking at footage: the best local version that fits this Mac's memory and disk (Best is
    /// faster than Standard where it fits, footage-index.md › Speed). OpenRouter only where nothing
    /// local can run. Transcription: Apple, the fastest, and it keeps false starts. The editor: the
    /// chosen program while it's installed, else whichever is.
    static func advise(_ f: MacFacts, editor current: EditorRunsOn, installed: Set<EditorProgram>) -> EngineAdvice {
        var missing: [Missing] = []
        var engine = SharedSettings.LookEngine.thisMac, detail: String?
        if f.appleSilicon {
            let fits = SharedSettings.lookDetails.reversed().filter { f.memory >= $0.minimumMemory }
            let room = fits.first { f.downloaded.contains($0.id) || f.freeBytes >= $0.bytes + 2_000_000_000 }
            if let room { detail = room.id }
            else if f.hasOpenRouterKey { engine = .openRouter }
            else { detail = fits.last?.id ?? "quick" }
            if engine == .thisMac, !f.mlxVLM { missing.append(Missing(name: "mlx-vlm", why: "Looking at footage on this Mac needs it.", command: "uv tool install mlx-vlm")) }
        } else {
            engine = .openRouter
        }
        var editor: EditorRunsOn?
        if current != .yourOwn {
            if let p = current.program, installed.contains(p) { editor = current }
            else if let p = EditorProgram.allCases.first(where: installed.contains) { editor = EditorRunsOn(rawValue: p.rawValue) }
            else { missing.append(Missing(name: "Claude Code", why: "The editor runs in it, or in Codex.", command: EditorProgram.claudeCode.installCommand)) }
        }
        return EngineAdvice(lookEngine: engine, lookDetail: detail, transcription: .apple, editor: editor, missing: missing)
    }

    var lookName: String {
        guard lookEngine == .thisMac else { return "OpenRouter" }
        return SharedSettings.lookDetails.first { $0.id == lookDetail }.map { "\($0.label.components(separatedBy: " \u{00B7} ").first ?? $0.name) (\($0.name))" } ?? "This Mac"
    }
}

/// The first group: the Mac, what it's missing, and what to use on it, with Use Recommended.
/// Nothing changes until the director chooses.
struct ThisMacGroup: View {
    var app: AppModel?
    var preview = false
    @State private var facts: MacFacts?
    @AppStorage(SharedSettings.IndexKey.engine, store: SharedSettings.defaults) private var lookEngine = SharedSettings.LookEngine.thisMac.rawValue
    @AppStorage(SharedSettings.IndexKey.detail, store: SharedSettings.defaults) private var detail = SharedSettings.defaultLookDetail()
    @AppStorage(SharedSettings.Key.transcriptionEngine, store: SharedSettings.defaults) private var transcription = SharedSettings.TranscriptionEngine.apple.rawValue
    private var programs: EditorPrograms { EditorPrograms.shared }

    var body: some View {
        let _ = programs.changes
        SettingsGroup(label: "This Mac", note: AnyView(SettingsNote("Recommended from this Mac\u{2019}s chip, memory, free space and what\u{2019}s installed. Nothing changes until you choose."))) {
            if let facts {
                let advice = EngineAdvice.advise(facts, editor: EditorSetup.runsOn, installed: Set(EditorProgram.allCases.filter { programs.install($0) != nil }))
                SettingsRow(label: facts.chip, detail: "\(facts.memory >> 30) GB memory \u{00B7} \(SystemSupport.bytes(facts.freeBytes)) free on \(facts.volume)", first: true) { EmptyView() }
                ForEach(advice.missing, id: \.name) { m in
                    SettingsRow(label: "\(m.name) isn\u{2019}t installed", detail: m.why) {
                        Button("Copy Command") { SystemSupport.copy(m.command) }.buttonStyle(.gate(.normal))
                    }
                }
                recommendedRow(advice)
            } else {
                SettingsRow(label: "Looking at this Mac\u{2026}", first: true) { GateSpinner() }
            }
        }
        .task { facts = preview ? .preview : await MacFacts.read() }
    }

    private func recommendedRow(_ a: EngineAdvice) -> some View {
        let changes = differences(a)
        // One line a job, each saying what it replaces.
        let lines = ["Looking at footage: \(a.lookName)" + now(changes.look), "Transcription: Apple" + now(changes.transcription), a.editor.map { "Editor: \($0.label)" + now(changes.editor) }].compactMap { $0 }
        return SettingsRow(label: "Recommended", detail: lines.joined(separator: "\n")) {
            if changes.any { Button("Use Recommended") { if !preview { use(a) } }.buttonStyle(.gate(.normal)) }
            else { Chip("In use", style: .ok, mono: false) }
        }
    }

    /// What differs from what's chosen now, as the current choice's name.
    private func differences(_ a: EngineAdvice) -> (look: String?, transcription: String?, editor: String?, any: Bool) {
        let chosenEngine = preview ? "thisMac" : lookEngine, chosenDetail = preview ? "standard" : detail
        var look: String?
        if chosenEngine != a.lookEngine.rawValue || (a.lookEngine == .thisMac && chosenDetail != a.lookDetail) {
            look = chosenEngine == SharedSettings.LookEngine.openRouter.rawValue ? "OpenRouter" : SharedSettings.lookDetails.first { $0.id == chosenDetail }?.label.components(separatedBy: " \u{00B7} ").first
        }
        let words = (preview ? "apple" : transcription) == a.transcription.rawValue ? nil : "Whisper"
        let editor = a.editor.flatMap { $0 == EditorSetup.runsOn ? nil : EditorSetup.runsOn.label }
        return (look, words, editor, look != nil || words != nil || editor != nil)
    }
    private func now(_ current: String?) -> String { current.map { ", instead of \($0)" } ?? "" }

    private func use(_ a: EngineAdvice) {
        lookEngine = a.lookEngine.rawValue
        if let d = a.lookDetail { detail = d }
        transcription = a.transcription.rawValue
        if let e = a.editor, e != EditorSetup.runsOn { EditorSetup.choose(e); app?.film?.refresh(force: true) }
    }
}
