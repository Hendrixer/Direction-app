import SwiftUI
import AppKit
import DirectionCore

// Watch through (frames 13–15): the Cut room's full-screen mode. The cut straight through, full-bleed, glass chrome
// that fades after the idle time in Settings, and one act: N drops a mark without stopping. Esc, or the end of the
// cut, goes back to the sheet with the marks waiting as notes to write. Spec: design/spec/specs/cut.md › Watch through.

extension EnvironmentValues {
    /// Snapshots of frame 14 start with the chrome already hidden.
    @Entry var screeningStartsQuiet = false
}

struct WatchThrough: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    @Environment(\.screeningStartsQuiet) private var startsQuiet
    var body: some View { ScreeningStage(model: model, app: app, startsQuiet: startsQuiet) }
}

struct ScreeningStage: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    @State private var chromeShown: Bool
    @State private var activity = 0
    @State private var toastMarkID: String?
    @State private var toastToken = 0
    @State private var toastHovered = false
    @State private var dockHovered = false
    @State private var window: NSWindow?
    @State private var fullScreen = false
    /// Settings › General › Start screenings full screen. Back to notes leaves the full screen it entered.
    @AppStorage(SettingsKey.screeningFullScreen) private var startsFullScreen = false
    @State private var enteredFullScreen = false
    @State private var showsVolume = false
    @State private var screeningsSeen = 0
    @State private var clock = WakeClock()
    @AppStorage("showTimeWhileScreening") private var showTime = true
    @AppStorage("screeningVolume") private var volume = 1.0
    @AppStorage("screeningMuted") private var muted = false
    @FocusState private var focused: Bool

    init(model: FilmModel, app: AppModel?, startsQuiet: Bool) {
        self.model = model; self.app = app
        _chromeShown = State(initialValue: !startsQuiet)
    }

    /// The chrome stays while paused, and whenever VoiceOver runs.
    private var chromeVisible: Bool { chromeShown || !model.playing || NSWorkspace.shared.isVoiceOverEnabled }
    private var marks: [ReviewComment] { model.screeningMarkIDs.compactMap { model.note($0) }.filter { $0.lifecycle != .dropped } }
    private var stripMarks: [StripMark] { marks.compactMap { c in model.noteTime(c).map { StripMark(id: c.id, time: $0, fresh: c.id == model.freshMarkID) } } }
    private var visibleToastID: String? { toastMarkID ?? (model.isPreview ? model.freshMarkID : nil) }

    var body: some View {
        ZStack {
            Gate.Surface.canvas
            picture
            if chromeVisible && model.playing && showsHint { hint.transition(.opacity) }
            if !chromeVisible { quietLabels.transition(.opacity) }
            dock.opacity(chromeVisible ? 1 : 0).allowsHitTesting(chromeVisible)
            WatchTitlebar(model: model, app: app, end: end)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(chromeVisible ? 1 : 0).allowsHitTesting(chromeVisible)
            if let id = visibleToastID, let note = model.note(id) { markToast(note).transition(toastTransition) }
        }
        .ignoresSafeArea()
        .animation(gateAnimation(Gate.Motion.settle), value: chromeVisible)
        .animation(gateAnimation(Gate.Motion.glide), value: visibleToastID)
        .onContinuousHover { phase in if case .active = phase { wake() } }
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { handle($0) }
        .background(WindowReader { window = $0; fullScreen = $0?.styleMask.contains(.fullScreen) ?? false; enterFullScreenIfAsked($0) })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { n in if (n.object as? NSWindow) === window { fullScreen = true } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { n in if (n.object as? NSWindow) === window { fullScreen = false } }
        .task(id: activity) { await hideWhenIdle() }
        .task(id: toastToken) { await expireToast() }
        .onChange(of: model.playing) { _, _ in wake() }
        .onChange(of: chromeVisible) { _, visible in setTrafficLights(visible) }
        .onAppear {
            focused = true
            applyVolume()
            if !model.isPreview, let id = model.project?.id {
                let key = "screenings.\(id)"
                screeningsSeen = UserDefaults.standard.integer(forKey: key)
                UserDefaults.standard.set(screeningsSeen + 1, forKey: key)
            }
        }
        .onDisappear {
            setTrafficLights(true); NSCursor.setHiddenUntilMouseMoves(false)
            if enteredFullScreen, let window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }

    // MARK: Picture

    private var picture: some View {
        let still = model.isPreview ? model.stripScene(at: model.position)?.art ?? .dusk : nil
        return PictureView(player: model.isPreview ? nil : model.player, still: still, aspect: model.aspect)
            .overlay { if model.isPreparing { GateSpinner() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // A click plays or pauses at once; the second click of a double-click puts that back and goes full screen.
            .onTapGesture {
                model.togglePlayback()
                if NSApp.currentEvent?.clickCount == 2 { toggleFullScreen() }
            }
            .accessibilityHidden(true)
    }

    // MARK: Dock

    private var dock: some View {
        HStack(spacing: 10) {
            Button { model.togglePlayback() } label: {
                Group { if model.isPreparing { GateSpinner() } else { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .medium)) } }
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.gate(.ghost, icon: true))
            .help(model.playing ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel("\(model.playing ? "Pause" : "Play"), \(model.watchedCut?.name ?? "the cut") at \(Self.spoken(model.position))")
            Text("\(Text(Timecode.format(model.position, fps: model.fps)).foregroundColor(Gate.Text.primary))\(Text(" / \(Timecode.duration(model.duration))").foregroundColor(Gate.Text.disabled))")
                .font(Gate.Font.timecode).lineLimit(1).fixedSize()
                .accessibilityLabel("\(Self.spoken(model.position)) of \(Self.spoken(model.duration))")
            strip
            markCount
            Button { showsVolume.toggle() } label: { Image(systemName: muted || volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.gate(.ghost, icon: true)).help("Volume")
                .accessibilityLabel("Volume")
                .gatePopover(isPresented: $showsVolume, arrowEdge: .top) { volumePopover }
            Button(action: toggleFullScreen) { Image(systemName: fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.gate(.ghost, icon: true)).help(fullScreen ? "Exit Full Screen (F)" : "Full Screen (F)")
                .accessibilityLabel(fullScreen ? "Exit full screen" : "Full screen")
        }
        .padding(.leading, 11).padding(.trailing, 15).padding(.top, 7).padding(.bottom, 3)
        .frame(width: 960, height: 54)
        .gateGlass(16)
        .onHover { dockHovered = $0 }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 24)
    }

    private var strip: some View {
        let scenes = model.stripScenes
        return SceneStrip(scenes: scenes, duration: model.duration, playhead: model.position, marks: stripMarks, onSeek: { model.seek($0); wake() }) { scene in
            SceneContextMenu(model: model, scene: scene)
        }
        .overlay { pinTargets(scenes) }
        .accessibilityLabel("Scene strip")
        .accessibilityValue(model.stripScene(at: model.position).map { "Scene \($0.number), \($0.title), \(Self.spoken(model.position)) of \(Self.spoken(model.duration))" } ?? "")
    }

    /// Pins are tips on hover and seek on click.
    private func pinTargets(_ scenes: [StripScene]) -> some View {
        GeometryReader { g in
            ForEach(stripMarks) { mark in
                Color.clear.frame(width: 12, height: 12).contentShape(Rectangle())
                    .onTapGesture { model.seek(mark.time); wake() }
                    .help(Timecode.format(mark.time, fps: model.fps))
                    .position(x: Self.stripX(mark.time, scenes: scenes, duration: model.duration, width: g.size.width), y: 8 + Gate.Component.Strip.scene + 7)
                    .accessibilityLabel("Director\u{2019}s mark at \(Timecode.format(mark.time, fps: model.fps))")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    @ViewBuilder private var markCount: some View {
        if marks.isEmpty {
            Text("No marks").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary).padding(.horizontal, 7).frame(height: Gate.Size.chip).fixedSize()
        } else {
            HStack(spacing: 5) {
                PinMark(size: 8)
                Text(marks.count == 1 ? "1 mark" : "\(marks.count) marks").font(Gate.Font.mono)
            }
            .foregroundStyle(Gate.Voice.director).padding(.horizontal, 7).frame(height: Gate.Size.chip)
            .background(RoundedRectangle(cornerRadius: Gate.Radius.chip).fill(Gate.Voice.directorWash))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(marks.count == 1 ? "1 mark" : "\(marks.count) marks")
        }
    }

    private var volumePopover: some View {
        HStack(spacing: 10) {
            Button { muted.toggle(); applyVolume() } label: { Image(systemName: muted ? "speaker.slash" : "speaker.wave.2") }
                .buttonStyle(.gate(.ghost, .small, icon: true)).help(muted ? "Unmute" : "Mute")
            Slider(value: $volume, in: 0...1).frame(width: 140).controlSize(.small)
                .onChange(of: volume) { _, _ in muted = false; applyVolume() }
                .accessibilityLabel("Volume")
        }
        .padding(12)
    }

    // MARK: Overlays

    private var showsHint: Bool { model.isPreview || screeningsSeen < 2 }

    private var hint: some View {
        HStack(spacing: 8) { Text("Press"); Kbd("N"); Text("to mark a moment. Playback won\u{2019}t stop.") }
            .font(.system(size: 12)).foregroundStyle(Gate.Text.tertiary)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 112)
            .allowsHitTesting(false)
    }

    private var quietLabels: some View {
        ZStack {
            if !marks.isEmpty {
                HStack(spacing: 6) { PinMark(size: 10, color: Gate.Steel.ramp[6]); Text("\(marks.count)") }
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 24).padding(.bottom, 18)
                    .accessibilityLabel("\(marks.count) marks")
            }
            if showTime {
                Text(Timecode.format(model.position, fps: model.fps)).font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.disabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 24).padding(.bottom, 20)
            }
        }
        .allowsHitTesting(false)
    }

    /// "Mark 3 at 01:12:08 · Keep watching. Write it after." with Undo. Glass, top right.
    private func markToast(_ note: ReviewComment) -> some View {
        let n = (model.screeningMarkIDs.firstIndex(of: note.id) ?? 0) + 1
        return HStack(spacing: 12) {
            PinMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Mark \(n) at \(Text(Timecode.format(model.noteTime(note) ?? 0, fps: model.fps)).font(Gate.Font.timecode))").font(Gate.Font.body).foregroundStyle(Gate.Text.primary)
                Text("Keep watching. Write it after.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            Button { undoMark(note.id) } label: { HStack(spacing: 6) { Text("Undo"); KeyHint("\u{2318}Z") } }
                .buttonStyle(.gate(.ghost, .small)).focusable(false)
                .accessibilityHidden(true)
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .fixedSize()
        .background(GlassBackground(radius: 12))
        .onHover { toastHovered = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 68).padding(.trailing, 20)
    }

    private var toastTransition: AnyTransition {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 8)), removal: .opacity)
    }

    // MARK: Acts

    /// N: a mark at the playhead. Never pauses. Marks closer than 0.5 s are ignored;
    /// within 1 s they merge, and the toast re-times.
    private func dropMark() {
        if let last = marks.last, let t = model.noteTime(last), abs(model.position - t) < 1 {
            if abs(model.position - t) >= 0.5 { toastMarkID = last.id; toastToken += 1 }
            return
        }
        let before = model.screeningMarkIDs
        model.mark()
        guard let id = model.screeningMarkIDs.last, model.screeningMarkIDs.count > before.count else { return }
        model.toast = nil
        toastMarkID = id; toastToken += 1
        model.registerUndo("Mark") { $0.undoScreeningMark(id) }
        AccessibilityNotification.Announcement("Mark \(model.screeningMarkIDs.count) at \(Self.spoken(model.position))").post()
    }

    private func undoMark(_ id: String) {
        if let manager = model.undoManager, manager.canUndo, manager.undoActionName == "Mark" { manager.undo() } else { model.undoScreeningMark(id) }
        if toastMarkID == id { toastMarkID = nil }
    }

    private func end() { model.endScreening() }

    private func toggleFullScreen() { (window ?? NSApp.keyWindow)?.toggleFullScreen(nil) }
    private func enterFullScreenIfAsked(_ window: NSWindow?) {
        guard startsFullScreen, !model.isPreview, !enteredFullScreen, let window, !window.styleMask.contains(.fullScreen) else { return }
        enteredFullScreen = true
        window.toggleFullScreen(nil)
    }

    private func applyVolume() {
        guard !model.isPreview else { return }
        model.player.volume = Float(volume); model.player.isMuted = muted
    }

    // MARK: Chrome timing

    /// Pointer movement or a key shows the chrome and restarts the idle timer.
    private func wake() {
        let now = Date()
        if chromeShown, now.timeIntervalSince(clock.lastWake) < 0.25 { return }
        clock.lastWake = now
        if !chromeShown { chromeShown = true }
        activity += 1
    }

    private func hideWhenIdle() async {
        let after = Self.hideAfter
        guard after > 0 else { return }
        try? await Task.sleep(for: .seconds(after))
        guard !Task.isCancelled, model.playing, !dockHovered, !showsVolume, !NSWorkspace.shared.isVoiceOverEnabled else { return }
        chromeShown = false
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    /// Settings › General: seconds of stillness before the chrome fades. 0 or less never hides it.
    static var hideAfter: Double {
        switch UserDefaults.standard.object(forKey: "hideControlsAfter") {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.filter { $0.isNumber || $0 == "." }) ?? 0
        default: return 2
        }
    }

    private func expireToast() async {
        guard toastMarkID != nil else { return }
        try? await Task.sleep(for: .seconds(3))
        while toastHovered && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(250)) }
        if !Task.isCancelled { toastMarkID = nil }
    }

    private func setTrafficLights(_ visible: Bool) {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Gate.Motion.settleDuration
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(type)?.animator().alphaValue = visible ? 1 : 0 }
        }
    }

    // MARK: Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard !TextInput.hasFocus else { return .ignored }
        if press.modifiers.contains(.command) || press.modifiers.contains(.control) { return .ignored }
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .space: model.togglePlayback(); return .handled
        case .escape: end(); return .handled
        case .leftArrow: if shift { jumpScene(-1) } else { model.seek(model.position - 5) }; wake(); return .handled
        case .rightArrow: if shift { jumpScene(1) } else { model.seek(model.position + 5) }; wake(); return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "n": dropMark(); return .handled
        case "j": model.shuttle(model.playing && model.player.rate < 0 ? max(-4, model.player.rate * 2) : -1); return .handled
        case "k": model.shuttle(0); return .handled
        case "l": model.shuttle(model.playing && model.player.rate >= 1 ? min(4, model.player.rate * 2) : 1); return .handled
        case "f": toggleFullScreen(); return .handled
        case "w": end(); return .handled
        default: wake(); return .ignored
        }
    }

    private func jumpScene(_ delta: Int) {
        let scenes = model.stripScenes
        guard let i = scenes.firstIndex(where: { model.position >= $0.start && model.position < $0.end }) ?? (scenes.isEmpty ? nil : scenes.count - 1) else { return }
        let target = delta < 0 && model.position - scenes[i].start > 1 ? i : i + delta
        if scenes.indices.contains(target) { model.seek(scenes[target].start) }
    }

    // MARK: Helpers

    /// "1 minute 12", "40 seconds".
    static func spoken(_ seconds: Double) -> String {
        let s = Int(max(0, seconds)), m = s / 60, r = s % 60
        if m == 0 { return r == 1 ? "1 second" : "\(r) seconds" }
        return (m == 1 ? "1 minute" : "\(m) minutes") + (r > 0 ? " \(r)" : "")
    }

    /// Where a time sits on a strip of this width. Mirrors SceneStrip.
    static func stripX(_ t: Double, scenes: [StripScene], duration: Double, width: CGFloat) -> CGFloat {
        let gaps = CGFloat(max(0, scenes.count - 1)) * Gate.Component.Strip.gap
        let total = max(duration, scenes.map(\.end).max() ?? 0, 0.001), usable = max(1, width - gaps)
        guard !scenes.isEmpty else { return usable * t / total }
        var x: CGFloat = 0
        for (i, s) in scenes.enumerated() {
            let w = usable * s.duration / total
            if t < s.end || i == scenes.count - 1 { return x + w * CGFloat(max(0, min(1, (t - s.start) / max(s.duration, 0.0001)))) }
            x += w + Gate.Component.Strip.gap
        }
        return x
    }
}

