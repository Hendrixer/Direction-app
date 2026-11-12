import Foundation
import Darwin
import DirectionCore
import DirectionTools

/// Starts the editor program (Claude Code, Codex, or an agent over ACP) for each job and follows it (specs/editor.md › How Direction runs a job).
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
        /// An ACP agent's side of the conversation, and where Direction's side is written.
        var acp: ACPConversation?
        var input: FileHandle?
        var buffer = Data()
        /// Tool calls it has made that haven't answered yet, by id, with the tool's name.
        var pending: [String: String] = [:]
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
        /// The last time the program said anything, in awake time (a Mac asleep isn't a program saying nothing),
        /// and whether this silence was logged yet.
        var lastHeard = ProcessInfo.processInfo.systemUptime { didSet { quietLogged = false } }
        var quietLogged = false
        /// The step it was stuck on, and for how long, when Direction stopped it to start it again.
        var stuckStep: String?
        var stuckMinutes = 0
        init(runID: String, store: ProjectStore, program: EditorProgram, process: Process) { self.runID = runID; self.store = store; self.program = program; self.process = process }
    }

    /// Finishing runs while Direction does its own steps first (FinishingPass), before the program starts: the
    /// pass, so Stop and Quit reach it.
    private var preparing: [String: Task<Void, Never>] = [:]
    func isLive(_ runID: String) -> Bool { live[runID] != nil || preparing[runID] != nil }
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
            guard live.count + preparing.count < Self.maxConcurrent, let runs = try? store.runs() else { continue }
            // Any program still alive, a stopped one included while it winds down, keeps the next one waiting.
            guard !runs.contains(where: { isLive($0.id) }) else { continue }
            guard let next = runs.first(where: { $0.state == .queued && !$0.held }) else { continue }
            launch(next, store: store)
        }
    }

    // MARK: Launch

    /// Starts the program for a run: its first job text, or `continuation` on the saved session.
    func launch(_ run: EditorRun, store: ProjectStore, continuation: String? = nil, restartingStuck: Bool = false, prepared: Bool = false) {
        register(store)
        // The store's copy: the session or state may have moved since the caller read it.
        var run = (try? store.run(run.id)) ?? run
        // A run that never started takes the film's editor, and the version and effort for its job at the
        // film's speed and quality as they are now (Choose another editor…, the slider).
        let state = try? store.directingState()
        if run.invocations == 0, let p = EditorSetup.runsOn(film: state?.editor).program, programOverride.isEmpty {
            let pick = EditorPicks.pick(p, run.job, state?.speedAndQuality ?? .balanced)
            if p.rawValue != run.program || pick.version != run.version || pick.effort != run.effort {
                run = (try? store.updateRun(run.id) { $0.program = p.rawValue; $0.version = pick.version; $0.effort = pick.effort }) ?? run
            }
        }
        // A run left by an agent Direction no longer runs starts over with the film's editor: its session was that agent's.
        if EditorProgram(rawValue: run.program) == nil, let p = EditorSetup.runsOn(film: state?.editor).program {
            let pick = EditorPicks.pick(p, run.job, state?.speedAndQuality ?? .balanced)
            run = (try? store.updateRun(run.id) { $0.program = p.rawValue; $0.version = pick.version; $0.effort = pick.effort; $0.session = nil }) ?? run
        }
        guard live[run.id] == nil, preparing[run.id] == nil else { return }
        guard let program = EditorProgram(rawValue: run.program) else { end(run.id, store: store, outcome: .init(state: .failed, reason: .notInstalled)); return }
        offlineRetries[run.id]?.cancel(); offlineRetries[run.id] = nil
        // Try again, Resume or back online: a fresh start, with its one restart to come.
        if !restartingStuck { restarted.remove(run.id) }
        let install = EditorPrograms.shared.install(program)
        guard let path = programOverride[program] ?? install?.path else {
            end(run.id, store: store, outcome: .init(state: .failed, reason: .notInstalled)); return
        }
        // An agent too old to speak ACP: found, but Direction can't talk to it.
        if programOverride[program] == nil, let install, !install.usable {
            end(run.id, store: store, outcome: .init(state: .failed, reason: .outOfDate, detail: "In Terminal, run \(program.updateCommand(path: install.path))")); return
        }
        guard let helper = helperOverride ?? EditorJobs.helperPath else {
            end(run.id, store: store, outcome: .init(state: .failed, reason: .programQuit, detail: "Direction\u{2019}s tools aren\u{2019}t in this copy of the app. Build it with scripts/build-app.sh.")); return
        }
        // Finishing: Direction's own steps first, then the editor on what's left. Again on Resume when the
        // editor never started (a quit during the steps): each step only does what's still to do.
        if run.job == .finish, run.invocations == 0, !prepared {
            _ = try? store.updateRun(run.id) { $0.state = .starting }
            onChange?(store.url)
            let runID = run.id
            preparing[runID] = Task { @MainActor in
                await FinishingPass.run(store: store, runID: runID)
                self.preparing[runID] = nil
                // Stopped or paused meanwhile: it stays that way.
                guard !Task.isCancelled, let again = try? store.run(runID), again.state == .starting || again.state == .queued else { self.onChange?(store.url); self.pump(); return }
                self.launch(again, store: store, continuation: continuation, restartingStuck: restartingStuck, prepared: true)
            }
            return
        }
        do {
            let folder = try EditorJobs.prepareFolder(film: store.url, job: run.job)
            let mcp = folder.appendingPathComponent(".mcp.json"), schema = folder.appendingPathComponent(".direction/result.schema.json")
            try EditorProgram.mcpConfig(helper: helper, film: store.url, runID: run.id, job: run.job).data(pretty: true).write(to: mcp, options: .atomic)
            try EditorProgram.resultSchema.data(pretty: true).write(to: schema, options: .atomic)
            // A continuation without a saved session starts over with the whole job, then the answer.
            let session = continuation == nil ? nil : run.session
            // A fresh session counts its spend from nothing. A run resumed from before sessions' totals were
            // kept takes what it has recorded as the session's total so far.
            if session == nil, run.sessionSpend != nil { run = (try? store.updateRun(run.id) { $0.sessionSpend = nil }) ?? run }
            else if session != nil, run.sessionSpend == nil, let spent = run.spend { run = (try? store.updateRun(run.id) { $0.sessionSpend = spent }) ?? run }
            var job = try (session == nil ? EditorJobs.text(for: run, store: store) : continuation!)
            if session == nil, let c = continuation, run.invocations > 0 { job += "\n" + c }
            // The run's own, once it has started; an older run without one reads its job's.
            let effort = run.effort ?? EditorPicks.pick(program, run.job, state?.speedAndQuality ?? .balanced).effort
            let invocation = EditorProgram.Invocation(job: job, role: EditorJobs.role, version: run.version, effort: effort, session: session, folder: folder, mcpConfig: mcp, schema: schema, helper: helper, film: store.url, runID: run.id, scripts: EditorSetup.runsScripts, kind: run.job)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = programOverride[program] == nil ? (install?.arguments(invocation) ?? program.arguments(invocation)) : program.arguments(invocation)
            p.currentDirectoryURL = folder
            p.environment = EditorDiscovery.environment(adding: path, extra: ["DIRECTION_RUN_ID": run.id], shellKey: EditorSetup.usesShellKey(program),
                                                        fallback: program == .gemini ? EditorDiscovery.geminiHomeEnvironment() : [:])
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            let l = LiveRun(runID: run.id, store: store, program: program, process: p)
            if program.usesACP {
                // The whole job, for a saved session the agent can't load.
                let whole = session == nil ? job : ((try? EditorJobs.text(for: run, store: store)).map { $0 + "\n" + job } ?? job)
                let input = Pipe()
                // An agent that's gone must not take Direction with it: writes fail instead of raising SIGPIPE.
                _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                p.standardInput = input
                l.input = input.fileHandleForWriting
                l.acp = program.conversation(invocation, wholeJob: whole)
            }
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
            if var conversation = l.acp {
                let hello = conversation.start(); l.acp = conversation; send(l, hello)
                // An agent that never opens a session would otherwise wait for the silence watch.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.sessionWithin) { MainActor.assumeIsolated {
                    guard l.exited == nil, l.process.isRunning, l.acp?.sessionID == nil, l.intent == .none else { return }
                    l.failures.append("\(l.program.name) didn\u{2019}t open a session within \(Int(Self.sessionWithin)) seconds.")
                    self.stopFirmly(l)
                } }
            }
            DirectionLog.info("Started \(program.name) for \(run.job.rawValue) (run \(run.id), \(run.version.isEmpty ? "default version" : run.version), \(effort.isEmpty ? "default effort" : effort + " effort"), session \(session ?? "new"), pid \(p.processIdentifier)) in \(store.url.lastPathComponent)", "editor")
            live[run.id] = l
            watchForSilence()
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
        l.lastHeard = ProcessInfo.processInfo.systemUptime
        if data.isEmpty { l.outputClosed = true; maybeFinish(l); return }
        l.buffer.append(data)
        while let nl = l.buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: l.buffer[l.buffer.startIndex..<nl], as: UTF8.self)
            l.buffer.removeSubrange(l.buffer.startIndex...nl)
            if var conversation = l.acp {
                let step = conversation.receive(line)
                l.acp = conversation
                send(l, step.send)
                for e in step.events { handle(l, e) }
                if step.done { endConversation(l) }
                continue
            }
            let events = l.program == .claudeCode ? l.claude.parse(line) : l.codex.parse(line)
            for e in events { handle(l, e) }
        }
    }

    /// Direction's side of an ACP conversation, a line each.
    private func send(_ l: LiveRun, _ messages: [JSONValue]) {
        guard let input = l.input else { return }
        for m in messages { try? input.write(contentsOf: ACPConversation.line(m)) }
    }

    /// The prompt is answered: the agent's stdin closes, and an agent that stays open after that is ended, with
    /// everything it started.
    private func endConversation(_ l: LiveRun) {
        try? l.input?.close(); l.input = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { MainActor.assumeIsolated { if l.process.isRunning { self.stopFirmly(l) } } }
    }

    /// SIGTERM to the program's whole group, then SIGKILL. Off the main thread.
    private func stopFirmly(_ l: LiveRun) {
        let group = l.process.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async { ChildProcesses.stop(group: group, ChildProcesses.firmly) }
    }

    /// How long an ACP agent has to open its session, and to hear a cancelled turn before the signal.
    static var sessionWithin: Double = 120
    static var cancelGrace: Double = 1.5

    func handle(_ l: LiveRun, _ e: StreamEvent) {
        switch e {
        // A new session counts its spend from nothing (an ACP agent that couldn't load the saved one).
        case .session(let s): _ = try? l.store.updateRun(l.runID) { if $0.session != s { if $0.session != nil { $0.sessionSpend = nil }; $0.session = s } }
        case .toolStarted(let id, let name, let input):
            l.pending[id] = name
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
            l.pending[id] = nil
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
        // A stop, pause, quit or stuck restart asked for the exit: logged, but it isn't an error (and isn't reported).
        if status != 0 || !l.failures.isEmpty {
            (l.intent == .none ? DirectionLog.error : DirectionLog.info)("\(l.program.name) exited with status \(status) in run \(l.runID). Failures: \(l.failures.joined(separator: " | ").prefix(1_500)). Last stderr: \(l.stderrTail.suffix(8).joined(separator: " | "))", "editor")
        }
        let result = l.result.flatMap(EditorResult.parse)
        live[l.runID] = nil
        // Stopped because it was stuck: started again at once on its session, told where it was, before the queue
        // is looked at, so nothing queued takes its place (one run per film, two films at once).
        let restarting = l.intent == .restart
        end(l.runID, store: l.store, outcome: RunStateMachine.outcome(exit), cost: l.cost, tokens: l.tokens, result: result, asked: (l.askedAt ?? l.began, forOK), pumps: !restarting)
        if restarting {
            if let run = try? l.store.run(l.runID), run.state == .paused {
                launch(run, store: l.store, continuation: EditorJobs.continuation(Self.restartNote(l.stuckStep ?? "unknown", minutes: l.stuckMinutes), job: run.job), restartingStuck: true)
            }
            pump()
        }
    }

    /// Records how a run ended, and what that means for its turnover. `pumps`: the next queued run may start.
    private func end(_ runID: String, store: ProjectStore, outcome o: RunStateMachine.Outcome, cost: Double? = nil, tokens: Int? = nil, result: EditorResult? = nil, asked: (at: Double, forOK: Bool)? = nil, pumps: Bool = true) {
        guard let run = try? store.updateRun(runID, { r in
            // A pause the director asked for stays a pause even if the program exits on its own.
            if r.state == .paused && o.state != .done && o.reason != .pausedByQuit { r.endedAt = Date().timeIntervalSince1970 }
            else { r.state = o.state; r.reason = o.reason; r.detail = o.detail; r.pausedByQuit = o.reason == .pausedByQuit; r.endedAt = Date().timeIntervalSince1970 }
            if let cost {
                // A running total for the session: what's new since its last report. Lower than that last
                // report, it's a fresh count, all new.
                let before = r.sessionSpend ?? 0
                r.spend = (r.spend ?? 0) + (cost >= before ? cost - before : cost)
                r.sessionSpend = cost
            }
            if let tokens { r.tokens = (r.tokens ?? 0) + tokens }
            if let result { r.summary = result.summary; r.needsYou = result.needsYou }
            if let asked { r.askedAt = asked.at; r.askedForOK = asked.forOK }
            r.pid = nil
        }) else { return }
        let ended = "Run \(run.id) (\(run.job.rawValue)) ended \(run.state.rawValue)\(run.reason.map { ": \($0.rawValue)" } ?? "")\(run.detail.map { " \u{2014} \($0)" } ?? "")"
        // The director's own Stop is what they asked for, not something that went wrong.
        if run.state == .failed || (run.state == .stopped && run.reason != .stoppedByYou) { DirectionLog.error(ended, "editor") } else { DirectionLog.info(ended + (run.summary.map { ". \($0)" } ?? ""), "editor") }
        // A run that finished is proof the program is signed in, whatever an earlier check said.
        if run.state == .done || run.state == .waitingForYou, let p = EditorProgram(rawValue: run.program), EditorSetup.signedIn(p) != true { EditorSetup.setSignedIn(p, true) }
        if run.state == .failed, let reason = run.reason {
            if let id = run.turnoverID { failTurnover(id, reason: reason, run: run, store: store) }
            if reason == .notSignedIn, let p = EditorProgram(rawValue: run.program) { EditorSetup.setSignedIn(p, false) }
            if reason == .offline { retryWhenOnline(run.id, store: store) }
        }
        stayAwake()
        onChange?(store.url)
        if pumps { pump() }
    }

    // MARK: Silence

    /// A program that says nothing for 10 minutes while it's meant to be working is logged as an error, with its last
    /// step: Direction's log shows it, and with crash reports on it's a report (system.md › Crash reports). Thinking
    /// is quiet too, but not for ten minutes.
    static let warnAfter: Double = 10 * 60
    /// Quiet this long, it's stuck: Direction stops it and starts it again on its session, once a run, telling it
    /// which step it was on. Stuck again, the run stops and says so (hang recovery).
    nonisolated(unsafe) static var restartAfter: Double = 15 * 60
    /// While it waits on a call that does its long work inside the call (an import copying a whole file), the
    /// program is quiet because the call is, so it has this long instead.
    nonisolated(unsafe) static var restartAfterLongCall: Double = 2 * 60 * 60
    private var restarted: Set<String> = []
    private var silenceTimer: Timer?
    private func watchForSilence() {
        guard silenceTimer == nil else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkSilence() } }
    }
    /// `now` in awake time (ProcessInfo.systemUptime), like `lastHeard`.
    func checkSilence(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if live.isEmpty { silenceTimer?.invalidate(); silenceTimer = nil; return }
        for l in live.values where l.intent == .none && !l.finished && !waitsForReadBackOK(l) {
            let quiet = now - l.lastHeard, minutes = Int(quiet / 60)
            let longCall = l.pending.values.contains { name in DirectionMCPServer.unlimited.contains { name.hasSuffix($0) } }
            if quiet >= (longCall ? Self.restartAfterLongCall : Self.restartAfter) {
                recover(l, step: lastStep(l), minutes: minutes)
                continue
            }
            guard !longCall, quiet >= Self.warnAfter, !l.quietLogged else { continue }
            l.quietLogged = true
            let job = (try? l.store.run(l.runID))?.job.rawValue ?? "run"
            DirectionLog.error("\(l.program.name) has said nothing for \(minutes) min in run \(l.runID) (\(job)); tool calls open: \(l.pending.count); last step: \(lastStep(l))", "editor")
        }
    }
    /// It posted a read-back for a turnover that waits for the director's OK, and the OK hasn't come: waiting for
    /// it isn't being stuck. Asking a question doesn't count: the editor keeps cutting what it doesn't hold up.
    private func waitsForReadBackOK(_ l: LiveRun) -> Bool {
        guard l.waitsForOK, let id = (try? l.store.run(l.runID))?.turnoverID, let t = try? l.store.turnover(id) else { return false }
        return t.waitForOK && t.state == .readBack && !t.readBackApproved
    }
    /// "Watching 0:15": what the run was last seen doing.
    private func lastStep(_ l: LiveRun) -> String {
        (try? l.store.activity(runID: l.runID))?.max { $0.at < $1.at }.map { "\($0.verb) \($0.object)" } ?? "starting"
    }
    /// Stops a stuck program (SIGINT, then SIGTERM, then SIGKILL, with everything it started) and either starts it
    /// again on its session or, the second time, ends the run as stuck.
    private func recover(_ l: LiveRun, step: String, minutes: Int) {
        if restarted.contains(l.runID) {
            DirectionLog.error("\(l.program.name) got stuck again in run \(l.runID) after \(minutes) min on: \(step). Stopping the run.", "editor")
            l.intent = .stuck(step)
        } else {
            restarted.insert(l.runID)
            DirectionLog.error("\(l.program.name) said nothing for \(minutes) min in run \(l.runID) on: \(step). Starting it again on its session.", "editor")
            l.intent = .restart
            l.stuckStep = step
            l.stuckMinutes = minutes
        }
        interrupt(l)
        stayAwake(); onChange?(l.store.url)
    }
    /// What the program hears when it's started again after getting stuck.
    static func restartNote(_ step: String, minutes: Int) -> String {
        let m = max(minutes, 1)
        return "Direction stopped you and started you again: you\u{2019}d said nothing for \(m == 1 ? "a minute" : "\(m) minutes"), and your last step was \u{201C}\(step)\u{201D}. Don\u{2019}t do it the same way again. If it was one of Direction\u{2019}s tools, it may get stuck on the same thing: try a shorter passage or fewer frames, or look at what you added there last (an effect or a graphic that never finishes). If it was a command you ran, give it a time limit. Then carry on where you were."
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
        // Still on Direction's own steps: they stop between steps, or inside one that's rendering.
        preparing[runID]?.cancel()
        guard let l = live[runID] else { onChange?(store.url); pump(); return }
        l.intent = .stop
        interrupt(l)
    }

    /// SIGINT to the program's whole group (it saves its session and stops), SIGTERM if anything is
    /// still there after a few seconds, then SIGKILL. Off the main thread.
    private func interrupt(_ l: LiveRun) {
        // An ACP agent hears the turn is cancelled first, and has a moment to save the session before the signal.
        let cancel = l.acp?.cancel()
        if let cancel { send(l, [cancel]) }
        let group = l.process.processIdentifier, steps = stopSteps, grace = cancel == nil ? 0 : Self.cancelGrace
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + grace) { ChildProcesses.stop(group: group, steps) }
    }

    /// Quitting: pause every working run and keep its session; the next launch offers Resume.
    /// Calls back once every program and everything it started has gone: SIGINT, then SIGTERM after
    /// 4 s, then SIGKILL after 2 more, so nothing is left working on a film Direction isn't watching.
    func pauseAllForQuit(_ done: @escaping @MainActor () -> Void) {
        // A run still on Direction's own steps: paused like the rest, and Resume does what's left of them.
        for (runID, task) in preparing {
            task.cancel()
            for store in stores.values where (try? store.run(runID)) != nil {
                _ = try? store.updateRun(runID) { $0.state = .paused; $0.reason = .pausedByQuit; $0.pausedByQuit = true }
            }
        }
        let working = Array(live.values)
        guard !working.isEmpty else { done(); return }
        for l in working {
            l.intent = .quit
            _ = try? l.store.updateRun(l.runID) { $0.state = .paused; $0.reason = .pausedByQuit; $0.pausedByQuit = true }
        }
        // Gemini CLI hears the turn is cancelled, and have a moment to save, before the signals.
        var cancelled = false
        for l in working { if let cancel = l.acp?.cancel() { send(l, [cancel]); cancelled = true } }
        let groups = working.map(\.process.processIdentifier), steps = stopSteps
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (cancelled ? Self.cancelGrace : 0)) {
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
        case .outOfDate: return "\(name) needs updating."
        case .offline: return "The editor is offline."
        case .programQuit: return "The editor quit unexpectedly."
        case .stoppedWithoutFinishing: return "The editor stopped before finishing."
        case .spendCap: return "You\u{2019}ve reached this month\u{2019}s limit."
        case .pausedByQuit: return "The editor was paused when Direction quit."
        case .stoppedByYou: return "You stopped the editor."
        case .stuck: return "The editor got stuck."
        }
    }
}
