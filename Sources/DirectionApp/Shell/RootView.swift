import SwiftUI
import DirectionCore

/// The main window: the Films list when no film is open, otherwise the film.
struct MainWindow: View {
    @Bindable var app: AppModel
    var body: some View {
        Group {
            if let film = app.film { FilmWindow(app: app, model: film) }
            else { FilmsView(app: app) }
        }
        .frame(minWidth: Gate.Size.windowMin.width, minHeight: Gate.Size.windowMin.height)
        .background(WindowConfigurator())
        .preferredColorScheme(.dark)
        .alert("Direction", isPresented: Binding(get: { app.error != nil || app.film?.error != nil }, set: { if !$0 { app.error = nil; app.film?.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.error ?? app.film?.error ?? "") }
    }
}

/// One open film: titlebar, banners, the current room, then sheets and overlays.
struct FilmWindow: View {
    var app: AppModel?
    @Bindable var model: FilmModel
    @State private var sweep: CGFloat = -1
    @Environment(\.undoManager) private var undoManager
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if !screeningFullBleed { Titlebar(model: model, app: app) }
                SystemBanners(model: model)
                EditorRunBanner(model: model)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if screeningFullBleed { ScreeningRoom(model: model, app: app).environment(\.editorPlayhead, nil) }
            sweepEdge
            if let sheet = model.sheet { sheetView(sheet).zIndex(10) }
            if model.showCommandMenu { CommandMenuOverlay(model: model, app: app).zIndex(20) }
            if model.showShortcuts { ShortcutsOverlay(model: model).zIndex(20) }
            toast.zIndex(30)
            // Grain sits on the chrome, never on a full-bleed picture.
            if !screeningFullBleed { GrainOverlay().ignoresSafeArea().zIndex(40) }
        }
        .background(Gate.Surface.ground)
        .ignoresSafeArea()
        // Nothing moves during playback except the playhead and time.
        .environment(\.motionHeld, model.playing)
        .environment(\.editorPlayhead, editorPlayhead)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: model.sweepToken) { _, _ in runSweep() }
        .onChange(of: model.position) { _, _ in model.tickChanges() }
        .onChange(of: model.openQuestions.count) { _, _ in app?.updateDockBadge() }
        .onChange(of: model.unreviewedAnswers.count) { _, _ in app?.updateDockBadge() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in acceptDrop(providers) }
        .animation(gateAnimation(Gate.Motion.glide), value: model.sheet)
    }

    private var screeningFullBleed: Bool { model.room == .screening && model.onboardingStep == nil }
    /// The editor's latest timed activity, for every scene strip. Never in Screening.
    private var editorPlayhead: EditorPlayheadValue? {
        guard model.room != .screening, let a = model.runs.playhead, let t = a.time else { return nil }
        return EditorPlayheadValue(time: t, at: a.at, hold: model.isPreview)
    }

    @ViewBuilder private var content: some View {
        if let step = model.onboardingStep { OnboardingView(model: model, step: step) }
        else {
            switch model.room {
            case .dailies: DailiesRoom(model: model)
            case .script: ScriptRoom(model: model)
            case .screening: Color.clear
            case .notes: NotesRoom(model: model)
            case .changes: ChangesRoom(model: model)
            case .finish: FinishRoom(model: model)
            }
        }
    }

    @ViewBuilder private func sheetView(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .turnover: TurnoverSheet(model: model)
        case .lockPicture: LockPictureSheet(model: model)
        case .deliver: DeliverSheet(model: model)
        case .share: ShareSheet(model: model)
        case .relink: RelinkSheet(model: model)
        case .brief: BriefSheet(model: model)
        case .look: LookSheet(model: model)
        case .editorSetup: EditorSetupSheet(model: model)
        }
    }

    @ViewBuilder private var sweepEdge: some View {
        if sweep >= 0 {
            GeometryReader { g in
                // One pass left to right, then the edge rests as a static line before fading.
                if sweep < 1 { Gate.Voice.prism.frame(width: g.size.width * 0.4, height: 2).offset(x: g.size.width * (sweep * 1.4 - 0.4)) }
                else { Gate.Voice.prism.frame(width: g.size.width, height: 2) }
            }.frame(height: 2).padding(.top, Gate.Size.titlebar).allowsHitTesting(false).zIndex(5).transition(.opacity)
        }
    }

    private func runSweep() {
        sweep = 0
        withAnimation(gateAnimation(Gate.Motion.sweep)) { sweep = 1 }
        Task {
            try? await Task.sleep(for: .seconds(Gate.Motion.sweepDuration + Gate.Motion.shimmerPeriod))
            withAnimation(gateAnimation(Gate.Motion.settle)) { sweep = -1 }
        }
    }

    @ViewBuilder private var toast: some View {
        if let toast = model.toast {
            VStack {
                if model.room == .screening { ToastView(toast: toast, action: toast.run.map { run in { model.toast = nil; run() } }) { model.toast = nil }.padding(.top, 70); Spacer() }
                else { Spacer(); ToastView(toast: toast, action: toast.actionTitle == nil ? nil : { model.toast = nil; if let run = toast.run { run() } else { model.go(.changes) } }) { model.toast = nil }.padding(.bottom, 96) }
            }
            .frame(maxWidth: .infinity, alignment: model.room == .screening ? .topTrailing : .bottomLeading)
            .padding(.horizontal, model.room == .screening ? 20 : 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .task(id: toast.id) { try? await Task.sleep(for: .seconds(toast.actionTitle == nil ? 4 : 8)); if model.toast?.id == toast.id { model.toast = nil } }
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup(); var urls: [URL] = []
        for p in providers { group.enter(); _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { urls.append(url) }; group.leave() } }
        group.notify(queue: .main) { MainActor.assumeIsolated { model.importFootage(urls) } }
        return true
    }
}

extension FilmModel {
    /// The one steel button: the room's primary action in its current state.
    var primaryAction: PrimaryAction? {
        if let p = editorPrimary { return p }
        if let step = onboardingStep { return onboardingPrimary(step) }
        switch room {
        case .dailies: return dailiesPrimary
        case .script: return scriptPrimary
        case .screening: return nil
        case .notes: return notesPrimary
        case .changes: return changesPrimary
        case .finish: return finishPrimary
        }
    }

    /// When Direction starts the editor: work held for your Start makes the room's primary "Start the
    /// editor", and a stopped turnover makes it "Try again" in Notes (frame 58).
    private var editorPrimary: PrimaryAction? {
        guard runs.startsEditor, room != .screening, onboardingStep != .brief else { return nil }
        if case .readyToCut = pill { return PrimaryAction(title: "Start the editor", icon: "play.fill", help: "Start the editor (\u{2318}\u{21A9})") { self.runs.start(self) } }
        if let f = runs.failed, room == .notes, onboardingStep == nil, f.turnoverID != nil, f.turnoverID == openTurnover?.id {
            return PrimaryAction(title: "Try again", icon: "arrow.uturn.backward", help: "Start the editor again where it stopped (\u{2318}\u{21A9})") { self.runs.retry(self) }
        }
        return nil
    }
}
