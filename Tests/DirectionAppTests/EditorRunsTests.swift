import Testing
import Foundation
import DirectionCore
import DirectionTools
@testable import DirectionApp

// specs/editor.md: the event streams, the activity table, the run state machine, the job
// templates, the command lines, and an end-to-end run against a fake program.

@Suite("Editor streams")
struct EditorStreamTests {
    /// Claude Code 2.1 `--output-format stream-json --verbose`, trimmed from a real `ready` check plus a tool call.
    static let claude = [
        #"{"type":"system","subtype":"init","cwd":"/tmp/Film.direction/Editor","session_id":"650435d2-1588-4385-9f1a-22f5243ccc38","tools":["mcp__direction__direction_watch"],"mcp_servers":[{"name":"direction","status":"connected"}],"model":"claude-opus-5-5"}"#,
        #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"Watching the ridge."},{"type":"tool_use","id":"toolu_01","name":"mcp__direction__direction_watch","input":{"start":72.33,"end":84}}]},"session_id":"650435d2-1588-4385-9f1a-22f5243ccc38"}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_01","content":[{"type":"text","text":"{\"frames\":12}"}]}]}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_02","name":"mcp__direction__direction_make","input":{"kind":"music","noteID":"note-4"}}]}}"#,
        #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_02","is_error":true,"content":"{\"code\":\"spend_cap\",\"message\":\"You've reached this month's limit: $50.00 spent on services this month.\"}"}]}}"#,
        #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#,
        #"{"type":"result","subtype":"success","is_error":false,"result":"{\"finished\": false, \"summary\": \"Waiting on you.\", \"needsYou\": [\"Raise the limit\"]}","total_cost_usd":0.8431,"session_id":"650435d2-1588-4385-9f1a-22f5243ccc38","num_turns":4}"#,
    ]

    @Test func claudeStreamGivesSessionToolsCostAndResult() {
        var p = ClaudeStreamParser()
        let events = Self.claude.flatMap { p.parse($0) }
        #expect(events.first == .session("650435d2-1588-4385-9f1a-22f5243ccc38"))
        #expect(events.contains(.toolStarted(id: "toolu_01", name: "mcp__direction__direction_watch", input: .object(["start": .number(72.33), "end": .number(84)]))))
        #expect(events.contains(.toolFinished(id: "toolu_01", isError: false, text: "{\"frames\":12}")))
        #expect(events.contains { if case .toolFinished("toolu_02", true, let t) = $0 { EditorFailure.isSpendCap(t) } else { false } })
        #expect(events.contains(.cost(0.8431)))
        guard case .result(let text, let isError) = events.last else { Issue.record("No result"); return }
        #expect(!isError)
        #expect(EditorResult.parse(text) == EditorResult(finished: false, summary: "Waiting on you.", needsYou: ["Raise the limit"]))
        // The editor's prose and rate-limit chatter aren't events.
        #expect(events.count == 8)
    }

    @Test func claudeNotSignedInReadsAsSignIn() {
        var p = ClaudeStreamParser()
        let events = p.parse(#"{"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login","session_id":"s"}"#)
        #expect(events.contains(.result(text: "Invalid API key · Please run /login", isError: true)))
        #expect(EditorFailure.reason("Invalid API key · Please run /login") == .notSignedIn)
    }

    /// Codex 0.164 `exec --json`: the real `ready` check's shape plus an MCP call, a command and a file change.
    static let codex = [
        #"{"type":"thread.started","thread_id":"01a186af-5cc0-7410-875d-55d7457034f8"}"#,
        #"{"type":"turn.started"}"#,
        #"{"type":"item.started","item":{"id":"item_0","type":"mcp_tool_call","server":"direction","tool":"direction_frame","arguments":{"assetID":"take-3b-t1"},"result":null,"error":null,"status":"in_progress"}}"#,
        #"{"type":"item.completed","item":{"id":"item_0","type":"mcp_tool_call","server":"direction","tool":"direction_frame","arguments":{"assetID":"take-3b-t1"},"result":{"content":[{"type":"text","text":"ok"}]},"error":null,"status":"completed"}}"#,
        #"{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"python3 analyze.py","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#,
        #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"python3 analyze.py","aggregated_output":"","exit_code":1,"status":"failed"}}"#,
        #"{"type":"item.completed","item":{"id":"item_2","type":"file_change","changes":[{"path":"Graphics/title/index.html","kind":"add"}],"status":"completed"}}"#,
        #"{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"{\"finished\": true, \"summary\": \"Delivered Cut 4.\", \"needsYou\": []}"}}"#,
        #"{"type":"turn.completed","usage":{"input_tokens":24502,"cached_input_tokens":13184,"output_tokens":5}}"#,
    ]

    @Test func codexStreamGivesThreadCallsTokensAndMessage() {
        var p = CodexStreamParser()
        let events = Self.codex.flatMap { p.parse($0) }
        #expect(events.first == .session("01a186af-5cc0-7410-875d-55d7457034f8"))
        #expect(events.contains(.toolStarted(id: "item_0", name: "direction_frame", input: .object(["assetID": .string("take-3b-t1")]))))
        #expect(events.contains(.toolFinished(id: "item_0", isError: false, text: "ok")))
        #expect(events.contains(.toolStarted(id: "item_1", name: "command_execution", input: .object(["command": .string("python3 analyze.py")]))))
        #expect(events.contains(.toolFinished(id: "item_1", isError: true, text: "")))
        #expect(events.contains(.toolStarted(id: "item_2", name: "file_change", input: .object(["path": .string("Graphics/title/index.html")]))))
        #expect(events.contains(.tokens(24507)))
        guard case .result(let text, false) = events.last else { Issue.record("No result"); return }
        #expect(EditorResult.parse(text)?.summary == "Delivered Cut 4.")
    }

    @Test func codexFailuresAreFailures() {
        var p = CodexStreamParser()
        #expect(p.parse(#"{"type":"turn.failed","error":{"message":"stream disconnected before completion: error sending request"}}"#) == [.failure("stream disconnected before completion: error sending request")])
        #expect(p.parse(#"{"type":"error","message":"401 Unauthorized. Run codex login."}"#) == [.failure("401 Unauthorized. Run codex login.")])
        #expect(EditorFailure.reason("stream disconnected before completion") == .offline)
        #expect(EditorFailure.reason("401 Unauthorized") == .notSignedIn)
        #expect(EditorFailure.amount("$50.00 spent on services this month.") == "$50.00")
    }

    /// Codex's initialize carries experimental capabilities the Swift SDK can't decode; they're dropped.
    @Test func codexHandshakeLosesOnlyItsExperimentalCapabilities() throws {
        let initialize = Data(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"experimental":{"codex/auth-change":{}},"elicitation":{"form":{},"url":{}}},"clientInfo":{"name":"codex-mcp-client","title":"Codex","version":"0.164.0"}}}"#.utf8)
        let clean = try JSONDecoder().decode(JSONValue.self, from: EditorClientTransport.sanitized(initialize))
        #expect(clean["params"]["capabilities"]["experimental"] == .null)
        #expect(clean["params"]["capabilities"]["elicitation"] != .null && clean["params"]["clientInfo"]["name"].string == "codex-mcp-client")
        let call = Data(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"direction_brief","arguments":{"experimental":true}}}"#.utf8)
        #expect(EditorClientTransport.sanitized(call) == call)
    }

    @Test func resultIsFoundInsideProseOrAFence() {
        #expect(EditorResult.parse("All set.\n```json\n{\"finished\": true, \"summary\": \"Logged 214 takes.\", \"needsYou\": [\"Check two names\"]}\n```") == EditorResult(finished: true, summary: "Logged 214 takes.", needsYou: ["Check two names"]))
        #expect(EditorResult.parse("No JSON here.") == nil)
    }
}

