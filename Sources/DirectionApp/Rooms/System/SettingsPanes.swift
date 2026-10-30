import SwiftUI
import AppKit
import CoreAudio
import UserNotifications
import DirectionCore
import DirectionMedia

// MARK: 42 · General

struct GeneralPane: View {
    var preview = false
    @AppStorage(SettingsKey.whenOpening) private var whenOpening = "lastFilm"
    @AppStorage(SettingsKey.showFilmsWhenEmpty) private var showFilms = true
    @AppStorage(SettingsKey.screeningFullScreen) private var fullScreen = false
    @AppStorage(SettingsKey.hideControlsAfter) private var hideAfter = 2.0
    @AppStorage(SettingsKey.audioOutput) private var audioOutput = ""
    @AppStorage(SettingsKey.filmGrain) private var grain = true
    @AppStorage(SettingsKey.reduceMotion) private var reduceMotion = "system"
    @State private var outputs: [AudioOutputDevice] = []

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Start") {
                SettingsRow(label: "When Direction opens", first: true) {
                    GateSelect(options: [("lastFilm", "Reopen the last film"), ("films", "Show Films"), ("newFilm", "Start a new film")], selection: $whenOpening)
                }
                SettingsRow(label: "Show Films when no film is open") { GateSwitch(isOn: $showFilms) }
            }
            SettingsGroup(label: "Playback") {
                SettingsRow(label: "Start screenings full screen", first: true) { GateSwitch(isOn: $fullScreen) }
                SettingsRow(label: "Hide controls in Screening after") {
                    GateSelect(options: [(1.0, "1 second"), (2.0, "2 seconds"), (4.0, "4 seconds"), (0.0, "Never")], selection: $hideAfter)
                }
                SettingsRow(label: "Audio output") {
                    GateSelect(options: [("", "System default")] + outputs.map { ($0.uid, $0.name) }, selection: $audioOutput)
                }
            }
            SettingsGroup(label: "Look") {
                SettingsRow(label: "Film grain", detail: "A fine texture over the interface. Never drawn over the picture.", first: true) { GateSwitch(isOn: $grain) }
                SettingsRow(label: "Reduce motion", detail: "Replaces shimmer and sweeps with fades.") {
                    GateSelect(options: [("system", "Follow system"), ("on", "On"), ("off", "Off")], selection: $reduceMotion)
                }
            }
            Text(versionLine).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
                .frame(maxWidth: .infinity).padding(.top, 14)
        }
        .task { if !preview { outputs = AudioOutputDevice.all() } }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return preview ? "Direction 1.0 (214)" : "Direction · development build" }
        return "Direction \(version) (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }
}

/// A Core Audio output device for Settings › General › Audio output.
struct AudioOutputDevice: Hashable {
    var uid: String
    var name: String

    static func all() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioOutputDevice(uid: uid, name: name)
        }
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

// MARK: 43 · Editor

/// Latitude, shared by Settings › Editor, the Editor popover and the Turnover sheet's default.
@MainActor enum LatitudeSetting {
    static var current: Latitude { Latitude(rawValue: UserDefaults.standard.string(forKey: SettingsKey.defaultLatitude) ?? "") ?? .faithful }
    /// Changes the default for new turnovers and the open film's own setting.
    static func set(_ latitude: Latitude, film: FilmModel?) {
        UserDefaults.standard.set(latitude.rawValue, forKey: SettingsKey.defaultLatitude)
        guard let film, film.directing.latitude != latitude else { return }
        film.perform { _ = try $0.updateDirectingState(summary: "Freedom: \(latitude.label)") { $0.latitude = latitude } }
    }
}

struct EditorPane: View {
    var app: AppModel?
    var preview = false
    @AppStorage(SettingsKey.defaultLatitude) private var latitude = Latitude.faithful.rawValue
    @AppStorage(SettingsKey.waitForReadBack) private var waitForOK = true
    @AppStorage(SettingsKey.cutFeelingTwoWays) private var twoWays = true
    @AppStorage(SettingsKey.askBeforeGuessing) private var askFirst = true
    @AppStorage(SettingsKey.conflictOrder) private var order = SettingsKey.defaultConflictOrder

    static func detail(_ l: Latitude) -> String {
        switch l {
        case .exact: "Changes only what each note names. Never offers options. Asks when a note is unclear."
        case .faithful: "Interprets what you meant. May touch the shots around a note. Cuts Feeling notes two ways."
        case .free: "May also suggest changes no note asked for. Each one is marked Unasked and waits for your OK."
        }
    }

