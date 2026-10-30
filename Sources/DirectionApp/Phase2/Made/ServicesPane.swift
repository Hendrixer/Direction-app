import SwiftUI
import AppKit
import DirectionCore

/// Settings › Engines › OpenRouter (specs/settings.md › 54): the key, the version for each kind,
/// and the director's spend limits. Limits and versions live in the shared suite so the editor's tools follow them.
struct ServicesGroups: View {
    var preview = false
    @State private var state = ServicesState()
    @AppStorage(SharedSettings.SpendKey.askAbove, store: SharedSettings.defaults) private var askAbove = 5.0
    @AppStorage(SharedSettings.SpendKey.stopAt, store: SharedSettings.defaults) private var stopAt = 50.0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup(label: "OpenRouter", note: AnyView(SettingsNote("Your key is kept in your Mac\u{2019}s keychain. The editor never sees it; Direction makes every request."))) { keyRow }
            SettingsGroup(label: "What the editor uses", note: AnyView(SettingsNote("Slow motion and sharpening happen on this Mac and cost nothing."))) {
                versionRow(.music, "Music", first: true)
                versionRow(.voice, "Voice")
                versionRow(.shot, "New shots")
                    .help("Extended shots and bridges use this version too. Frames of your takes are sent to OpenRouter, so they leave this Mac.")
                versionRow(.changedShot, "Changed shots")
                    .help("The take\u{2019}s range itself is sent to OpenRouter, so it leaves this Mac.")
                versionRow(.still, "Stills")
            }
            SettingsGroup(label: "Spending", note: AnyView(SettingsNote("Check each version\u{2019}s terms on OpenRouter before you release a film. Some don\u{2019}t cover film or TV."))) {
                SettingsRow(label: "Ask before spending more than", detail: "The editor prices each turnover\u{2019}s plan first, and asks only when it goes over.", first: true) {
                    GateSelect(options: SharedSettings.askAboveChoices.map { ($0, MadeFormat.money($0) + " per turnover") }, selection: limit($askAbove, preview: 5))
                }
                SettingsRow(label: "Stop for the month at") {
                    GateSelect(options: SharedSettings.stopAtChoices.map { ($0, $0 > 0 ? MadeFormat.money($0) : "No limit") }, selection: limit($stopAt, preview: 50))
                }
                SpendMeterRow(entries: state.entries, cap: preview ? 50 : (stopAt > 0 ? stopAt : nil))
            }
        }
        .task { await state.load(preview: preview) }
        .task(id: preview) {
            // The editor spends from its own process; keep the meter current while the pane is open.
            guard !preview else { return }
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(5)); state.entries = SpendLedger.entries() }
        }
    }

    /// Snapshots show the defaults and never write the shared suite.
    private func limit(_ stored: Binding<Double>, preview value: Double) -> Binding<Double> {
        preview ? .constant(value) : stored
    }

    // MARK: The key

    private var keyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("O").font(.system(size: 12, weight: .bold)).foregroundStyle(Gate.Text.secondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: Gate.Radius.control).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.subtle, lineWidth: 1)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenRouter").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                    Text(subLabel).font(.system(size: 11.5)).foregroundStyle(failing ? Gate.State.alert : Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { keyControl }.fixedSize()
            }
            if state.editing { editor.transition(.opacity) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Replace Key\u{2026}") { state.beginEditing() }
            Button("Remove Key") { state.remove() }.disabled(state.key == .notSet)
            Divider()
            Button("Show Credits") { NSWorkspace.shared.open(URL(string: "https://openrouter.ai/credits")!) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("OpenRouter")
    }

    private var failing: Bool { if case .failing = state.key, !state.editing { return true }; return false }
    private var subLabel: String {
        if case .failing(let why) = state.key, !state.editing { return "That key didn\u{2019}t work: \(why)" }
        return "Music, voice, sound effects, shots and stills"
    }

    @ViewBuilder private var keyControl: some View {
        if state.editing {
            Button { NSWorkspace.shared.open(URL(string: "https://openrouter.ai/keys")!) } label: {
                HStack(spacing: 4) { Text("Get a key").foregroundStyle(Gate.Text.secondary); Image(systemName: "arrow.up.right.square").font(.system(size: 10, weight: .medium)).foregroundStyle(Gate.Text.tertiary) }
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain).help("Opens openrouter.ai/keys")
        } else {
            switch state.key {
            case .checking: GateSpinner()
            case .ready(let left):
                if let left { Text("\(MadeFormat.money(left)) left").font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary) }
                Chip("Ready", style: .ok, mono: false)
            case .notSet:
                Button { state.beginEditing() } label: { Label("Add Key\u{2026}", systemImage: "key") }.buttonStyle(.gate)
            case .failing:
                Button("Replace Key\u{2026}") { state.beginEditing() }.buttonStyle(.gate)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField("", text: $state.draft)
                    .gateField(focused: fieldFocused, error: state.error != nil)
                    .overlay(alignment: .leading) {
                        if state.draft.isEmpty { Text("Paste your OpenRouter key").font(Gate.Font.body).foregroundStyle(Gate.Text.disabled).padding(.leading, 10).allowsHitTesting(false) }
                    }
                    .focused($fieldFocused)
                    .onSubmit { Task { await state.save() } }
                    .accessibilityLabel("OpenRouter key")
                Button("Cancel") { state.cancel() }.buttonStyle(.gate(.ghost)).keyboardShortcut(.cancelAction)
                Button { Task { await state.save() } } label: { if state.saving { GateSpinner() } else { Text("Save") } }
                    .buttonStyle(.gate).disabled(state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.saving)
            }
            if let error = state.error { Text(error).font(.system(size: 11.5)).foregroundStyle(Gate.State.alert).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.leading, 44)
        .onAppear { fieldFocused = true }
    }

    // MARK: Versions

    private func versionRow(_ kind: MadeKind, _ label: String, first: Bool = false) -> some View {
        let choices = state.catalog.choices(kind)
        let current = state.catalog.version(kind, chosen: preview ? nil : state.chosen[kind])
        let price = current.flatMap { MadeFormat.priceLine(kind, $0) }
        // `.set-row` with a sub-label whose money is SF Mono ("About $0.04 a 30 s clip").
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                if let price { MadeText.money(in: price, size: 11.5, mono: 11).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if choices.isEmpty {
                    Text("Not listed").font(.system(size: 12.5)).foregroundStyle(Gate.Text.tertiary)
                } else {
                    GateSelect(options: choices.map { ($0.id, $0.name) }, selection: Binding(get: { current?.id ?? choices[0].id }, set: { id in
                        guard !preview else { return }
                        state.choose(kind, id)
                    }))
                }
            }
            .fixedSize()
            .accessibilityLabel(label).accessibilityHint(price ?? "")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { if !first { SystemHairline() } }
        .accessibilityElement(children: .contain)
    }
}

