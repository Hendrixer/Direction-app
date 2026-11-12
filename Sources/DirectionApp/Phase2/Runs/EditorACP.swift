import Foundation
import DirectionCore
import DirectionTools

/// One invocation of an agent over the Agent Client Protocol (agentclientprotocol.com, version 1): newline-delimited
/// JSON-RPC 2.0 over stdin and stdout. Direction starts the agent, says hello, opens a session with Direction's
/// tools (or loads the saved one), sends one prompt, and is done when the prompt is answered. Pure, so the whole
/// conversation is testable: `receive` takes a line and returns the events Direction reads and the lines to send.
struct ACPConversation {
    /// Direction's MCP server, as the agent should start it.
    struct Server { var command: String; var args: [String]; var env: [String: String] }

    /// What the agent may do without asking the director (the same as Claude Code's allowed tools): Direction's
    /// tools, reading and searching, and changes inside its own folder. Never commands (its scripts are Direction's,
    /// in direction_run), never the web.
    struct Permissions {
        var folder: URL
    }

    struct Step: Equatable {
        var events: [StreamEvent] = []
        var send: [JSONValue] = []
        var done = false
    }

    let cwd: URL
    let server: Server
    /// What to say: the whole job, or the continuation on a session that loads.
    let prompt: String
    /// The whole job and the continuation, for a saved session the agent can't load.
    let wholeJob: String
    let resume: String?
    let permissions: Permissions

    private(set) var sessionID: String?
    private(set) var done = false
    private var nextID = 1
    private var waiting: [Int: String] = [:]
    /// A loaded session replays what was said before: none of it is this invocation's.
    private var loading = false
    private var message = ""
    private var calls: [String: JSONValue] = [:]
    private var started: Set<String> = []
    private var informed: Set<String> = []
    private var ended: Set<String> = []

    init(cwd: URL, server: Server, prompt: String, wholeJob: String? = nil, resume: String? = nil, permissions: Permissions) {
        self.cwd = cwd; self.server = server; self.prompt = prompt; self.wholeJob = wholeJob ?? prompt; self.resume = resume; self.permissions = permissions
    }

    // MARK: Sending

