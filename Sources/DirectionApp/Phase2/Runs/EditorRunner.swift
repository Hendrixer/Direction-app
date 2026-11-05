import Foundation
import Darwin
import DirectionCore
import DirectionTools

/// Starts Claude Code or Codex for each job and follows it (specs/editor.md › How Direction runs a job).
/// App-wide: a film's run keeps working after its window moves on to another film. One run per
/// film; two films at once; the rest queue. Runs live in each film's store, so they survive relaunch.
@MainActor final class EditorRunner {
    static let shared = EditorRunner()
    static let maxConcurrent = 2

    /// Tests point these at the fake program and helper.
    var programOverride: [EditorProgram: String] = [:]
    var helperOverride: String?
    /// How a program is stopped (Stop, Pause, Quit). Tests shorten the waits.
    var stopSteps = ChildProcesses.gently
    /// Called after a run's state changes, with the film it belongs to.
    var onChange: ((URL) -> Void)?

    private var stores: [String: ProjectStore] = [:]
    private var live: [String: LiveRun] = [:]
    private var awake: NSObjectProtocol?
    private var offlineRetries: [String: Task<Void, Never>] = [:]

    @MainActor final class LiveRun {
        let runID: String, store: ProjectStore, program: EditorProgram, process: Process
        var claude = ClaudeStreamParser(), codex = CodexStreamParser()
        var buffer = Data()
        var pending: Set<String> = []
        var intent: RunStateMachine.Intent = .none
        var pauseWhenIdle = false
        var stderrTail: [String] = []
        var failures: [String] = []
        var spendCap: String?
        var result: String?
        var cost: Double?
        var tokens: Int?
        var exited: Int32?
        var outputClosed = false
        var finished = false
        /// This invocation's start, the first time it asked the director something, and whether a read-back
        /// waits on the OK (it posted one, or one was waiting when it began).
        let began = Date().timeIntervalSince1970
        var askedAt: Double?
        var waitsForOK = false
        init(runID: String, store: ProjectStore, program: EditorProgram, process: Process) { self.runID = runID; self.store = store; self.program = program; self.process = process }
    }

    func isLive(_ runID: String) -> Bool { live[runID] != nil }
    /// Tests hold it weakly to see it let go once the run is over.
    func liveRun(_ runID: String) -> LiveRun? { live[runID] }
    var liveCount: Int { live.count }
    func register(_ store: ProjectStore) { stores[store.url.path] = store }

    // MARK: Queue

    /// Starts queued runs where there's room: one per film, two films at once.
    func pump() {
        // Not until programs have been looked for: a run would fail as not installed.
        let programs = EditorPrograms.shared
        guard (programs.checked && !programs.checking) || !programOverride.isEmpty else { return }
        for store in stores.values {
            guard live.count < Self.maxConcurrent, let runs = try? store.runs() else { continue }
            // Any program still alive, a stopped one included while it winds down, keeps the next one waiting.
            guard !runs.contains(where: { isLive($0.id) }) else { continue }
            guard let next = runs.first(where: { $0.state == .queued && !$0.held }) else { continue }
            launch(next, store: store)
        }
    }

    // MARK: Launch