/// Remembers the last wake without redrawing on every pointer move.
@MainActor final class WakeClock { var lastWake = Date.distantPast }

extension FilmModel {
    /// Takes back a mark from this screening. Its number stays used.
    func undoScreeningMark(_ id: String) {
        screeningMarkIDs.removeAll { $0 == id }
        if freshMarkID == id { freshMarkID = nil }
        perform { try $0.dropNote(id: id) }
        registerUndo("Mark") { $0.redoScreeningMark(id) }
    }
    func redoScreeningMark(_ id: String) {
        perform { try $0.restoreNote(id: id) }
        if !screeningMarkIDs.contains(id) { screeningMarkIDs.append(id) }
        registerUndo("Mark") { $0.undoScreeningMark(id) }
    }
}

// MARK: Titlebar over picture

/// The titlebar over the picture: crumb without menus, rooms, the editor, Back to notes.
/// No steel button while a cut plays.
struct WatchTitlebar: View {
    @Bindable var model: FilmModel
    var app: AppModel?
    var end: () -> Void
    var body: some View {
        ZStack {
            TitlebarDragArea()
            HStack(spacing: 10) {
                Color.clear.frame(width: 62, height: 1)
                HStack(spacing: 2) {
                    Text(model.filmName).fontWeight(.semibold).foregroundStyle(Gate.Text.primary).padding(.horizontal, 7)
                    Text("/").foregroundStyle(Gate.Text.disabled).padding(.horizontal, 2)
                    Text(model.watchedCut?.name ?? "Working cut").fontWeight(.medium).foregroundStyle(Gate.Text.secondary).padding(.horizontal, 7)
                }
                .font(.system(size: 13)).lineLimit(1).allowsHitTesting(false)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Button { model.showEditorPopover.toggle() } label: { EditorPill(state: model.pill, program: model.editorProgram) }
                        .buttonStyle(.plain)
                        .gatePopover(isPresented: $model.showEditorPopover, arrowEdge: .bottom) { EditorPopover(model: model) }
                        .help("The editor")
                    Button(action: end) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble").font(.system(size: 12, weight: .medium))
                            Text("Back to notes")
                            KeyHint("esc")
                        }
                    }
                    .buttonStyle(.gate(.ghost))
                    .help("Back to notes (esc)")
                }
            }
            .padding(.leading, 20).padding(.trailing, 12)
            RoomSwitcher(model: model)
        }
        .frame(height: Gate.Size.titlebar)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }
}

/// Hands the hosting window to SwiftUI.
struct WindowReader: NSViewRepresentable {
    var onChange: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView { ReaderView(onChange: onChange) }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class ReaderView: NSView {
        let onChange: (NSWindow?) -> Void
        init(onChange: @escaping (NSWindow?) -> Void) { self.onChange = onChange; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = self.window
            DispatchQueue.main.async { self.onChange(window) }
        }
    }
}