    var body: some View {
        SettingsPane {
            EditorWhoEditsGroup(app: app, preview: preview)
            SettingsGroup(label: "How much freedom the editor has", note: AnyView(SettingsNote("You can change this for a single turnover in the Turnover sheet."))) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Latitude.allCases, id: \.self) { l in latitudeCard(l) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
                .accessibilityElement(children: .contain).accessibilityLabel("How much freedom the editor has")
            }
            // The conflict list moved into Change…'s popover so the pane stays under 860 (frame 43).
            SettingsGroup(label: "Before cutting", note: AnyView(SettingsNote("The editor reads the brief before every cut."))) {
                SettingsRow(label: "Wait for my OK on read-backs", detail: "Off: the editor starts cutting right after it reads back. You can still read it.", first: true) { GateSwitch(isOn: $waitForOK) }
                SettingsRow(label: "Cut Feeling notes two ways", detail: "You pick A or B in Changes.") { GateSwitch(isOn: $twoWays) }
                    .disabled(latitude == Latitude.exact.rawValue)
                SettingsRow(label: "Ask before guessing", detail: "When a note could mean two things, the editor asks instead of choosing.") { GateSwitch(isOn: $askFirst) }
                ConflictOrderRow(order: $order)
            }
        }
    }

    private func latitudeCard(_ l: Latitude) -> some View {
        let on = latitude == l.rawValue
        return Button { LatitudeSetting.set(l, film: app?.film) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) { RadioDot(on: on); Text(l.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary).cssLineHeight(1.45, size: 13) }
                Text(Self.detail(l)).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.4, size: 11.5).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).fill(on ? Gate.Surface.hover : Gate.Surface.raised))
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).strokeBorder(on ? Gate.Text.primary : Gate.Line.subtle, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Gate.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.label).accessibilityHint(Self.detail(l))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// The tiebreak order for conflicting notes. Drag a row, or focus it and press ⌥↑ / ⌥↓.
struct ConflictOrderList: View {
    @Binding var order: String
    @State private var dragging: NoteKind?
    @FocusState private var focused: NoteKind?

    static func describe(_ k: NoteKind) -> String {
        switch k {
        case .feeling: "How it should feel"
        case .story: "What happens and in what order"
        case .pace: "Length and rhythm"
        case .picture: "Framing, crop, look"
        case .sound: "Music, levels, dialogue"
        }
    }

    var body: some View {
        let kinds = SettingsKey.conflictKinds(order)
        VStack(spacing: 0) {
            ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.disabled)
                    Text("\(i + 1)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Text.disabled).frame(width: 14, alignment: .leading)
                    Text(k.label).font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                    Spacer(minLength: 8)
                    Text(Self.describe(k)).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary)
                }
                .padding(.leading, 8).padding(.trailing, 12).frame(height: 34)
                .background(dragging == k || focused == k ? Gate.Surface.hover : .clear)
                .overlay(alignment: .top) { if i > 0 { SystemHairline() } }
                .contentShape(Rectangle())
                .modifier(ReorderBehavior(kind: k, label: "\(k.label), \(i + 1) of \(kinds.count)", hint: Self.describe(k), focused: $focused, dragging: $dragging, move: move, drop: drop))
            }
        }
    }

    /// Drops a dragged row onto `target`: the dragged kind takes the target's place.
    private func drop(_ raw: String, onto target: NoteKind) -> Bool {
        defer { dragging = nil }
        var list = SettingsKey.conflictKinds(order)
        guard let moved = NoteKind(rawValue: raw), moved != target, let to = list.firstIndex(of: target) else { return false }
        list.removeAll { $0 == moved }
        list.insert(moved, at: min(to, list.count))
        withAnimation(SettingsKey.reducesMotion ? nil : Gate.Motion.settle) { order = list.map(\.rawValue).joined(separator: ",") }
        return true
    }

    private func move(_ k: NoteKind, by delta: Int) {
        var list = SettingsKey.conflictKinds(order)
        guard let i = list.firstIndex(of: k) else { return }
        let j = max(0, min(list.count - 1, i + delta))
        guard i != j else { return }
        list.swapAt(i, j)
        withAnimation(SettingsKey.reducesMotion ? nil : Gate.Motion.settle) { order = list.map(\.rawValue).joined(separator: ",") }
    }
}

