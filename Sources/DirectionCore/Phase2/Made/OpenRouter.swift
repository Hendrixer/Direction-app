import Foundation
import Security

/// OpenRouter: the one service behind made media and, optionally, looking at footage
/// (specs/made-media.md › Services). Direction makes every request; the key never reaches the editor.
public enum OpenRouter {
    public static let base = URL(string: "https://openrouter.ai/api/v1")!

    /// Per-task stand-ins for tests, so suites running in parallel never share a transport, key,
    /// ledger or cache. A job's task inherits them from the call that started it.
    public struct Overrides: Sendable {
        public var transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?
        public var key: String?
        public var service: String?
        public var ledger: URL?
        public var catalog: URL?
        public var limits: SpendLimits?
        public var pollInterval: Double?
        public var quality: MadeQuality?
        public var refusals: URL?
        public init(transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil, key: String? = nil, service: String? = nil, ledger: URL? = nil, catalog: URL? = nil, limits: SpendLimits? = nil, pollInterval: Double? = nil, quality: MadeQuality? = nil, refusals: URL? = nil) {
            self.transport = transport; self.key = key; self.service = service; self.ledger = ledger; self.catalog = catalog; self.limits = limits; self.pollInterval = pollInterval; self.quality = quality; self.refusals = refusals
        }
    }
    @TaskLocal public static var overrides = Overrides()

    /// The director's key, kept in the login keychain as Direction's own item.
    ///
    /// Each Direction binary keeps its own copy: account "app" for the app and "tools" for the bundled
    /// `direction` helper the editor's tool calls run in. Since macOS 10.12 a login-keychain item carries a
    /// partition list of its creator's signature (`cdhash:` for unsigned or ad-hoc builds), and a second
    /// binary is asked for the keychain password even when the item's ACL trusts it, so one shared item
    /// can't be read by both without a prompt. The app writes its own copy and hands the key to the helper
    /// on a pipe (`direction key save`); every read is of the reader's own item, with keychain UI off.
    /// Nothing ever prints the key back out.
    public enum Key {
        public static let defaultService = "dev.direction.openrouter"
        /// Tests use their own service name (`Overrides.service`) so they never touch the director's item.
        nonisolated(unsafe) public static var service = defaultService
        static var current: String { overrides.service ?? service }
        /// The helper beside this app. Tests point it at the built `direction` product.
        nonisolated(unsafe) public static var helper: URL? = defaultHelper

        public enum Role: String, Sendable { case app, tools }
        /// The bundled tool runs as `direction`; everything else (the app, previews, tests) is the app.
        public static var role: Role { Bundle.main.executableURL?.lastPathComponent == "direction" ? .tools : .app }

        /// The key for a request: `DIRECTION_OPENROUTER_KEY` for development, else this binary's own item.
        public static func read() -> String? {
            if let key = overrides.key { return key }
            if current == defaultService, let key = ProcessInfo.processInfo.environment["DIRECTION_OPENROUTER_KEY"], !key.isEmpty { return key }
            return item(role)
        }
        /// Whether this binary has a copy it can read without asking.
        public static var isSaved: Bool { read() != nil }

        /// Saves the key for the app and, from the app, for the helper too.
        public static func save(_ key: String) throws {
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.count <= 4_096 else { throw DirectionError("invalid_key", "Paste your OpenRouter key.") }
            try store(key, role)
            if role == .app { try handToHelper(key) }
        }

        /// Removes every copy. Made clips stay; new requests stop at once.
        public static func remove() {
            delete(role)
            if role == .app { _ = try? runHelper(["key", "remove"], input: nil) }
        }

        /// The helper can lose its copy when it's rebuilt (its signature changes). The app gives it the key again.
        public static func syncHelper() {
            guard role == .app, let key = item(.app), let status = try? runHelper(["key", "status"], input: nil),
                  (try? JSONDecoder().decode(JSONValue.self, from: status))?["readable"].bool != true else { return }
            try? handToHelper(key)
        }

