import Foundation
import DirectionCore

/// One invocation of an agent over the Agent Client Protocol (agentclientprotocol.com, version 1): newline-delimited
/// JSON-RPC 2.0 over stdin and stdout. Direction starts the agent, says hello, opens a session with Direction's
/// tools (or loads the saved one), sends one prompt, and is done when the prompt is answered. Pure, so the whole
/// conversation is testable: `receive` takes a line and returns the events Direction reads and the lines to send.
struct ACPConversation {
    /// Direction's MCP server, as the agent should start it.
    struct Server { var command: String; var args: [String]; var env: [String: String] }

    /// What the agent may do without asking the director (the same as Claude Code's allowed tools): Direction's
    /// tools, reading and searching, and changes inside its own folder. Commands only while scripts are on;
    /// never the web.
    struct Permissions {
        var folder: URL
        var scripts: Bool
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
        // ACP's "auth_required" (-32000): the agent isn't signed in.
        if error["code"].int == -32000 || text.lowercased().contains("auth") { text = "Not signed in: " + text }
        return Step(events: [.failure(text)], done: true)
    }

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

    func allows(_ call: JSONValue) -> Bool {
        if Self.name(call).hasPrefix("mcp__direction__") { return true }
        switch call["kind"].string ?? "other" {
        case "execute": return permissions.scripts
        case "fetch": return false
        case "edit", "delete", "move":
            let root = permissions.folder.standardizedFileURL.path
            return Self.paths(call).allSatisfy { p in
                let full = (p.hasPrefix("/") ? URL(fileURLWithPath: p) : permissions.folder.appendingPathComponent(p)).standardizedFileURL.path
                return full == root || full.hasPrefix(root + "/")
            }
        default: return true
        }
    }

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
            // Started once the agent says what it's doing: an input, or work under way.
            if !started.contains(id), call["rawInput"] != .null || status != "pending" {
                started.insert(id)
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

    /// The tool's input, with the file it touches as `path` when only its locations say.
    static func input(_ call: JSONValue) -> JSONValue {
        var input = call["rawInput"]
        if case .null = input { input = .object([:]) }
        guard case .object(var o) = input else { return input }
        if o["path"] == nil, o["file_path"] == nil, let p = paths(call).first { o["path"] = .string(p) }
        return .object(o)
    }

    static func paths(_ call: JSONValue) -> [String] {
        let located = (call["locations"].array ?? []).compactMap { $0["path"].string }
        if !located.isEmpty { return located }
        let raw = call["rawInput"]
        return [raw["path"].string, raw["file_path"].string, raw["filePath"].string].compactMap { $0 }
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