/// Focus, ⌥↑/⌥↓, drag and drop, and VoiceOver's adjustable action for one reorderable row.
private struct ReorderBehavior: ViewModifier {
    var kind: NoteKind
    var label: String
    var hint: String
    var focused: FocusState<NoteKind?>.Binding
    @Binding var dragging: NoteKind?
    var move: (NoteKind, Int) -> Void
    var drop: (String, NoteKind) -> Bool

    func body(content: Content) -> some View {
        content
            .focusable(interactions: .activate).focused(focused, equals: kind).focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                guard press.modifiers.contains(.option) else { return .ignored }
                move(kind, press.key == .upArrow ? -1 : 1)
                return .handled
            }
            .draggable(kind.rawValue) { dragPreview }
            .dropDestination(for: String.self) { items, _ in items.first.map { drop($0, kind) } ?? false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAdjustableAction { d in move(kind, d == .increment ? 1 : -1) }
            .accessibilityAction(named: "Move up") { move(kind, -1) }
            .accessibilityAction(named: "Move down") { move(kind, 1) }
    }

    private var dragPreview: some View {
        Text(kind.label).font(Gate.Font.body).foregroundStyle(Gate.Text.primary).padding(8)
            .background(SystemPopBackground(radius: 8))
            .onAppear { dragging = kind }
    }
}

// MARK: 54 · Footage

/// Settings › Footage: how takes are transcribed. Stored in the shared suite, because the editor's
/// tools run in their own process and transcribe with whatever is chosen here.
struct FootagePane: View {
    var preview = false
    @AppStorage(SharedSettings.Key.transcriptionEngine, store: SharedSettings.defaults) private var engine = SharedSettings.TranscriptionEngine.apple.rawValue
    @AppStorage(SharedSettings.Key.whisperModel, store: SharedSettings.defaults) private var model = SharedSettings.whisperModels[0].id
    @State private var whisper: WhisperSetup = .checking

    enum WhisperSetup: Equatable { case checking, ready(String), missing, needsFFmpeg }
    private static let sizes = ["mlx-community/whisper-large-v3-turbo": "1.6 GB", "mlx-community/whisper-large-v3-mlx": "3.1 GB"]
    private var usesWhisper: Bool { engine == SharedSettings.TranscriptionEngine.whisper.rawValue }

    // Measured on the director's 3:12 take on an M4 Max (footage-index.md › Transcription engines):
    // Apple 2.2 s, keeps false starts; Turbo 7.0 s; Large v3 11.9 s. Word starts agree within 0.08 s.
    private var engineDetail: String {
        usesWhisper ? "Whisper on this Mac\u{2019}s graphics chip. It tidies speech, so false starts and repeated lines can drop out."
            : "Built into macOS, on the Neural Engine. The fastest, and it keeps false starts, which helps find retakes."
    }
    private var modelDetail: String {
        let size = Self.sizes[model] ?? ""
        let downloaded = preview ? model == SharedSettings.whisperModels[0].id : WhisperTranscriber.isDownloaded(model)
        let speed = model == SharedSettings.whisperModels[0].id ? "About 25\u{00D7} real time. Nearly as accurate as Large v3." : "About 16\u{00D7} real time, and a little more accurate."
        return speed + (downloaded ? " Downloaded \u{00B7} \(size)." : " Downloads \(size) the first time it\u{2019}s used.")
    }

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Transcription", note: AnyView(SettingsNote("Takes already transcribed keep their words. New footage uses this engine."))) {
                SettingsRow(label: "Transcribe with", detail: engineDetail, first: true) {
                    GateSegmented(options: [(SharedSettings.TranscriptionEngine.apple.rawValue, "Apple"), (SharedSettings.TranscriptionEngine.whisper.rawValue, "Whisper")], selection: $engine)
                }
                SettingsRow(label: "Whisper version", detail: modelDetail) {
                    GateSelect(options: SharedSettings.whisperModels.map { ($0.id, $0.name) }, selection: $model)
                }
                .disabled(!usesWhisper)
                if usesWhisper { setupRow }
            }
            FootageLookingGroup(preview: preview)
            FootageColorGroup(preview: preview)
        }
        .task { await check() }
    }

    @ViewBuilder private var setupRow: some View {
        switch whisper {
        case .checking:
            SettingsRow(label: "mlx-whisper", detail: "Looking for it on this Mac\u{2026}") { GateSpinner() }
        case .ready(let path):
            SettingsRow(label: "mlx-whisper", detail: (path as NSString).abbreviatingWithTildeInPath) { Chip("Ready", style: .ok, mono: false) }
        case .missing:
            SettingsRow(label: "mlx-whisper isn\u{2019}t installed", detail: "Install it in Terminal with pip install mlx-whisper. Until then, Apple transcribes.") {
                Button("Copy Command") { SystemSupport.copy("pip install mlx-whisper") }.buttonStyle(.gate(.normal))
            }
        case .needsFFmpeg:
            SettingsRow(label: "Whisper needs ffmpeg", detail: "Install it in Terminal with brew install ffmpeg. Until then, Apple transcribes.") {
                Button("Copy Command") { SystemSupport.copy("brew install ffmpeg") }.buttonStyle(.gate(.normal))
            }
        }
    }

    private func check() async {
        if preview { whisper = .ready(NSHomeDirectory() + "/.local/bin/mlx_whisper"); return }
        let found = await Task.detached { (WhisperTranscriber.executable()?.path, WhisperTranscriber.ffmpeg() != nil) }.value
        whisper = found.0 == nil ? .missing : !found.1 ? .needsFFmpeg : .ready(found.0!)
    }
}

