import SwiftUI
import DirectionCore

// Start: from nothing to a first cut. Brief → Footage (bring it, the editor logs it) → First look.
// Films (01–02) is in FilmsView.swift; the brief in BriefViews.swift; footage and logging in
// FootageViews.swift; the assembly in AssemblyView.swift.

/// Brief · Footage · First look, in place of the room switcher until the film has footage logged.
/// Done steps are clickable backwards: Brief opens the brief.
struct OnboardingStepper: View {
    var step: OnboardingStep
    @FocusedValue(\.onboardingFilm) private var film

    var body: some View {
        HStack(spacing: 6) {
            item(.brief, "Brief")
            bar
            item(.footage, "Footage")
            bar
            item(.firstLook, "First look")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Steps")
    }

    private var bar: some View { Gate.Line.strong.frame(width: 18, height: 1) }

    private func item(_ s: OnboardingStep, _ title: String) -> some View {
        let done = s < step, on = s == step
        return Button { if done, s == .brief { film?.sheet = .brief } } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(on ? Gate.Steel.ramp[9] : done ? Gate.Surface.hover : .clear)
                    if !on && !done { Circle().strokeBorder(Gate.Line.strong, lineWidth: 1) }
                    if done { Image(systemName: "checkmark").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Gate.Text.primary) }
                    else { Text(String(s.rawValue + 1)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(on ? Gate.Steel.ramp[1] : Gate.Text.tertiary) }
                }
                .frame(width: 16, height: 16)
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(on ? Gate.Text.primary : done ? Gate.Text.secondary : Gate.Text.disabled)
            .padding(.leading, 6).padding(.trailing, 10).frame(height: 24)
            .background { if on { Capsule().fill(Gate.Surface.raised).overlay(Capsule().strokeBorder(Gate.Line.subtle, lineWidth: 1)) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(done && s == .brief)
        .help(done && s == .brief ? "Edit the brief (\u{2318}B)" : "")
        .accessibilityLabel("\(title), step \(s.rawValue + 1) of 3, \(on ? "current" : done ? "done" : "not yet")")
    }
}

extension FocusedValues {
    /// The film in onboarding, so the titlebar's stepper can step back.
    @Entry var onboardingFilm: FilmModel?
}

/// The window's content before the first cut: the brief, bringing footage, logging, then the assembly.
struct OnboardingView: View {
    @Bindable var model: FilmModel
    var step: OnboardingStep
    var body: some View {
        Group {
            switch step {
            case .brief: OnboardingBriefStep(model: model)
            case .footage:
                if model.hasFootage { OnboardingLoggingView(model: model) } else { OnboardingFootageDrop(model: model) }
            case .firstLook: OnboardingAssemblyView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedSceneValue(\.onboardingFilm, model)
        .transition(.opacity)
    }
}

/// What onboarding holds before it reaches the store: the brief being written (saved on Continue,
/// so typing never moves the window on) and footage dropped but not yet handed to the editor.
/// One per open film, shared by the views and the titlebar's primary.
@MainActor @Observable final class OnboardingSession {
    enum Field: Hashable { case title, logline, feeling }

    weak var owner: FilmModel?
    var title = ""
    var brief = Brief()
    /// Required fields left empty when Continue was pressed.
    var missing: Set<Field> = []
    /// Dropped footage, imported after a second unless more arrives.
    var pending: [URL] = []
    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    private static var sessions: [ObjectIdentifier: OnboardingSession] = [:]

    static func of(_ model: FilmModel) -> OnboardingSession {
        let key = ObjectIdentifier(model)
        if let s = sessions[key], s.owner === model { return s }
        sessions = sessions.filter { $0.value.owner != nil }
        let s = OnboardingSession()
        s.owner = model; s.title = model.isUntitled ? "" : model.filmName; s.brief = model.brief
        sessions[key] = s
        return s
    }

    var canContinue: Bool { [title, brief.logline, brief.feeling].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    /// Continue (⌘↩): names the film, saves the brief, and hands over any footage attached from a folder.
    func continueBrief() {
        guard let model = owner else { return }
        missing = Set([(Field.title, title), (.logline, brief.logline), (.feeling, brief.feeling)].filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.0))
        guard missing.isEmpty else { return }
        model.renameFilm(title)
        model.saveBrief(brief)
        if !pending.isEmpty { importPending() }
    }

    /// Footage dropped on the window: wait a second for more, then start logging.
    func add(_ urls: [URL], wait: Bool) {
        pending += urls.filter { !pending.contains($0) }
        pendingTask?.cancel()
        guard wait else { importPending(); return }
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.importPending()
        }
    }

    func importPending() {
        pendingTask?.cancel(); pendingTask = nil
        guard let model = owner, !pending.isEmpty, model.brief.isComplete else { return }
        let files = pending; pending = []
        model.importFootage(files)
    }
}

extension FilmModel {
    /// "Untitled film", "Untitled film 2": the name a new film gets before the brief names it.
    var isUntitled: Bool { (project?.name ?? "").range(of: #"^Untitled film( \d+)?$"#, options: .regularExpression) != nil }

    /// Renames the film. Its package on disk keeps its name; the Films list shows the new one.
    func renameFilm(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = project, !name.isEmpty, name != p.name else { return }
        let old = p.name
        perform { store in
            _ = try store.update(expectedRevision: p.editRevision, key: UUID().uuidString, request: Data("rename:\(name)".utf8), summary: "Named the film \(name)") { $0.name = name }
            try? ProjectLibrary().register(store)
        }
        registerUndo("Rename Film") { $0.renameFilm(old) }
    }

    /// Leaves logging for Dailies; the editor keeps logging in the background.
    func openDailiesFromLogging(scene: String? = nil) {
        onboardingDismissed = true
        selectedSceneID = scene ?? scenes.first?.id
        openTakeID = nil
        go(.dailies)
    }

    func onboardingPrimary(_ step: OnboardingStep) -> PrimaryAction? {
        let session = OnboardingSession.of(self)
        switch step {
        case .brief:
            return PrimaryAction(title: "Continue", enabled: session.canContinue) { session.continueBrief() }
        case .footage:
            if hasFootage { return PrimaryAction(title: "Open Dailies", icon: "square.grid.2x2", enabled: !dailies.scenes.isEmpty) { self.openDailiesFromLogging() } }
            return PrimaryAction(title: "Start logging", enabled: !session.pending.isEmpty) { session.importPending() }
        case .firstLook:
            return PrimaryAction(title: "Screen the assembly", icon: "play.fill", enabled: !cuts.isEmpty) { self.go(.screening) }
        }
    }
}
