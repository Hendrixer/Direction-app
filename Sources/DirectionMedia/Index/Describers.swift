import Foundation
import DirectionCore

// MARK: This Mac: mlx-vlm in a helper process

/// Describes shots with mlx-vlm through `describe.py`, which loads the version once and answers
/// JSON lines. One helper per version per process; it stops 60 s after its last shot.
public struct LocalDescriber: ShotDescriber {
    public let repo: String
    public var engine: String { "mlx-vlm \u{00B7} " + repo }
    public var concurrency: Int { 1 }
    public init(repo: String) { self.repo = repo }

    public func describe(_ request: DescribeRequest) async throws -> DescribeResult {
        let helper = LocalVisionHelper.shared(repo)
        return try await DescribePrompt.run(words: request.words) { prompt in
            (try await helper.ask(images: request.images, prompt: prompt, maxTokens: DescribePrompt.maxTokens), nil)
        }
    }
    public func finish() async { await LocalVisionHelper.shared(repo).scheduleStop() }
}

/// The helper process. Requests are one at a time; each carries an id so a reply that arrives
/// after a cancelled request is never taken for the next one.
public actor LocalVisionHelper {
    nonisolated(unsafe) private static var helpers: [String: LocalVisionHelper] = [:]
    private static let lock = NSLock()
    public static func shared(_ repo: String) -> LocalVisionHelper {
        lock.withLock {
            if let h = helpers[repo] { return h }
            let h = LocalVisionHelper(repo: repo); helpers[repo] = h; return h
        }
    }

    public let repo: String
    /// Tests point these at a stand-in helper.
    public var python: URL?
    public var script: URL?
    public var idleSeconds: Double = 60
    public var timeoutSeconds: Double = 180
    /// Extra environment for the helper (tests add a stand-in mlx_vlm to PYTHONPATH).
    public var environment: [String: String] = [:]

    private var process: Process?
    private var input: FileHandle?
    private var reader: LineReader?
    private var errors = ErrorTail()
    private var nextID = 0
    private var busy = false
    private var lastUse = Date()
    private var idle: Task<Void, Never>?

    public init(repo: String, python: URL? = nil, script: URL? = nil) { self.repo = repo; self.python = python; self.script = script }
    public func configure(python: URL?, script: URL?, idleSeconds: Double? = nil, environment: [String: String] = [:], timeout: Double? = nil) { self.python = python; self.script = script; self.environment = environment; if let idleSeconds { self.idleSeconds = idleSeconds }; if let timeout { timeoutSeconds = timeout } }

    public var isRunning: Bool { process?.isRunning ?? false }

    /// Starts the helper and waits for it to load the version (which downloads it the first time).
    public func start() async throws {
        if process?.isRunning == true, reader != nil { return }
        guard let python = python ?? VisionHelper.python() else { throw DirectionError("mlx_vlm_missing", "mlx-vlm isn't installed. Install it in Terminal with uv tool install mlx-vlm.") }
        guard let script = script ?? VisionHelper.script() else { throw DirectionError("vision_helper_missing", "Direction's vision helper (describe.py) is missing from the app.") }
        let p = Process()
        p.executableURL = python
        p.arguments = ["-u", script.path, "--model", repo, "--max-tokens", String(DescribePrompt.maxTokens)]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"; env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"; env["TOKENIZERS_PARALLELISM"] = "false"
        env.merge(environment) { _, new in new }
        p.environment = env
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        let tail = ErrorTail(); errors = tail
        stderr.fileHandleForReading.readabilityHandler = { h in tail.append(h.availableData) }
        let lines = LineReader(stdout.fileHandleForReading)
        try p.run()
        process = p; input = stdin.fileHandleForWriting; reader = lines
        let first = await withTaskCancellationHandler { await lines.next() } onCancel: { p.terminate() }
        try Task.checkCancellation()
        guard let first, let reply = try? JSONDecoder().decode(JSONValue.self, from: Data(first.utf8)), reply["ready"].bool == true else {
            let reason = first.flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }?["error"].string ?? tail.last
            stop()
            throw DirectionError("vision_helper_failed", "mlx-vlm couldn't load \(repo). \(reason)".trimmingCharacters(in: .whitespaces))
        }
    }

    /// One request: images and a prompt in, the text the version wrote out.
    public func ask(images: [URL], prompt: String, maxTokens: Int) async throws -> String {
        idle?.cancel()
        try await start()
        guard let input, let reader, let process else { throw DirectionError("vision_helper_failed", "The vision helper isn't running.") }
        busy = true; defer { busy = false; lastUse = Date(); scheduleStop() }
        nextID += 1
        let id = nextID
        let request = JSONValue.object(["id": .number(Double(id)), "images": .array(images.map { .string($0.path) }), "prompt": .string(prompt), "max_tokens": .number(Double(maxTokens))])
        try input.write(contentsOf: try request.data() + Data("\n".utf8))
        let timeout = timeoutSeconds
        let watchdog = Task { try? await Task.sleep(for: .seconds(timeout)); if !Task.isCancelled { process.terminate() } }
        defer { watchdog.cancel() }
        while true {
            let line = await withTaskCancellationHandler { await reader.next() } onCancel: { /* the reply is skipped by id next time */ }
            try Task.checkCancellation()
            guard let line else {
                let reason = errors.last
                stop()
                throw DirectionError("vision_helper_failed", "The vision helper stopped. \(reason)".trimmingCharacters(in: .whitespaces))
            }
            guard let reply = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), reply["id"].int == id else { continue }
            if let error = reply["error"].string { throw DirectionError("vision_helper_failed", error) }
            return reply["text"].string ?? ""
        }
    }

    /// Stops the helper after the idle time unless another shot comes first.
    public func scheduleStop() {
        idle?.cancel()
        let wait = idleSeconds
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.stopIfIdle(after: wait)
        }
    }
    private func stopIfIdle(after seconds: Double) { if !busy && Date().timeIntervalSince(lastUse) >= seconds - 0.5 { stop() } }

    public func stop() {
        if let input { try? input.write(contentsOf: Data("{\"quit\": true}\n".utf8)); try? input.close() }
        if let p = process, p.isRunning { p.terminate() }
        process = nil; input = nil; reader = nil
    }
}

