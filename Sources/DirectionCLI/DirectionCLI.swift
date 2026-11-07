import Foundation
import ArgumentParser
import DirectionCore
import DirectionMedia
import DirectionTools
import DirectionReports

@main
struct DirectionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "direction", abstract: "Native, local video editing and contextual review for agents.", version: "0.2.0", subcommands: [Create.self, Inspect.self, Import.self, Cut.self, Comment.self, Feedback.self, Audio.self, Transcribe.self, Transcript.self, Export.self, Frame.self, Call.self, Tools.self, API.self, MCP.self, KeyCommand.self, Reap.self])
}

struct ProjectOptions: ParsableArguments {
    @Option(help: "Path to a .direction project package.") var project: String
    func runtime() throws -> ToolRuntime { try ToolRuntime(store: ProjectStore(url: URL(fileURLWithPath: NSString(string: project).expandingTildeInPath))) }
}

func emit<T: Encodable>(_ value: T) throws {
    let data = try JSONValue.wrapping(value).data(pretty: true)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

func execute(_ runtime: ToolRuntime, _ name: String, _ arguments: [String: JSONValue]) async throws {
    let result = try await runtime.invoke(name, arguments: .object(arguments))
    if let job = try? result.value.decode(JobRecord.self) { let completed = try await runtime.waitForJob(job.id); try emit(completed.result ?? .null) }
    else { try emit(result.value) }
}

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a new local project.")
    @Argument var path: String
    @Option var name: String = "Untitled project"
    func run() async throws { let store = try ProjectStore.create(at: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath), name: name); try ProjectLibrary().register(store); try emit(store.read()) }
}

struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Inspect sources, audio tracks, clips, and revision.")
    @OptionGroup var options: ProjectOptions
    @Option var revision: Int?
    @Option var sequenceID: String?
    func run() async throws { var a: [String: JSONValue] = [:]; if let revision { a["revision"] = .number(Double(revision)) }; if let sequenceID { a["sequenceID"] = .string(sequenceID) }; try await execute(options.runtime(), "direction_inspect", a) }
}

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Import a source; optionally append it to the sequence.")
    @OptionGroup var options: ProjectOptions
    @Argument var path: String
    @Flag var append: Bool = false
    func run() async throws { try await execute(options.runtime(), "direction_import", ["path": .string(path), "append": .bool(append)]) }
}

struct Cut: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Ripple-remove a range in sequence seconds.")
    @OptionGroup var options: ProjectOptions
    @Option var start: Double
    @Option var end: Double
    @Option var baseRevision: Int?
    @Option var sequenceID: String?
    @Option var key: String?
    func run() async throws {
        let runtime = try options.runtime()
        let op: JSONValue = .object(["op": .string("removeRange"), "range": .object(["start": .number(start), "end": .number(end)]), "ripple": .bool(true)])
        var a: [String: JSONValue] = ["baseEditRevision": .number(Double(try baseRevision ?? runtime.store.revision())), "summary": .string("Removed \(start)\u{2013}\(end)"), "operations": .array([op])]
        if let sequenceID { a["sequenceID"] = .string(sequenceID) }; if let key { a["idempotencyKey"] = .string(key) }
        try await execute(runtime, "direction_edit", a)
    }
}

struct Comment: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add feedback to the current or a historical cut.")
    @OptionGroup var options: ProjectOptions
    @Option var text: String
    @Option var author: String = "Director"
    @Option var start: Double?
    @Option var end: Double?
    @Option var time: Double?
    @Option var revision: Int?
    @Option var sequenceID: String?
    func run() async throws {
        var a: [String: JSONValue] = ["text": .string(text), "author": .string(author)]
        if let start { a["start"] = .number(start) }; if let end { a["end"] = .number(end) }; if let time { a["time"] = .number(time) }; if let revision { a["revision"] = .number(Double(revision)) }; if let sequenceID { a["sequenceID"] = .string(sequenceID) }
        try await execute(options.runtime(), "direction_add_comment", a)
    }
}

