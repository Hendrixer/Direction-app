import Foundation
import DirectionCore

/// What Direction reads from a running program. The editor's prose is never shown; only tool
/// calls, the session, spend and the final message matter.
enum StreamEvent: Equatable {
    case session(String)
    /// `name` is the program's own tool name: `mcp__direction__direction_watch`, `Read`, or Codex's `direction_watch`.
    case toolStarted(id: String, name: String, input: JSONValue)
    case toolFinished(id: String, isError: Bool, text: String)
    /// Dollars for this invocation so far (Claude Code's result event).
    case cost(Double)
    /// Tokens for this invocation (Codex's turn.completed).
    case tokens(Int)
    /// The final message, and whether the program called it an error.
    case result(text: String, isError: Bool)
    /// An error the program reported outside a tool call.
    case failure(String)
}

/// Claude Code's `--output-format stream-json --verbose`: one JSON object per line.
struct ClaudeStreamParser {
    mutating func parse(_ line: String) -> [StreamEvent] {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { return [] }
        var out: [StreamEvent] = []
        switch v["type"].string {
        case "system":
            if v["subtype"].string == "init", let s = v["session_id"].string { out.append(.session(s)) }
        case "assistant":
            for block in v["message"]["content"].array ?? [] where block["type"].string == "tool_use" {
                out.append(.toolStarted(id: block["id"].string ?? UUID().uuidString, name: block["name"].string ?? "", input: block["input"]))
            }
            // An assistant turn the API refused (not signed in, no credit) arrives with an error field.
            if let e = v["error"].string { out.append(.failure(e + " " + Self.text(v["message"]["content"]))) }
        case "user":
            for block in v["message"]["content"].array ?? [] where block["type"].string == "tool_result" {
                out.append(.toolFinished(id: block["tool_use_id"].string ?? "", isError: block["is_error"].bool ?? false, text: Self.text(block["content"])))
            }
        case "result":
            if let s = v["session_id"].string { out.append(.session(s)) }
            if let c = v["total_cost_usd"].double { out.append(.cost(c)) }
            let isError = v["is_error"].bool ?? (v["subtype"].string != "success")
            out.append(.result(text: v["result"].string ?? (v["errors"].array?.compactMap(\.string).joined(separator: " ") ?? ""), isError: isError))
        default: break
        }
        return out
    }

    /// Text from a string or a list of `{type: text, text}` blocks.
    static func text(_ v: JSONValue) -> String {
        if let s = v.string { return s }
        return (v.array ?? []).compactMap { $0["text"].string }.joined(separator: "\n")
    }
}

/// Codex's `exec --json`: thread.started, item.started / item.completed, turn.completed, turn.failed, error.
struct CodexStreamParser {
    private var lastMessage = ""
    mutating func parse(_ line: String) -> [StreamEvent] {
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { return [] }
        var out: [StreamEvent] = []
        let item = v["item"], id = item["id"].string ?? UUID().uuidString
        switch v["type"].string {
        case "thread.started":
            if let s = v["thread_id"].string { out.append(.session(s)) }
        case "item.started":
            if let call = Self.call(item) { out.append(.toolStarted(id: id, name: call.0, input: call.1)) }
        case "item.completed":
            switch item["type"].string {
            case "agent_message": lastMessage = item["text"].string ?? lastMessage
            case "file_change":
                // File changes arrive whole; each counts as a start and an end.
                for change in item["changes"].array ?? [.null] { out.append(.toolStarted(id: id, name: "file_change", input: .object(["path": change["path"]]))) }
                out.append(.toolFinished(id: id, isError: item["status"].string == "failed", text: ""))
            case "mcp_tool_call", "command_execution":
                let failed = item["status"].string == "failed" || item["error"] != .null || (item["exit_code"].int ?? 0) != 0
                let text = item["error"]["message"].string ?? item["error"].string ?? ClaudeStreamParser.text(item["result"]["content"])
                out.append(.toolFinished(id: id, isError: failed, text: text))
            case "error": out.append(.failure(item["message"].string ?? "Codex reported an error."))
            default: break
            }
        case "turn.completed":
            let u = v["usage"]
            out.append(.tokens((u["input_tokens"].int ?? 0) + (u["output_tokens"].int ?? 0)))
            out.append(.result(text: lastMessage, isError: false))
        case "turn.failed":
            out.append(.failure(v["error"]["message"].string ?? "The turn failed."))
        case "error":
            out.append(.failure(v["message"].string ?? "Codex reported an error."))
        default: break
        }
        return out
    }

    /// An MCP tool call or a command, as (tool name, input).
    static func call(_ item: JSONValue) -> (String, JSONValue)? {
        switch item["type"].string {
        case "mcp_tool_call":
            var args = item["arguments"]
            if let s = args.string, let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) { args = parsed }
            let server = item["server"].string ?? "direction"
            return (server == "direction" ? (item["tool"].string ?? "") : "mcp__\(server)__\(item["tool"].string ?? "")", args)
        case "command_execution": return ("command_execution", .object(["command": item["command"]]))
        default: return nil
        }
    }
}