    /// Starts the program for a run: its first job text, or `continuation` on the saved session.
    func launch(_ run: EditorRun, store: ProjectStore, continuation: String? = nil) {
        register(store)
        // The store's copy: the session or state may have moved since the caller read it.
        var run = (try? store.run(run.id)) ?? run
        // A run that never started takes the film's editor and the version and effort chosen now for its job
        // (Choose another editor…, Change per job…).
        if run.invocations == 0, let p = EditorSetup.runsOn(film: try? store.directingState().editor).program, programOverride.isEmpty {
            let version = EditorSetup.version(p, for: run.job), effort = EditorSetup.effort(p, for: run.job)
            if p.rawValue != run.program || version != run.version || effort != run.effort {
                run = (try? store.updateRun(run.id) { $0.program = p.rawValue; $0.version = version; $0.effort = effort }) ?? run
            }
        }
        guard live[run.id] == nil, let program = EditorProgram(rawValue: run.program) else { return }
        offlineRetries[run.id]?.cancel(); offlineRetries[run.id] = nil
        guard let path = programOverride[program] ?? EditorPrograms.shared.install(program)?.path else {
            end(run.id, store: store, outcome: .init(state: .failed, reason: .notInstalled)); return
        }
        guard let helper = helperOverride ?? EditorJobs.helperPath else {
            end(run.id, store: store, outcome: .init(state: .failed, reason: .programQuit, detail: "Direction\u{2019}s tools aren\u{2019}t in this copy of the app. Build it with scripts/build-app.sh.")); return
        }
        do {
            let folder = try EditorJobs.prepareFolder(film: store.url, job: run.job)
            let mcp = folder.appendingPathComponent(".mcp.json"), schema = folder.appendingPathComponent(".direction/result.schema.json")
            try EditorProgram.mcpConfig(helper: helper, film: store.url, runID: run.id).data(pretty: true).write(to: mcp, options: .atomic)
            try EditorProgram.resultSchema.data(pretty: true).write(to: schema, options: .atomic)
            // A continuation without a saved session starts over with the whole job, then the answer.
            let session = continuation == nil ? nil : run.session
            var job = try (session == nil ? EditorJobs.text(for: run, store: store) : continuation!)
            if session == nil, let c = continuation, run.invocations > 0 { job += "\n" + c }
            // The run's own, once it has started; an older run without one reads its job's.
            let effort = run.effort ?? EditorSetup.effort(program, for: run.job)
            let invocation = EditorProgram.Invocation(job: job, role: EditorJobs.role, version: run.version, effort: effort, session: session, folder: folder, mcpConfig: mcp, schema: schema, helper: helper, film: store.url, runID: run.id, scripts: EditorSetup.runsScripts)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = program.arguments(invocation)
            p.currentDirectoryURL = folder
            p.environment = EditorDiscovery.environment(adding: path, extra: ["DIRECTION_RUN_ID": run.id], shellKey: EditorSetup.usesShellKey(program))
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            let l = LiveRun(runID: run.id, store: store, program: program, process: p)
            // At the end of a pipe the handler is called again and again with nothing, so each one
            // stops itself there, on its own thread: left to the main queue, a finished run kept a
            // core spinning for as long as the app stayed open.
            out.fileHandleForReading.readabilityHandler = { [weak self] h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.output(l, d) } }
            }
            err.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { h.readabilityHandler = nil; return }
                DispatchQueue.main.async { MainActor.assumeIsolated { l.stderrTail = Array((l.stderrTail + String(decoding: d, as: UTF8.self).split(separator: "\n").map(String.init)).suffix(20)) } }
            }
            p.terminationHandler = { [weak self] proc in
                let status = proc.terminationStatus
                DispatchQueue.main.async { MainActor.assumeIsolated { l.exited = status; self?.maybeFinish(l) } }
                // A grandchild holding the pipe open mustn't keep the run alive forever.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { l.outputClosed = true; self?.maybeFinish(l) } }
            }
            try p.run()
            ChildProcesses.started(p)
            DirectionLog.info("Started \(program.name) for \(run.job.rawValue) (run \(run.id), \(run.version.isEmpty ? "default version" : run.version), \(effort.isEmpty ? "default effort" : effort + " effort"), session \(session ?? "new"), pid \(p.processIdentifier)) in \(store.url.lastPathComponent)", "editor")
            live[run.id] = l
            try store.updateRun(run.id) { r in
                r.state = .starting; r.reason = nil; r.detail = nil; r.held = false; r.pausedByQuit = false
                r.pid = p.processIdentifier; r.ownerPID = getpid(); r.startedAt = r.startedAt ?? Date().timeIntervalSince1970; r.endedAt = nil; r.invocations += 1
            }
            if run.job == .turnover || run.job == .assemble, let id = run.turnoverID {
                reopenTurnover(id, store: store)
                if let t = try? store.turnover(id) { l.waitsForOK = t.state == .readBack && !t.readBackApproved }
            }
            stayAwake()
            onChange?(store.url)
        } catch {
            end(run.id, store: store, outcome: .init(state: .failed, reason: .programQuit, detail: error.localizedDescription))
        }
    }

    // MARK: Following

    private func output(_ l: LiveRun, _ data: Data) {
        guard !l.finished else { return }
        if data.isEmpty { l.outputClosed = true; maybeFinish(l); return }
        l.buffer.append(data)
        while let nl = l.buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: l.buffer[l.buffer.startIndex..<nl], as: UTF8.self)
            l.buffer.removeSubrange(l.buffer.startIndex...nl)
            let events = l.program == .claudeCode ? l.claude.parse(line) : l.codex.parse(line)
            for e in events { handle(l, e) }
        }
    }

    func handle(_ l: LiveRun, _ e: StreamEvent) {
        switch e {
        case .session(let s): _ = try? l.store.updateRun(l.runID) { if $0.session != s { $0.session = s } }
        case .toolStarted(let id, let name, let input):
            l.pending.insert(id)
            if let r = try? l.store.run(l.runID), r.state == .starting { _ = try? l.store.updateRun(l.runID) { $0.state = .working } }
            // Asking: anything the director does from here on answers it, even before the program exits.
            let tool = name.hasPrefix("mcp__direction__") ? String(name.dropFirst("mcp__direction__".count)) : name
            let readBack = tool == "direction_turnover_update" && input["readBack"] != .null
            if readBack || tool == "direction_ask" { l.askedAt = l.askedAt ?? Date().timeIntervalSince1970 }
            if readBack { l.waitsForOK = true }
            // Direction's own tools write their activity in the MCP server; the rest is the program's.
            let isDirection = name.hasPrefix("mcp__direction__") || name.hasPrefix("direction_")
            if !isDirection, let a = EditorActivityLog.programActivity(tool: name, path: input["file_path"].string ?? input["path"].string ?? input["notebook_path"].string) {
                _ = try? l.store.recordActivity(a, runID: l.runID)
            }
        case .toolFinished(let id, let isError, let text):
            l.pending.remove(id)
            if isError { DirectionLog.warning("A tool call in run \(l.runID) failed: \(text.prefix(600))", "editor") }
            if isError, EditorFailure.isSpendCap(text) { l.spendCap = EditorFailure.amount(text).map { "\($0) spent on services this month." } ?? "This month\u{2019}s limit for services is reached." }
            if l.pauseWhenIdle, l.pending.isEmpty { l.pauseWhenIdle = false; interrupt(l) }
        case .cost(let c): l.cost = c
        case .tokens(let t): l.tokens = (l.tokens ?? 0) + t
        case .result(let text, let isError): l.result = text; if isError { l.failures.append(text) }
        case .failure(let m): l.failures.append(m)
        }
    }

    private func maybeFinish(_ l: LiveRun) {
        guard !l.finished, let status = l.exited, l.outputClosed else { return }
        l.finished = true
        // Whatever it left running in its group (a shell's `ffmpeg … &`) stops with it, and the
        // process lets go of the run so neither outlives it.
        ChildProcesses.ended(l.process)
        l.process.terminationHandler = nil
        if !l.buffer.isEmpty { output(l, Data("\n".utf8)) }
        guard let run = try? l.store.run(l.runID) else { live[l.runID] = nil; return }
        // Only a turnover that waits for the director's OK has one to wait on.
        let forOK = l.waitsForOK && run.turnoverID.flatMap { try? l.store.turnover($0) }?.waitForOK == true
        let answered = Self.answered(run, store: l.store, since: l.began, waitedForOK: forOK)
        var exit = RunStateMachine.Exit(status: status, intent: l.intent, finished: Self.finished(run, store: l.store), waitingForYou: Self.waitingForYou(run, store: l.store) || answered, failures: l.failures, spendCap: l.spendCap, lastErrorLine: l.stderrTail.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
        if status != 0 { exit.failures += l.stderrTail }
        if status != 0 || !l.failures.isEmpty {
            DirectionLog.error("\(l.program.name) exited with status \(status) in run \(l.runID). Failures: \(l.failures.joined(separator: " | ").prefix(1_500)). Last stderr: \(l.stderrTail.suffix(8).joined(separator: " | "))", "editor")
        }
        let result = l.result.flatMap(EditorResult.parse)
        live[l.runID] = nil
        end(l.runID, store: l.store, outcome: RunStateMachine.outcome(exit), cost: l.cost, tokens: l.tokens, result: result, asked: (l.askedAt ?? l.began, forOK))
    }

    /// Records how a run ended, and what that means for its turnover.
    private func end(_ runID: String, store: ProjectStore, outcome o: RunStateMachine.Outcome, cost: Double? = nil, tokens: Int? = nil, result: EditorResult? = nil, asked: (at: Double, forOK: Bool)? = nil) {
        guard let run = try? store.updateRun(runID, { r in
            // A pause the director asked for stays a pause even if the program exits on its own.
            if r.state == .paused && o.state != .done && o.reason != .pausedByQuit { r.endedAt = Date().timeIntervalSince1970 }
            else { r.state = o.state; r.reason = o.reason; r.detail = o.detail; r.pausedByQuit = o.reason == .pausedByQuit; r.endedAt = Date().timeIntervalSince1970 }
            if let cost { r.spend = (r.spend ?? 0) + cost }
            if let tokens { r.tokens = (r.tokens ?? 0) + tokens }
            if let result { r.summary = result.summary; r.needsYou = result.needsYou }
            if let asked { r.askedAt = asked.at; r.askedForOK = asked.forOK }
            r.pid = nil
        }) else { return }
        let ended = "Run \(run.id) (\(run.job.rawValue)) ended \(run.state.rawValue)\(run.reason.map { ": \($0.rawValue)" } ?? "")\(run.detail.map { " \u{2014} \($0)" } ?? "")"
        if run.state == .failed || run.state == .stopped { DirectionLog.error(ended, "editor") } else { DirectionLog.info(ended + (run.summary.map { ". \($0)" } ?? ""), "editor") }
        // A run that finished is proof the program is signed in, whatever an earlier check said.
        if run.state == .done || run.state == .waitingForYou, let p = EditorProgram(rawValue: run.program), EditorSetup.signedIn(p) != true { EditorSetup.setSignedIn(p, true) }
        if run.state == .failed, let reason = run.reason {
            if let id = run.turnoverID { failTurnover(id, reason: reason, run: run, store: store) }
            if reason == .notSignedIn, let p = EditorProgram(rawValue: run.program) { EditorSetup.setSignedIn(p, false) }
            if reason == .offline { retryWhenOnline(run.id, store: store) }
        }
        stayAwake()
        onChange?(store.url)
        pump()
    }

    // MARK: Control

    /// Interrupts after the current tool call (SIGINT; the program saves its session). Edits made stay.
    func pause(_ runID: String, store: ProjectStore) {
        _ = try? store.updateRun(runID) { if $0.state.isOpen { $0.state = .paused } }
        guard let l = live[runID] else { onChange?(store.url); return }
        l.intent = .pause
        if l.pending.isEmpty { interrupt(l) }
        else {
            l.pauseWhenIdle = true
            // A tool call that never returns mustn't keep the editor working.
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { MainActor.assumeIsolated { if l.exited == nil { self.interrupt(l) } } }
        }
        stayAwake(); onChange?(store.url)
    }

    /// Ends the run: the program and everything it started get SIGINT, then SIGTERM if they linger,
    /// then SIGKILL.
    func stop(_ runID: String, store: ProjectStore) {
        _ = try? store.updateRun(runID) { $0.state = .stopped; $0.reason = .stoppedByYou; $0.held = false }
        offlineRetries[runID]?.cancel(); offlineRetries[runID] = nil
        guard let l = live[runID] else { onChange?(store.url); pump(); return }
        l.intent = .stop
        interrupt(l)
    }

    /// SIGINT to the program's whole group (it saves its session and stops), SIGTERM if anything is
    /// still there after a few seconds, then SIGKILL. Off the main thread.
    private func interrupt(_ l: LiveRun) {
        let group = l.process.processIdentifier, steps = stopSteps
        DispatchQueue.global(qos: .userInitiated).async { ChildProcesses.stop(group: group, steps) }
    }

    /// Quitting: pause every working run and keep its session; the next launch offers Resume.
    /// Calls back once every program and everything it started has gone: SIGINT, then SIGTERM after
    /// 4 s, then SIGKILL after 2 more, so nothing is left working on a film Direction isn't watching.
    func pauseAllForQuit(_ done: @escaping @MainActor () -> Void) {
        let working = Array(live.values)
        guard !working.isEmpty else { done(); return }
        for l in working {
            l.intent = .quit
            _ = try? l.store.updateRun(l.runID) { $0.state = .paused; $0.reason = .pausedByQuit; $0.pausedByQuit = true }
        }
        let groups = working.map(\.process.processIdentifier), steps = stopSteps
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.concurrentPerform(iterations: groups.count) { ChildProcesses.stop(group: groups[$0], steps) }
            DispatchQueue.main.async { MainActor.assumeIsolated { done() } }
        }
    }

    /// At launch: runs a previous Direction left working are paused, so they can be resumed.
    func recover(_ store: ProjectStore) {
        register(store)
        let editorFolder = store.url.appendingPathComponent("Editor").standardizedFileURL.path
        for r in (try? store.runs()) ?? [] where r.state.isActive && !isLive(r.id) {
            // Only if it's still that film's editor (working in its Editor folder): after a restart
            // the number may belong to something else. Its reaper has usually stopped it already.
            if let pid = r.pid, r.ownerPID != getpid(), ChildProcesses.workingDirectory(pid)?.hasPrefix(editorFolder) == true {
                DispatchQueue.global(qos: .utility).async { ChildProcesses.stop(group: pid, ChildProcesses.gently) }
            }
            _ = try? store.updateRun(r.id) { $0.state = .paused; $0.reason = .pausedByQuit; $0.pausedByQuit = true; $0.pid = nil }
        }
    }

    private func retryWhenOnline(_ runID: String, store: ProjectStore) {
        offlineRetries[runID]?.cancel()
        offlineRetries[runID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, let r = try? store.run(runID), r.state == .failed, r.reason == .offline else { return }
            self.launch(r, store: store, continuation: EditorJobs.continuation("Continue where you stopped.", job: r.job))
        }
    }

    /// Holds the Mac awake (not the display) while a run works.
    private func stayAwake() {
        let working = live.values.contains { $0.intent == .none }
        if working, awake == nil { awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "The editor is working") }
        if !working, let a = awake { ProcessInfo.processInfo.endActivity(a); awake = nil }
    }

    // MARK: What the store says

    /// The job's finishing tool did its work (specs/editor.md › Jobs).
    static func finished(_ run: EditorRun, store: ProjectStore) -> Bool {
        switch run.job {
        case .logFootage:
            guard let p = try? store.read(), let d = try? store.dailies(), !p.assets.isEmpty else { return false }
            // A batch is finished when its takes are logged; an older run logged everything.
            if let ids = run.assetIDs { return ids.allSatisfy { d.isLogged($0) } }
            return p.assets.allSatisfy { d.isLogged($0.id) }
        case .assemble, .turnover:
            return (try? run.turnoverID.map { try store.turnover($0) })??.state == .delivered
        case .finish:
            guard let s = try? store.directingState(), s.pictureLocked, let items = s.finishing else { return false }
            return items.filter { $0.by.contains("editor") }.allSatisfy { ["done", "needsYou"].contains($0.state) }
        case .style:
            // A style was written into the Styles folder since the run began.
            let since = (run.startedAt ?? run.createdAt) - 1
            return StyleLibrary.list(in: SharedSettings.stylesFolder).contains { $0.updatedAt >= since }
        case .technique:
            // A technique was written into the Techniques folder since the run began.
            let since = (run.startedAt ?? run.createdAt) - 1
            return TechniqueLibrary.list(in: SharedSettings.techniquesFolder).contains { $0.updatedAt >= since }
        case .script:
            // Every row has a picture, every note it was given has a reply, and nothing waits on the director.
            // A film from a story needs what we hear on every row too.
            guard let s = try? store.script(), !s.rows.isEmpty else { return false }
            return s.rows.allSatisfy { !$0.picture.isEmpty && !(s.isStory && $0.soundUndecided) } && s.turnedOver.isEmpty && s.openQuestions.isEmpty
        case .breakdown:
            guard let b = try? store.breakdown(), !b.shots.isEmpty else { return false }
            return b.turnedOver.isEmpty && !b.shots.contains { $0.question?.isOpen == true }
        }
    }

    /// The program stopped to wait for the director: a read-back to OK or a question to answer.
    static func waitingForYou(_ run: EditorRun, store: ProjectStore) -> Bool {
        // A question on a row or a shot (specs/script.md › Questions).
        if run.job == .script, let s = try? store.script(), !s.openQuestions.isEmpty { return true }
        if run.job == .breakdown, let b = try? store.breakdown(), b.shots.contains(where: { $0.question?.isOpen == true }) { return true }
        let open = ((try? store.questions()) ?? []).filter { $0.answer == nil }
        if let id = run.turnoverID, let t = try? store.turnover(id) {
            if t.state == .readBack && !t.readBackApproved { return true }
            return open.contains { $0.turnoverID == id }
        }
        return open.contains { $0.turnoverID == nil && $0.createdAt >= (run.startedAt ?? run.createdAt) }
    }

    /// The director already answered what this invocation asked before the program exited: the OK to the
    /// read-back it waited on, or a question it asked. The run goes on as if it had waited.
    static func answered(_ run: EditorRun, store: ProjectStore, since: Double, waitedForOK: Bool) -> Bool {
        if run.job == .script, let s = try? store.script(), s.rows.contains(where: { ($0.question?.answeredAt ?? 0) >= since }) { return true }
        if run.job == .breakdown, let b = try? store.breakdown(), b.shots.contains(where: { ($0.question?.answeredAt ?? 0) >= since }) { return true }
        if waitedForOK, let id = run.turnoverID, let t = try? store.turnover(id), t.readBackApproved, t.state == .cutting { return true }
        return ((try? store.questions()) ?? []).contains { $0.turnoverID == run.turnoverID && $0.createdAt >= since && $0.answer != nil }
    }

    /// A failed run leaves its turnover stopped at the note it was on (frame 58).
    private func failTurnover(_ id: String, reason: EditorRunReason, run: EditorRun, store: ProjectStore) {
        _ = try? store.modifyTurnover(id, summary: "The editor stopped") { t in
            guard t.state.isOpen else { return }
            t.state = .failed
            t.message = EditorStopCopy.title(reason, run: run)
            for (k, v) in t.progress where v == .working { t.progress[k] = .stopped }
        }
    }

    /// Starting again puts a stopped turnover back where the editor left it; the read-back stays.
    private func reopenTurnover(_ id: String, store: ProjectStore) {
        _ = try? store.modifyTurnover(id, summary: "The editor started again") { t in
            guard t.state == .failed else { return }
            t.state = t.readBack.isEmpty ? .waiting : (t.readBackApproved || !t.waitForOK || t.kind == "assembly") ? .cutting : .readBack
            t.message = nil
            for (k, v) in t.progress where v == .stopped { t.progress[k] = .queued }
        }
    }
}

/// Frame 58's words for each reason.
enum EditorStopCopy {
    static func title(_ reason: EditorRunReason, run: EditorRun?) -> String {
        let name = run.flatMap { EditorProgram(rawValue: $0.program)?.name } ?? "The editor"
        switch reason {
        case .notInstalled: return "The editor isn\u{2019}t installed."
        case .notSignedIn: return "\(name) isn\u{2019}t signed in."
        case .offline: return "The editor is offline."
        case .programQuit: return "The editor quit unexpectedly."
        case .stoppedWithoutFinishing: return "The editor stopped before finishing."
        case .spendCap: return "You\u{2019}ve reached this month\u{2019}s limit."
        case .pausedByQuit: return "The editor was paused when Direction quit."
        case .stoppedByYou: return "You stopped the editor."
        }
    }
}