/// Lines from a pipe, handed to whoever's waiting, in order. Fed from the pipe's own thread.
final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [String] = []
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var closed = false

    init(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            self?.feed(data)
        }
    }

    func feed(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if data.isEmpty { closed = true; for w in waiters { w.resume(returning: nil) }; waiters = []; return }
        buffer.append(data)
        while let n = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<n], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...n)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if waiters.isEmpty { lines.append(line) } else { waiters.removeFirst().resume(returning: line) }
        }
    }

    func next() async -> String? {
        await withCheckedContinuation { c in
            lock.lock(); defer { lock.unlock() }
            if !lines.isEmpty { c.resume(returning: lines.removeFirst()) }
            else if closed { c.resume(returning: nil) }
            else { waiters.append(c) }
        }
    }
}

/// The last few lines a helper wrote to stderr, for error messages.
final class ErrorTail: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ data: Data) { lock.lock(); text = String((text + String(decoding: data, as: UTF8.self)).suffix(4_000)); lock.unlock() }
    var last: String {
        lock.lock(); defer { lock.unlock() }
        return text.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(String.init) ?? ""
    }
}

// MARK: OpenRouter

/// Describes shots through OpenRouter with the director's key: three JPEG keyframes as data-URL
/// image parts, `response_format` set to the description's schema, 4 requests at a time.
/// Only these keyframes leave this Mac.
public struct OpenRouterDescriber: ShotDescriber {
    public let version: String
    /// nil reads the director's key from the keychain; tests pass their own.
    public var key: String?
    public var engine: String { "OpenRouter \u{00B7} " + version }
    public var concurrency: Int { 4 }
    public init(version: String, key: String? = nil) { self.version = version; self.key = key }

    public func body(_ request: DescribeRequest, prompt: String) throws -> JSONValue {
        var parts: [JSONValue] = [.object(["type": .string("text"), "text": .string(prompt)])]
        for url in request.images {
            let data = try Data(contentsOf: url)
            parts.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string("data:image/jpeg;base64," + data.base64EncodedString())])]))
        }
        return .object([
            "model": .string(version),
            "messages": .array([.object(["role": .string("user"), "content": .array(parts)])]),
            "temperature": .number(0),
            "max_tokens": .number(Double(DescribePrompt.maxTokens)),
            "response_format": .object(["type": .string("json_schema"), "json_schema": .object(["name": .string("shot"), "strict": .bool(true), "schema": ShotLook.jsonSchema])]),
            "usage": .object(["include": .bool(true)]),
        ])
    }

    public func describe(_ request: DescribeRequest) async throws -> DescribeResult {
        try await DescribePrompt.run(words: request.words) { prompt in
            let reply = try await OpenRouter.chat(try body(request, prompt: prompt), key: key, spend: .looking)
            let content = reply["choices"].array?.first?["message"]["content"]
            // Content is a string, or a list of text parts from some versions.
            let text = content?.string ?? content?.array?.compactMap { $0["text"].string }.joined() ?? ""
            return (text, reply["usage"]["cost"].double)
        }
    }
    public func finish() async {}
}