@Suite("Editor activity")
@MainActor
struct EditorActivityTests {
    private var context: EditorActivityLog.Context {
        let p = SampleFilm.project(clips: SampleFilm.cut3Clips, revision: 12)
        return .init(project: p, dailies: SampleFilm.dailies(), cuts: SampleFilm.cuts, turnovers: [], noteNumbers: { ["note-1": 1, "note-3": 3, "note-4": 4, "note-8": 8] })
    }
    private func activity(_ name: String, _ a: [String: JSONValue]) -> ActivityInput? { EditorActivityLog.activity(for: name, .object(a), context: context) }

    @Test func watchingAndLooking() {
        let watch = activity("direction_watch", ["start": .number(SampleFilm.tc(1, 12, 8)), "end": .number(SampleFilm.tc(1, 14))])
        #expect(watch?.verb == "Watching")
        #expect(watch?.object == "01:12:08\u{2013}01:14:00")
        #expect(watch?.mono == true && watch?.time == SampleFilm.tc(1, 12, 8))
        let frame = activity("direction_frame", ["time": .number(SampleFilm.tc(1, 12, 8))])
        #expect(frame?.verb == "Watching" && frame?.object == "01:12:08" && frame?.time != nil)
        let take = activity("direction_frame", ["assetID": .string("take-3b-t1")])
        #expect(take?.verb == "Looking at" && take?.object == "3B T1" && take?.time == nil)
        #expect(activity("direction_contact_sheet", ["assetID": .string("take-2a-t2")])?.object == "2A T2")
        #expect(activity("direction_transcribe", ["assetID": .string("take-2a-t3")])?.verb == "Listening to")
        let search = activity("direction_search_footage", ["query": .string("Maya laughing")])
        #expect(search?.verb == "Searching footage for" && search?.object == "\u{201C}Maya laughing\u{201D}")
    }

    @Test func editsNameTheirVerbScenesDeltaAndNote() {
        // The edit functions' shape (agent-timeline.md): the first operation's verb, the scenes touched.
        let trim = activity("direction_edit", ["baseEditRevision": .number(12), "notes": .array([.number(1)]), "operations": .array([.object(["op": .string("removeRange"), "range": .object(["start": .number(4.2), "end": .number(8.4)])])])])
        #expect(trim?.verb == "Trimming" && trim?.object == "scene 1")
        #expect(trim?.detail == "\u{2212}4.2 s \u{00B7} note 1")
        #expect(trim?.time == 4.2)
        let reframe = activity("direction_edit", ["operations": .array([.object(["op": .string("reframe"), "clipID": .string("clip-take-3a-t2-65"), "scale": .number(1.6)])]), "notes": .array([.string("note-3")])])
        #expect(reframe?.verb == "Reframing" && reframe?.object == "3A T2 to 1.6\u{00D7}" && reframe?.detail == "note 3" && reframe?.time == 65)
        let swap = activity("direction_edit", ["operations": .array([.object(["op": .string("replaceTake"), "clipID": .string("clip-take-2a-t2-25"), "withAssetID": .string("take-2a-t3")]), .object(["op": .string("roll"), "editPoint": .string("clip-take-3a-t2-65|clip-take-4a-t1-110"), "frames": .number(-6)])])])
        #expect(swap?.verb == "Swapping takes in" && swap?.object == "scenes 2 and 3")
        // Today's batch shape still reads: { batch: { operations: [{ type, … }] } }.
        let legacy = activity("direction_edit", ["batch": .object(["operations": .array([.object(["type": .string("speed"), "clipID": .string("clip-take-4a-t1-110")])])])])
        #expect(legacy?.verb == "Retiming" && legacy?.object == "scene 4")
    }

    @Test func makingDrawingAndTheRestOfTheTable() {
        #expect(activity("direction_make", ["kind": .string("music"), "noteID": .string("note-4")])?.object == "music for note 4")
        let graphic = activity("direction_graphic", ["name": .string("the title"), "note": .number(8), "at": .number(2)])
        #expect(graphic?.verb == "Drawing" && graphic?.object == "the title for note 8" && graphic?.time == 2)
        #expect(activity("direction_make_look", ["noteID": .string("note-3")])?.object == "for note 3")
        #expect(activity("direction_turnover_update", ["turnoverID": .string("t"), "readBack": .array(Array(repeating: .object([:]), count: 7))])?.object == "7 notes")
        #expect(activity("direction_turnover_update", ["turnoverID": .string("t"), "progress": .object([:])]) == nil)
        #expect(activity("direction_ask", ["noteIDs": .array([.string("note-3")])])?.object == "about note 3")
        #expect(activity("direction_turnover_complete", ["turnoverID": .string("t")])?.object == "Cut 4")
        #expect(activity("direction_brief", [:])?.object == "the brief")
        #expect(activity("direction_turnovers", [:])?.object == "the notes")
        #expect(activity("direction_looks", [:]).map { "\($0.verb) \($0.object)" } == "Reading the looks")
        #expect(activity("direction_editor_status", ["phase": .string("x")]) == nil)
        #expect(EditorActivityLog.programActivity(tool: "Write", path: "/f/Editor/Graphics/title.html")?.object == "title.html")
    }

    @Test func pastTenseForFinishedRows() {
        #expect(EditorActivityWords.past("Reframing") == "Reframed")
        #expect(EditorActivityWords.past("Reading back") == "Read back")
        #expect(EditorActivityWords.past("Swapping takes in") == "Swapped takes in")
        #expect(EditorActivityWords.past("Listening to") == "Listening to")
        #expect(EditorActivityWords.past("Watching") == "Watching")
    }