/// The program's final message: `{"finished", "summary", "needsYou"}`, found anywhere in its text.
struct EditorResult: Equatable {
    var finished: Bool
    var summary: String
    var needsYou: [String]
    static func parse(_ text: String) -> EditorResult? {
        // The last {...} in the text that decodes; the program may wrap it in prose or a code fence.
        var candidates: [Substring] = []
        var depth = 0, start: String.Index?
        for i in text.indices {
            if text[i] == "{" { if depth == 0 { start = i }; depth += 1 }
            else if text[i] == "}", depth > 0 { depth -= 1; if depth == 0, let s = start { candidates.append(text[s...i]) } }
        }
        for c in candidates.reversed() {
            guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(c.utf8)), let f = v["finished"].bool else { continue }
            return EditorResult(finished: f, summary: v["summary"].string ?? "", needsYou: v["needsYou"].array?.compactMap(\.string) ?? [])
        }
        return nil
    }
}

/// Reasons from the program's own words (frame 58's table).
enum EditorFailure {
    static func reason(_ text: String) -> EditorRunReason? {
        let t = text.lowercased()
        if isOutOfDate(t) { return .outOfDate }
        let auth = ["not logged in", "please run /login", "run /login", "invalid api key", "authentication_failed", "authentication failed", "authentication_error", "unauthorized", "oauth token", "not signed in", "please log in", "login required", "codex login", "invalid_grant"]
        // 401 only as a status ("API Error: 401", "status 401"), never inside an id or a number.
        if auth.contains(where: t.contains) || t.contains(/(status|error|http|code)[ :=(]{0,3}401\b/) { return .notSignedIn }
        let offline = ["enotfound", "econnrefused", "econnreset", "etimedout", "getaddrinfo", "could not resolve", "connection error", "network error", "network is unreachable", "internet connection", "offline", "stream disconnected", "failed to connect", "unable to connect"]
        if offline.contains(where: t.contains) { return .offline }
        if isSpendCap(t) { return .spendCap }
        return nil
    }
    /// The program refused an option Direction starts it with: Claude Code says "error: unknown option
    /// '--effort'", Codex "error: unexpected argument '--ephemeral' found".
    static func isOutOfDate(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["unknown option '--", "unexpected argument '--", "unrecognized option '--", "unknown option \"--"].contains(where: t.contains)
    }
    /// A service refused because this month's limit is reached (made-media.md › Spending).
    static func isSpendCap(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("spend_cap") || t.contains("monthly_limit") || t.contains("month\u{2019}s limit") || t.contains("month's limit") || t.contains("monthly limit") || t.contains("stop_at")
    }
    /// "$50.00" from the service's message, if it says.
    static func amount(_ text: String) -> String? { text.firstMatch(of: /\$\d+(?:\.\d{2})?/).map { String($0.0) } }
}

/// What a run becomes when its program exits. Pure, so the whole table is testable.
enum RunStateMachine {
    /// Why Direction ended it, if it did.
    /// `restart`: it stopped answering and Direction starts it again on the same session. `stuck`: it did that again.
    enum Intent: Equatable { case none, pause, stop, quit, restart, stuck(String) }

    struct Exit: Equatable {
        var status: Int32 = 0
        var intent: Intent = .none
        /// The job's finishing tool did its work (the store says so, not the program).
        var finished = false
        /// The program ended its turn on purpose: a read-back to OK, a question to answer.
        var waitingForYou = false
        /// Errors the program reported, its result text when it was an error, and stderr's tail.
        var failures: [String] = []
        var spendCap: String?
        var lastErrorLine: String?
        var notInstalled = false
    }

    struct Outcome: Equatable {
        var state: EditorRunState
        var reason: EditorRunReason?
        var detail: String?
    }

    static func outcome(_ e: Exit) -> Outcome {
        if e.notInstalled { return .init(state: .failed, reason: .notInstalled) }
        switch e.intent {
        case .pause: return .init(state: .paused)
        case .quit: return .init(state: .paused, reason: .pausedByQuit)
        case .stop: return .init(state: .stopped, reason: .stoppedByYou)
        case .restart: return .init(state: .paused)
        case .stuck(let step): return .init(state: .failed, reason: .stuck, detail: step)
        case .none: break
        }
        if e.finished { return .init(state: .done) }
        if let cap = e.spendCap { return .init(state: .failed, reason: .spendCap, detail: cap) }
        for f in e.failures { if let r = EditorFailure.reason(f), r != .spendCap { return .init(state: .failed, reason: r, detail: f) } }
        if e.waitingForYou { return .init(state: .waitingForYou) }
        if e.status != 0 { return .init(state: .failed, reason: .programQuit, detail: e.lastErrorLine ?? e.failures.last) }
        return .init(state: .failed, reason: .stoppedWithoutFinishing)
    }
}
