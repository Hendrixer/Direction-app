import Foundation
import Darwin
import JavaScriptCore
import DirectionCore

// direction_run: the editor writes a short JavaScript that calls Direction's tools as functions, and only what the
// script returns comes back (specs/editor.md › Scripts). A loop of measure → decide → change is one step instead of
// dozens, and every step the editor saves is everything said so far it doesn't send again.
//
// An editor Direction starts has only this tool (JobTools.swift): every step is a script, even a single call.
//
// The script runs in a helper process (`direction script`) that macOS's own sandbox closes off before any of it
// runs: the pure-computation profile, so no files, no network, no programs. All it can do is ask Direction, over
// its stdin and stdout, to run a tool, and each ask is checked exactly like a direct call. A script can do nothing
// the editor couldn't do one call at a time.
extension ToolCatalog {
    public static let runName = "direction_run"
    static var scriptDefinitions: [ToolDefinition] { [
        definition(runName, "Direction\u{2019}s tools as functions in a short JavaScript: one step instead of many, and only what the script returns comes back. Each tool is a function on `direction`, named without direction_ and taking that tool\u{2019}s own arguments: `const m = direction.measure_audio({ranges: [{start: 0, end: 8}]})` returns the tool\u{2019}s answer as an object (a tool that draws images or makes a sound adds imagePaths or audioPaths). Calls are synchronous; a tool that fails throws an Error with code and message, which the script can catch. `return x` answers with x; `print(...)` adds a line to the answer; `show(path)` puts an image (up to 8) or a sound a tool made in this script into the answer, to look at or listen to. `keep` is an object that stays between your scripts in this job: put ids, measurements and the operations you plan in it (`keep.ops = [...]`) and use them in a later script, so you never write them out twice (a trial edit, then the same `keep.ops` committed). Gather changes and make them in one direction.edit call. `direction.help()` lists Direction\u{2019}s other tools, and `direction.help(\"name\")` gives one in full. The script reaches nothing but Direction\u{2019}s tools (no files, network or programs). It stops after 4 minutes of its own work (the tools\u{2019} time doesn\u{2019}t count) or 300 calls; changes made before a failure stay.",
                   ["code": noted(string, "The script\u{2019}s body: a function body, so end with return."),
                    "does": noted(string, "What it does in a few plain words, as the director reads it: \u{201C}Evening out the narration\u{201D}.")],
                   required: ["code", "does"], readOnly: false),
    ] }
}

extension ToolRuntime {
    func invokeScript(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        guard name == ToolCatalog.runName else { return nil }
        // The script's calls come back here, checked and run as direct calls are.
        return try await ScriptRunner.run(code: a.requiredString("code"), kept: KeptValues.forThisProcess(cache: cacheDirectory)) { [self] name, arguments in try await invoke(name, arguments: arguments) }
    }
}

/// Direction's side: starts the helper, answers its calls, and stops it at the limits.
public enum ScriptRunner {
    /// Set while a script's own calls run, so only its changes show in the editor's activity (the run itself is one row).
    @TaskLocal public static var running = false
    /// The job the tool server was started for, so direction.help knows which tools it was given.
    @TaskLocal public static var job: EditorJob?
    /// The `direction` program to start; nil finds it (this process when it is `direction`, else beside the app).
    nonisolated(unsafe) public static var helper: String?
    /// The script's own work: time spent waiting on a tool doesn't count, since each call has the limits a direct
    /// one has (DirectionMCPServer.limited).
    nonisolated(unsafe) public static var seconds: Double = 240
    nonisolated(unsafe) public static var maxMemory: UInt64 = 2 << 30
    public static let maxCalls = 300
    public static let maxShown = 8, maxSounds = 2, maxAnswer = 40_000, maxPrinted = 8_000, maxPrintedLines = 200
    /// A line from the helper longer than this stops it: the most an edit batch or an answer needs, many times over.
    static let maxLine = 8 << 20