/// The money row: "$12.80 of $50.00", a steel meter (one segment per kind, proportional to the month's cap) and its legend.
struct SpendMeterRow: View {
    var entries: [SpendEntry]
    var cap: Double?
    var body: some View {
        let groups = SpendLedger.byGroup(entries), total = groups.reduce(0) { $0 + $1.spent }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("Spent this month").font(Gate.Font.body).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13)
                Spacer(minLength: 0)
                Text(cap.map { "\(MadeFormat.money(total)) of \(MadeFormat.money($0))" } ?? MadeFormat.money(total))
                    .font(.system(size: 12, design: .monospaced)).monospacedDigit().foregroundStyle(Gate.Text.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { g in
                    HStack(spacing: 1) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { i, s in
                            Self.color(i).frame(width: max(2, g.size.width * CGFloat(s.spent / max(0.01, cap ?? total))))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 8).background(Gate.Surface.hover).clipShape(RoundedRectangle(cornerRadius: 4))
                if !groups.isEmpty {
                    HStack(spacing: 18) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(Self.color(i)).frame(width: 8, height: 8)
                                Text(s.group).font(Gate.Font.small)
                                Text(MadeFormat.money(s.spent)).font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit()
                            }
                        }
                    }
                    .foregroundStyle(Gate.Text.tertiary)
                    .cssLineHeight(1.45, size: 12)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { SystemHairline() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spent this month")
        .accessibilityValue(([cap.map { "\(MadeFormat.money(total)) of \(MadeFormat.money($0))" } ?? MadeFormat.money(total)] + groups.map { "\($0.group) \(MadeFormat.money($0.spent))" }).joined(separator: ", "))
    }
    /// Steel only, brightest first, as Storage's meter.
    static func color(_ i: Int) -> Color { Gate.Steel.ramp[max(4, 9 - i)] }
}