    @Test func storeMergesConsecutiveCallsAndTellsTheApp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir, name: "Activity")
        let before = try store.eventCursor()
        EditorActivityLog.record("direction_watch", .object(["start": .number(1), "end": .number(2)]), store: store, runID: "run-1")
        EditorActivityLog.record("direction_brief", .object([:]), store: store, runID: "run-1")
        EditorActivityLog.record("direction_brief", .object([:]), store: store, runID: "run-1")
        EditorActivityLog.record("direction_brief", .object([:]), store: store, runID: nil)
        let rows = try store.activity()
        #expect(rows.map(\.verb) == ["Reading", "Reading", "Watching"])
        #expect(rows[1].count == 2 && rows[1].runID == "run-1")
        #expect(rows[0].runID == nil)
        #expect(try store.activity(runID: "run-1").count == 2)
        #expect(try store.eventCursor() == before + 4)
    }
}

@Suite("Editor run state machine")
struct RunStateMachineTests {
    typealias E = RunStateMachine.Exit
    @Test func everyEndingHasItsState() {
        #expect(RunStateMachine.outcome(E(finished: true)).state == .done)
        #expect(RunStateMachine.outcome(E(status: 130, intent: .pause)).state == .paused)
        #expect(RunStateMachine.outcome(E(status: 130, intent: .quit)) == .init(state: .paused, reason: .pausedByQuit))
        #expect(RunStateMachine.outcome(E(status: 143, intent: .stop)) == .init(state: .stopped, reason: .stoppedByYou))
        #expect(RunStateMachine.outcome(E(waitingForYou: true)).state == .waitingForYou)
        #expect(RunStateMachine.outcome(E()) == .init(state: .failed, reason: .stoppedWithoutFinishing))
        #expect(RunStateMachine.outcome(E(status: 1, failures: ["Invalid API key · Please run /login"])).reason == .notSignedIn)
        #expect(RunStateMachine.outcome(E(status: 1, failures: ["getaddrinfo ENOTFOUND api.anthropic.com"])).reason == .offline)
        #expect(RunStateMachine.outcome(E(spendCap: "$50.00 spent on services this month.")) == .init(state: .failed, reason: .spendCap, detail: "$50.00 spent on services this month."))
        #expect(RunStateMachine.outcome(E(status: 3, lastErrorLine: "fell over")) == .init(state: .failed, reason: .programQuit, detail: "fell over"))
        #expect(RunStateMachine.outcome(E(notInstalled: true)).reason == .notInstalled)
        // A sign-in failure wins over "waiting": the read-back can't be continued without signing in.
        #expect(RunStateMachine.outcome(E(status: 1, waitingForYou: true, failures: ["Please run /login"])).reason == .notSignedIn)
    }
}

@Suite("Editor jobs and programs")
@MainActor
struct EditorJobTests {
    @Test func aStyleFromVideosNamesEachStudyAndGoesOnceTheStyleIsSaved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("style-videos-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir, name: "Launch film")
        let folder = dir.appendingPathComponent("Editor/Learn/2026-10-31-1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let study = VideoStudy(title: "How I edit", by: "Someone", link: "https://youtu.be/abc", seconds: 60, pace: .init(shots: 20, cutsPerMinute: 19, averageShot: 3, medianShot: 3, longestShot: 7, firstCut: 1, cutsByMinute: [19]),
                               picture: .init(close: 0.5, medium: 0.5, wide: 0, noFace: 0, punchIns: 0.4, brightness: 0.5, contrast: 0.2, saturation: 0.4, warmth: 0), shots: [])
        try JSONEncoder.direction.encode(study).write(to: folder.appendingPathComponent(VideoStudy.fileName))
        try Data("video".utf8).write(to: folder.appendingPathComponent("video.mp4"))
        var run = EditorRun(job: .style, program: "claudeCode", version: "claude-opus-5-5")
        run.request = "The pace and the captions."; run.studies = [folder.path]
        let text = try EditorJobs.text(for: run, store: store)
        #expect(text.contains("`Learn/2026-10-31-1/`") && text.contains("How I edit") && text.contains("studies: [\"Learn/2026-10-31-1\"]") && text.contains("`Learn/2026-10-31-1/video.mp4`") && !text.contains("{{"))
        // Still running or stopped: the folder stays for Try Again. Done: it goes, and only folders in the film.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        run.studies = [folder.path, outside.path]; run.state = .failed
        try store.saveRun(run)
        EditorRunsModel.cleanUpStudies(try store.runs(), store: store)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        _ = try store.updateRun(run.id) { $0.state = .done }
        EditorRunsModel.cleanUpStudies(try store.runs(), store: store)
        let after = try #require(try store.run(run.id))
        #expect(!FileManager.default.fileExists(atPath: folder.path) && FileManager.default.fileExists(atPath: outside.path) && after.studies == nil)

        // A technique's tutorial goes the same way once it's saved.
        let tutorial = dir.appendingPathComponent("Editor/Learn/2026-10-31-tutorial")
        try FileManager.default.createDirectory(at: tutorial, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: tutorial.appendingPathComponent("video.mp4"))
        var learn = EditorRun(job: .technique, state: .working, program: "claudeCode", version: "claude-opus-5-5")
        learn.learnFolder = tutorial.path; learn.learnVideo = tutorial.appendingPathComponent("video.mp4").path
        try store.saveRun(learn)
        EditorRunsModel.cleanUpStudies(try store.runs(), store: store)
        #expect(FileManager.default.fileExists(atPath: tutorial.path))
        _ = try store.updateRun(learn.id) { $0.state = .done }
        EditorRunsModel.cleanUpStudies(try store.runs(), store: store)
        let learned = try #require(try store.run(learn.id))
        #expect(!FileManager.default.fileExists(atPath: tutorial.path) && learned.learnFolder == nil && learned.learnVideo == nil)
    }