// MARK: 44 · Cutting

struct CuttingPane: View {
    var app: AppModel?
    @AppStorage(SettingsKey.handleSeconds) private var handles = 2.0
    @AppStorage(SettingsKey.cutNaming) private var naming = "number"
    @AppStorage(SettingsKey.frameRate) private var frameRate = "match"
    @AppStorage(SettingsKey.loudness) private var loudness = -14.0
    @AppStorage(SettingsKey.ducking) private var ducking = 6.0
    // Shared, so the editor's tools see whether it may add transitions without a note.
    @AppStorage(SettingsKey.transitions, store: SharedSettings.defaults) private var transitions = "hard"
    @AppStorage(SettingsKey.keepCuts) private var keepCuts = "all"
    @AppStorage(SettingsKey.playFromProxies) private var proxies = true

    private var film: FilmModel? { app?.film }
    private var nextCut: String { "Cut \(max(2, (film?.cuts.count ?? 3) + 1))" }
    private var today: String { Date().formatted(.dateTime.month(.abbreviated).day()) }
    private var handlesDetail: String {
        if let film, let cut = film.latestCut, !film.changedRanges(in: cut).isEmpty {
            return "Untouched picture shown before and after each change. Play changes runs \(Timecode.duration(film.changesDuration(in: cut)))."
        }
        return "Untouched picture shown before and after each change."
    }
    private var assemblyExists: Bool { !(film?.cuts.isEmpty ?? true) }

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Reviewing changes") {
                SettingsRow(label: "Handles in Play changes", detail: handlesDetail, first: true) {
                    GateStepper(value: $handles, range: 0...5, step: 0.5) { String(format: "%.1f s", $0) }
                }
                SettingsRow(label: "Name new cuts") {
                    GateSegmented(options: [("number", nextCut), ("date", today), ("both", "Both")], selection: $naming)
                }
            }
            SettingsGroup(label: "Picture and sound") {
                SettingsRow(label: "Frame rate for new films", detail: assemblyExists ? "This film's rate was set when the Assembly was built." : nil, first: true) {
                    GateSelect(options: [("match", "Match footage"), ("23.976", "23.976"), ("24", "24"), ("25", "25"), ("29.97", "29.97"), ("30", "30"), ("60", "60")], selection: $frameRate)
                }
                SettingsRow(label: "Loudness target") {
                    GateSelect(options: [(-14.0, "\u{2212}14 LUFS · Web"), (-16.0, "\u{2212}16 LUFS · Podcast"), (-23.0, "\u{2212}23 LUFS · Broadcast (EBU R128)"), (-24.0, "\u{2212}24 LUFS · Broadcast (ATSC A/85)")], selection: $loudness)
                }
                SettingsRow(label: "Music under dialogue", detail: "Used when a note doesn\u{2019}t say. Notes always win.") {
                    GateSelect(options: [(3.0, "Duck 3 dB"), (6.0, "Duck 6 dB"), (9.0, "Duck 9 dB"), (0.0, "Don\u{2019}t duck")], selection: $ducking)
                }
                SettingsRow(label: "Transitions") {
                    GateSelect(options: [("hard", "Hard cuts unless a note asks"), ("editor", "Editor\u{2019}s choice")], selection: $transitions)
                }
            }
            SettingsGroup(label: "Keeping cuts") {
                SettingsRow(label: "Keep earlier cuts", detail: "Earlier cuts stay playable and comparable in History.", first: true) {
                    GateSelect(options: [("all", "All of them"), ("last5", "Last 5"), ("lockedAndCurrent", "Only locked and current")], selection: $keepCuts)
                }
                SettingsRow(label: "Play from proxies", detail: "Smaller copies for smooth playback. Deliveries always use the originals.") { GateSwitch(isOn: $proxies) }
            }
        }
    }
}

