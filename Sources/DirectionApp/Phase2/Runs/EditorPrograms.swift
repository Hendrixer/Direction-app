import Foundation
import DirectionCore

/// The programs Direction starts as the editor, and every command line it runs them with
/// (specs/editor.md › Programs, How Direction runs a job). Programs change: every flag lives in
/// this file, and EditorProgramTests runs `--help` and fails when one disappears.
enum EditorProgram: String, CaseIterable, Codable, Sendable {
    case claudeCode, codex

    var name: String { self == .claudeCode ? "Claude Code" : "Codex" }
    var command: String { self == .claudeCode ? "claude" : "codex" }
    var installCommand: String { self == .claudeCode ? "curl -fsSL https://claude.ai/install.sh | bash" : "npm install -g @openai/codex" }
    /// Brings the copy at `path` up to date: Claude Code updates itself; Codex the way it was installed.
    func updateCommand(path: String?) -> String {
        if self == .claudeCode { return "claude update" }
        return path.map { $0.hasPrefix("/opt/homebrew/") || $0.hasPrefix("/usr/local/Cellar/") } == true ? "brew upgrade codex" : "npm install -g @openai/codex@latest"
    }

    /// Versions offered in Settings › Engines; "Other…" takes any string the program accepts. Codex's
    /// are the ones its own model menu lists, read from its cache, so they follow the installed Codex.
    var versions: [(id: String, name: String)] {
        switch self {
        case .claudeCode: [("claude-opus-5-5", "Claude Opus 5.5"), ("claude-fable-5-1", "Claude Fable 5.1"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"), ("claude-haiku-5-5", "Claude Haiku 5.5")]
        case .codex: [("", "The program\u{2019}s default")] + Self.codexModels()
        }
    }

    /// Codex's own cache of its model menu.
    static let codexCache = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/models_cache.json")
    private struct CodexCache: Decodable {
        struct Level: Decodable { var effort: String }
        struct Model: Decodable { var slug: String; var display_name: String?; var visibility: String?; var priority: Int?; var supported_reasoning_levels: [Level]? }
        var models: [Model]
        static func read(_ url: URL) -> Self? { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } }
    }

    /// Codex's model menu: `~/.codex/models_cache.json`, listed models by priority, named the way
    /// its menu names them ("GPT-6.1-Sol" → "GPT-6.1 Sol"). Without the cache, the list it had on 2026-10-29.
    static func codexModels(cache: URL = codexCache) -> [(id: String, name: String)] {
        func name(_ display: String) -> String {
            let parts = display.split(separator: "-", maxSplits: 2).map(String.init)
            return parts.count == 3 ? "\(parts[0])-\(parts[1]) \(parts[2])" : display
        }
        if let c = CodexCache.read(cache) {
            let listed = c.models.filter { ($0.visibility ?? "list") == "list" }.sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
            if !listed.isEmpty { return listed.map { ($0.slug, name($0.display_name ?? $0.slug)) } }
        }
        return [("gpt-6.1-sol", "GPT-6.1 Sol"), ("gpt-6-astra", "GPT-6 Astra"), ("gpt-6.1-terra", "GPT-6.1 Terra"), ("gpt-6-sol", "GPT-6 Sol"), ("gpt-6-luna", "GPT-6 Luna"), ("gpt-5.6-sol", "GPT-5.6 Sol"), ("gpt-5.6-terra", "GPT-5.6 Terra"), ("gpt-5.6-luna", "GPT-5.6 Luna")]
    }
    var defaultVersion: String { versions[0].id }
    func versionName(_ id: String) -> String { versions.first { $0.id == id }?.name ?? id }

    /// How hard the editor thinks before each step, in Settings › Engines. "" leaves it to the program (Codex's
    /// GPT-6.1 Sol and Terra default to low). Every Claude version takes all five; each Codex version lists its
    /// own in Codex's cache.
    func efforts(_ version: String, codexCache: URL = Self.codexCache) -> [(id: String, name: String)] {
        var levels = Self.efforts
        if self == .codex, !version.isEmpty, let model = CodexCache.read(codexCache)?.models.first(where: { $0.slug == version }), let listed = model.supported_reasoning_levels {
            // "ultra" hands work to agents of its own; Direction runs one editor at a time and follows what it does.
            levels = listed.map(\.effort).filter { $0 != "ultra" }
        }
        return [("", "The program\u{2019}s default")] + levels.map { ($0, Self.effortName($0)) }
    }
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
    /// "Extra high"; a Codex level Direction doesn't know is capitalized.
    static func effortName(_ id: String) -> String {
        ["low": "Low", "medium": "Medium", "high": "High", "xhigh": "Extra high", "max": "Max"][id] ?? id.capitalized
    }

    /// Folders searched before asking a login shell.
    static var searchFolders: [String] {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin"]
    }

    // MARK: Flags (checked against `--help` by EditorProgramTests)

    static let claudeFlags = ["--print", "--output-format", "--verbose", "--model", "--effort", "--mcp-config", "--strict-mcp-config", "--allowedTools", "--disallowedTools", "--append-system-prompt", "--resume", "--permission-mode", "--settings", "--tools", "--no-session-persistence"]
    static let codexExecFlags = ["--json", "--model", "--cd", "--sandbox", "--config", "--output-schema", "--skip-git-repo-check", "--ignore-user-config", "--ephemeral"]
    static let codexResumeFlags = ["--json", "--model", "--config", "--output-schema", "--skip-git-repo-check", "--ignore-user-config"]

    /// What one invocation needs to know.
    struct Invocation {
        var job: String
        var role: String
        var version: String
        /// "" leaves it to the program.
        var effort: String = ""
        var session: String?
        var folder: URL
        var mcpConfig: URL
        var schema: URL
        var helper: String
        var film: URL
        var runID: String
        var scripts: Bool
    }

    /// The arguments after the program's path.
    func arguments(_ i: Invocation) -> [String] {
        switch self {
        case .claudeCode:
            // The prompt goes right after --print: --allowedTools and --mcp-config take lists.
            var args = ["--print", i.job, "--output-format", "stream-json", "--verbose"]
            if !i.version.isEmpty { args += ["--model", i.version] }
            if !i.effort.isEmpty { args += ["--effort", i.effort] }
            args += ["--mcp-config", i.mcpConfig.path, "--strict-mcp-config"]
            // Every Direction tool, file read and write inside the working folder, and scripts when allowed.
            var allowed = ["mcp__direction", "Read", "Glob", "Grep", "Edit(./**)", "Write(./**)"]
            if i.scripts { allowed.append("Bash") }
            args += ["--allowedTools", allowed.joined(separator: ","), "--append-system-prompt", i.role, "--permission-mode", "dontAsk"]
            // Its own settings stay Direction's: a hook written there would run outside the sandbox next time.
            args += ["--disallowedTools", "Edit(./.claude/**),Write(./.claude/**),Edit(./.codex/**),Write(./.codex/**)"]
            // Scripts run in Claude Code's sandbox: this folder only, no network.
            if i.scripts { args += ["--settings", #"{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":true,"allowUnsandboxedCommands":false}}"#] }
            if let s = i.session { args += ["--resume", s] }
            return args
        case .codex:
            let toml = { (s: String) in "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            // Scripts off: read-only is Codex's only way to keep commands from running.
            let sandbox = i.scripts ? "workspace-write" : "read-only"
            // --ignore-user-config: only Direction's tools, not the director's other MCP servers (auth still works).
            var shared = ["--json", "--skip-git-repo-check", "--ignore-user-config"]
            if !i.version.isEmpty { shared += ["--model", i.version] }
            if !i.effort.isEmpty { shared += ["--config", "model_reasoning_effort=\(toml(i.effort))"] }
            shared += [
                "--config", "mcp_servers.direction.command=\(toml(i.helper))",
                "--config", "mcp_servers.direction.args=[\(toml("mcp")),\(toml("--project")),\(toml(i.film.path))]",
                "--config", "mcp_servers.direction.env.DIRECTION_RUN_ID=\(toml(i.runID))",
                // Codex strips a tool's field descriptions, then its nested shapes, past 5,000 bytes of schema; direction_edit's is bigger.
                "--config", "mcp_servers.direction.tool_input_schema_max_bytes=32768",
                "--config", "sandbox_workspace_write.network_access=false",
                "--config", "approval_policy=\"never\"",
                "--output-schema", i.schema.path,
            ]
            if let s = i.session { return ["exec", "resume"] + shared + ["--config", "sandbox_mode=\(toml(sandbox))", s, i.job] }
            return ["exec"] + shared + ["--cd", i.folder.path, "--sandbox", sandbox, i.job]
        }
    }

    /// The signed-in check: a job that only replies `ready`, with no tools.
    func readyArguments(version: String) -> [String] {
        let prompt = "Reply with the single word ready and nothing else."
        switch self {
        case .claudeCode:
            var args = ["--print", prompt, "--output-format", "json", "--tools", "", "--strict-mcp-config", "--no-session-persistence"]
            if !version.isEmpty { args += ["--model", version] }
            return args
        case .codex:
            var args = ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "--ephemeral"]
            if !version.isEmpty { args += ["--model", version] }
            return args + [prompt]
        }
    }

    /// The Claude Code MCP config for one run: only Direction, pointed at this film.
    static func mcpConfig(helper: String, film: URL, runID: String) -> JSONValue {
        .object(["mcpServers": .object(["direction": .object([
            "type": .string("stdio"), "command": .string(helper),
            "args": .array([.string("mcp"), .string("--project"), .string(film.path)]),
            "env": .object(["DIRECTION_RUN_ID": .string(runID)]),
        ])])])
    }

    /// The shape every job's final message must match (specs/editor.md › The result).
    static let resultSchema: JSONValue = .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "required": .array(["finished", "summary", "needsYou"].map(JSONValue.string)),
        "properties": .object([
            "finished": .object(["type": .string("boolean")]),
            "summary": .object(["type": .string("string")]),
            "needsYou": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
        ]),
    ])
}

/// A program found on this Mac.
struct EditorInstall: Equatable, Sendable {
    var program: EditorProgram
    var path: String
    var version: String?
}

/// What the ready job said: signed in, not signed in, or no clear answer (too slow, another error).
enum SignInCheck: Equatable, Sendable {
    case signedIn
    case notSignedIn(String)
    case couldNotCheck(String)
}

/// Finding programs, their versions and the login shell's PATH. Blocking; call off the main actor.
enum EditorDiscovery {
    static func find(_ program: EditorProgram) -> EditorInstall? {
        let fm = FileManager.default
        // The known folders, then Terminal's own PATH (.zshrc included: nvm, Volta and the like set it up there, and a
        // login shell alone never reads it), then the version managers' folders in case the shell didn't answer.
        let pathFolders = loginPath.split(separator: ":").map(String.init)
        var path = firstExecutable(program.command, in: EditorProgram.searchFolders + pathFolders)
        if path == nil { path = firstExecutable(program.command, in: versionManagerFolders()) }
        if path == nil, let prefix = shell("npm prefix -g")?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty, fm.isExecutableFile(atPath: "\(prefix)/bin/\(program.command)") { path = "\(prefix)/bin/\(program.command)" }
        if path == nil, let found = shell("command -v \(program.command)")?.split(separator: "\n").last.map(String.init), found.hasPrefix("/"), fm.isExecutableFile(atPath: found) { path = found }
        guard let path else { return nil }
        return EditorInstall(program: program, path: path, version: version(of: path, environment: environment(adding: path)))
    }

