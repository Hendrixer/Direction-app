import SwiftUI
import AppKit
import DirectionCore
import DirectionTools

/// The editor's runs for one film: activity, state, control (specs/editor.md). Work is found from
/// the store's state, so a turnover, an answer or a picture lock starts the editor however it was made.
@MainActor @Observable final class EditorRunsModel {
    /// Oldest first.
    var runs: [EditorRun] = []
    /// Newest first, every run (and your own session's calls).
    var activity: [EditorActivity] = []
    /// Snapshots and previews: whether Direction starts the editor, and whether it's set up.
    var previewStarts: Bool?
    var previewReady = true
    /// "Show all" in the activity popover.
    var showsAllActivity = false
    /// Snapshots draw the popover themselves; the pill still looks open.
    var previewPillOpen = false
    /// The setup sheet offered itself once for this film.
    @ObservationIgnored private var offeredSetup = false
    @ObservationIgnored private var known: [String: EditorRunState] = [:]
    @ObservationIgnored private var recovered = false
    /// Bumped when your own session's latest call goes stale, so the pill stops saying it works.
    private var tick = 0
    @ObservationIgnored private var staleTask: Task<Void, Never>?

    init() {
        // The app's own tool calls (bringing footage in) are the director's, never the editor's activity.
        EditorActivityLog.isEnabled = false
    }

    // MARK: Reading

    /// Called from `FilmModel.refresh()` whenever the store changes.
    func refresh(_ film: FilmModel) {
        guard !film.isPreview, let store = film.store else { return }
        let runner = EditorRunner.shared
        runner.register(store)
        if !recovered { recovered = true; runner.recover(store); EditorPrograms.shared.refreshIfNeeded() }
        runs = (try? store.runs()) ?? []
        activity = (try? store.activity(limit: 200)) ?? []
        watchOwnSession()
        announce(film)
        findWork(film, store: store)
        offerSetup(film)
        runner.pump()
    }

    /// Direction starts the editor (Settings › Editor › Editor runs on isn't Your own session).
    var startsEditor: Bool { previewStarts ?? EditorSetup.directionStarts }
    /// The program Direction starts is chosen and found.
    var ready: Bool { previewStarts != nil ? previewReady : EditorSetup.ready }

    /// The run the window shows: working, paused, waiting, stopped or held, newest first.
    var current: EditorRun? {
        runs.last { $0.state.isActive } ?? runs.last { [.paused, .failed, .waitingForYou].contains($0.state) || ($0.state == .queued && $0.held) }
    }
    var active: EditorRun? { runs.last { $0.state.isActive } }
    var isWorking: Bool { active != nil }
    var isPaused: Bool { current?.state == .paused }
    var failed: EditorRun? { current?.state == .failed ? current : nil }
    /// Paused because Direction quit: the banner offers Resume.
    var pausedByQuit: EditorRun? { runs.last { $0.state == .paused && $0.pausedByQuit } }
    /// Work waiting for your Start (Start work: Ask me first, or after you stopped it).
    var held: EditorRun? { runs.last { $0.state == .queued && $0.held } }
    func run(for turnover: Turnover?) -> EditorRun? { turnover.flatMap { t in runs.last { $0.turnoverID == t.id } } }
    func activity(of run: EditorRun?) -> [EditorActivity] { run.map { r in activity.filter { $0.runID == r.id } } ?? activity }

    /// The latest activity that had a time, while it's fresh: the editor's playhead on the strip.
    var playhead: EditorActivity? {
        guard isWorking || ownSession != nil else { return nil }
        return activity.first { $0.time != nil && $0.runID == active?.id }
    }

    /// Your own session's latest call, while it's recent: its activity drives the pill and the playhead too.
    var ownSession: EditorActivity? {
        _ = tick
        guard let a = activity.first, a.runID == nil, Date().timeIntervalSince1970 - a.at < Self.ownSessionWindow else { return nil }
        return a
    }
    static let ownSessionWindow: Double = 20

    private func watchOwnSession() {
        staleTask?.cancel()
        guard let a = ownSession else { return }
        let left = a.at + Self.ownSessionWindow - Date().timeIntervalSince1970
        staleTask = Task { [weak self] in try? await Task.sleep(for: .seconds(max(0.1, left))); if !Task.isCancelled { self?.tick += 1 } }
    }

    /// "Watching 01:12", "Cutting scene 2": the pill's words while the editor works without other progress.
    var activityText: String? {
        guard let a = active.map({ r in activity.first { $0.runID == r.id } }) ?? ownSession else { return nil }
        let object = a.mono ? String(a.object.prefix(5)) : a.object
        return "\(a.verb) \(object.count > 18 ? String(object.prefix(17)) + "\u{2026}" : object)"
    }