struct Feedback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read feedback; use --context ID for frames, audio, and source anchors.")
    @OptionGroup var options: ProjectOptions
    @Option var since: Int = 0
    @Option var context: String?
    @Flag var textOnly = false
    func run() async throws {
        if let context { try await execute(options.runtime(), "direction_feedback_context", ["commentID": .string(context), "includeMedia": .bool(!textOnly)]) }
        else { try await execute(options.runtime(), "direction_feedback", ["since": .number(Double(since))]) }
    }
}

struct Audio: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Mute/unmute or change gain on an embedded audio stream.")
    @OptionGroup var options: ProjectOptions
    @Argument var assetID: String
    @Option var track: Int
    @Option var muted: Bool?
    @Option var gain: Double?
    @Option var clipID: String?
    @Option var baseRevision: Int?
    func run() async throws {
        let runtime = try options.runtime()
        var changes: [String: JSONValue] = [:]
        if let muted { changes["muted"] = .bool(muted) }; if let gain { changes["gainDB"] = .number(gain) }
        var op: [String: JSONValue] = ["op": .string("audio"), "assetID": .string(assetID), "audioTrackID": .number(Double(track)), "audio": .object(changes)]
        if let clipID { op["clipID"] = .string(clipID) }
        try await execute(runtime, "direction_edit", ["baseEditRevision": .number(Double(try baseRevision ?? runtime.store.revision())), "summary": .string("Changed a sound track"), "operations": .array([.object(op)])])
    }
}

struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Transcribe a source audio track locally on this Mac.")
    @OptionGroup var options: ProjectOptions
    @Argument var assetID: String
    @Option var track: Int?
    @Option var language: String = "en-US"
    func run() async throws { var a: [String: JSONValue] = ["assetID": .string(assetID), "language": .string(language)]; if let track { a["trackID"] = .number(Double(track)) }; try await execute(options.runtime(), "direction_transcribe", a) }
}

struct Transcript: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read timed transcript words for the edited sequence.")
    @OptionGroup var options: ProjectOptions
    @Option var offset: Int = 0
    @Option var limit: Int = 1_000
    func run() async throws { try await execute(options.runtime(), "direction_transcript", ["offset": .number(Double(offset)), "limit": .number(Double(limit))]) }
}

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Export a pinned edit using native codecs; waits for completion.")
    @OptionGroup var options: ProjectOptions
    @Argument var path: String
    @Option var preset: String = "h264"
    @Option var revision: Int?
    @Option var sequenceID: String?
    func run() async throws { var a: [String: JSONValue] = ["path": .string(path), "preset": .string(preset)]; if let revision { a["revision"] = .number(Double(revision)) }; if let sequenceID { a["sequenceID"] = .string(sequenceID) }; try await execute(options.runtime(), "direction_export", a) }
}

struct Frame: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Sample an actual edited frame; outputs PNG path and context.")
    @OptionGroup var options: ProjectOptions
    @Option var time: Double = 0
    @Option var revision: Int?
    func run() async throws { var a: [String: JSONValue] = ["time": .number(time)]; if let revision { a["revision"] = .number(Double(revision)) }; try await execute(options.runtime(), "direction_frame", a) }
}

struct OptionalProjectOptions: ParsableArguments {
    @Option(help: "Optional default .direction project path; otherwise pass projectPath on each tool call.") var project: String?
    func router() throws -> ProjectRouter {
        let runtime = try project.map { try ToolRuntime(store: ProjectStore(url: URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath))) }
        return try ProjectRouter(runtime: runtime)
    }
}