    /// The first folder holding `command` as a program, in order.
    static func firstExecutable(_ command: String, in folders: [String]) -> String? {
        folders.lazy.filter { $0.hasPrefix("/") }.map { "\($0)/\(command)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Where Node version managers put the programs npm installs, newest Node first for nvm: npm's `-g` lands in
    /// the Node that was current, and Terminal reaches it only through .zshrc.
    static func versionManagerFolders(home: String = NSHomeDirectory()) -> [String] {
        let nvm = "\(home)/.nvm/versions/node"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).filter { $0.hasPrefix("v") }
            .sorted { $0.dropFirst().split(separator: ".").compactMap { Int($0) }.lexicographicallyPrecedes($1.dropFirst().split(separator: ".").compactMap { Int($0) }) }
            .reversed()
        return versions.map { "\(nvm)/\($0)/bin" } + ["\(home)/.volta/bin", "\(home)/.bun/bin", "\(home)/.asdf/shims", "\(home)/.local/share/mise/shims", "\(home)/.local/share/pnpm"]
    }

    /// "2.1.312 (Claude Code)" → "2.1.312"; "codex-cli 0.164.0" → "0.164.0".
    static func version(of path: String, environment: [String: String]) -> String? {
        guard let out = run(path, ["--version"], environment: environment, timeout: 10)?.output else { return nil }
        return parseVersion(out)
    }
    static func parseVersion(_ text: String) -> String? {
        text.firstMatch(of: /(\d+\.\d+(?:\.\d+)?)/).map { String($0.1) }
    }

    /// The PATH Terminal has, so programs installed with npm, nvm or Homebrew find `node` and friends.
    nonisolated(unsafe) private static var cachedPath: String?
    static var loginPath: String {
        if let cachedPath { return cachedPath }
        let p = shellEnvironment["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? shell("printf %s \"$PATH\"").flatMap { $0.isEmpty ? nil : $0 } ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        cachedPath = p
        return p
    }

    /// What the person's shell sets when they open Terminal, .zshrc included: an app opened from the Dock
    /// gets none of it. Read once; empty when the shell doesn't answer in 10 seconds.
    nonisolated(unsafe) private static var cachedShell: [String: String]?
    static var shellEnvironment: [String: String] {
        if let cachedShell { return cachedShell }
        // Into a file, not a pipe: something .zshrc starts in the background can hold a pipe open forever.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("direction-shell-\(UUID().uuidString).env")
        defer { try? FileManager.default.removeItem(at: file) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "/usr/bin/env -0 > \"$DIRECTION_SHELL_FILE\""]
        // A clean start, as a new Terminal window has: what comes back is what the person's shell sets, not
        // what launched Direction (a Claude Code session's own settings, say).
        let mine = ProcessInfo.processInfo.environment
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "DIRECTION_SHELL_FILE": file.path]
        for key in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG"] { env[key] = mine[key] }
        p.environment = env
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { p in ChildProcesses.ended(p); done.signal() }
        var found: [String: String] = [:]
        if (try? p.run()) != nil {
            ChildProcesses.started(p)
            if done.wait(timeout: .now() + 10) == .timedOut { p.terminate() }
            else if let data = try? Data(contentsOf: file) {
                for pair in data.split(separator: 0) {
                    let text = String(decoding: pair, as: UTF8.self)
                    guard let eq = text.firstIndex(of: "="), text[..<eq] != "DIRECTION_SHELL_FILE" else { continue }
                    found[String(text[..<eq])] = String(text[text.index(after: eq)...])
                }
            }
        }
        cachedShell = found
        return found
    }