// MARK: 45 · Notifications

struct NotificationsPane: View {
    var preview = false
    @AppStorage(NotificationKey.cutReady) private var cutReady = true
    @AppStorage(NotificationKey.question) private var question = true
    @AppStorage(NotificationKey.cant) private var cant = true
    @AppStorage(NotificationKey.delivery) private var delivery = true
    @AppStorage(SettingsKey.outsideNotes) private var outside = "hourly"
    @AppStorage(SettingsKey.holdDuringScreening) private var hold = true
    @AppStorage(SettingsKey.notificationSound) private var sound = "default"
    @State private var denied = false
    /// Direction hasn't asked yet: the first turnover asks, or Turn On here.
    @State private var notAsked = false

    var body: some View {
        SettingsPane {
            if denied || notAsked {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash").font(.system(size: 12)).foregroundStyle(Gate.Text.secondary)
                    Text(denied ? "Notifications are off for Direction in System Settings." : "Direction hasn\u{2019}t asked to send notifications yet.").font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary)
                    Spacer(minLength: 8)
                    if denied { Button("Open System Settings") { SystemNotifications.openSystemSettings() }.buttonStyle(.gate(.normal, .small)) }
                    else { Button("Turn On") { SystemNotifications.requestPermission { Task { await check() } } }.buttonStyle(.gate(.normal, .small)) }
                }
                .padding(.horizontal, 14).frame(height: 36)
                .background(SystemCardBackground())
                .padding(.top, 16)
            }
            Group {
                SettingsGroup(label: "Tell me when") {
                    SettingsRow(label: "A cut is ready", first: true) { GateSwitch(isOn: $cutReady) }
                    SettingsRow(label: "The editor has a question") { GateSwitch(isOn: $question) }
                    SettingsRow(label: "The editor can\u{2019}t do a note") { GateSwitch(isOn: $cant) }
                    SettingsRow(label: "An outside note arrives", detail: "Groups notes from share links into one notification.") {
                        GateSelect(options: [("now", "Right away"), ("hourly", "Once an hour"), ("daily", "Once a day"), ("never", "Never")], selection: $outside)
                    }
                    SettingsRow(label: "A delivery finishes") { GateSwitch(isOn: $delivery) }
                }
                SettingsGroup(label: "Quiet") {
                    SettingsRow(label: "Hold notifications during a screening", detail: "They wait until you end the screening.", first: true) { GateSwitch(isOn: $hold) }
                    SettingsRow(label: "Sound") {
                        GateSelect(options: [("default", "System sound"), ("none", "None")], selection: $sound)
                    }
                }
            }
            .disabled(denied)
        }
        .task { await check() }
        // Coming back from System Settings: ask again, or the pane keeps the old answer.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await check() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in Task { await check() } }
    }

    private func check() async {
        guard !preview, SystemSupport.isBundledApp else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        denied = status == .denied; notAsked = status == .notDetermined
    }
}

// MARK: 46 · Shortcuts