struct Call: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Call any shared tool with JSON arguments; waits for jobs.")
    @OptionGroup var options: OptionalProjectOptions
    @Argument var tool: String
    @Option var json: String?
    @Option var file: String?
    func run() async throws {
        guard json == nil || file == nil else { throw ValidationError("Use --json or --file.") }
        let data = try file.map { try Data(contentsOf: URL(fileURLWithPath: $0)) } ?? Data((json ?? "{}").utf8)
        let args = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let object) = args else { throw ValidationError("Arguments must be a JSON object.") }
        let router = try options.router()
        let result = try await router.invoke(tool, arguments: .object(object))
        if let job = try? result.value.decode(JobRecord.self) {
            var args: [String: JSONValue] = ["jobID": .string(job.id)]
            if let path = object["projectPath"] { args["projectPath"] = path }
            while true {
                let current = try await router.invoke("direction_job", arguments: .object(args))
                let state = try current.value.decode(JobRecord.self)
                if state.isTerminal {
                    guard state.status == "completed" else { throw DirectionError("job_failed", state.error ?? "Job did not complete.") }
                    try emit(state.result ?? .null); break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        } else { try emit(result.value) }
    }
}

struct Tools: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print tool schemas; no project required.")
    func run() async throws { try emit(ToolCatalog.definitions) }
}

struct API: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "api", abstract: "Serve newline-delimited local JSON requests on stdin/stdout. Request: {id,method,params}.")
    @OptionGroup var options: OptionalProjectOptions
    func run() async throws {
        stopsItsProgramsWhenStopped()
        let runtime = try options.router()
        while let line = readLine() {
            var id: JSONValue = .null
            let output: JSONValue
            do {
                guard line.utf8.count <= 16_000_000 else { throw DirectionError("request_too_large", "Request exceeds 16 MB.") }
                let request = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)); id = request["id"]
                let result = try await runtime.invoke(request.requiredString("method"), arguments: request["params"] == .null ? .object([:]) : request["params"])
                output = .object(["id": id, "result": result.value])
            } catch { let e = error as? DirectionError ?? DirectionError("operation_failed", error.localizedDescription); output = .object(["id": id, "error": try .wrapping(e)]) }
            FileHandle.standardOutput.write(try output.data() + Data("\n".utf8))
        }
        await runtime.cancelAll()
        ChildProcesses.stopAll()
    }
}

struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "mcp", abstract: "Serve the official MCP stdio transport for an external agent.")
    @OptionGroup var options: OptionalProjectOptions
    @Option(help: "The job Direction started the editor for (assemble, turnover, finish…): only its tools are listed, with direction_more_tools for the rest.") var job: String?
    func run() async throws {
        let job = try job.map { name in
            guard let job = EditorJob(rawValue: name) else { throw ValidationError("Unknown job \(name): use one of \(EditorJob.allCases.map(\.rawValue).joined(separator: ", ")).") }
            return job
        }
        stopsItsProgramsWhenStopped()
        // Crash reports, when the person turned them on: the editor's tools run here.
        Reports.startIfAllowed(process: "helper")
        DirectionMCPServer.onStuck = { name, minutes in Reports.stuck("Tool \(name)", minutes: minutes, tags: ["tool": name]) }
        try await DirectionMCPServer.run(router: options.router(), job: job)
        ChildProcesses.stopAll()
    }
}

/// Stopping this helper (the editor's group is stopped, or Ctrl-C) stops what it started first:
/// Whisper and the vision helper run in groups of their own and would otherwise carry on.
func stopsItsProgramsWhenStopped() {
    signal(SIGPIPE, SIG_IGN)
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { ChildProcesses.stopAll(); exit(128 + sig) }
        source.resume()
        stoppers.append(source)
    }
}
nonisolated(unsafe) private var stoppers: [DispatchSourceSignal] = []

struct Reap: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reap", abstract: "Direction starts this with a pipe: when the pipe closes, the programs it listed are stopped.", shouldDisplay: false)
    func run() throws {
        // Its own Ctrl-C, or a signal meant for Direction's programs, isn't a reason to leave them running.
        signal(SIGINT, SIG_IGN); signal(SIGHUP, SIG_IGN)
        Reaper.serve(.standardInput)
    }
}