        // MARK: Keychain

        static func query(_ role: Role) -> [CFString: Any] {
            [kSecClass: kSecClassGenericPassword, kSecAttrService: current, kSecAttrAccount: role.rawValue]
        }

        /// This binary's copy, read with keychain UI off so a stale item fails instead of prompting.
        public static func item(_ role: Role) -> String? {
            var q = query(role); q[kSecReturnData] = true; q[kSecMatchLimit] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = withoutKeychainUI { SecItemCopyMatching(q as CFDictionary, &item) }
            guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
            return key
        }
        /// An item exists, readable or not (attributes need no permission).
        public static func exists(_ role: Role) -> Bool {
            var q = query(role); q[kSecReturnAttributes] = true; q[kSecMatchLimit] = kSecMatchLimitOne
            var item: CFTypeRef?
            return withoutKeychainUI { SecItemCopyMatching(q as CFDictionary, &item) } == errSecSuccess
        }
        public static func store(_ key: String, _ role: Role) throws {
            delete(role)
            var item = query(role)
            item[kSecAttrLabel] = role == .app ? "Direction · OpenRouter key" : "Direction · OpenRouter key (direction tool)"
            item[kSecValueData] = Data(key.utf8)
            let status = withoutKeychainUI { SecItemAdd(item as CFDictionary, nil) }
            guard status == errSecSuccess else { throw DirectionError("keychain_failed", "Couldn\u{2019}t save the key to the keychain (\(status)).") }
        }
        public static func delete(_ role: Role) { _ = withoutKeychainUI { SecItemDelete(query(role) as CFDictionary) } }

        /// `SecKeychainSetUserInteractionAllowed` is the only switch the file-based keychain honors
        /// (`kSecUseAuthenticationUIFail` is ignored there). Looked up at run time: the call is deprecated
        /// but still the supported way to keep a tool from raising a dialog.
        private static let lock = NSLock()
        private static func withoutKeychainUI<T>(_ body: () -> T) -> T {
            typealias Get = @convention(c) (UnsafeMutablePointer<DarwinBoolean>) -> OSStatus
            typealias Set = @convention(c) (DarwinBoolean) -> OSStatus
            let handle = dlopen(nil, RTLD_NOW)
            guard let g = dlsym(handle, "SecKeychainGetUserInteractionAllowed"), let s = dlsym(handle, "SecKeychainSetUserInteractionAllowed") else { return body() }
            let get = unsafeBitCast(g, to: Get.self), set = unsafeBitCast(s, to: Set.self)
            lock.lock(); defer { lock.unlock() }
            var was: DarwinBoolean = true
            _ = get(&was); _ = set(false)
            defer { _ = set(was) }
            return body()
        }

        // MARK: The helper's copy

        static var defaultHelper: URL? {
            guard let exe = Bundle.main.executableURL else { return nil }
            let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/direction")
            let beside = exe.deletingLastPathComponent().appendingPathComponent("direction")
            return [bundled, beside].first { FileManager.default.isExecutableFile(atPath: $0.path) && $0.resolvingSymlinksInPath() != exe.resolvingSymlinksInPath() }
        }
        static func handToHelper(_ key: String) throws {
            guard helper != nil else { return }
            _ = try runHelper(["key", "save"], input: Data(key.utf8))
        }
        /// Runs `direction key …` with the key on stdin only. Its output never carries the key.
        @discardableResult
        static func runHelper(_ arguments: [String], input: Data?) throws -> Data {
            guard let helper else { throw DirectionError("no_helper", "The direction tool isn\u{2019}t beside this app.") }
            let p = Process(), stdin = Pipe(), stdout = Pipe()
            p.executableURL = helper
            p.arguments = arguments + ["--service", current]
            p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.nullDevice
            var env = ProcessInfo.processInfo.environment; env.removeValue(forKey: "DIRECTION_OPENROUTER_KEY"); p.environment = env
            try p.run()
            if let input { stdin.fileHandleForWriting.write(input) }
            try? stdin.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(15)
            while p.isRunning && Date() < deadline { usleep(20_000) }
            if p.isRunning { p.terminate(); throw DirectionError("helper_timeout", "The direction tool didn\u{2019}t answer.") }
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            guard p.terminationStatus == 0 else { throw DirectionError("keychain_failed", "The direction tool couldn\u{2019}t keep the key (\(p.terminationStatus)).") }
            return out
        }
    }