struct ShortcutsPane: View {
    var recording: ShortcutAction?
    @State private var store = ShortcutStore.shared
    @State private var query = ""
    @State private var recorder = ShortcutRecorder()
    @State private var confirmRestore = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                    TextField("", text: $query, prompt: Text("Search shortcuts").foregroundColor(Gate.Text.disabled)).textFieldStyle(.plain).font(Gate.Font.body)
                }
                .padding(.horizontal, 10).frame(height: Gate.Size.control).background(GateFieldBackground())
                Button("Restore defaults") { confirmRestore = true }.buttonStyle(.gate)
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    SettingsPane {
                        ForEach(ShortcutGroup.allCases) { group in
                            let rows = ShortcutAction.overlayActions.filter { $0.group == group && matches($0) }
                            if !rows.isEmpty {
                                SettingsGroup(label: group.title, note: note(for: rows)) {
                                    ForEach(Array(rows.enumerated()), id: \.element) { i, action in row(action, first: i == 0) }
                                }
                                .id(group)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .onAppear {
                    guard let recording else { return }
                    recorder.start(recording, store: store)
                    if let group = recording.group { proxy.scrollTo(group, anchor: .top) }
                }
            }
        }
        .frame(height: 690 - 76)
        .onDisappear { recorder.stop() }
        .alert("Restore all shortcuts to their defaults?", isPresented: $confirmRestore) {
            Button("Restore Defaults", role: .destructive) { store.restoreDefaults() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func matches(_ action: ShortcutAction) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || action.label.lowercased().contains(q) || store.caps(action).joined().lowercased().contains(q)
    }

    @ViewBuilder private func row(_ action: ShortcutAction, first: Bool) -> some View {
        let conflict = recorder.conflict?.action == action ? recorder.conflict : nil
        VStack(spacing: 0) {
            SettingsRow(label: action.label, first: first) {
                if store.isEdited(action) { Text("Edited").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary) }
                if recorder.action == action {
                    Text(conflict.map { $0.combo.text } ?? "Press keys\u{2026}").font(.system(size: 12)).foregroundStyle(Gate.Text.secondary)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(GateFieldBackground(focused: conflict == nil, error: conflict != nil))
                } else if action.isCustomizable {
                    Button { recorder.start(action, store: store) } label: { keys(action) }
                        .buttonStyle(.plain).help("Click to record a new shortcut. ⌫ clears it.")
                } else {
                    keys(action)
                }
            }
            if let conflict {
                HStack(spacing: 8) {
                    Text("\(conflict.combo.text) is already \(conflict.other.label).").font(.system(size: 11.5)).foregroundStyle(Gate.State.alert)
                    Spacer(minLength: 8)
                    Button("Replace") { recorder.replace(store: store) }.buttonStyle(.gate(.normal, .small))
                    Button("Cancel") { recorder.stop() }.buttonStyle(.gate(.ghost, .small))
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private func keys(_ action: ShortcutAction) -> some View {
        let caps = store.caps(action)
        if caps.isEmpty { Text("None").font(.system(size: 12)).foregroundStyle(Gate.Text.disabled) } else { KeyCaps(keys: caps) }
    }

    /// "R also opens Other readings in Script." under the group whose row is being recorded.
    private func note(for rows: [ShortcutAction]) -> AnyView? {
        guard let action = recorder.action, rows.contains(action), recorder.conflict == nil, let other = store.sharedAcrossRooms(action), let room = other.rooms.first, other.rooms.count == 1 else { return nil }
        return AnyView(HStack(spacing: 6) {
            KeyCaps(keys: store.caps(action), small: true)
            SettingsNote("also opens \(other.label) in \(room.title). A key can mean one thing per room.")
        })
    }
}

/// Records one shortcut from the keyboard: esc cancels, ⌫ clears, a key in use in the same room asks to replace.
@MainActor @Observable
final class ShortcutRecorder {
    struct Conflict: Equatable { var action: ShortcutAction; var combo: KeyCombo; var other: ShortcutAction }
    var action: ShortcutAction?
    var conflict: Conflict?
    @ObservationIgnored private var monitor: Any?

    func start(_ action: ShortcutAction, store: ShortcutStore) {
        stop()
        self.action = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let self, let action = self.action else { return false }
                let bare = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                if event.keyCode == 53 && bare { self.stop(); return true }
                if event.keyCode == 51 && bare && self.conflict == nil { store.set(nil, for: action); self.stop(); return true }
                guard self.conflict == nil, let combo = KeyCombo(event: event) else { return true }
                if let other = store.conflict(for: action, with: combo) { self.conflict = Conflict(action: action, combo: combo, other: other); return true }
                store.set(combo, for: action); self.stop()
                return true
            }
            return used ? nil : event
        }
    }
    func replace(store: ShortcutStore) {
        guard let c = conflict else { return }
        store.replace(c.combo, for: c.action, taking: c.other)
        stop()
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; action = nil; conflict = nil
    }
}

// MARK: 47 · Storage

struct UsageSlice: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var bytes: Int64
    var color: Color
}

struct StoragePane: View {
    var app: AppModel?
    var preview = false
    @AppStorage(SettingsKey.libraryFolder) private var library = SettingsKey.defaultLibrary
    @AppStorage(SettingsKey.footageImport) private var footage = "link"
    @AppStorage(SettingsKey.proxyCleanup) private var proxies = "after30"
    @State private var usage: StorageUsage?
    @State private var clearing = false

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Library") {
                SettingsRow(label: "Location", first: true) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary)
                        Text(displayPath).font(.system(size: 12)).foregroundStyle(Gate.Text.primary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).frame(width: 260, height: Gate.Size.control).background(GateFieldBackground())
                    .help(library)
                    Button("Change\u{2026}") { chooseLibrary() }.buttonStyle(.gate)
                }
                SettingsRow(label: "When you bring footage", detail: "Linking saves space. Copying keeps films working when drives are unplugged.") {
                    GateSegmented(options: [("link", "Link to originals"), ("copy", "Copy into library")], selection: $footage)
                }
            }
            if let usage, usage.free < 10_000_000_000 {
                Banner(icon: "exclamationmark.triangle", title: "Less than 10 GB free.", detail: "The editor may not be able to finish a cut.", alert: true) { EmptyView() }
                    .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.card)).padding(.top, 16)
            }
            SettingsGroup(label: usage.map { "Using \(SystemSupport.bytes($0.used)) on \($0.volume)" } ?? "Using \u{2026}") {
                VStack(alignment: .leading, spacing: 10) {
                    UsageMeter(slices: usage?.slices ?? [], capacity: usage?.capacity ?? 1)
                    HStack(spacing: 18) {
                        ForEach(usage?.slices ?? []) { s in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 8, height: 8)
                                Text("\(s.name) \(SystemSupport.bytes(s.bytes))")
                            }
                        }
                    }
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                }
                .padding(14)
            }
            SettingsGroup(label: "Cleanup") {
                SettingsRow(label: "Render cache", detail: cutting ? "Available when the editor finishes." : "Rebuilt when needed. Nothing you made is lost.", first: true) {
                    Button(usage.map { "Clear \(SystemSupport.bytes($0.renderCache))" } ?? "Clear") { clearCache() }
                        .buttonStyle(.gate).disabled(cutting || clearing || (usage?.renderCache ?? 0) == 0)
                }
                SettingsRow(label: "Proxies for locked films") {
                    GateSelect(options: [("keep", "Keep"), ("after30", "Delete after 30 days"), ("now", "Delete now")], selection: $proxies)
                }
            }
        }
        .task(id: library) { await measure() }
    }

    private var displayPath: String { (library as NSString).abbreviatingWithTildeInPath }
    private var cutting: Bool {
        guard let t = app?.film?.openTurnover else { return false }
        return t.state == .cutting
    }

    private func measure() async {
        if preview {
            usage = StorageUsage(volume: "Macintosh HD", capacity: 494_000_000_000, free: 120_000_000_000, slices: [
                .init(name: "Copied footage", bytes: 12_800_000_000, color: Gate.Steel.ramp[9]), .init(name: "Proxies", bytes: 34_100_000_000, color: Gate.Steel.ramp[8]),
                .init(name: "Cuts", bytes: 7_900_000_000, color: Gate.Steel.ramp[7]), .init(name: "Render cache", bytes: 6_600_000_000, color: Gate.Steel.ramp[6]),
            ], renderCache: 6_600_000_000)
            return
        }
        let folder = library
        let measured = await Task.detached(priority: .utility) { StorageUsage.measure(library: folder) }.value
        usage = measured
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel(); panel.title = "Choose a library folder"; panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: library)
        guard panel.runModal() == .OK, let url = panel.url, url.path != library else { return }
        let alert = NSAlert()
        alert.messageText = "Save new films in \u{201C}\(url.lastPathComponent)\u{201D}?"
        alert.informativeText = "Films already in \((library as NSString).abbreviatingWithTildeInPath) stay where they are and keep working."
        alert.addButton(withTitle: "Use This Folder"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { library = url.path }
    }

    private func clearCache() {
        clearing = true
        let keep = app?.film?.runtime?.cacheDirectory
        Task {
            await Task.detached(priority: .utility) { StorageUsage.clearRenderCache(keeping: keep) }.value
            clearing = false
            await measure()
        }
    }
}