    static func helperPath() throws -> String {
        if let helper { return helper }
        let fm = FileManager.default
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            if exe.lastPathComponent == "direction" { return exe.path }
            let folder = exe.deletingLastPathComponent()
            for candidate in [folder.deletingLastPathComponent().appendingPathComponent("Helpers/direction"), folder.appendingPathComponent("direction")] where fm.isExecutableFile(atPath: candidate.path) { return candidate.path }
        }
        throw DirectionError("script_unavailable", "Direction\u{2019}s script helper isn\u{2019}t here, so scripts can\u{2019}t run. Make the calls one at a time.")
    }

    /// Why the helper was stopped before it finished.
    enum Stop: Sendable { case time, memory, longLine }

    static let keepTooBig = "keep is over \(KeptValues.most / 1_000) KB and wasn\u{2019}t kept: what was kept before this script is still there. Keep less."
    static let keepUnreadable = "keep wasn\u{2019}t kept: it has to be an object of plain values (no functions, cycles or BigInt). What was kept before this script is still there."

    public static func run(code: String, kept: KeptValues? = nil, invoke: @escaping @Sendable (String, JSONValue) async throws -> ToolResponse) async throws -> ToolResponse {
        let started = SuspendingClock.now, limit = seconds, memory = maxMemory, job = Self.job
        // Time inside tool calls, and when the call in flight began: the rest is the script's own.
        let waited = Box<(total: Duration, since: SuspendingClock.Instant?)>((.zero, nil))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: try helperPath())
        p.arguments = ["script"]
        // Nothing of Direction's or the editor's: the script can't read its environment anyway.
        var env = ["HOME": NSHomeDirectory(), "LANG": ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8"]
        if let tz = ProcessInfo.processInfo.environment["TZ"] { env["TZ"] = tz }
        p.environment = env
        let input = Pipe(), output = Pipe(), errors = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        p.standardInput = input; p.standardOutput = output; p.standardError = errors
        let ended = AsyncStream<Void> { c in p.terminationHandler = { p in ChildProcesses.ended(p); c.yield(); c.finish() } }
        try p.run()
        ChildProcesses.started(p)
        let pid = p.processIdentifier
        let stop = Box<Stop?>(nil), stderrTail = ScriptOutput()
        errors.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil } else { stderrTail.append(String(decoding: d, as: UTF8.self)) }
        }
        // Lines split on the newline byte alone (JSON writes U+2028 and its kin raw inside strings), read on the
        // pipe's own handler so scripts running at once never wait on each other.
        let lines = AsyncStream<Data> { c in
            let pending = Box(Data())
            output.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; c.finish(); return }
                pending.value.append(d)
                while let nl = pending.value.firstIndex(of: 0x0A) {
                    c.yield(Data(pending.value[pending.value.startIndex..<nl]))
                    pending.value.removeSubrange(pending.value.startIndex...nl)
                }
                if pending.value.count > maxLine { stop.value = .longLine; kill(pid, SIGKILL); h.readabilityHandler = nil; c.finish() }
            }
        }
        let writer = input.fileHandleForWriting
        func send(_ v: JSONValue) {
            let data = (try? v.data()) ?? (try? JSONValue.object(["error": .object(["code": .string("unreadable_answer"), "message": .string("The tool\u{2019}s answer couldn\u{2019}t be passed to the script.")])]).data()) ?? Data("{}".utf8)
            try? writer.write(contentsOf: data + Data("\n".utf8))
        }
        let keptBefore = kept?.read() ?? .object([:])
        send(.object(["code": .string(code), "seconds": .number(limit), "keep": keptBefore]))

        let got = Collected()
        let work = Task {
            try await $running.withValue(true) {
                for await data in lines {
                    guard let message = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
                    if let name = message["call"].string {
                        if got.calls >= maxCalls { send(.object(["error": .object(["code": .string("too_many_calls"), "message": .string("A script makes at most \(maxCalls) calls. Return what you have and run another for the rest.")])])); continue }
                        if name == ToolCatalog.runName { send(.object(["error": .object(["code": .string("not_in_a_script"), "message": .string("A script can\u{2019}t run another script.")])])); continue }
                        got.calls += 1
                        do {
                            if name == "direction_help" { send(.object(["value": try ToolCatalog.help(message["arguments"], job: job)])); continue }
                            let arguments = message["arguments"]
                            waited.value.since = .now
                            defer { if let since = waited.value.since { waited.value = (waited.value.total + (.now - since), nil) } }
                            let r = try await DirectionMCPServer.limited(name) { try await invoke(name, arguments) }
                            var value = r.value
                            got.rendered += r.imagePaths; got.sounds += r.audioPaths
                            for (key, paths) in [("imagePaths", r.imagePaths), ("audioPaths", r.audioPaths)] where !paths.isEmpty {
                                if case .object(var o) = value { o[key] = .array(paths.map(JSONValue.string)); value = .object(o) }
                                else { value = .object(["answer": value, key: .array(paths.map(JSONValue.string))]) }
                            }
                            send(.object(["value": value]))
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            let e = error as? DirectionError ?? DirectionError("operation_failed", error.localizedDescription)
                            var fields: [String: JSONValue] = ["code": .string(e.code), "message": .string(e.message)]
                            if let index = e.index { fields["index"] = .number(Double(index)) }
                            send(.object(["error": .object(fields)]))
                        }
                    } else if let text = message["print"].string {
                        guard got.printed.count < maxPrintedLines, got.printedSize < maxPrinted else { continue }
                        let kept = String(text.prefix(maxPrinted - got.printedSize)); got.printedSize += max(1, kept.count)
                        got.printed.append(kept.count < text.count ? kept + "\u{2026}" : kept)
                    } else if message.has("done") {
                        got.done = message["done"]; got.cutFrom = message["cutFrom"].int; got.shown = message["shown"].array?.compactMap(\.string) ?? []
                        got.keep = message["keep"]
                    } else if let text = message["failed"].string {
                        got.failure = (text, message["line"].int ?? 0); got.keep = message["keep"]
                    }
                }
            }
        }
        // The limits: the script's own awake time (as the tool limit counts it) and memory. Either stops the helper and
        // the call in flight.
        let watch = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(250), clock: .suspending)
                let now = SuspendingClock.now, w = waited.value
                if now - started - w.total - (w.since.map { now - $0 } ?? .zero) > .seconds(limit) { stop.value = .time }
                else if footprint(pid) > memory { stop.value = .memory }
                else { continue }
                kill(pid, SIGKILL); work.cancel(); return
            }
        }
        defer { watch.cancel(); errors.fileHandleForReading.readabilityHandler = nil; output.fileHandleForReading.readabilityHandler = nil; if p.isRunning { kill(pid, SIGKILL) } }
        do {
            try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel(); kill(pid, SIGKILL) }
        } catch is CancellationError where stop.value != nil && !Task.isCancelled {}
        for await _ in ended { break }

        let calls = got.calls, printed = got.printed
        // What the script kept, for the next one: also when it failed, since what it found before failing is still true.
        var keptNote: String?
        var keptProblem = ""
        if let kept, let keep = got.keep {
            if case .object = keep {
                if kept.write(keep, since: keptBefore) { let names = kept.names; keptNote = names.isEmpty ? nil : names.joined(separator: ", ") } else { keptNote = keepTooBig; keptProblem = " " + keepTooBig }
            } else if let why = keep.string {
                let note = why == "big" ? keepTooBig : keepUnreadable
                keptNote = note; keptProblem = " " + note
            }
        }
        let tail = printed.isEmpty ? "" : " It printed: " + String(printed.joined(separator: " | ").suffix(1_000))
        let madeCalls = calls == 0 ? "" : " \(calls) call\(calls == 1 ? "" : "s") had run; changes they made stay."
        switch stop.value {
        case .time: throw DirectionError("script_too_long", "The script worked past \(Int(limit / 60)) minutes on its own (the tools\u{2019} time doesn\u{2019}t count) and was stopped.\(madeCalls) Do less in one script, or look for a loop that never ends.\(tail)")
        case .memory: throw DirectionError("script_too_big", "The script used more than \(memory >> 30) GB of memory and was stopped.\(madeCalls) Keep less at once.\(tail)")
        case .longLine: throw DirectionError("script_too_big", "The script sent more than \(maxLine >> 20) MB at once and was stopped.\(madeCalls) Send and return less.\(tail)")
        case nil: break
        }
        if let failure = got.failure { throw DirectionError("script_failed", (failure.line > 0 ? "Line \(failure.line): " : "") + sentence(failure.message) + madeCalls + keptProblem + tail) }
        guard let done = got.done else {
            let why = stderrTail.text.split(separator: "\n").suffix(3).joined(separator: " ")
            throw DirectionError("script_failed", "The script stopped without an answer\(why.isEmpty ? "" : " (\(why))").\(madeCalls)\(tail)")
        }
        var answer: [String: JSONValue] = ["result": done, "calls": .number(Double(calls)), "seconds": .number(((SuspendingClock.now - started) / .milliseconds(100)).rounded() / 10)]
        if let cutFrom = got.cutFrom { answer["cut"] = .string("The answer was \(cutFrom) characters and is cut at \(maxAnswer): return less.") }
        if !printed.isEmpty { answer["printed"] = .array(printed.map(JSONValue.string)) }
        if let keptNote { answer["keep"] = .string(keptNote) }
        // Only images and sounds a tool made for this script, never another file, and only those still there.
        let kept = { (made: [String], most: Int) in Array(got.shown.filter { made.contains($0) && FileManager.default.fileExists(atPath: $0) }.prefix(most)) }
        let images = kept(got.rendered, maxShown), sounds = kept(got.sounds, maxSounds)
        if got.shown.count > images.count + sounds.count { answer["notShown"] = .string("show takes the imagePaths or audioPaths a tool returned in this script, up to \(maxShown) images and \(maxSounds) sounds.") }
        return ToolResponse(.object(answer), imagePaths: images, audioPaths: sounds)
    }

    /// A message as a sentence: one full stop, not two.
    static func sentence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.last.map { ".!?\u{2026}".contains($0) } == true ? t : t + "."
    }

    /// The memory a process has, as Activity Monitor counts it.
    static func footprint(_ pid: pid_t) -> UInt64 {
        var info = rusage_info_v2()
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) } }
        return r == 0 ? info.ri_phys_footprint : 0
    }
}