    /// The shell's settings an editor reads to find its sign-in and the network: where its settings live,
    /// a Bedrock or Vertex setup, a proxy and its certificates.
    static func carried(_ key: String) -> Bool {
        let prefixes = ["ANTHROPIC_", "CLAUDE_CODE_", "CODEX_", "OPENAI_", "AWS_", "VERTEX_"]
        let names = ["CLAUDE_CONFIG_DIR", "GOOGLE_APPLICATION_CREDENTIALS", "CLOUD_ML_REGION", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE"]
        return (names.contains(key) || prefixes.contains { key.hasPrefix($0) }) && !nesting.contains(key)
    }
    /// Billed per use, not the person's plan: passed only when the program has no sign-in of its own.
    static let shellKeys = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "CODEX_API_KEY"]
    /// Claude Code's own markers, so a Direction started from a Claude Code terminal doesn't nest.
    static let nesting = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"]
    static func hasShellKey(_ p: EditorProgram) -> Bool {
        let keys = p == .claudeCode ? ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] : ["OPENAI_API_KEY", "CODEX_API_KEY"]
        return keys.contains { shellEnvironment[$0]?.isEmpty == false }
    }

    /// The environment a program runs with: the app's, the shell's settings for it, the login PATH and the
    /// program's own folder first. An API key goes only with `shellKey`, so work runs on the person's plan.
    static func environment(adding program: String, extra: [String: String] = [:], shellKey: Bool = false) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (k, v) in shellEnvironment where carried(k) && env[k] == nil { env[k] = v }
        if !shellKey { for key in shellKeys { env.removeValue(forKey: key) } }
        for key in nesting { env.removeValue(forKey: key) }
        env["PATH"] = ((program as NSString).deletingLastPathComponent) + ":" + loginPath
        for (k, v) in extra { env[k] = v }
        return env
    }

    static func shell(_ command: String) -> String? {
        run("/bin/zsh", ["-lc", command], environment: ProcessInfo.processInfo.environment, timeout: 10).flatMap { $0.status == 0 ? $0.output : nil }
    }

    /// Runs to completion (or the timeout) and returns stdout, stderr and the exit status.
    static func run(_ path: String, _ args: [String], environment: [String: String], timeout: Double, directory: URL? = nil) -> (output: String, error: String, status: Int32)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args; p.environment = environment
        if let directory { p.currentDirectoryURL = directory }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { p in ChildProcesses.ended(p); done.signal() }
        do { try p.run() } catch { return nil }
        ChildProcesses.started(p)
        // Drain while it runs so a chatty program can't fill the pipe and stall.
        nonisolated(unsafe) var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); _ = done.wait(timeout: .now() + 2); return nil }
        group.wait()
        return (String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self), p.terminationStatus)
    }

    /// Asks the program to answer "ready". Signed in when it does; not signed in only when it says so.
    static func checkSignedIn(_ install: EditorInstall, version: String, shellKey: Bool = false) -> SignInCheck {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-ready-check")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let seconds = 45
        guard let r = run(install.path, install.program.readyArguments(version: version), environment: environment(adding: install.path, shellKey: shellKey), timeout: Double(seconds), directory: folder) else {
            return .couldNotCheck("\(install.program.name) didn\u{2019}t answer within \(seconds) seconds")
        }
        return readyAnswer(install.program, output: r.output, error: r.error, status: r.status, path: install.path)
    }

    /// What the ready job's output says. Its JSON is read, not searched, so a number or an id in a good
    /// answer never reads as an error.
    static func readyAnswer(_ program: EditorProgram, output: String, error: String, status: Int32, path: String? = nil) -> SignInCheck {
        if EditorFailure.isOutOfDate(output + "\n" + error) { return .couldNotCheck("\(program.name) is out of date for Direction. In Terminal, run \(program.updateCommand(path: path))") }
        var answered = false, said: [String] = []
        for line in output.split(separator: "\n") {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            switch program {
            case .claudeCode:
                guard o["type"] as? String == "result" || o["result"] != nil else { continue }
                let text = o["result"] as? String ?? ""
                if o["is_error"] as? Bool == true || (o["subtype"] as? String).map({ $0 != "success" }) == true { said.append(text.isEmpty ? o["subtype"] as? String ?? "an error" : text) }
                else if text.lowercased().contains("ready") { answered = true }
            case .codex:
                let item = (o["item"] ?? o["msg"]) as? [String: Any]
                if item?["type"] as? String == "agent_message", ((item?["text"] ?? item?["message"]) as? String)?.lowercased().contains("ready") == true { answered = true }
                if o["type"] as? String == "error", let m = o["message"] as? String { said.append(m) }
                if let m = (o["error"] as? [String: Any])?["message"] as? String { said.append(m) }
            }
        }
        if answered, status == 0 { return .signedIn }
        let stderr = error.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let problem = (said + stderr.suffix(3)).joined(separator: " ")
        if EditorFailure.reason(problem) == .notSignedIn { return .notSignedIn(String(problem.prefix(200))) }
        // A version that answers in plain words instead of JSON.
        if status == 0, said.isEmpty, !output.contains("{"), output.lowercased().contains("ready") { return .signedIn }
        return .couldNotCheck(problem.isEmpty ? "\(program.name) stopped (exit \(status)) without answering" : String(problem.prefix(200)))
    }
}