/// Real disk use: films in the library, files copied into it, and the render cache.
struct StorageUsage: Sendable {
    var volume: String
    var capacity: Int64
    var free: Int64
    var slices: [UsageSlice]
    var renderCache: Int64
    var used: Int64 { slices.reduce(0) { $0 + $1.bytes } }

    static var cacheRoot: URL { DirectionPaths.caches }
    /// Rebuildable renders. Thumbnails stay: takes show them in Dailies.
    static let clearable = ["Frames", "Previews", "Feedback", "Render", "Audio"]

    static func measure(library: String) -> StorageUsage {
        let libraryURL = URL(fileURLWithPath: library)
        var films: Int64 = 0, copied: Int64 = 0
        let items = (try? FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil)) ?? []
        for item in items { if item.pathExtension == "direction" { films += size(of: item) } else { copied += size(of: item) } }
        var cache: Int64 = 0
        for project in (try? FileManager.default.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)) ?? [] {
            for name in clearable { cache += size(of: project.appendingPathComponent(name)) }
        }
        let probe = FileManager.default.fileExists(atPath: library) ? libraryURL : URL(fileURLWithPath: NSHomeDirectory())
        let values = try? probe.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        var slices: [UsageSlice] = []
        if copied > 0 { slices.append(.init(name: "Copied footage", bytes: copied, color: Gate.Steel.ramp[9])) }
        slices.append(.init(name: "Films", bytes: films, color: Gate.Steel.ramp[8]))
        slices.append(.init(name: "Render cache", bytes: cache, color: Gate.Steel.ramp[6]))
        return StorageUsage(volume: values?.volumeName ?? "this Mac", capacity: Int64(values?.volumeTotalCapacity ?? 1), free: values?.volumeAvailableCapacityForImportantUsage ?? .max, slices: slices, renderCache: cache)
    }

    static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
        while let file = e?.nextObject() as? URL {
            let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// Deletes rebuildable renders. The open film keeps the files its player is using.
    static func clearRenderCache(keeping open: URL?) {
        for project in (try? FileManager.default.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)) ?? [] {
            let isOpen = open.map { $0.standardizedFileURL == project.standardizedFileURL } ?? false
            for name in clearable where !(isOpen && ["Render", "Audio"].contains(name)) {
                try? FileManager.default.removeItem(at: project.appendingPathComponent(name))
            }
        }
    }
}