/// What one script's calls and lines gave, written by the task that answers them and read once it's over.
final class Collected: @unchecked Sendable {
    var calls = 0, printed: [String] = [], printedSize = 0, rendered: [String] = [], sounds: [String] = []
    var done: JSONValue?, cutFrom: Int?, shown: [String] = [], failure: (message: String, line: Int)?, keep: JSONValue?
}

/// What an editor's scripts keep between them (`keep`): the run's, in a file in the film's cache, so it's there
/// after the director answers and the session continues; a session of your own keeps it while its tool server runs.
public final class KeptValues: @unchecked Sendable {
    public static let most = 256_000
    private let lock = NSLock()
    private let file: URL?
    private var value: JSONValue = .object([:])
    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let v = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = v { value = v }
    }
    nonisolated(unsafe) private static var shared: [String: KeptValues] = [:]
    private static let sharedLock = NSLock()
    /// One per film in this process: the run's file when Direction started the editor (DIRECTION_RUN_ID).
    public static func forThisProcess(cache: URL) -> KeptValues {
        sharedLock.lock(); defer { sharedLock.unlock() }
        if let k = shared[cache.path] { return k }
        let run = ProcessInfo.processInfo.environment["DIRECTION_RUN_ID"].flatMap { $0.isEmpty ? nil : $0 }
        let k = KeptValues(file: run.map { cache.appendingPathComponent("Scripts/keep-\($0.filter { $0.isLetter || $0.isNumber || $0 == "-" }).json") })
        shared[cache.path] = k
        return k
    }
    public func read() -> JSONValue { lock.lock(); defer { lock.unlock() }; return value }
    public var names: [String] { if case .object(let o) = read() { return o.keys.sorted() }; return [] }
    /// What a script changed since it read `before` goes over what's kept now, so two scripts at once don't lose
    /// each other's. False when the result is too big to keep; what was kept before stays.
    public func write(_ new: JSONValue, since before: JSONValue = .object([:])) -> Bool {
        guard case .object(let fields) = new else { return false }
        lock.lock(); defer { lock.unlock() }
        var merged: [String: JSONValue] = [:]
        if case .object(let now) = value { merged = now }
        var old: [String: JSONValue] = [:]
        if case .object(let o) = before { old = o }
        for (k, v) in fields where old[k] != v { merged[k] = v }
        for k in old.keys where fields[k] == nil { merged[k] = nil }
        let result = JSONValue.object(merged)
        guard let data = try? result.data(), data.count <= Self.most else { return false }
        value = result
        if let file {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
        return true
    }
}

