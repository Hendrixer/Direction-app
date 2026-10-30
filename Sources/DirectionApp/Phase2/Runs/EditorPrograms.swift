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

    /// Versions offered in Settings › Editor; "Other…" takes any string the program accepts. Codex's
    /// are the ones its own model menu lists, read from its cache, so they follow the installed Codex.
    var versions: [(id: String, name: String)] {
        switch self {
        case .claudeCode: [("claude-opus-5-5", "Claude Opus 5.5"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"), ("claude-haiku-5-5", "Claude Haiku 5.5")]
        case .codex: [("", "The program\u{2019}s default")] + Self.codexModels()
        }
    }

    /// Codex's model menu: `~/.codex/models_cache.json`, listed models by priority, named the way
    /// its menu names them ("GPT-6.1-Sol" → "GPT-6.1 Sol"). Without the cache, the list it had on 2026-10-29.
    static func codexModels(cache: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/models_cache.json")) -> [(id: String, name: String)] {
        struct Cache: Decodable { struct Model: Decodable { var slug: String; var display_name: String?; var visibility: String?; var priority: Int? }; var models: [Model] }
        func name(_ display: String) -> String {
            let parts = display.split(separator: "-", maxSplits: 2).map(String.init)
            return parts.count == 3 ? "\(parts[0])-\(parts[1]) \(parts[2])" : display
        }
        if let data = try? Data(contentsOf: cache), let c = try? JSONDecoder().decode(Cache.self, from: data) {
            let listed = c.models.filter { ($0.visibility ?? "list") == "list" }.sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
            if !listed.isEmpty { return listed.map { ($0.slug, name($0.display_name ?? $0.slug)) } }
        }
        return [("gpt-6.1-sol", "GPT-6.1 Sol"), ("gpt-6-astra", "GPT-6 Astra"), ("gpt-6.1-terra", "GPT-6.1 Terra"), ("gpt-6-sol", "GPT-6 Sol"), ("gpt-6-luna", "GPT-6 Luna"), ("gpt-5.6-sol", "GPT-5.6 Sol"), ("gpt-5.6-terra", "GPT-5.6 Terra"), ("gpt-5.6-luna", "GPT-5.6 Luna")]
    }
    var defaultVersion: String { versions[0].id }
    func versionName(_ id: String) -> String { versions.first { $0.id == id }?.name ?? id }

    /// Folders searched before asking a login shell.
    static var searchFolders: [String] {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin"]
    }

    // MARK: Flags (checked against `--help` by EditorProgramTests)

    static let claudeFlags = ["--print", "--output-format", "--verbose", "--model", "--mcp-config", "--strict-mcp-config", "--allowedTools", "--append-system-prompt", "--resume", "--permission-mode", "--settings", "--tools", "--no-session-persistence"]
    static let codexExecFlags = ["--json", "--model", "--cd", "--sandbox", "--config", "--output-schema", "--skip-git-repo-check", "--ignore-user-config", "--ephemeral"]
    static let codexResumeFlags = ["--json", "--model", "--config", "--output-schema", "--skip-git-repo-check", "--ignore-user-config"]

    /// What one invocation needs to know.
    struct Invocation {
        var job: String
        var role: String
        var version: String
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
            args += ["--mcp-config", i.mcpConfig.path, "--strict-mcp-config"]
            // Every Direction tool, file read and write inside the working folder, and scripts when allowed.
            var allowed = ["mcp__direction", "Read", "Glob", "Grep", "Edit(./**)", "Write(./**)"]
            if i.scripts { allowed.append("Bash") }
            args += ["--allowedTools", allowed.joined(separator: ","), "--append-system-prompt", i.role, "--permission-mode", "dontAsk"]
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
            shared += [
                "--config", "mcp_servers.direction.command=\(toml(i.helper))",
                "--config", "mcp_servers.direction.args=[\(toml("mcp")),\(toml("--project")),\(toml(i.film.path))]",
                "--config", "mcp_servers.direction.env.DIRECTION_RUN_ID=\(toml(i.runID))",
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

/// Finding programs, their versions and the login shell's PATH. Blocking; call off the main actor.
enum EditorDiscovery {
    static func find(_ program: EditorProgram) -> EditorInstall? {
        let fm = FileManager.default
        var path = EditorProgram.searchFolders.map { "\($0)/\(program.command)" }.first { fm.isExecutableFile(atPath: $0) }
        if path == nil, let prefix = shell("npm prefix -g")?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty, fm.isExecutableFile(atPath: "\(prefix)/bin/\(program.command)") { path = "\(prefix)/bin/\(program.command)" }
        if path == nil, let found = shell("command -v \(program.command)")?.split(separator: "\n").last.map(String.init), found.hasPrefix("/"), fm.isExecutableFile(atPath: found) { path = found }
        guard let path else { return nil }
        return EditorInstall(program: program, path: path, version: version(of: path, environment: environment(adding: path)))
    }

    /// "2.1.312 (Claude Code)" → "2.1.312"; "codex-cli 0.164.0" → "0.164.0".
    static func version(of path: String, environment: [String: String]) -> String? {
        guard let out = run(path, ["--version"], environment: environment, timeout: 10)?.output else { return nil }
        return parseVersion(out)
    }
    static func parseVersion(_ text: String) -> String? {
        text.firstMatch(of: /(\d+\.\d+(?:\.\d+)?)/).map { String($0.1) }
    }

    /// The login shell's PATH, so programs installed with npm, nvm or Homebrew find `node` and friends.
    nonisolated(unsafe) private static var cachedPath: String?
    static var loginPath: String {
        if let cachedPath { return cachedPath }
        let p = shell("printf %s \"$PATH\"").flatMap { $0.isEmpty ? nil : $0 } ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        cachedPath = p
        return p
    }

    /// The environment a program runs with: the app's, with the login PATH and the program's own folder first.
    /// Claude Code's own markers are dropped so a Direction started from a Claude Code terminal doesn't nest.
    static func environment(adding program: String, extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] { env.removeValue(forKey: key) }
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
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        // Drain while it runs so a chatty program can't fill the pipe and stall.
        nonisolated(unsafe) var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); _ = done.wait(timeout: .now() + 2); return nil }
        group.wait()
        return (String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self), p.terminationStatus)
    }

    /// Signed in: the ready job answers within 30 s without an auth error.
    static func checkSignedIn(_ install: EditorInstall, version: String) -> Bool {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("direction-ready-check")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let r = run(install.path, install.program.readyArguments(version: version), environment: environment(adding: install.path), timeout: 30, directory: folder) else { return false }
        let text = (r.output + "\n" + r.error)
        if EditorFailure.reason(text) == .notSignedIn { return false }
        return r.status == 0 && text.lowercased().contains("ready")
    }
}
