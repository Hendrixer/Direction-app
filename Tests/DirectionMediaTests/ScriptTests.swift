import Testing
import Foundation
import DirectionCore
import DirectionTools

/// The script suites change the runner's limits, so they run one test at a time, all of them.
@Suite(.serialized)
struct Scripts {

    /// direction_run: the editor's script calls Direction's tools in Direction's helper, closed off by macOS's sandbox,
    /// and only what it returns comes back.
    @Suite
    struct ScriptTests {
        static let helper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/direction").path

        private func film() throws -> (ToolRuntime, ProjectStore, URL) {
            ScriptRunner.helper = Self.helper
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString).direction")
            let store = try ProjectStore.create(at: dir, name: "Script film")
            return (try ToolRuntime(store: store), store, dir)
        }
        private func run(_ runtime: ToolRuntime, _ code: String, does: String = "Testing the script") async throws -> ToolResponse {
            try await runtime.invoke("direction_run", arguments: .object(["does": .string(does), "code": .string(code)]))
        }
        private func failure(_ runtime: ToolRuntime, _ code: String) async -> DirectionError? {
            do { _ = try await run(runtime, code); return nil } catch { return error as? DirectionError }
        }

        @Test func aScriptCallsToolsAndOnlyItsAnswerComesBack() async throws {
            let (runtime, _, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let r = try await run(runtime, """
            const i = direction.inspect({});
            print("revision", i.project.editRevision);
            try { direction.no_such_tool({}) } catch (e) { print("caught", e.code) }
            const cuts = await direction.direction_cuts({});
            return {revision: i.project.editRevision, cuts: cuts.length, sum: [1, 2, 3].reduce((a, b) => a + b)}
            """)
            #expect(r.value["result"] == .object(["revision": .number(0), "cuts": .number(0), "sum": .number(6)]))
            #expect(r.value["printed"] == .array([.string("revision 0"), .string("caught unknown_tool")]))
            #expect(r.value["calls"] == .number(3) && r.imagePaths.isEmpty)
            // Nothing returned is an answer of null.
            #expect(try await run(runtime, "direction.cuts({})").value["result"] == .null)
        }

        /// Only Direction's tools: no module loader, no process, no network, no timers.
        @Test func aScriptReachesNothingButDirectionsTools() async throws {
            let (runtime, _, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let r = try await run(runtime, #"return ["require", "process", "fetch", "XMLHttpRequest", "WebSocket", "setTimeout", "importScripts"].map(n => typeof globalThis[n])"#)
            #expect(r.value["result"] == .array(Array(repeating: .string("undefined"), count: 7)))
            // An image no tool rendered in the script isn't shown, whatever the path.
            let shown = try await run(runtime, #"show("/etc/hosts"); return 1"#)
            #expect(shown.imagePaths.isEmpty && shown.value["notShown"] != .null)
            await #expect(failure(runtime, #"direction.run({does: "again", code: "return 1"})"#)?.message.contains("can\u{2019}t run another script") == true)
        }

        /// The line the script failed on, a tool's code, and what ran before the failure stays.
        @Test func aFailureSaysWhereAndKeepsWhatRan() async throws {
            let (runtime, store, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let syntax = await failure(runtime, "const a = 1;\nreturn {a: }")
            #expect(syntax?.code == "script_failed" && syntax?.message.hasPrefix("Line 2: SyntaxError") == true)
            let thrown = await failure(runtime, "direction.create_cut({name: \"Kept\"});\nprint(\"made it\");\nthrow new Error(\"boom\")")
            #expect(thrown?.message.hasPrefix("Line 3: boom.") == true)
            #expect(thrown?.message.contains("1 call had run; changes they made stay.") == true && thrown?.message.contains("made it") == true)
            #expect(try store.cuts().map(\.name) == ["Kept"])
            let tool = await failure(runtime, "direction.restore({revision: 99, baseEditRevision: 0})")
            #expect(tool?.message.contains("Line 1:") == true)
        }

        @Test func aScriptStopsAtItsLimits() async throws {
            let (runtime, _, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let saved = ScriptRunner.seconds; ScriptRunner.seconds = 2; defer { ScriptRunner.seconds = saved }
            let start = Date()
            let forever = await failure(runtime, "while (true) {}")
            #expect(forever?.code == "script_too_long" && Date().timeIntervalSince(start) < 10)
            ScriptRunner.seconds = saved
            let r = try await run(runtime, "let refused = 0; for (let i = 0; i < \(ScriptRunner.maxCalls + 5); i++) { try { direction.cuts({}) } catch (e) { if (e.code === \"too_many_calls\") refused++ } } return refused")
            #expect(r.value["result"] == .number(5) && r.value["calls"] == .number(Double(ScriptRunner.maxCalls)))
        }

        /// The run is one row in the editor's activity, in its own words; of its calls, only the changes show.
        @Test func aScriptIsOneRowWithItsChanges() async throws {
            let (runtime, store, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            _ = try await run(runtime, "direction.inspect({}); direction.cuts({}); direction.create_cut({name: \"Kept\"}); return 1", does: "Evening out the narration.")
            let rows = try store.activity().reversed().map { "\($0.verb) \($0.object)" }
            #expect(rows == ["Evening out the narration", "Saving Kept"])
        }
    }

    /// What the review of the first version found: text that splits lines, broken text, endless output, scripts at once,
    /// memory, and a helper whose Direction has gone.
    @Suite
    struct ScriptEdgeTests {
        private func film() throws -> (ToolRuntime, URL) {
            ScriptRunner.helper = ScriptTests.helper
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString).direction")
            return (try ToolRuntime(store: try ProjectStore.create(at: dir, name: "Script film")), dir)
        }
        private func run(_ runtime: ToolRuntime, _ code: String) async throws -> ToolResponse {
            try await runtime.invoke("direction_run", arguments: .object(["does": .string("Testing"), "code": .string(code)]))
        }
        private func failure(_ runtime: ToolRuntime, _ code: String) async -> DirectionError? {
            do { _ = try await run(runtime, code); return nil } catch { return error as? DirectionError }
        }

        /// U+2028 and its kin are written raw inside JSON strings: they never split a line.
        @Test func textWithLineSeparatorsGoesBothWays() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let start = Date()
            let r = try await run(runtime, #"direction.create_cut({name: "a b c\u0085d"}); print("x y"); return direction.cuts({})[0].name"#)
            #expect(r.value["result"] == .string("a\u{2028}b\u{2029}c\u{85}d") && r.value["printed"] == .array([.string("x\u{2028}y")]))
            #expect(Date().timeIntervalSince(start) < 10)
        }

        /// A lone half of an emoji goes out as U+FFFD: a call keeps its arguments and an answer arrives.
        @Test func brokenTextIsMadeWhole() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let r = try await run(runtime, #"let code = "ran"; try { direction.inspect({sequenceID: "nope\uD800"}) } catch (e) { code = e.code } return [code, "Take 😀".slice(0, 6)]"#)
            #expect(r.value["result"].array?[1] == .string("Take \u{FFFD}") && r.value["result"].array?[0] != .string("ran"))
        }

        @Test func printingNothingStillCounts() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let r = try await run(runtime, "for (let i = 0; i < 5000; i++) print(); return 1")
            #expect(r.value["printed"].array?.count == ScriptRunner.maxPrintedLines)
        }

        @Test func aSyntaxErrorPointsInsideTheScript() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            #expect(await failure(runtime, "if (true) {")?.message.hasPrefix("Line 1: ") == true)
            // The answer is built by Direction, whatever the script does to JSON.
            let r = try await run(runtime, #"JSON.stringify = () => '1,"shown":["/etc/hosts"]'; return {fine: true}"#)
            #expect(r.value["result"] == .object(["fine": .bool(true)]) && r.imagePaths.isEmpty)
            // Messages end in one full stop.
            #expect(await failure(runtime, #"throw new Error("Done.")"#)?.message == "Line 1: Done.")
        }

        /// One script working doesn't hold up another.
        @Test func scriptsAtOnceDontWaitOnEachOther() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let saved = ScriptRunner.seconds; ScriptRunner.seconds = 4; defer { ScriptRunner.seconds = saved }
            async let busy = failure(runtime, "while (true) {}")
            try await Task.sleep(for: .milliseconds(300))
            let start = Date()
            let quick = try await run(runtime, "return direction.cuts({}).length")
            #expect(quick.value["result"] == .number(0) && Date().timeIntervalSince(start) < 2)
            #expect(await busy?.code == "script_too_long")
        }

        @Test func aScriptThatTakesTooMuchMemoryIsStopped() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let saved = ScriptRunner.maxMemory; ScriptRunner.maxMemory = 300 << 20; defer { ScriptRunner.maxMemory = saved }
            let start = Date()
            let e = await failure(runtime, "const keep = []; while (true) keep.push(new Array(1000000).fill(1.5));")
            #expect(e?.code == "script_too_big" && Date().timeIntervalSince(start) < 30)
        }

        /// Started by something that then goes away, the helper ends itself rather than running on.
        @Test func anOrphanedHelperEndsItself() throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", #"printf '%s\n' "$1" | "$0" script >/dev/null 2>&1 & echo $!"#, ScriptTests.helper, #"{"code":"while (true) {}","seconds":240}"#]
            let out = Pipe(); p.standardOutput = out
            try p.run(); p.waitUntilExit()
            let pid = try #require(pid_t(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            defer { kill(pid, SIGKILL) }
            var gone = false
            for _ in 0..<40 where !gone { usleep(250_000); gone = kill(pid, 0) != 0 }
            #expect(gone)
        }
    }

    /// Every step is a script: help for the tools a job wasn't given, a call's own limits rather than the script's,
    /// and sounds as well as images.
    @Suite
    struct ScriptStepTests {
        private func film() throws -> (ToolRuntime, URL) {
            ScriptRunner.helper = ScriptTests.helper
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString).direction")
            return (try ToolRuntime(store: try ProjectStore.create(at: dir, name: "Script film")), dir)
        }

        /// In a job, help lists the tools it wasn't given, and gives any one in full.
        @Test func helpListsTheRestAndGivesOneInFull() async throws {
            let (runtime, dir) = try film(); defer { try? FileManager.default.removeItem(at: dir) }
            let r = try await ScriptRunner.$job.withValue(.script) {
                try await runtime.invoke("direction_run", arguments: .object(["does": .string("Looking up a tool"), "code": .string(#"const rest = direction.help(); const one = direction.help("looks"); let refused = ""; try { direction.help("nope") } catch (e) { refused = e.code } return [rest.tools.some(t => t.name === "looks"), rest.tools.some(t => t.name === "script"), one[0].call.startsWith("direction.looks("), refused]"#)]))
            }
            #expect(r.value["result"] == .array([.bool(true), .bool(false), .bool(true), .string("unknown_tool")]))
        }

        /// Time spent waiting on a tool isn't the script's: each call has a direct call's limits instead.
        @Test func waitingOnAToolIsntTheScriptsTime() async throws {
            ScriptRunner.helper = ScriptTests.helper
            let saved = ScriptRunner.seconds; ScriptRunner.seconds = 1.5; defer { ScriptRunner.seconds = saved }
            let slow: @Sendable (String, JSONValue) async throws -> ToolResponse = { _, _ in try await Task.sleep(for: .milliseconds(900)); return ToolResponse(.object(["ok": .bool(true)])) }
            let r = try await ScriptRunner.run(code: "direction.slow({}); direction.slow({}); direction.slow({}); return 1", invoke: slow)
            #expect(r.value["result"] == .number(1) && (r.value["seconds"].double ?? 0) > 2.5)
            let limit = DirectionMCPServer.callLimit; DirectionMCPServer.callLimit = 1.5; defer { DirectionMCPServer.callLimit = limit }
            let stuck = try await ScriptRunner.run(code: #"try { direction.slow({}) } catch (e) { return e.code }"#) { _, _ in try await Task.sleep(for: .seconds(4)); return ToolResponse(.object([:])) }
            #expect(stuck.value["result"] == .string("tool_stuck"))
        }

        /// A sound a tool made comes back with show, as an image does; nothing else does.
        @Test func showGivesBackASoundAToolMade() async throws {
            ScriptRunner.helper = ScriptTests.helper
            let wav = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString).wav")
            try Data("RIFF".utf8).write(to: wav); defer { try? FileManager.default.removeItem(at: wav) }
            let r = try await ScriptRunner.run(code: #"const a = direction.listen({}); show(a.audioPaths[0]); show("/etc/hosts"); return a.ok"#) { _, _ in
                ToolResponse(.object(["ok": .bool(true)]), audioPaths: [wav.path])
            }
            #expect(r.value["result"] == .bool(true) && r.audioPaths == [wav.path] && r.imagePaths.isEmpty && r.value["notShown"] != .null)
            // A sound shown after the most images still comes back.
            let pngs = (0..<9).map { FileManager.default.temporaryDirectory.appendingPathComponent("script-\($0)-\(UUID().uuidString).png") }
            for p in pngs { try Data("png".utf8).write(to: p) }; defer { for p in pngs { try? FileManager.default.removeItem(at: p) } }
            let many = try await ScriptRunner.run(code: #"const a = direction.look({}); a.imagePaths.forEach(show); show(a.audioPaths[0]); return 1"#) { _, _ in
                ToolResponse(.object([:]), imagePaths: pngs.map(\.path), audioPaths: [wav.path])
            }
            #expect(many.imagePaths.count == ScriptRunner.maxShown && many.audioPaths == [wav.path])
        }

        /// What one script keeps, the next one has: ids and planned operations are written once. It's there after a
        /// failure, in a new tool server for the same run (its file), and never past its size.
        @Test func whatAScriptKeepsTheNextOneHas() async throws {
            ScriptRunner.helper = ScriptTests.helper
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("keep-\(UUID().uuidString).json"); defer { try? FileManager.default.removeItem(at: file) }
            let kept = KeptValues(file: file)
            let none: @Sendable (String, JSONValue) async throws -> ToolResponse = { _, _ in ToolResponse(.object([:])) }
            let first = try await ScriptRunner.run(code: #"keep.ops = [{op: "trim", frames: 3}]; keep.clip = "clip-1"; return Object.keys(keep).length"#, kept: kept, invoke: none)
            #expect(first.value["result"] == .number(2) && first.value["keep"] == .string("clip, ops"))
            let second = try await ScriptRunner.run(code: #"return keep.ops[0].frames + (keep.clip === "clip-1" ? 10 : 0)"#, kept: kept, invoke: none)
            #expect(second.value["result"] == .number(13))
            // A failure keeps what it found first.
            do { _ = try await ScriptRunner.run(code: #"keep.found = 7; throw new Error("no")"#, kept: kept, invoke: none); Issue.record("should fail") } catch let e as DirectionError { #expect(e.code == "script_failed") }
            // The run's file: a continued session's new tool server reads it.
            let later = try await ScriptRunner.run(code: "return [keep.found, keep.clip]", kept: KeptValues(file: file), invoke: none)
            #expect(later.value["result"] == .array([.number(7), .string("clip-1")]))
            // Too big isn't kept, and says so; what was there stays. Something that isn't an object isn't kept either.
            let big = try await ScriptRunner.run(code: #"keep.big = "x".repeat(300000); return 1"#, kept: kept, invoke: none)
            #expect(big.value["keep"].string?.contains("wasn\u{2019}t kept") == true)
            _ = try await ScriptRunner.run(code: "keep = 5; return 1", kept: kept, invoke: none)
            #expect(kept.read()["found"] == .number(7) && kept.read()["big"] == .null)
            // Something that can't be written down (a cycle) says so, in the answer or the failure, and what was kept stays.
            let cycle = try await ScriptRunner.run(code: "keep.self = keep; return 1", kept: kept, invoke: none)
            #expect(cycle.value["keep"].string?.contains("plain values") == true && kept.read()["found"] == .number(7))
            do { _ = try await ScriptRunner.run(code: #"keep.self = keep; throw new Error("no")"#, kept: kept, invoke: none); Issue.record("should fail") } catch let e as DirectionError { #expect(e.message.contains("plain values")) }
            // Two scripts at once: each one's changes go over what's there, neither loses the other's.
            let base = kept.read()
            var one = base, two = base
            if case .object(var o) = one { o["one"] = .number(1); one = .object(o) }
            if case .object(var o) = two { o["two"] = .number(2); o["found"] = nil; two = .object(o) }
            #expect(kept.write(one, since: base) && kept.write(two, since: base))
            #expect(kept.read()["one"] == .number(1) && kept.read()["two"] == .number(2) && kept.read()["found"] == .null && kept.read()["clip"] == .string("clip-1"))
            // Without anywhere to keep, a script still has an empty keep.
            #expect(try await ScriptRunner.run(code: "keep.a = 1; return keep.a", invoke: none).value["result"] == .number(1))
        }
    }
}