    /// "Claude Code · Claude Opus 5.5 · 4 min" under the activity popover's title.
    func programLine(_ run: EditorRun, now: Date = Date()) -> String {
        let program = EditorProgram(rawValue: run.program)
        let version = program.map { p in run.version.isEmpty ? nil : p.versionName(run.version) } ?? nil
        let minutes = run.startedAt.map { max(1, Int(((run.endedAt ?? now.timeIntervalSince1970) - $0) / 60)) }
        return [program?.name, version, minutes.map { "\($0) min" }].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Finding work

    private func findWork(_ film: FilmModel, store: ProjectStore) {
        guard startsEditor, ready, !film.offline, !film.directing.editorPaused, let program = EditorSetup.runsOn.program else { return }
        func latest(_ job: EditorJob, _ turnoverID: String? = nil) -> EditorRun? { runs.last { $0.job == job && $0.turnoverID == turnoverID } }
        // Turn over, Assemble from circles: each open turnover gets one run.
        for t in film.turnovers where t.state.isOpen && !runs.contains(where: { $0.turnoverID == t.id }) {
            create(t.kind == "assembly" ? .assemble : .turnover, program: program, turnoverID: t.id, store: store)
        }
        // Footage arriving: once the index has looked and Direction has the words, log what isn't logged.
        if film.isLogging, !film.index.busy {
            let total = film.project?.assets.count ?? 0, last = latest(.logFootage)
            if last == nil || (last!.state == .done && (last!.assetCount ?? 0) < total) { create(.logFootage, program: program, assetCount: total, store: store) }
        }
        // Lock picture: finishing, once.
        if film.isPictureLocked, latest(.finish) == nil, !EditorRunner.finished(EditorRun(job: .finish, program: program.rawValue, version: ""), store: store) {
            create(.finish, program: program, store: store)
        }
        // Answering a question or approving a read-back continues the same session (one run at a time).
        for r in runs where r.state == .waitingForYou && !EditorRunner.shared.isLive(r.id) && active == nil {
            if let answer = continuation(for: r, film: film) { EditorRunner.shared.launch(r, store: store, continuation: EditorJobs.continuation(answer, job: r.job)); break }
        }
    }

    private func create(_ job: EditorJob, program: EditorProgram, turnoverID: String? = nil, assetCount: Int? = nil, store: ProjectStore) {
        var run = EditorRun(job: job, program: program.rawValue, version: EditorSetup.version(program), turnoverID: turnoverID, assetCount: assetCount)
        run.held = EditorSetup.asksFirst
        try? store.saveRun(run)
        runs.append(run)
    }

    /// What the director said since the run stopped to wait, in words for the editor.
    private func continuation(for run: EditorRun, film: FilmModel) -> String? {
        let since = run.endedAt ?? run.updatedAt
        var said: [String] = []
        if let t = film.turnovers.first(where: { $0.id == run.turnoverID }) {
            if t.readBackApproved, t.state == .cutting, t.updatedAt > since {
                said.append("I approved your read-back. Cut it.")
                for (id, text) in t.adjustments { said.append("For note \(film.noteNumber(id)) I said: \u{201C}\(text)\u{201D}") }
            }
        }
        for q in film.questions where q.turnoverID == run.turnoverID {
            guard let a = q.answer, a.at > since else { continue }
            let choice = a.choiceID.flatMap { id in q.choices.first { $0.id == id }?.label }
            said.append("You asked: \u{201C}\(q.text)\u{201D} " + [choice.map { "I chose \u{201C}\($0)\u{201D}." }, a.text.map { "I said: \u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " "))
        }
        return said.isEmpty ? nil : said.joined(separator: "\n")
    }

    /// Frame 56 shows itself the first time a film needs the editor and none is set up.
    private func offerSetup(_ film: FilmModel) {
        guard !offeredSetup, !EditorSetup.isChosen, film.hasFootage, film.isLogging, film.sheet == nil else { return }
        offeredSetup = true
        film.sheet = .editorSetup
    }

    /// "The editor stopped": a notification (or a toast when Direction is in front), once per failure.
    private func announce(_ film: FilmModel) {
        for r in runs {
            let before = known[r.id]; known[r.id] = r.state
            guard before != nil, before != r.state, r.state == .failed, let reason = r.reason, reason != .pausedByQuit else { continue }
            film.onNotify?("The editor stopped", EditorStopCopy.title(reason, run: r), NotificationKey.editorStopped)
        }
    }

    // MARK: Control

    /// Start (Ask me first, or after you stopped it).
    func start(_ film: FilmModel) {
        guard let store = film.store else { return }
        if let h = held { _ = try? store.updateRun(h.id) { $0.held = false }; refresh(film); return }
        // A turnover you stopped waits for Start: it gets a new run.
        if let t = film.openTurnover, let program = EditorSetup.runsOn.program, run(for: t)?.state == .stopped {
            create(t.kind == "assembly" ? .assemble : .turnover, program: program, turnoverID: t.id, store: store)
            if let r = runs.last { _ = try? store.updateRun(r.id) { $0.held = false } }
            refresh(film)
        }
    }

    func pause(_ film: FilmModel) {
        guard let store = film.store, let r = active ?? current, r.state.isOpen else { return }
        EditorRunner.shared.pause(r.id, store: store)
        film.refresh(force: true)
    }

    /// Resume: the saved session and "Continue where you stopped."
    func resume(_ film: FilmModel) {
        guard let store = film.store, let r = runs.last(where: { $0.state == .paused }) else { film.refresh(force: true); return }
        EditorRunner.shared.launch(r, store: store, continuation: EditorJobs.continuation("Continue where you stopped.", job: r.job))
        film.refresh(force: true)
    }

    /// Try again: a new invocation of the same job, on the previous session if it still exists.
    func retry(_ film: FilmModel, _ answer: String = "Try again. Continue where you stopped.") {
        guard let store = film.store, let r = runs.last(where: { $0.state == .failed }) else { return }
        // Not installed: look again, and start once the search is done (pump waits for it).
        if r.reason == .notInstalled {
            EditorPrograms.shared.refresh()
            _ = try? store.updateRun(r.id) { $0.state = .queued; $0.held = false; $0.reason = nil }
            film.refresh(force: true); return
        }
        if r.reason == .notSignedIn, let p = EditorProgram(rawValue: r.program) { EditorSetup.setSignedIn(p, nil); EditorPrograms.shared.checkSignIn(p) }
        EditorRunner.shared.launch(r, store: store, continuation: EditorJobs.continuation(answer, job: r.job))
        film.refresh(force: true)
    }

    /// Spend cap: carry on with the footage only.
    func continueWithoutServices(_ film: FilmModel) { retry(film, "Continue without making anything with a service. Use the footage.") }

    /// Stop the editor? The turnover stays turned over and the unfinished cut is discarded.
    func confirmStop(_ film: FilmModel) {
        guard let r = active ?? current else { return }
        let alert = NSAlert()
        alert.messageText = "Stop the editor?"
        alert.informativeText = stopDetail(r, film: film)
        alert.addButton(withTitle: "Stop"); alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        stop(film)
    }

    func stopDetail(_ r: EditorRun, film: FilmModel) -> String {
        switch r.job {
        case .turnover: "\(film.nextCutName) isn\u{2019}t finished. Your notes stay turned over, and you can start again."
        case .assemble: "The assembly isn\u{2019}t finished. Your circles stay, and you can start again."
        case .logFootage: "Logging isn\u{2019}t finished. Your footage stays, and you can start again."
        case .finish: "Finishing isn\u{2019}t done. Picture stays locked, and you can start again."
        }
    }

    func stop(_ film: FilmModel) {
        guard let store = film.store, let r = active ?? current else { return }
        EditorRunner.shared.stop(r.id, store: store)
        if let id = r.turnoverID, let t = try? store.turnover(id), t.state.isOpen {
            discardUnfinishedCut(t, store: store)
            _ = try? store.modifyTurnover(id, summary: "Stopped the editor") { t in
                t.state = .waiting; t.message = nil; t.percent = nil; t.phase = nil
                for k in t.noteIDs { t.progress[k] = .queued }
            }
        }
        film.refresh(force: true)
    }

    /// Take the turnover back (frame 58): the notes return to written, the unfinished cut is discarded.
    func takeTurnoverBack(_ film: FilmModel) {
        guard let store = film.store, let t = film.openTurnover else { return }
        if let r = run(for: t), r.state.isOpen { EditorRunner.shared.stop(r.id, store: store) }
        discardUnfinishedCut(t, store: store)
        _ = try? store.modifyTurnover(t.id, summary: "Took the notes back") { if $0.state.isOpen { $0.state = .waiting } }
        film.perform { try $0.cancelTurnover(t.id) }
    }

    /// Edits the editor made toward a cut it never delivered go back to how the turnover found them.
    private func discardUnfinishedCut(_ t: Turnover, store: ProjectStore) {
        guard let current = try? store.read(), current.editRevision > t.baseRevision else { return }
        _ = try? store.restore(revision: t.baseRevision, expectedRevision: current.editRevision, key: "discard-\(t.id)-\(current.editRevision)")
    }

    /// The banner after a quit: Resume, or Not now (it stays paused).
    func dismissQuitBanner(_ film: FilmModel) {
        guard let store = film.store, let r = pausedByQuit else { return }
        _ = try? store.updateRun(r.id) { $0.pausedByQuit = false; $0.reason = nil }
        film.refresh(force: true)
    }
}