/// A value shared with a pipe's handler.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Text gathered from another thread.
final class ScriptOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func append(_ s: String) { lock.lock(); value = String((value + s).suffix(4_000)); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return value }
}

private extension JSONValue {
    func has(_ key: String) -> Bool { if case .object(let o) = self { return o[key] != nil }; return false }
}

/// The helper's side (`direction script`): reads the script, closes itself off, runs it in JavaScriptCore, and asks
/// Direction for each tool call over stdin and stdout.
public enum ScriptHost {
    @_silgen_name("sandbox_init") private static func sandboxInit(_ profile: UnsafePointer<CChar>, _ flags: UInt64, _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

    /// One line to Direction. When Direction has gone, there's no one to answer: stop.
    static func write(_ v: JSONValue) {
        guard let data = try? v.data() else { return }
        do { try FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8)) } catch { _exit(0) }
    }

    /// macOS's pure-computation sandbox: no files, no network, no other programs, no services. Already-open pipes
    /// still work. Looked up rather than declared, so a macOS without it fails closed.
    static func closeOff() -> String? {
        guard let name = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "kSBXProfilePureComputation") else { return "macOS has no pure-computation sandbox here" }
        var error: UnsafeMutablePointer<CChar>?
        guard sandboxInit(name.assumingMemoryBound(to: CChar.self), 1, &error) == 0 else { return error.map { String(cString: $0) } ?? "the sandbox didn\u{2019}t start" }
        return nil
    }

    /// What a script has: `direction.<tool>(args)`, print, show and console.log, which it can't replace. Direction's
    /// own functions are kept in here and taken off the global object before the script runs. Text goes out well
    /// formed (a lone half of an emoji becomes U+FFFD), so every line Direction reads is JSON.
    static let prelude = #"""
    (function () {
      "use strict";
      const call = __call, say = __print, done = __done, fail = __fail;
      const __keep = globalThis.__kept;
      for (const name of ["__call", "__print", "__done", "__fail", "__kept"]) delete globalThis[name];
      const stringify = JSON.stringify, parse = JSON.parse, wellFormed = String.prototype.toWellFormed;
      const json = function (x) { return stringify(x, function (k, v) { return typeof v === "string" ? wellFormed.call(v) : v; }); };
      const shown = [];
      const direction = new Proxy({}, { get: function (_, name) {
        if (typeof name !== "string" || name === "then" || name === "toJSON") return undefined;
        return function (args) {
          const answer = parse(call(name, json(args === undefined ? {} : args)));
          if (answer.error) { const e = new Error(answer.error.message); e.code = answer.error.code; if (answer.error.index !== undefined) e.index = answer.error.index; throw e; }
          return answer.value;
        };
      } });
      const print = function () {
        const parts = [];
        for (let i = 0; i < arguments.length; i++) { const x = arguments[i]; parts.push(typeof x === "string" ? wellFormed.call(x) : json(x)); }
        say(parts.join(" "));
      };
      const show = function (path) { if (typeof path !== "string") throw new Error("show takes a path from a tool's imagePaths or audioPaths"); if (shown.length < 64) shown.push(path); };
      const kept = function () { try { const k = json(globalThis.keep); return typeof k === "string" ? k : "!"; } catch (x) { return "!"; } };
      const report = function (e) { fail(e && e.message !== undefined ? (e.code ? e.code + ": " : "") + String(e.message) : String(e), e && e.stack ? String(e.stack) : "", kept()); };
      Object.defineProperties(globalThis, {
        direction: { value: direction }, print: { value: print }, show: { value: show }, keep: { value: parse(__keep), writable: true },
        console: { value: Object.freeze({ log: print, info: print, warn: print, error: print }) },
        __start: { value: function (body) {
          let running;
          try { running = body(); } catch (e) { report(e); return; }
          Promise.resolve(running).then(function (v) {
            let s; try { s = json(v === undefined ? null : v); } catch (x) { s = json(String(v)); }
            done(s === undefined ? "null" : s, stringify(shown), kept());
          }, report);
        } },
      });
    })();
    """#

    /// The script's line for a line of the wrapped source (its body starts on the wrapper's second line), within the script.
    static func line(_ wrapped: Int, lines: Int) -> Int { wrapped <= 1 ? 0 : min(wrapped - 1, lines) }
    static func line(fromStack stack: String, lines: Int) -> Int {
        for frame in stack.split(separator: "\n") {
            guard let r = frame.range(of: "script.js:") else { continue }
            if let n = Int(frame[r.upperBound...].prefix { $0.isNumber }) { return line(n, lines: lines) }
        }
        return 0
    }

    public static func serve() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let parent = getppid()
        guard let first = readLine(strippingNewline: true), let request = try? JSONDecoder().decode(JSONValue.self, from: Data(first.utf8)), let code = request["code"].string else {
            write(.object(["failed": .string("No script came")])); _exit(1)
        }
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).count
        // Limits that hold even if Direction goes away without stopping it: CPU time (the script's own work; waiting on
        // a tool takes none) and the parent itself (an orphan is handed to launchd, pid 1). Not wall time: one tool
        // call can take minutes.
        let limit = max(1, request["seconds"].double ?? ScriptRunner.seconds)
        var cpu = rlimit(rlim_cur: rlim_t(limit + 15), rlim_max: rlim_t(limit + 30)); setrlimit(RLIMIT_CPU, &cpu)
        Thread.detachNewThread {
            while true { if getppid() == 1 || getppid() != parent { _exit(3) }; sleep(1) }
        }

        let context = JSContext()!
        nonisolated(unsafe) var finished = false, printedLines = 0, printedSize = 0
        let call: @convention(block) (String, String) -> String = { name, arguments in
            guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8)) else {
                return #"{"error":{"code":"invalid_arguments","message":"The arguments aren’t JSON Direction can read. Nothing was run."}}"#
            }
            write(.object(["call": .string(name.hasPrefix("direction_") ? name : "direction_" + name), "arguments": parsed]))
            guard let answer = readLine(strippingNewline: true) else { _exit(0) }
            return answer
        }
        let say: @convention(block) (String) -> Void = { text in
            // Direction keeps 200 lines and 8,000 characters; past those there's no need to send any.
            guard printedLines < ScriptRunner.maxPrintedLines, printedSize < ScriptRunner.maxPrinted else { return }
            printedLines += 1; printedSize += max(1, text.count)
            write(.object(["print": .string(String(text.prefix(ScriptRunner.maxPrinted)))]))
        }
        // What the script kept, as an object, or nothing when it isn't one.
        let keeping: (String) -> JSONValue = { text in
            guard text.utf8.count <= KeptValues.most else { return .string("big") }
            guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .object = v else { return .string("unreadable") }
            return v
        }
        let done: @convention(block) (String, String, String) -> Void = { value, shown, keep in
            finished = true
            // All of them (the script keeps 64): Direction sorts images from sounds and keeps what it may.
            let paths = (try? JSONDecoder().decode([String].self, from: Data(shown.utf8))) ?? []
            if value.count > ScriptRunner.maxAnswer {
                write(.object(["done": .string(String(value.prefix(ScriptRunner.maxAnswer))), "cutFrom": .number(Double(value.count)), "shown": .array(paths.map(JSONValue.string)), "keep": keeping(keep)]))
            } else if let answer = try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) {
                write(.object(["done": answer, "shown": .array(paths.map(JSONValue.string)), "keep": keeping(keep)]))
            } else {
                write(.object(["failed": .string("The script\u{2019}s answer isn\u{2019}t JSON Direction can read")]))
            }
        }
        let fail: @convention(block) (String, String, String) -> Void = { message, stack, keep in
            finished = true
            write(.object(["failed": .string(message), "line": .number(Double(line(fromStack: stack, lines: lines))), "keep": keeping(keep)]))
        }
        context.setObject(call, forKeyedSubscript: "__call" as NSString)
        context.setObject(say, forKeyedSubscript: "__print" as NSString)
        context.setObject(done, forKeyedSubscript: "__done" as NSString)
        context.setObject(fail, forKeyedSubscript: "__fail" as NSString)
        let keptBefore: JSONValue = { if case .object = request["keep"] { return request["keep"] }; return .object([:]) }()
        context.setObject((try? keptBefore.data()).map { String(decoding: $0, as: UTF8.self) } ?? "{}", forKeyedSubscript: "__kept" as NSString)
        nonisolated(unsafe) var syntax: (String, Int)?
        context.exceptionHandler = { _, exception in
            syntax = (exception?.toString() ?? "an error", line(Int(exception?.objectForKeyedSubscript("line")?.toInt32() ?? 0), lines: lines))
        }
        // What the engine reads lazily (the time zone, numbers and dates in words, sorting text) before it can't
        // read anything.
        _ = context.evaluateScript(prelude)
        _ = context.evaluateScript("JSON.stringify([new Date().getTimezoneOffset(), new Date().toString(), new Date().toLocaleString(), Intl.DateTimeFormat().resolvedOptions().timeZone, (1234.5).toLocaleString(), 'a'.localeCompare('b'), [3,1].sort(), /x/.test('x')])")
        if syntax != nil { write(.object(["failed": .string("Direction couldn\u{2019}t set up the script")])); _exit(1) }
        if let why = closeOff() { write(.object(["failed": .string("Direction couldn\u{2019}t close off the script (\(why)), so it didn\u{2019}t run")])); _exit(1) }
        let body = context.evaluateScript("(async function () {\n" + code + "\n})", withSourceURL: URL(string: "script.js"))
        if let (message, at) = syntax { write(.object(["failed": .string(message), "line": .number(Double(at))])); _exit(0) }
        if let body, body.isObject { _ = context.objectForKeyedSubscript("__start").call(withArguments: [body]) }
        if !finished {
            if let (message, at) = syntax { write(.object(["failed": .string(message), "line": .number(Double(at))])) }
            else { write(.object(["failed": .string("The script ended waiting on something that never came (an await on a promise nothing settles)")])) }
        }
        _exit(0)
    }
}
