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
    /// Read-back corrections already sent to each waiting run.
    @ObservationIgnored private var sentCorrections: [String: [String: String]] = [:]
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
        let chosen = film.directing.editor.flatMap(EditorRunsOn.init(rawValue:))
        if chosen != choice { choice = chosen }
        let runner = EditorRunner.shared
        runner.register(store)
        if !recovered { recovered = true; runner.recover(store); EditorPrograms.shared.refreshIfNeeded() }
        // Set only when they differ, so the rooms aren't drawn again on every tick of a run.
        let runs = (try? store.runs()) ?? [], activity = (try? store.activity(limit: 200)) ?? []
        if runs != self.runs { self.runs = runs }
        if activity != self.activity { self.activity = activity }
        Self.cleanUpStudies(runs, store: store)
        watchOwnSession()
        announce(film)
        findWork(film, store: store)
        offerSetup(film)
        runner.pump()
    }

    /// Learning from videos leaves nothing behind: once a style or a technique is saved, the downloads and
    /// what was read from them go. A run that stopped keeps them for Try Again.
    static func cleanUpStudies(_ runs: [EditorRun], store: ProjectStore) {
        let film = store.url.standardizedFileURL.path + "/"
        func remove(_ path: String) { if URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(film) { try? FileManager.default.removeItem(atPath: path) } }
        for r in runs where r.state == .done {
            if r.job == .style, let studies = r.studies, !studies.isEmpty {
                studies.forEach(remove)
                _ = try? store.updateRun(r.id) { $0.studies = nil }
            }
            if r.job == .technique, let folder = r.learnFolder {
                remove(folder)
                _ = try? store.updateRun(r.id) { $0.learnFolder = nil; $0.learnVideo = nil }
            }
        }
    }

    /// Who edits this film, as chosen for it in Who's editing? (nil: a film from before films kept their own).
    var choice: EditorRunsOn?
    /// The film's editor, or Settings › Engines › Who edits for a film that has none of its own.
    var runsOn: EditorRunsOn { choice ?? EditorSetup.runsOn }
    /// Direction starts the editor (not your own session).
    var startsEditor: Bool { previewStarts ?? (runsOn != .yourOwn) }
    /// The program Direction starts is chosen and found.
    var ready: Bool { previewStarts != nil ? previewReady : EditorSetup.ready(runsOn, chosen: choice != nil || EditorSetup.isChosen) }

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
    /// Logging you stopped: nothing more is logged until you Start it again.
    var stoppedLogging: EditorRun? { runs.last { $0.job == .logFootage }.flatMap { $0.state == .stopped ? $0 : nil } }
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

    /// "Watching 1:12–1:14", "Cutting scene 2": the pill's words while the editor works without other progress.
    /// A time reads whole: times have no frames to drop now (Timecode.format).
    var activityText: String? {
        guard let a = active.map({ r in activity.first { $0.runID == r.id } }) ?? ownSession else { return nil }
        let object = a.object
        return "\(a.verb) \(object.count > 18 ? String(object.prefix(17)) + "\u{2026}" : object)"
    }

    /// "Claude Opus 5.5 · Extra high effort · 4 min" under the activity popover's title. The version names
    /// the program; with the program's default version, the program does ("Codex · High effort").
    func programLine(_ run: EditorRun, now: Date = Date()) -> String {
        let program = EditorProgram(rawValue: run.program)
        let version = program.map { p in run.version.isEmpty ? nil : p.versionName(run.version) } ?? nil
        let effort = run.effort.flatMap { $0.isEmpty ? nil : EditorProgram.effortName($0) + " effort" }
        let minutes = run.startedAt.map { max(1, Int(((run.endedAt ?? now.timeIntervalSince1970) - $0) / 60)) }
        return [version ?? program?.name, effort, minutes.map { "\($0) min" }].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Finding work

    private func findWork(_ film: FilmModel, store: ProjectStore) {
        // Nothing starts while Who's editing? is open: a new film's work waits for its editor.
        guard startsEditor, ready, !film.offline, !film.directing.editorPaused, film.sheet != .editorSetup, let program = runsOn.program else { return }
        func latest(_ job: EditorJob, _ turnoverID: String? = nil) -> EditorRun? { runs.last { $0.job == job && $0.turnoverID == turnoverID } }
        // Turn over, Assemble from circles: each open turnover gets one run.
        for t in film.turnovers where t.state.isOpen && !runs.contains(where: { $0.turnoverID == t.id }) {
            create(t.kind == "assembly" ? .assemble : .turnover, program: program, turnoverID: t.id, store: store)
        }
        // Footage arriving: log it in batches as takes are ready, one fresh session per batch.
        if film.isLogging, let batch = nextLogBatch(film, store: store) {
            create(.logFootage, program: program, assetCount: film.footage.count, assetIDs: batch, store: store)
        }
        // Prep (specs/script.md, specs/breakdown.md): the picture column when a script comes in, the breakdown
        // once it's OK'd, and a pass whenever the director turns over notes on either.
        if let script = film.script {
            // The first script, or a new draft, since the last pass began.
            let fresh = script.rows.contains { $0.picture.isEmpty } && latest(.script).map { (script.source?.importedAt ?? 0) > $0.createdAt } ?? true
            if (fresh || !script.turnedOver.isEmpty), latest(.script)?.state.isOpen != true { startPrep(.script, film: film, program: program, store: store) }
            if script.isOK {
                let breakdown = film.breakdown
                let fresh = latest(.breakdown) == nil && (breakdown?.shots.isEmpty ?? true)
                if (fresh || breakdown?.turnedOver.isEmpty == false), latest(.breakdown)?.state.isOpen != true { startPrep(.breakdown, film: film, program: program, store: store) }
            }
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

    /// Logging in batches (footage-index.md › Logging in batches): up to 20 takes a run, so every run
    /// stays small and the director can circle while the rest is still coming in. The first batch
    /// starts at 5 ready takes, later ones at 20, and the last with whatever is left. Takes in sync go
    /// together. One logging run at a time, and none while one is stopped or waiting for Try Again.
    static let batchSize = 20, firstBatch = 5

    private func nextLogBatch(_ film: FilmModel, store: ProjectStore) -> [String]? {
        let logging = runs.filter { $0.job == .logFootage }
        guard logging.allSatisfy({ $0.state == .done }) else { return nil }
        let unlogged = film.footage.filter { !film.dailies.isLogged($0.id) }
        var tries: [String: Int] = [:]
        for r in logging { for id in r.assetIDs ?? [] { tries[id, default: 0] += 1 } }
        let decision = Self.logBatch(unlogged: unlogged.map(\.id), ready: Set(unlogged.filter { film.index.readyToLog($0) }.map(\.id)), tries: tries, firstRun: logging.isEmpty) { film.dailies.syncGroup(for: $0)?.takes.map(\.assetID) ?? [] }
        switch decision {
        case .wait: return nil
        case .run(let ids): return ids
        case .unplace(let ids):
            for id in ids { try? store.logUnplaced(assetID: id, caption: film.index.shots(id).first?.look?.description ?? film.asset(id)?.name ?? "Take") }
            return nil
        }
    }

    enum LogBatch: Equatable { case wait, run([String]), unplace([String]) }

    /// Pure: what logging does next with the takes not logged yet, in footage order.
    static func logBatch(unlogged: [String], ready: Set<String>, tries: [String: Int], firstRun: Bool, partners: (String) -> [String]) -> LogBatch {
        let fresh = unlogged.filter { tries[$0, default: 0] < 2 }
        // Takes two runs left unlogged: Direction puts them in Unsorted once nothing else is coming.
        if fresh.isEmpty { return unlogged.isEmpty ? .wait : .unplace(unlogged) }
        let readyFresh = fresh.filter(ready.contains), preparing = readyFresh.count < fresh.count
        guard !readyFresh.isEmpty, readyFresh.count >= batchSize || !preparing || (firstRun && readyFresh.count >= firstBatch) else { return .wait }
        var batch = Array(readyFresh.prefix(batchSize))
        let pool = Set(readyFresh)
        for id in batch { for p in partners(id) where pool.contains(p) && !batch.contains(p) { batch.append(p) } }
        return .run(batch)
    }

    /// Make a style (styles.md › Making a style): the director asked, so it starts now, not held.
    /// False when Direction doesn't start the editor (Your own session) or it isn't set up.
    @discardableResult
    func makeStyle(_ film: FilmModel, request: String, fromFilm: Bool, studies: [URL] = []) -> Bool {
        guard startsEditor, ready, let store = film.store, let program = runsOn.program else { return false }
        var run = EditorSetup.newRun(.style, on: program)
        run.request = request; run.fromFilm = fromFilm; run.studies = studies.isEmpty ? nil : studies.map(\.path)
        try? store.saveRun(run)
        runs.append(run)
        film.refresh(force: true)
        return true
    }

    /// Learn a technique from a video (techniques.md › Learning one), once Direction has it ready in `folder`.
    @discardableResult
    func learnTechnique(_ film: FilmModel, request: String, folder: URL, video: URL) -> Bool {
        guard startsEditor, ready, let store = film.store, let program = runsOn.program else { return false }
        var run = EditorSetup.newRun(.technique, on: program)
        run.request = request; run.learnFolder = folder.path; run.learnVideo = video.path
        try? store.saveRun(run)
        runs.append(run)
        film.refresh(force: true)
        return true
    }

    /// A prep pass: what it changes is marked as this pass's.
    private func startPrep(_ job: EditorJob, film: FilmModel, program: EditorProgram, store: ProjectStore) {
        if job == .script { _ = try? store.beginScriptPass() } else { _ = try? store.beginBreakdownPass() }
        create(job, program: program, store: store)
    }

    /// A prep pass on rows that are going: stopped, so the next one starts on the new rows.
    func stopPrep(_ job: EditorJob, film: FilmModel) {
        guard let store = film.store, let r = runs.last(where: { $0.job == job && $0.state.isOpen }) else { return }
        EditorRunner.shared.stop(r.id, store: store)
    }

    /// Update the breakdown after the script changed (the Breakdown room's banner).
    @discardableResult
    func updateBreakdown(_ film: FilmModel) -> Bool {
        guard startsEditor, ready, let store = film.store, let program = runsOn.program, runs.last(where: { $0.job == .breakdown })?.state.isOpen != true else { return false }
        startPrep(.breakdown, film: film, program: program, store: store)
        if let r = runs.last { _ = try? store.updateRun(r.id) { $0.held = false } }
        film.refresh(force: true)
        return true
    }

    private func create(_ job: EditorJob, program: EditorProgram, turnoverID: String? = nil, assetCount: Int? = nil, assetIDs: [String]? = nil, store: ProjectStore) {
        var run = EditorSetup.newRun(job, on: program, turnoverID: turnoverID, assetCount: assetCount, assetIDs: assetIDs)
        run.held = EditorSetup.asksFirst
        try? store.saveRun(run)
        runs.append(run)
    }

    /// What the director said since the run asked, in words for the editor. Corrections to a read-back that
    /// waits for the OK send the editor back to post a new one; it then waits for the OK again.
    private func continuation(for run: EditorRun, film: FilmModel) -> String? {
        // From when it asked, not when it exited: an answer can come in before the program has gone.
        let since = run.askedAt ?? run.endedAt ?? run.updatedAt
        var said: [String] = []
        if let t = film.turnovers.first(where: { $0.id == run.turnoverID }) {
            let corrections = t.noteIDs.compactMap { id in t.adjustments[id].map { "For note \(film.noteNumber(id)) I said: \u{201C}\($0)\u{201D}" } }
            if t.readBackApproved, t.state == .cutting, run.askedForOK ?? (t.updatedAt > since) {
                said.append("I approved your read-back. Cut it.")
                said += corrections
            } else if t.state == .readBack, !t.readBackApproved, !t.adjustments.isEmpty, sentCorrections[run.id] != t.adjustments {
                // Each set of corrections goes once; a new read-back clears them, and new ones go again.
                sentCorrections[run.id] = t.adjustments
                said.append("I corrected your read-back. Post a new one that honors what I said, then wait for my OK again.")
                said += corrections
            }
            if t.adjustments.isEmpty { sentCorrections[run.id] = nil }
        }
        for q in film.questions where q.turnoverID == run.turnoverID {
            guard let a = q.answer, a.at > since || q.createdAt >= since else { continue }
            let choice = a.choiceID.flatMap { id in q.choices.first { $0.id == id }?.label }
            said.append("You asked: \u{201C}\(q.text)\u{201D} " + [choice.map { "I chose \u{201C}\($0)\u{201D}." }, a.text.map { "I said: \u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " "))
        }
        said += EditorJobs.prepAnswers(run.job, script: film.script, breakdown: film.breakdown, since: since)
        return said.isEmpty ? nil : said.joined(separator: "\n")
    }

    /// Frame 56 opens on a new film (FilmModel.askWhoEdits). It also shows itself the first time an older
    /// film needs the editor and none is chosen: takes to log, or a script whose picture isn't written yet.
    private func offerSetup(_ film: FilmModel) {
        let work = (film.hasFootage && film.isLogging) || film.script?.rows.contains(where: { $0.picture.isEmpty }) == true
        guard !offeredSetup, choice == nil, !EditorSetup.isChosen, work, film.sheet == nil else { return }
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
        // Logging you stopped starts again on the same takes; what's logged already stays.
        if let r = stoppedLogging { _ = try? store.updateRun(r.id) { $0.state = .queued; $0.held = false; $0.reason = nil }; refresh(film); return }
        // A turnover you stopped waits for Start: it gets a new run.
        if let t = film.openTurnover, let program = runsOn.program, run(for: t)?.state == .stopped {
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

    /// Finishing again, once you've done what the editor stopped to ask for: a new run for whatever
    /// on the checklist isn't done.
    func finishAgain(_ film: FilmModel) {
        guard let store = film.store, film.isPictureLocked, active == nil, let program = runsOn.program else { return }
        create(.finish, program: program, store: store)
        if let r = runs.last { _ = try? store.updateRun(r.id) { $0.held = false } }
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
        case .style: "The style isn\u{2019}t saved. Your film is as it was, and you can ask again."
        case .technique: "The technique isn\u{2019}t saved. Your film is as it was, and you can ask again."
        case .script: "The picture column isn\u{2019}t finished. What\u{2019}s written stays, and you can start again."
        case .breakdown: "The breakdown isn\u{2019}t finished. What\u{2019}s there stays, and you can start again."
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