    @Test func briefReferencesThatAreVideosAreStudiedAndTheirStudiesGoWithThem() throws {
        #expect(ReferenceVideo.isVideo("https://www.youtube.com/watch?v=abc") && ReferenceVideo.isVideo("https://youtu.be/abc") && ReferenceVideo.isVideo("https://vimeo.com/123"))
        #expect(!ReferenceVideo.isVideo("https://example.com/article") && ReferenceVideo.isVideo("/Volumes/Card/A001.mov") && !ReferenceVideo.isVideo("/Users/me/still.jpg"))
        #expect(ReferenceVideo.isLink("https://youtu.be/abc") && !ReferenceVideo.isLink("not a link"))
        let film = FileManager.default.temporaryDirectory.appendingPathComponent("refs-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: film) }
        for id in ["ref-keep", "ref-gone"] { try FileManager.default.createDirectory(at: ReferenceVideo.folder(id, film: film), withIntermediateDirectories: true) }
        var brief = Brief(); brief.references = [BriefReference(id: "ref-keep", title: "Keep", why: "")]
        ReferenceVideo.cleanUp(brief, film: film)
        #expect(FileManager.default.fileExists(atPath: ReferenceVideo.folder("ref-keep", film: film).path) && !FileManager.default.fileExists(atPath: ReferenceVideo.folder("ref-gone", film: film).path))
        // Only the video and its frames go from a study; what was read from it stays.
        let study = ReferenceVideo.folder("ref-keep", film: film)
        for name in ["video.mp4", "video.info.json", "study.json", "transcript.txt", "sheet-1.jpg"] { try Data("x".utf8).write(to: study.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: study.appendingPathComponent("frames"), withIntermediateDirectories: true)
        ReferenceVideo.removeVideo(in: study)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: study.path)) == ["video.info.json", "study.json", "transcript.txt", "sheet-1.jpg"])
    }

    @Test func everyTemplateShipsAndFillsCompletely() throws {
        for name in EditorJobs.templateNames {
            let t = try #require(EditorJobs.template(name), "\(name).md is missing from the app bundle")
            #expect(t.hasPrefix("<!-- direction-job \(name) v"), "\(name).md needs its version line")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir, name: "Launch film")
        var b = Brief(); b.logline = "Maya spent two years building the part nobody wanted to build."; b.feeling = "Tired, then proud."
        try store.saveBrief(b)
        let t = try store.turnOver(noteIDs: [], kind: "assembly", latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        for job in EditorJob.allCases {
            let run = EditorRun(job: job, program: "claudeCode", version: "claude-opus-5-5", turnoverID: job == .assemble || job == .turnover ? t.id : nil)
            let text = try EditorJobs.text(for: run, store: store)
            #expect(!text.contains("{{"), "\(job) left a placeholder: \(text)")
            #expect(text.contains("`\(job.skill)`"))
            #expect(text.contains("Tired, then proud."))
        }
        // A style run carries the director's words and is done once a style is saved after it began.
        let styles = dir.appendingPathComponent("Styles")
        SharedSettings.stylesFolderOverride = styles
        defer { SharedSettings.stylesFolderOverride = nil }
        var style = EditorRun(job: .style, program: "claudeCode", version: "")
        style.request = "Fast and friendly.\nYellow captions."; style.fromFilm = true; style.startedAt = Date().timeIntervalSince1970
        let asked = try EditorJobs.text(for: style, store: store)
        #expect(asked.contains("> Fast and friendly.\n> Yellow captions.") && asked.contains(styles.path) && asked.contains("Don't take it from this film's cut."))
        #expect(!EditorRunner.finished(style, store: store))
        try StyleLibrary.create(name: "Desk Talk", summary: "", in: styles)
        #expect(EditorRunner.finished(style, store: store))
        let more = EditorJobs.continuation("I approved your read-back. Cut it.", job: .turnover)
        #expect(more.hasPrefix("I approved your read-back.") && !more.contains("{{"))
        #expect(!EditorJobs.role.contains("{{") && EditorJobs.role.contains("\"finished\""))
    }

    @Test func theFinishJobCarriesTheDirectorsCreditsAndLicenses() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("finish-\(UUID().uuidString).direction")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ProjectStore.create(at: dir, name: "Launch film")
        let run = EditorRun(job: .finish, program: "claudeCode", version: "")
        #expect(try EditorJobs.text(for: run, store: store).contains("hasn\u{2019}t written credits yet"))
        try store.saveCredits("Featuring\nMaya Chen\n\nCamera\nSam Ortiz")
        let license = FileManager.default.temporaryDirectory.appendingPathComponent("North Light \(UUID().uuidString).pdf")
        try Data("license".utf8).write(to: license); defer { try? FileManager.default.removeItem(at: license) }
        let file = try store.addLicense(from: license)
        let text = try EditorJobs.text(for: run, store: store)
        #expect(text.contains("> Featuring\n> Maya Chen\n>\n> Camera\n> Sam Ortiz") && text.contains("credits-roll") && text.contains(file.path))
        #expect(text.contains("direction_measure_audio") && !text.contains("{{"))
    }

    @Test func commandLinesUseOnlyTheCheckedFlags() {
        let i = EditorProgram.Invocation(job: "Do the job.", role: "Be the editor.", version: "claude-opus-5-5", session: nil, folder: URL(fileURLWithPath: "/f/Editor"), mcpConfig: URL(fileURLWithPath: "/f/Editor/.mcp.json"), schema: URL(fileURLWithPath: "/f/Editor/.direction/result.schema.json"), helper: "/A/direction", film: URL(fileURLWithPath: "/f"), runID: "run-1", scripts: true)
        let claude = EditorProgram.claudeCode.arguments(i)
        #expect(Array(claude.prefix(2)) == ["--print", "Do the job."])
        for flag in claude where flag.hasPrefix("--") { #expect(EditorProgram.claudeFlags.contains(flag), "\(flag) isn't in claudeFlags") }
        #expect(claude.contains("--strict-mcp-config") && claude.contains("mcp__direction,Read,Glob,Grep,Edit(./**),Write(./**),Bash"))
        var resumed = i; resumed.session = "s-1"; resumed.scripts = false
        let again = EditorProgram.claudeCode.arguments(resumed)
        #expect(again.suffix(2) == ["--resume", "s-1"] && !again.joined().contains("Bash"))
        let codex = EditorProgram.codex.arguments(i)
        #expect(codex.first == "exec" && codex.last == "Do the job.")
        for flag in codex where flag.hasPrefix("--") { #expect(EditorProgram.codexExecFlags.contains(flag), "\(flag) isn't in codexExecFlags") }
        #expect(codex.contains("mcp_servers.direction.args=[\"mcp\",\"--project\",\"/f\"]"))
        let codexAgain = EditorProgram.codex.arguments(resumed)
        #expect(Array(codexAgain.prefix(2)) == ["exec", "resume"] && codexAgain.suffix(2) == ["s-1", "Do the job."])
        for flag in codexAgain where flag.hasPrefix("--") { #expect(EditorProgram.codexResumeFlags.contains(flag), "\(flag) isn't in codexResumeFlags") }
        #expect(codexAgain.contains("sandbox_mode=\"read-only\""))
        // No effort chosen: the program decides. Chosen: Claude Code's flag, Codex's config key, on resume too.
        #expect(!claude.contains("--effort") && !codex.joined().contains("model_reasoning_effort"))
        var harder = i; harder.effort = "high"
        let claudeHigh = EditorProgram.claudeCode.arguments(harder)
        #expect(claudeHigh.firstIndex(of: "--effort").map { claudeHigh[$0 + 1] } == "high")
        harder.session = "s-1"
        #expect(EditorProgram.codex.arguments(harder).contains("model_reasoning_effort=\"high\""))
    }

    /// Programs change: when one is installed, every flag Direction uses must still be in its help.
    @Test func flagsStillExistInTheInstalledPrograms() {
        if let claude = EditorDiscovery.find(.claudeCode) {
            let help = EditorDiscovery.run(claude.path, ["--help"], environment: EditorDiscovery.environment(adding: claude.path), timeout: 30)
            let text = (help?.output ?? "") + (help?.error ?? "")
            for flag in EditorProgram.claudeFlags { #expect(text.contains(flag), "claude --help no longer lists \(flag)") }
        }
        if let codex = EditorDiscovery.find(.codex) {
            let env = EditorDiscovery.environment(adding: codex.path)
            let exec = EditorDiscovery.run(codex.path, ["exec", "--help"], environment: env, timeout: 30).map { $0.output + $0.error } ?? ""
            for flag in EditorProgram.codexExecFlags { #expect(exec.contains(flag), "codex exec --help no longer lists \(flag)") }
            let resume = EditorDiscovery.run(codex.path, ["exec", "resume", "--help"], environment: env, timeout: 30).map { $0.output + $0.error } ?? ""
            for flag in EditorProgram.codexResumeFlags { #expect(resume.contains(flag), "codex exec resume --help no longer lists \(flag)") }
        }
    }

    @Test func versionsReadFromThePrograms() {
        #expect(EditorDiscovery.parseVersion("2.1.312 (Claude Code)") == "2.1.312")
        #expect(EditorDiscovery.parseVersion("codex-cli 0.164.0") == "0.164.0")
        #expect(EditorProgram.claudeCode.versionName("claude-opus-5-5") == "Claude Opus 5.5")
    }
}

/// Runs the fake program in Tests/FakeEditor through the real runner: launch, stream, state, pause, resume.
@Suite("Editor runner", .serialized)
@MainActor
struct EditorRunnerTests {
    static let fake = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("FakeEditor/fake-claude").path

    private func film(logged: Bool) throws -> (ProjectStore, URL) {
        EditorPrograms.shared.setPreview([:])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("runner-\(UUID().uuidString).direction")
        let store = try ProjectStore.create(at: dir, name: "Runner film")
        let asset = MediaAsset(id: "take-1", name: "A001.mov", path: "/Volumes/Nowhere/A001.mov", duration: .init(seconds: 10))
        try store.addAsset(asset, append: false, expectedRevision: 0)
        if logged { _ = try store.logDailies(Dailies(scenes: [], takes: ["take-1": TakeInfo(assetID: "take-1")])) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Editor"), withIntermediateDirectories: true)
        let runner = EditorRunner.shared
        runner.programOverride = [.claudeCode: Self.fake]; runner.helperOverride = "/usr/bin/true"
        return (store, dir)
    }
    private func scenario(_ name: String, _ dir: URL) throws { try Data(name.utf8).write(to: dir.appendingPathComponent("Editor/.fake-scenario")) }
    private func args(_ dir: URL) -> [String] { ((try? String(contentsOf: dir.appendingPathComponent("Editor/.fake-args"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }

    private func wait(_ store: ProjectStore, _ id: String, until done: (EditorRun) -> Bool) async throws -> EditorRun {
        for _ in 0..<200 {
            if let r = try store.run(id), done(r) { return r }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DirectionError("timeout", "The run never got there: \(String(describing: try store.run(id)))")
    }
    private func ended(_ store: ProjectStore, _ id: String) async throws -> EditorRun {
        try await wait(store, id) { !$0.state.isActive && !EditorRunner.shared.isLive(id) && $0.endedAt != nil }
    }
    private func start(_ job: EditorJob, store: ProjectStore, turnoverID: String? = nil) throws -> EditorRun {
        let run = EditorRun(job: job, program: "claudeCode", version: "claude-opus-5-5", turnoverID: turnoverID)
        try store.saveRun(run)
        EditorRunner.shared.launch(run, store: store)
        return run
    }

    @Test func aFinishedJobEndsDoneWithItsSessionSpendAndActivity() async throws {
        let (store, dir) = try film(logged: true); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("done", dir)
        let run = try start(.logFootage, store: store)
        let r = try await ended(store, run.id)
        #expect(r.state == .done)
        #expect(r.session == "fake-session-1" && r.spend == 0.42 && r.summary == "Logged 1 take." && r.invocations == 1)
        let a = args(dir)
        #expect(a.first == "--print" && a.contains("stream-json") && a.contains("--strict-mcp-config") && a.contains("claude-opus-5-5"))
        #expect((try? String(contentsOf: dir.appendingPathComponent("Editor/.fake-run-id"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == run.id)
        let mcp = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: dir.appendingPathComponent("Editor/.mcp.json")))
        #expect(mcp["mcpServers"]["direction"]["args"] == .array([.string("mcp"), .string("--project"), .string(store.url.path)]))
        #expect(mcp["mcpServers"]["direction"]["env"]["DIRECTION_RUN_ID"].string == run.id)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Editor/.claude/skills/start-project/SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Editor/NOTES.md").path))
        #expect(try store.activity(runID: run.id).contains { $0.verb == "Reading" && $0.object == "NOTES.md" })
    }

    @Test func endingWithoutTheFinishingToolFails() async throws {
        let (store, dir) = try film(logged: false); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("unfinished", dir)
        let r = try await ended(store, try start(.logFootage, store: store).id)
        #expect(r.state == .failed && r.reason == .stoppedWithoutFinishing)
        #expect(EditorStopCopy.title(.stoppedWithoutFinishing, run: r) == "The editor stopped before finishing.")
    }

    @Test func notSignedInStopsTheTurnoverAtItsNote() async throws {
        let (store, dir) = try film(logged: true); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("auth", dir)
        let t = try store.turnOver(noteIDs: [], kind: "assembly", latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        let r = try await ended(store, try start(.assemble, store: store, turnoverID: t.id).id)
        #expect(r.state == .failed && r.reason == .notSignedIn)
        let after = try store.turnover(t.id)
        #expect(after.state == .failed && after.message == "Claude Code isn\u{2019}t signed in.")
        #expect(EditorSetup.signedIn(.claudeCode) == false)
    }

    @Test func aProgramThatQuitsKeepsItsLastErrorLine() async throws {
        let (store, dir) = try film(logged: false); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("crash", dir)
        let r = try await ended(store, try start(.logFootage, store: store).id)
        #expect(r.state == .failed && r.reason == .programQuit && r.detail == "fake-claude: the program fell over at frame 214")
    }

    @Test func pauseInterruptsAndResumeContinuesTheSession() async throws {
        let (store, dir) = try film(logged: false); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("slow", dir)
        let run = try start(.logFootage, store: store)
        _ = try await wait(store, run.id) { $0.state == .working && $0.session != nil }
        EditorRunner.shared.pause(run.id, store: store)
        #expect(try store.run(run.id)?.state == .paused)
        let paused = try await ended(store, run.id)
        #expect(paused.state == .paused && paused.session == "fake-session-1")
        // The director resumes; this time the work gets done.
        _ = try store.logDailies(Dailies(scenes: [], takes: ["take-1": TakeInfo(assetID: "take-1")]))
        try scenario("done", dir)
        EditorRunner.shared.launch(paused, store: store, continuation: EditorJobs.continuation("Continue where you stopped.", job: .logFootage))
        let done = try await wait(store, run.id) { $0.state == .done && !EditorRunner.shared.isLive(run.id) }
        #expect(done.invocations == 2 && done.spend == 0.42)
        let a = args(dir)
        #expect(a.suffix(2) == ["--resume", "fake-session-1"])
        #expect(a[1].hasPrefix("Continue where you stopped."))
    }

    /// The film finds the work itself: Ask me first holds it for Start, a run that ends without
    /// delivering stops the turnover (frame 58), and Take the turnover back returns the notes.
    @Test func aFilmHoldsWorkForStartThenShowsTheStop() async throws {
        // Every take is logged, so the assembly is the only work waiting.
        let (store, dir) = try film(logged: true); defer { try? FileManager.default.removeItem(at: dir) }
        EditorPrograms.shared.setPreview([.claudeCode: EditorInstall(program: .claudeCode, path: Self.fake, version: "2.4.1")],
                                         values: [EditorSetupKey.runsOn: "claudeCode", EditorSetupKey.startWork: "askFirst", EditorSetupKey.signedIn(.claudeCode): true])
        EditorRunner.shared.programOverride = [:]
        try scenario("unfinished", dir)
        var b = Brief(); b.logline = "One sentence."; b.feeling = "Quiet."; try store.saveBrief(b)
        let m = FilmModel()
        m.runtime = try ToolRuntime(store: store)
        defer { m.close() }
        let t = try store.turnOver(noteIDs: [], kind: "assembly", latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        m.refresh(force: true)
        #expect(m.runs.held?.turnoverID == t.id)
        #expect(m.pill == .readyToCut("Ready to cut"))
        #expect(m.primaryAction?.title == "Start the editor")
        m.runs.start(m)
        let run = try #require(m.runs.runs.last)
        let r = try await ended(store, run.id)
        m.refresh(force: true)
        #expect(r.state == .failed && r.reason == .stoppedWithoutFinishing)
        #expect(m.pill == .stopped)
        #expect(m.runs.stopBody(r, film: m) == "It ended without delivering the assembly.")
        #expect(try store.turnover(t.id).state == .failed)
        m.runs.takeTurnoverBack(m)
        #expect(try store.turnover(t.id).state == .cancelled)
        EditorRunner.shared.programOverride = [.claudeCode: Self.fake]
    }

    /// A notes turnover that waits for the OK, in a film whose window finds the work (Direction starts the editor).
    private func readBackFilm(_ store: ProjectStore) throws -> (FilmModel, Turnover, ReviewComment) {
        EditorPrograms.shared.setPreview([.claudeCode: EditorInstall(program: .claudeCode, path: Self.fake, version: "2.4.1")],
                                         values: [EditorSetupKey.runsOn: "claudeCode", EditorSetupKey.signedIn(.claudeCode): true])
        var b = Brief(); b.logline = "One sentence."; b.feeling = "Quiet."; try store.saveBrief(b)
        let note = try store.addComment(text: "The sky is too much.", sequenceID: nil, revision: try store.revision(), extra: NoteFields(kind: .picture))
        let t = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: true, cutID: nil, sequenceID: nil)
        let m = FilmModel()
        m.runtime = try ToolRuntime(store: store)
        return (m, t, note)
    }
    /// The fake has sent its read-back call, the runner has read it, and the fake waits for `.fake-go`.
    private func asked(_ dir: URL, _ store: ProjectStore, _ id: String) async throws {
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Editor/.fake-asked").path), try store.run(id)?.state == .working { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DirectionError("timeout", "The fake program never asked.")
    }
    /// The job text the program was last started with (it runs over several lines).
    private func jobText(_ dir: URL) -> String { args(dir).dropFirst().prefix { !$0.hasPrefix("--") }.joined(separator: "\n") }
    private func go(_ dir: URL) throws { try Data().write(to: dir.appendingPathComponent("Editor/.fake-go")) }
    private func again(_ dir: URL) {
        for name in [".fake-asked", ".fake-go"] { try? FileManager.default.removeItem(at: dir.appendingPathComponent("Editor/\(name)")) }
    }
    private func readBack(_ store: ProjectStore, _ t: Turnover, _ note: ReviewComment, _ plan: String) throws {
        _ = try store.reportTurnover(id: t.id, state: nil, readBack: [ReadBackLine(noteID: note.id, plan: plan, delta: "crop")], progress: nil, phase: nil, percent: nil, message: nil)
    }

    /// Correcting a line of the read-back (frame 24) sends the editor back to rewrite it; it posts the new
    /// read-back and waits for the OK again, and the OK sends it to cut.
    @Test func aCorrectedReadBackGoesBackToTheEditorAndWaitsForTheOKAgain() async throws {
        let (store, dir) = try film(logged: true); defer { try? FileManager.default.removeItem(at: dir) }
        let (m, t, note) = try readBackFilm(store); defer { m.close() }
        try scenario("readback", dir)
        let run = try start(.turnover, store: store, turnoverID: t.id)
        try await asked(dir, store, run.id)
        try readBack(store, t, note, "Reframe to about 1.6\u{00D7}; sky down to a third.")
        try go(dir)
        _ = try await wait(store, run.id) { $0.state == .waitingForYou && !EditorRunner.shared.isLive(run.id) }
        m.refresh(force: true)
        #expect(try store.run(run.id)?.invocations == 1)

        again(dir)
        _ = try store.adjustReadBack(turnoverID: t.id, noteID: note.id, text: "Not that tight. Keep the horizon.")
        m.refresh(force: true)
        try await asked(dir, store, run.id)
        let told = jobText(dir), number = note.number.map(String.init) ?? "–"
        #expect(told.hasPrefix("I corrected your read-back.") && told.contains("For note \(number) I said: \u{201C}Not that tight. Keep the horizon.\u{201D}"), "\(told)")
        #expect(args(dir).suffix(2) == ["--resume", "fake-session-1"])
        try readBack(store, t, note, "Reframe to about 1.25\u{00D7}, horizon kept; sky down to about half.")
        try go(dir)
        _ = try await wait(store, run.id) { $0.state == .waitingForYou && $0.invocations == 2 && !EditorRunner.shared.isLive(run.id) }
        // The rewrite waits for the OK: nothing more goes to the editor until the director acts.
        m.refresh(force: true)
        #expect(!EditorRunner.shared.isLive(run.id))
        #expect(try store.turnover(t.id).state == .readBack && store.run(run.id)?.invocations == 2)

        again(dir)
        try scenario("slow", dir)
        _ = try store.approveReadBack(turnoverID: t.id)
        m.refresh(force: true)
        _ = try await wait(store, run.id) { $0.invocations == 3 && $0.state == .working }
        let cut = jobText(dir)
        #expect(cut.hasPrefix("I approved your read-back. Cut it.") && !cut.contains("I corrected"), "\(cut)")
        EditorRunner.shared.stop(run.id, store: store)
        _ = try await ended(store, run.id)
    }

    /// An OK or an answer given in the seconds before the program exits isn't lost: the run goes on, told both.
    @Test func anAnswerBeforeTheEditorExitsStillContinuesTheRun() async throws {
        let (store, dir) = try film(logged: true); defer { try? FileManager.default.removeItem(at: dir) }
        let (m, t, note) = try readBackFilm(store); defer { m.close() }
        try scenario("readback", dir)
        let run = try start(.turnover, store: store, turnoverID: t.id)
        try await asked(dir, store, run.id)
        try readBack(store, t, note, "Two ways: hold on her, or cut to the window and back.")
        let q = try store.ask(EditorQuestion(id: newID("question"), turnoverID: t.id, kind: "question", noteIDs: [note.id], text: "Hold on her, or cut away?", detail: nil,
                                             choices: [.init(id: "hold", label: "Hold on her"), .init(id: "cut", label: "Cut away")], allowsText: false, answer: nil, createdAt: 0))
        _ = try store.answerQuestion(id: q.id, choiceID: "hold", text: nil)
        _ = try store.approveReadBack(turnoverID: t.id)
        try scenario("slow", dir)
        try go(dir)
        let waited = try await wait(store, run.id) { !$0.state.isActive && !EditorRunner.shared.isLive(run.id) && $0.endedAt != nil }
        #expect(try waited.state == .waitingForYou && store.turnover(t.id).state == .cutting)
        m.refresh(force: true)
        _ = try await wait(store, run.id) { $0.invocations == 2 && $0.state == .working }
        let told = jobText(dir)
        #expect(told.hasPrefix("I approved your read-back. Cut it.") && told.contains("I chose \u{201C}Hold on her\u{201D}."), "\(told)")
        #expect(args(dir).suffix(2) == ["--resume", "fake-session-1"])
        EditorRunner.shared.stop(run.id, store: store)
        _ = try await ended(store, run.id)
    }

    private func pid(_ dir: URL, _ name: String) async throws -> pid_t {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: dir.appendingPathComponent("Editor/\(name)"), encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return pid }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DirectionError("timeout", "The fake program never wrote \(name).")
    }
    private func gone(_ pid: pid_t) async throws -> Bool {
        for _ in 0..<100 { if kill(pid, 0) != 0 { return true }; try await Task.sleep(for: .milliseconds(50)) }
        kill(pid, SIGKILL)
        return false
    }
    private func quick() { EditorRunner.shared.stopSteps = [(SIGINT, 0.3), (SIGTERM, 0.3), (SIGKILL, 0)] }

    /// A job the editor left running in the background stops when it ends, and nothing holds on to
    /// the run afterwards: the process, its pipes and what was read go with it.
    @Test func whatTheEditorLeavesRunningStopsWithIt() async throws {
        let (store, dir) = try film(logged: true); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("straggler", dir)
        let run = try start(.logFootage, store: store)
        weak var live = EditorRunner.shared.liveRun(run.id)
        #expect(live != nil)
        let straggler = try await pid(dir, ".fake-straggler")
        #expect(try await ended(store, run.id).state == .done)
        #expect(try await gone(straggler))
        for _ in 0..<100 where live != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(live == nil)
    }

    /// Stop reaches a program that ignores Ctrl-C and SIGTERM.
    @Test func stopEndsAProgramThatWontListen() async throws {
        quick(); defer { EditorRunner.shared.stopSteps = ChildProcesses.gently }
        let (store, dir) = try film(logged: false); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("stubborn", dir)
        let run = try start(.logFootage, store: store)
        let pid = try await pid(dir, ".fake-pid")
        _ = try await wait(store, run.id) { $0.state == .working }
        EditorRunner.shared.stop(run.id, store: store)
        let r = try await ended(store, run.id)
        #expect(r.state == .stopped && r.reason == .stoppedByYou)
        #expect(try await gone(pid))
    }

    /// Quit goes ahead only once the editor and everything it started are gone, and the run waits
    /// to be resumed.
    @Test func quittingLeavesNothingRunning() async throws {
        quick(); defer { EditorRunner.shared.stopSteps = ChildProcesses.gently }
        let (store, dir) = try film(logged: false); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("stubborn", dir)
        let run = try start(.logFootage, store: store)
        let pid = try await pid(dir, ".fake-pid")
        _ = try await wait(store, run.id) { $0.state == .working }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in EditorRunner.shared.pauseAllForQuit { c.resume() } }
        #expect(try await gone(pid))
        let r = try await ended(store, run.id)
        #expect(r.state == .paused && r.pausedByQuit)
    }

    @Test func stopEndsTheRun() async throws {
        let (store, dir) = try film(logged: false); defer { try? FileManager.default.removeItem(at: dir) }
        try scenario("slow", dir)
        let run = try start(.logFootage, store: store)
        _ = try await wait(store, run.id) { $0.state == .working }
        EditorRunner.shared.stop(run.id, store: store)
        let r = try await ended(store, run.id)
        #expect(r.state == .stopped && r.reason == .stoppedByYou)
    }
}

@Test func codexVersionsAreTheModelsItsOwnMenuLists() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try #"{"models":[{"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","priority":2},{"slug":"gpt-reserve","display_name":"GPT-Reserve","visibility":"hide","priority":3},{"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list","priority":1},{"slug":"gpt-6.1-terra","display_name":"GPT-6.1 Terra","visibility":"list","priority":4}]}"#.write(to: file, atomically: true, encoding: .utf8)
    let models = EditorProgram.codexModels(cache: file)
    #expect(models.map(\.id) == ["gpt-6.1-sol", "gpt-6-astra", "gpt-6.1-terra"])
    #expect(models.map(\.name) == ["GPT-6.1 Sol", "GPT-6 Astra", "GPT-6.1 Terra"])
    // No cache: the list Codex had, never an empty menu.
    #expect(EditorProgram.codexModels(cache: file.appendingPathExtension("missing")).first?.id == "gpt-6.1-sol")
}

@Test func effortsAreWhatEachVersionTakes() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try #"{"models":[{"slug":"gpt-6.1-sol","visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"},{"effort":"xhigh"},{"effort":"max"},{"effort":"ultra"}]},{"slug":"gpt-6-luna","visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"}]}]}"#.write(to: file, atomically: true, encoding: .utf8)
    // The program's default comes first; "ultra" hands work to agents of its own, so it isn't offered.
    #expect(EditorProgram.codex.efforts("gpt-6.1-sol", codexCache: file).map(\.id) == ["", "low", "medium", "high", "xhigh", "max"])
    #expect(EditorProgram.codex.efforts("gpt-6-luna", codexCache: file).map(\.id) == ["", "low", "medium", "high"])
    // A version the cache doesn't list, and every Claude version, take all five.
    #expect(EditorProgram.codex.efforts("gpt-someday", codexCache: file).count == 6)
    #expect(EditorProgram.claudeCode.efforts("claude-fable-5-1").map(\.name) == ["The program\u{2019}s default", "Low", "Medium", "High", "Extra high", "Max"])
}

// MARK: Logging in batches (footage-index.md › Logging in batches)

@MainActor
@Test func loggingStartsSmallThenRunsInTwentiesAndKeepsSyncedTakesTogether() {
    let ids = (1...45).map { "t\($0)" }
    func decide(ready: Int, firstRun: Bool, tries: [String: Int] = [:], partners: [String: [String]] = [:]) -> EditorRunsModel.LogBatch {
        EditorRunsModel.logBatch(unlogged: ids, ready: Set(ids.prefix(ready)), tries: tries, firstRun: firstRun) { partners[$0] ?? [] }
    }
    // The first batch goes at 5 ready takes; nothing before.
    #expect(decide(ready: 4, firstRun: true) == .wait)
    #expect(decide(ready: 6, firstRun: true) == .run(Array(ids.prefix(6))))
    // Later ones wait for 20, and take at most 20, plus the takes in sync with them.
    #expect(decide(ready: 12, firstRun: false) == .wait)
    #expect(decide(ready: 30, firstRun: false, partners: ["t3": ["t25"]]) == .run(Array(ids.prefix(20)) + ["t25"]))
    // The last batch takes whatever is left.
    #expect(EditorRunsModel.logBatch(unlogged: ["a", "b"], ready: ["a", "b"], tries: [:], firstRun: false) { _ in [] } == .run(["a", "b"]))
    // A take two runs left unlogged is skipped; once only those are left, Direction places them itself.
    #expect(EditorRunsModel.logBatch(unlogged: ["a", "b"], ready: ["a", "b"], tries: ["a": 2], firstRun: false) { _ in [] } == .run(["b"]))
    #expect(EditorRunsModel.logBatch(unlogged: ["a"], ready: ["a"], tries: ["a": 2], firstRun: false) { _ in [] } == .unplace(["a"]))
    #expect(EditorRunsModel.logBatch(unlogged: [], ready: [], tries: [:], firstRun: false) { _ in [] } == .wait)
}

@MainActor
@Test func aBatchRunCarriesWhatDirectionFoundAndOnlyItsTakes() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString).direction")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try ProjectStore.create(at: dir, name: "Essay")
    var b = Brief(); b.logline = "An essay on the last invention."; b.feeling = "Calm."
    try store.saveBrief(b)
    let cam = MediaAsset(id: "cam", name: "camera.mp4", path: "/camera.mp4", duration: .init(seconds: 192), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)], audio: [.init(id: 2, index: 0, label: "Audio 1", channels: 2, sampleRate: 48_000)])
    let other = MediaAsset(id: "other", name: "later.mp4", path: "/later.mp4", duration: .init(seconds: 30), video: [.init(id: 1, width: 1920, height: 1080, frameRate: 30)])
    for a in [cam, other] { _ = try store.addAsset(a, append: false, expectedRevision: try store.revision()) }
    try store.replaceShots(assetID: "cam", [Shot(assetID: "cam", number: 1, start: 0, end: 43, look: ShotLook(description: "Close on a man with glasses speaking into a mic.", size: "close", movement: "static", flags: ["soft"]))])
    try store.saveTranscript(SourceTranscript(assetID: "cam", audioTrackID: 2, provider: "test", words: ["Imagine", "being", "a", "scientist."].enumerated().map { i, w in TranscriptWord(text: w, range: .init(start: Double(i) * 0.5, end: Double(i) * 0.5 + 0.4)) }))
    let run = EditorRun(job: .logFootage, program: "codex", version: "", assetIDs: ["cam"])
    let text = try EditorJobs.text(for: run, store: store)
    #expect(!text.contains("{{"))
    #expect(text.contains("This run logs 1 take") && text.contains("1 more come in later runs"))
    #expect(text.contains("### camera.mp4 \u{00B7} cam \u{00B7} 3:12"))
    #expect(text.contains("1. 0:00\u{2013}0:43 \u{00B7} close, static \u{00B7} Close on a man with glasses speaking into a mic. (flags: soft)"))
    #expect(text.contains("Words (4): Imagine being a scientist."))
    #expect(!text.contains("### later.mp4"))
    #expect(!text.contains("On screen:"))
    // A screen recording's text: its gist, largest text first, and where to read the rest.
    let shot = try #require(try store.shots(assetID: "cam").first)
    try store.replaceScreenText(assetID: "cam", [
        ScreenText(assetID: "cam", shotID: shot.id, start: 0, end: 43, lines: ["AI is the last thing humans will ever invent", "Planning"]),
        ScreenText(assetID: "cam", shotID: shot.id, start: 10, end: 20, lines: ["Draft v3"]),
    ])
    let withScreen = try EditorJobs.text(for: run, store: store)
    #expect(withScreen.contains("On screen: AI is the last thing humans will ever invent \u{00B7} Planning \u{00B7} Draft v3 (2 stretches over time: direction_screen_text with assetID)"))
}