    mutating func start() -> [JSONValue] {
        [request("initialize", [
            "protocolVersion": .number(1),
            // Direction gives the agent no files or terminal of its own: it reads and writes with its own tools.
            "clientCapabilities": .object(["fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]), "terminal": .bool(false)]),
            "clientInfo": .object(["name": .string("Direction"), "version": .string(Self.appVersion)]),
        ])]
    }

    /// Pause, Stop and Quit: the turn ends, and the agent answers the prompt with `cancelled`.
    func cancel() -> JSONValue? {
        sessionID.map { .object(["jsonrpc": .string("2.0"), "method": .string("session/cancel"), "params": .object(["sessionId": .string($0)])]) }
    }

    private mutating func request(_ method: String, _ params: [String: JSONValue]) -> JSONValue {
        let id = nextID; nextID += 1; waiting[id] = method
        return .object(["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method), "params": .object(params)])
    }

    private var mcpServers: JSONValue {
        if server.command.isEmpty { return .array([]) }
        return .array([.object([
            "name": .string("direction"), "command": .string(server.command),
            "args": .array(server.args.map(JSONValue.string)),
            "env": .array(server.env.sorted { $0.key < $1.key }.map { .object(["name": .string($0.key), "value": .string($0.value)]) }),
        ])])
    }

    private mutating func say(_ text: String) -> JSONValue {
        request("session/prompt", ["sessionId": .string(sessionID ?? ""), "prompt": .array([.object(["type": .string("text"), "text": .string(text)])])])
    }

    // MARK: Receiving

    mutating func receive(_ line: String) -> Step {
        guard !done, let v = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), case .object = v else { return Step() }
        if let method = v["method"].string {
            if v["id"] != .null { return Step(send: [answer(method, id: v["id"], params: v["params"])]) }
            return method == "session/update" && !loading ? Step(events: update(v["params"]["update"])) : Step()
        }
        guard let id = v["id"].int, let method = waiting.removeValue(forKey: id) else { return Step() }
        if v["error"] != .null { return failed(method, v["error"]) }
        let result = v["result"]
        var step = Step()
        switch method {
        case "initialize":
            // Builds from before ACP's version 1 (mid-2025) have no sessions as Direction knows them.
            if let v = result["protocolVersion"].int, v != 1 {
                done = true
                return Step(events: [.failure(Self.oldProtocol + " (version \(v))")], done: true)
            }
            if let resume, result["agentCapabilities"]["loadSession"].bool == true {
                loading = true
                step.send = [request("session/load", ["sessionId": .string(resume), "cwd": .string(cwd.path), "mcpServers": mcpServers])]
            } else {
                step.send = [request("session/new", ["cwd": .string(cwd.path), "mcpServers": mcpServers])]
            }
        case "session/new":
            guard let s = result["sessionId"].string else { return failed(method, .object(["message": .string("The agent opened no session.")])) }
            sessionID = s
            step.events = [.session(s)]
            // A saved session it couldn't load: the whole job again, then the continuation.
            step.send = [say(resume == nil ? prompt : wholeJob)]
        case "session/load":
            loading = false
            sessionID = resume
            step.events = resume.map { [.session($0)] } ?? []
            step.send = [say(prompt)]
        case "session/prompt":
            done = true
            step.done = true
            let stop = result["stopReason"].string ?? "end_turn"
            step.events = [.result(text: message, isError: stop == "refusal")]
            if stop == "refusal" { step.events.append(.failure("The agent refused to continue.")) }
        default: break
        }
        return step
    }

    // MARK: The sign-in check

    struct CheckStep { var send: [JSONValue] = []; var verdict: SignInCheck? }

    /// Hello, then a session with no tools, and no prompt: an agent that opens one is signed in, one that answers
    /// with ACP's auth_required isn't.
    mutating func checkStep(_ line: String) -> CheckStep {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), case .object = v else { return CheckStep() }
        if let method = v["method"].string { return v["id"] != .null ? CheckStep(send: [answer(method, id: v["id"], params: v["params"])]) : CheckStep() }
        guard let id = v["id"].int, let method = waiting.removeValue(forKey: id) else { return CheckStep() }
        if v["error"] != .null {
            let step = failed(method, v["error"])
            let text = step.events.compactMap { if case .failure(let t) = $0 { t } else { nil } }.first ?? "The agent reported an error."
            return CheckStep(verdict: text.hasPrefix("Not signed in") || EditorFailure.reason(text) == .notSignedIn ? .notSignedIn(String(text.prefix(200))) : .couldNotCheck(String(text.prefix(200))))
        }
        switch method {
        case "initialize": return CheckStep(send: [request("session/new", ["cwd": .string(cwd.path), "mcpServers": mcpServers])])
        case "session/new": return CheckStep(verdict: .signedIn)
        default: return CheckStep()
        }
    }

    /// An error answer: a session that won't load starts a new one; anything else ends the invocation.
    private mutating func failed(_ method: String, _ error: JSONValue) -> Step {
        if method == "session/load" {
            loading = false
            return Step(send: [request("session/new", ["cwd": .string(cwd.path), "mcpServers": mcpServers])])
        }
        done = true
        var text = error["message"].string ?? "The agent reported an error."
        if let data = error["data"]["message"].string ?? error["data"].string { text += " " + data }
        // A copy that doesn't know sessions speaks an older protocol; ACP's "auth_required" (-32000), or the agent's own
        // words for it, means it isn't signed in.
        if method == "session/new", error["code"].int == -32601 { text = Self.oldProtocol }
        else if error["code"].int == -32000 || EditorFailure.reason(text) == .notSignedIn || text.lowercased().contains("authentication required") { text = "Not signed in: " + text }
        return Step(events: [.failure(text)], done: true)
    }

    /// Read by EditorFailure as out of date, so the stop shows the agent's update command.
    static let oldProtocol = "This copy speaks an older agent client protocol than Direction does"

    /// The agent's own requests. Only permission is answered; Direction offers no files or terminal.
    private mutating func answer(_ method: String, id: JSONValue, params: JSONValue) -> JSONValue {
        guard method == "session/request_permission" else {
            return .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(-32601), "message": .string("Direction doesn\u{2019}t offer \(method).")])])
        }
        let callID = params["toolCall"]["toolCallId"].string ?? ""
        let call = merged(calls[callID] ?? .object([:]), params["toolCall"])
        calls[callID] = call
        let options = params["options"].array ?? []
        let allowed = allows(call)
        let kinds = allowed ? ["allow_once", "allow_always"] : ["reject_once", "reject_always"]
        let choice = kinds.lazy.compactMap { k in options.first { $0["kind"].string == k }?["optionId"].string }.first
        let outcome: JSONValue = choice.map { .object(["outcome": .string("selected"), "optionId": .string($0)]) } ?? .object(["outcome": .string("cancelled")])
        if !allowed { DirectionLog.info("Refused the agent's request to \(Self.name(call)) (\(call["kind"].string ?? "other"))", "editor") }
        return .object(["jsonrpc": .string("2.0"), "id": id, "result": .object(["outcome": outcome])])
    }

    /// What the step does decides first, so a command or a fetch that mentions a Direction tool is still a command.
    func allows(_ call: JSONValue) -> Bool {
        switch call["kind"].string ?? "other" {
        case "execute", "fetch", "switch_mode": return false
        case "edit", "delete", "move":
            // Every path it names, a move's destination too; none named, no telling where it writes.
            let paths = Self.paths(call)
            return !paths.isEmpty && paths.allSatisfy(writable)
        case "read", "think": return true
        // A web search is a search too.
        case "search": return !Self.looksLikeWeb(call)
        // Anything else is only Direction's own tools: not the director's other MCP servers, which Gemini CLI loads
        // (Claude Code runs with --strict-mcp-config and Codex with --ignore-user-config).
        default: return Self.isDirectionTool(call)
        }
    }

    /// Inside the job's folder, symlinks and `~` resolved, and not any agent's own settings.
    func writable(_ path: String) -> Bool {
        let root = Self.resolved(permissions.folder)
        let expanded = (path as NSString).expandingTildeInPath
        let full = Self.resolved(expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : permissions.folder.appendingPathComponent(expanded))
        guard full == root || full.hasPrefix(root + "/") else { return false }
        let first = full == root ? "" : String(full.dropFirst(root.count + 1).split(separator: "/").first ?? "")
        return !Self.agentSettings.contains(first)
    }

    /// The files and folders agents read their settings from, where a hook or an MCP server's command would run as the
    /// director the next time one starts. Direction moves any it finds out of the film (EditorJobs.prepareFolder), and
    /// no agent may write one.
    static let agentSettings: Set<String> = [".claude", ".codex", ".gemini", ".env", ".mcp.json", ".direction"]

    /// The real path, symlinks resolved; a file that doesn't exist yet by its folder's real path.
    static func resolved(_ url: URL) -> String {
        let u = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: u.path) { return u.resolvingSymlinksInPath().path }
        return u.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(u.lastPathComponent).path
    }

    static func looksLikeWeb(_ call: JSONValue) -> Bool {
        let said = ([call["title"].string, call["name"].string].compactMap { $0 } + [(try? JSONEncoder().encode(call["rawInput"])).map { String(decoding: $0, as: UTF8.self) } ?? ""]).joined(separator: " ").lowercased()
        return ["web", "http", "url", "google", "internet", "online", "browse"].contains(where: said.contains)
    }

    /// One of Direction's tools by its exact name, however the agent prefixes it.
    static func isDirectionTool(_ call: JSONValue) -> Bool {
        let n = name(call)
        return n.hasPrefix("mcp__direction__") && directionTools.contains(String(n.dropFirst("mcp__direction__".count)))
    }
    static let directionTools: Set<String> = Set(ToolCatalog.definitions.map(\.name))

    // MARK: Updates

    private mutating func update(_ u: JSONValue) -> [StreamEvent] {
        switch u["sessionUpdate"].string {
        case "agent_message_chunk":
            if let t = u["content"]["text"].string { message += t; if message.count > 200_000 { message = String(message.suffix(100_000)) } }
            return []
        case "tool_call", "tool_call_update":
            guard let id = u["toolCallId"].string else { return [] }
            let call = merged(calls[id] ?? .object([:]), u)
            calls[id] = call
            var out: [StreamEvent] = []
            let status = call["status"].string ?? "pending"
            // Started once the agent says what it's doing: an input that says something, or work under way. Agents
            // announce a call with an empty input and fill it in later.
            let hasInput = Self.says(call["rawInput"])
            if !started.contains(id), hasInput || status != "pending" {
                started.insert(id)
                if hasInput { informed.insert(id) }
                out.append(.toolStarted(id: id, name: Self.name(call), input: Self.input(call)))
            } else if started.contains(id), hasInput, !informed.contains(id), Self.isDirectionTool(call) {
                // Its input came after it started: Direction's own tools again, so a read-back or a question posted
                // this way is still seen (handling a Direction tool's start twice changes nothing else).
                informed.insert(id)
                out.append(.toolStarted(id: id, name: Self.name(call), input: Self.input(call)))
            }
            if status == "completed" || status == "failed", !ended.contains(id) {
                ended.insert(id)
                out.append(.toolFinished(id: id, isError: status == "failed", text: Self.output(call)))
            }
            return out
        case "usage_update":
            // The session's running cost, when the agent knows it.
            return u["cost"]["amount"].double.map { [.cost($0)] } ?? []
        default:
            return []
        }
    }

    /// The fields an update brings, over what was known.
    private func merged(_ old: JSONValue, _ new: JSONValue) -> JSONValue {
        guard case .object(var o) = old, case .object(let n) = new else { return new }
        for (k, v) in n where v != .null { o[k] = v }
        return .object(o)
    }

    // MARK: Names

    /// Direction's tools as Claude Code names them (`mcp__direction__direction_watch`), whatever the agent calls
    /// them ("direction_direction_watch", "direction__direction_watch", "direction_watch (direction MCP Server)");
    /// the agent's own tools by what they do, as Claude Code's are named.
    static func name(_ call: JSONValue) -> String {
        let said = [call["name"].string, call["title"].string, call["rawInput"]["tool"].string].compactMap { $0 }.joined(separator: " ")
        if let m = said.firstMatch(of: /direction_[a-z][a-z_]*/) {
            var tool = String(m.0)
            while tool.hasPrefix("direction_direction_") { tool.removeFirst("direction_".count) }
            return "mcp__direction__" + tool
        }
        switch call["kind"].string {
        case "read": return "Read"
        case "edit", "delete", "move": return "Edit"
        case "search": return "Grep"
        case "execute": return "Bash"
        case "fetch": return "WebFetch"
        default: return call["title"].string ?? call["kind"].string ?? "tool"
        }
    }

    /// An input with something in it: not null, `{}` or `[]`.
    static func says(_ v: JSONValue) -> Bool {
        switch v {
        case .null: false
        case .object(let o): !o.isEmpty
        case .array(let a): !a.isEmpty
        case .string(let s): !s.isEmpty
        default: true
        }
    }

    /// The tool's input, with the file it touches as `path` when only its locations say.
    static func input(_ call: JSONValue) -> JSONValue {
        var input = call["rawInput"]
        if case .null = input { input = .object([:]) }
        guard case .object(var o) = input else { return input }
        if o["path"] == nil, o["file_path"] == nil, let p = paths(call).first { o["path"] = .string(p) }
        return .object(o)
    }

    /// Every path the step names: its locations and its input's, a move's source and destination included.
    static func paths(_ call: JSONValue) -> [String] {
        let located = (call["locations"].array ?? []).compactMap { $0["path"].string }
        let raw = call["rawInput"]
        let named = ["path", "file_path", "filePath", "destination", "dest", "newPath", "new_path", "target", "to", "source", "from", "oldPath", "old_path"].compactMap { raw[$0].string }
        return Array(Set(located + named)).sorted()
    }

    /// What the tool returned, as text: its content blocks, or its raw output.
    static func output(_ call: JSONValue) -> String {
        let blocks = (call["content"].array ?? []).compactMap { c -> String? in c["content"]["text"].string ?? c["text"].string }
        if !blocks.isEmpty { return blocks.joined(separator: "\n") }
        if let s = call["rawOutput"].string { return s }
        if call["rawOutput"] != .null, let d = try? JSONEncoder().encode(call["rawOutput"]) { return String(decoding: d, as: UTF8.self) }
        return ""
    }

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    /// One line on the wire.
    static func line(_ v: JSONValue) -> Data {
        var d = (try? JSONEncoder().encode(v)) ?? Data("{}".utf8)
        d.append(0x0A)
        return d
    }
}