/// The stacked usage bar, proportional to the disk's capacity. Steel only.
struct UsageMeter: View {
    var slices: [UsageSlice]
    var capacity: Int64
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(slices) { s in
                    s.color.frame(width: max(s.bytes > 0 ? 2 : 0, g.size.width * CGFloat(Double(s.bytes) / Double(max(1, capacity)))))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 8)
        .background(Gate.Surface.hover)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement().accessibilityLabel(slices.map { "\($0.name) \(SystemSupport.bytes($0.bytes))" }.joined(separator: ", "))
    }
}

// MARK: 48 · Sharing

struct SharingPane: View {
    @AppStorage(SettingsKey.linkNotes) private var notes = true
    @AppStorage(SettingsKey.linkExpiry) private var expiry = 7
    @AppStorage(SettingsKey.linkWatermark) private var watermark = true
    @AppStorage(SettingsKey.linkDownload) private var download = false
    @AppStorage(SettingsKey.linkPassword) private var password = false
    @AppStorage(SettingsKey.creditOutsideNotes) private var credit = true

    var body: some View {
        SettingsPane {
            SettingsGroup(label: "Account") {
                HStack(spacing: 16) {
                    Image(systemName: "person").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.secondary)
                        .frame(width: 32, height: 32).background(Circle().fill(Gate.Surface.hover)).overlay(Circle().strokeBorder(Gate.Line.strong, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screening links aren\u{2019}t available yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                        Text("Direction works on this Mac only. To share a cut now, export a screening copy from File › Share Cut\u{2026}").font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Sign In") {}.buttonStyle(.gate).disabled(true).help("Sharing isn\u{2019}t set up on this Mac.")
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 64)
            }
            SettingsGroup(label: "New screening links", note: AnyView(SettingsNote("These are defaults for when screening links arrive. Each link can be changed in its Share sheet."))) {
                SettingsRow(label: "Viewers can leave notes", first: true) { GateSwitch(isOn: $notes) }
                SettingsRow(label: "Links expire") {
                    GateSelect(options: [(0, "Never"), (1, "After 1 day"), (7, "After 7 days"), (30, "After 30 days")], selection: $expiry)
                }
                SettingsRow(label: "Watermark with the viewer\u{2019}s name") { GateSwitch(isOn: Binding(get: { watermark || !download }, set: { watermark = $0 })) }
                    .disabled(!download)
                SettingsRow(label: "Allow download") { GateSwitch(isOn: $download) }
                SettingsRow(label: "Require a password") { GateSwitch(isOn: $password) }
            }
            .disabled(true)
            SettingsGroup(label: "Outside notes") {
                SettingsRow(label: "Show who wrote each note to the editor", detail: "Accepted notes keep the author\u{2019}s name, so the editor can weigh a client note against yours.", first: true) { GateSwitch(isOn: $credit) }
            }
        }
    }
}