    // MARK: Requests

    /// Tests swap the transport; everything else uses URLSession.
    nonisolated(unsafe) public static var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    /// Seconds between video job polls. Tests shorten it.
    nonisolated(unsafe) public static var pollInterval: Double = 5

    public struct Reply: Sendable {
        public var data: Data
        public var status: Int
        public var headers: [String: String]
        public var json: JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null }
    }

    /// One request. Throws OpenRouter's own message on a non-2xx reply. The key goes only in the header.
    /// `root` is another of OpenRouter's APIs (`Decisions.base`); the rest of Direction uses v1.
    public static func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: JSONValue? = nil, key: String? = nil, authorized: Bool = true, timeout: TimeInterval = 120, root: URL? = nil) async throws -> Reply {
        var components = URLComponents(url: (root ?? base).appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = method
        if authorized {
            guard let key = key ?? Key.read() else { throw DirectionError("no_openrouter_key", "Add an OpenRouter key in Settings \u{203A} Engines.") }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("https://direction.film", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Direction", forHTTPHeaderField: "X-OpenRouter-Title")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await (overrides.transport ?? transport)(request)
        let http = response as? HTTPURLResponse, status = http?.statusCode ?? 0
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v } }
        guard (200..<300).contains(status) else { throw DirectionError(status == 401 ? "openrouter_key_rejected" : status == 402 ? "openrouter_credits" : "openrouter_error", "OpenRouter said: \(message(data)) (\(status))") }
        return Reply(data: data, status: status, headers: headers)
    }

    /// OpenRouter's error message, without echoing anything we sent.
    static func message(_ data: Data) -> String {
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        let text = json?["error"]["message"].string ?? json?["message"].string ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "no details" : text
    }

    /// One JSON request; the body of the reply.
    public static func request(_ method: String, _ path: String, body: JSONValue? = nil, key: String? = nil) async throws -> Data {
        try await send(method, path, body: body, key: key).data
    }

    /// A non-streaming chat completion. Returns the whole response object. With `spend`, its
    /// `usage.cost` goes into this Mac's ledger under that kind (footage looking passes `.looking`).
    public static func chat(_ body: JSONValue, key: String? = nil, spend: SpendKind? = nil) async throws -> JSONValue {
        let reply = try JSONDecoder().decode(JSONValue.self, from: await request("POST", "chat/completions", body: body, key: key))
        if let spend, let cost = reply["usage"]["cost"].double, cost > 0 {
            try? SpendLedger.record(SpendEntry(kind: spend, version: body["model"].string ?? "", estimate: cost, spend: cost))
        }
        return reply
    }

    // MARK: Audio out of chat (music, sound effects)

    public struct AudioReply: Sendable {
        public var audio: Data
        public var transcript: String
        public var cost: Double?
        public var id: String?
    }

    /// Audio output streams (`stream: true`) as SSE; the base64 pieces arrive in `delta.audio.data`.
    public static func audioChat(_ body: JSONValue, key: String? = nil) async throws -> AudioReply {
        var b = body
        if case .object(var fields) = b { fields["stream"] = .bool(true); b = .object(fields) }
        let reply = try await send("POST", "chat/completions", body: b, key: key, timeout: 600)
        return try parseAudioStream(reply.data)
    }

    /// Server-sent events: `data:` lines (several make one event), `:` comments to ignore, `[DONE]` to end.
    /// A mid-stream failure arrives as an event with a top-level `error`.
    public static func parseAudioStream(_ data: Data) throws -> AudioReply {
        let text = String(decoding: data, as: UTF8.self)
        if !text.contains("data:"), let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            if json["error"] != .null { throw DirectionError("openrouter_error", "OpenRouter said: \(message(data))") }
            if let b64 = json["choices"].array?.first?["message"]["audio"]["data"].string, let audio = Data(base64Encoded: b64) {
                return AudioReply(audio: audio, transcript: json["choices"].array?.first?["message"]["audio"]["transcript"].string ?? "", cost: json["usage"]["cost"].double, id: json["id"].string)
            }
            throw DirectionError("no_audio", "OpenRouter sent no audio.")
        }
        var events: [String] = [], pending: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
            if line.isEmpty { if !pending.isEmpty { events.append(pending.joined(separator: "\n")); pending = [] }; continue }
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("data:") { pending.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
        if !pending.isEmpty { events.append(pending.joined(separator: "\n")) }
        var pieces: [String] = [], transcript = "", cost: Double?, id: String?
        for event in events {
            if event == "[DONE]" { break }
            guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(event.utf8)) else { continue }
            if json["error"] != .null { throw DirectionError("openrouter_error", "OpenRouter said: \(json["error"]["message"].string ?? "the stream stopped")") }
            id = id ?? json["id"].string
            if let c = json["usage"]["cost"].double { cost = c }
            for choice in json["choices"].array ?? [] {
                let audio = choice["delta"]["audio"]
                if let piece = audio["data"].string, !piece.isEmpty { pieces.append(piece) }
                if let t = audio["transcript"].string { transcript += t }
            }
        }
        guard !pieces.isEmpty else { throw DirectionError("no_audio", "OpenRouter sent no audio.") }
        // Pieces are usually whole base64 runs; if one isn't, they were split mid-quad, so join first.
        let decoded = pieces.map { Data(base64Encoded: $0) }
        let audio: Data
        if decoded.allSatisfy({ $0 != nil }) { audio = decoded.reduce(into: Data()) { $0.append($1!) } }
        else if let joined = Data(base64Encoded: pieces.joined()) { audio = joined }
        else { throw DirectionError("bad_audio", "OpenRouter\u{2019}s audio couldn\u{2019}t be read.") }
        return AudioReply(audio: audio, transcript: transcript, cost: cost, id: id)
    }

    // MARK: Speech, stills, shots

    /// `POST /audio/speech` returns raw audio bytes; the cost comes from the generation record.
    public static func speech(_ body: JSONValue, key: String? = nil) async throws -> (audio: Data, contentType: String, cost: Double?) {
        let reply = try await send("POST", "audio/speech", body: body, key: key, timeout: 300)
        var cost: Double?
        if let id = reply.headers["x-generation-id"] { cost = try? await generationCost(id, key: key) }
        return (reply.data, reply.headers["content-type"] ?? "", cost)
    }

    /// What a finished request cost, from `GET /generation`.
    public static func generationCost(_ id: String, key: String? = nil) async throws -> Double? {
        let json = try await send("GET", "generation", query: [URLQueryItem(name: "id", value: id)], key: key).json
        return json["data"]["total_cost"].double ?? json["data"]["usage"].double
    }

    /// `POST /images`: base64 images in `data[].b64_json`, the cost in `usage.cost`.
    public static func image(_ body: JSONValue, key: String? = nil) async throws -> (image: Data, mediaType: String, cost: Double?) {
        let json = try await send("POST", "images", body: body, key: key, timeout: 300).json
        guard let first = json["data"].array?.first, let b64 = first["b64_json"].string, let image = Data(base64Encoded: b64) else { throw DirectionError("no_image", "OpenRouter sent no image.") }
        return (image, first["media_type"].string ?? "image/png", json["usage"]["cost"].double)
    }

    public struct VideoJob: Sendable, Equatable {
        public var id: String
        public var status: String
        public var cost: Double?
        public var error: String?
        public var urls: Int
        init(_ json: JSONValue) {
            id = json["id"].string ?? ""; status = json["status"].string ?? "pending"
            cost = json["usage"]["cost"].double
            error = json["error"]["message"].string ?? json["error"].string
            urls = json["unsigned_urls"].array?.count ?? 0
        }
    }
    /// `POST /videos` answers 202 with a job to poll.
    public static func submitVideo(_ body: JSONValue, key: String? = nil) async throws -> VideoJob {
        let job = VideoJob(try await send("POST", "videos", body: body, key: key).json)
        guard !job.id.isEmpty else { throw DirectionError("openrouter_error", "OpenRouter didn\u{2019}t start the shot.") }
        return job
    }
    public static func video(_ id: String, key: String? = nil) async throws -> VideoJob {
        VideoJob(try await send("GET", "videos/\(id)", key: key).json)
    }
    /// The finished file. The URL isn't presigned, so it takes the key like every other call.
    /// A shot is paid for once it's made, so a dropped download is tried twice more.
    public static func videoContent(_ id: String, index: Int = 0, key: String? = nil) async throws -> Data {
        for attempt in 1...3 {
            do { return try await send("GET", "videos/\(id)/content", query: [URLQueryItem(name: "index", value: String(index))], key: key, timeout: 600).data }
            catch where !(error is CancellationError) && attempt < 3 { try await Task.sleep(for: .seconds(overrides.pollInterval ?? 2)) }
        }
        throw CancellationError()
    }
    /// Polls until the job finishes. `progress` hears each status.
    public static func waitForVideo(_ id: String, key: String? = nil, timeout: TimeInterval = 1_800, progress: @Sendable (VideoJob) -> Void = { _ in }) async throws -> VideoJob {
        let start = Date()
        var misses = 0
        while true {
            try Task.checkCancellation()
            let job: VideoJob
            // A shot takes minutes; one dropped poll mustn't lose it.
            do { job = try await video(id, key: key); misses = 0 }
            catch where !(error is CancellationError) && misses < 4 {
                misses += 1
                try await Task.sleep(for: .seconds(overrides.pollInterval ?? pollInterval))
                continue
            }
            progress(job)
            switch job.status {
            case "completed": return job
            case "failed", "cancelled", "expired": throw DirectionError("shot_failed", "OpenRouter couldn\u{2019}t make the shot: \(job.error ?? job.status).")
            default:
                guard Date().timeIntervalSince(start) < timeout else { throw DirectionError("shot_timeout", "The shot took longer than \(Int(timeout / 60)) minutes.") }
                try await Task.sleep(for: .seconds(overrides.pollInterval ?? pollInterval))
            }
        }
    }

    // MARK: Key and versions

    public struct KeyInfo: Sendable, Equatable {
        public var label: String?
        /// Credits left on the key, when the key or its budget has a limit.
        public var remaining: Double?
        public var usage: Double?
        public var isFreeTier: Bool
    }
    /// `GET /key`: checks a key and reads its limits. Free.
    public static func keyInfo(key: String? = nil) async throws -> KeyInfo {
        let d = try await send("GET", "key", key: key).json["data"]
        return KeyInfo(label: d["label"].string, remaining: d["limit_remaining"].double ?? d["effective_budget"]["remaining_usd"].double, usage: d["usage"].double, isFreeTier: d["is_free_tier"].bool ?? false)
    }

    /// `GET /models?output_modalities=…` and `GET /videos/models` are public; the key is sent when there is one.
    public static func models(output: String) async throws -> [JSONValue] {
        try await send("GET", "models", query: [URLQueryItem(name: "output_modalities", value: output)], authorized: Key.read() != nil).json["data"].array ?? []
    }
    public static func videoModels() async throws -> [JSONValue] {
        try await send("GET", "videos/models", authorized: Key.read() != nil).json["data"].array ?? []
    }
}