/// The pane's state: the key's status, the version lists and this Mac's spend record.
@MainActor @Observable final class ServicesState {
    enum KeyState: Equatable { case checking, notSet, ready(Double?), failing(String) }
    var key: KeyState = .checking
    var editing = false
    var draft = ""
    var saving = false
    var error: String?
    var catalog: MadeCatalog = .builtIn
    var entries: [SpendEntry] = []
    /// Chosen versions by kind (the shared suite).
    var chosen: [MadeKind: String] = [:]

    func load(preview: Bool) async {
        if preview { applyPreview(); return }
        chosen = Dictionary(uniqueKeysWithValues: MadeKind.allCases.compactMap { k in SharedSettings.madeVersion(k).map { (k, $0) } })
        catalog = MadeVersions.cached() ?? .builtIn
        entries = SpendLedger.entries()
        await check()
        catalog = await MadeVersions.load()
        // The helper keeps its own copy; give it the key again if a rebuild left it unreadable.
        Task.detached(priority: .utility) { OpenRouter.Key.syncHelper() }
    }

    /// `GET /key`: Ready with what's left, or OpenRouter's reason.
    func check() async {
        guard let saved = await Task.detached(operation: { OpenRouter.Key.read() }).value else { key = .notSet; return }
        do { key = .ready(try await OpenRouter.keyInfo(key: saved).remaining) }
        catch { key = .failing(Self.words(error)) }
    }

    func beginEditing() { editing = true; draft = ""; error = nil }
    func cancel() { editing = false; draft = ""; error = nil }

    /// Checks the pasted key first, then keeps it in the keychain (the app's copy and the helper's).
    func save() async {
        let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !saving else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            let info = try await OpenRouter.keyInfo(key: candidate)
            try await Task.detached { try OpenRouter.Key.save(candidate) }.value
            key = .ready(info.remaining); editing = false; draft = ""
        } catch {
            self.error = "That key didn\u{2019}t work: \(Self.words(error))"
        }
    }

    /// New requests stop at once; made clips stay playable.
    func remove() {
        key = .notSet; editing = false
        Task.detached { OpenRouter.Key.remove() }
    }

    func choose(_ kind: MadeKind, _ id: String) {
        chosen[kind] = id
        SharedSettings.defaults.set(id, forKey: SharedSettings.SpendKey.version(kind))
    }

    /// OpenRouter's own message, without "OpenRouter said:" or the status code.
    static func words(_ error: Error) -> String {
        var s = (error as? DirectionError)?.message ?? error.localizedDescription
        if s.hasPrefix("OpenRouter said: ") { s = String(s.dropFirst(17)) }
        if let r = s.range(of: #" \([0-9]{3}\)$"#, options: .regularExpression) { s = String(s[..<r.lowerBound]) }
        return s
    }

    /// Frame 55: Ready with $37.20 left, $12.80 spent this month.
    private func applyPreview() {
        key = .ready(37.20)
        var c = MadeCatalog.builtIn
        if let i = c.versions.firstIndex(where: { $0.listing == .speech }) { c.versions[i] = MadeVersion(id: "assemblyai/assemblyai-tts-1", name: "AssemblyAI TTS 1", listing: .speech, pricing: ["prompt": "0.000015"], voices: ["aai-jane"]) }
        catalog = c
        let now = Date()
        entries = [SpendEntry(at: now, kind: .music, version: "google/lyria-3-clip", estimate: 0.36, spend: 0.36),
                   SpendEntry(at: now, kind: .shot, version: "google/veo-3.1", estimate: 12.40, spend: 12.40),
                   SpendEntry(at: now, kind: .looking, version: "google/gemini-3.1-flash", estimate: 0.04, spend: 0.04)]
    }
}
