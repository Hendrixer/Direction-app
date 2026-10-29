import Testing
import Foundation
@testable import DirectionCore

// Made media through OpenRouter. Every request goes through a stubbed transport (OpenRouter.Overrides),
// the ledger and version cache live in temporary files, and the keychain test uses a test service name.

/// A stand-in OpenRouter: records each request and answers from `respond`.
final class StubOpenRouter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var respond: (URLRequest, Int) throws -> (Int, Data, [String: String])
    init(_ respond: @escaping (URLRequest, Int) throws -> (Int, Data, [String: String])) { self.respond = respond }
    var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        { [self] request in
            let n: Int = lock.withLock { requests.append(request); return requests.count - 1 }
            let (status, data, headers) = try respond(request, n)
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
    }
    func body(_ i: Int) -> JSONValue { lock.withLock { (requests[i].httpBody).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null } }
    var count: Int { lock.withLock { requests.count } }
    var paths: [String] { lock.withLock { requests.map { "\($0.httpMethod ?? "") \($0.url!.path.replacingOccurrences(of: "/api/v1/", with: ""))" } } }
}

func json(_ value: JSONValue) -> Data { try! value.data() }
func temporaryFile(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("direction-made-\(UUID().uuidString)-\(name)") }

/// An SSE stream as OpenRouter sends audio: a processing comment, base64 pieces in delta.audio, the usage chunk, [DONE].
func audioStream(_ audio: Data, pieces: Int = 3, cost: Double? = 0.04, splitMidQuad: Bool = false) -> Data {
    var lines = [": OPENROUTER PROCESSING", ""]
    let step = max(1, audio.count / pieces)
    var chunks: [String] = []
    if splitMidQuad {
        let b64 = audio.base64EncodedString(), cut = b64.index(b64.startIndex, offsetBy: 7)
        chunks = [String(b64[..<cut]), String(b64[cut...])]
    } else {
        var i = 0
        while i < audio.count { chunks.append(audio[i..<min(audio.count, i + step)].base64EncodedString()); i += step }
    }
    for (n, c) in chunks.enumerated() {
        let event: JSONValue = .object(["id": .string("gen-1"), "choices": .array([.object(["delta": .object(["audio": .object(["data": .string(c), "transcript": .string(n == 0 ? "♪" : "")])])])])])
        lines += ["data: " + String(decoding: json(event), as: UTF8.self), ""]
    }
    if let cost { lines += ["data: " + String(decoding: json(.object(["id": .string("gen-1"), "choices": .array([.object(["delta": .object(["content": .string("")]), "finish_reason": .string("stop")])]), "usage": .object(["cost": .number(cost)])])), as: UTF8.self), ""] }
    lines += ["data: [DONE]", ""]
    return Data(lines.joined(separator: "\n").utf8)
}

/// A mono 16-bit WAV tone, small enough for stubs.
func toneWAV(seconds: Double, rate: Int = 8_000) -> Data {
    let n = Int(seconds * Double(rate))
    var pcm = Data(capacity: n * 2)
    for i in 0..<n { var v = Int16(sin(Double(i) * 2 * .pi * 440 / Double(rate)) * 6_000).littleEndian; pcm.append(Data(bytes: &v, count: 2)) }
    return MadeMedia.wav(pcm16: pcm, sampleRate: rate)
}

@Suite(.serialized) struct MadeCoreTests {
    @Test func streamedAudioIsAssembledFromBase64Pieces() throws {
        let wav = toneWAV(seconds: 0.5)
        let reply = try OpenRouter.parseAudioStream(audioStream(wav))
        #expect(reply.audio == wav)
        #expect(reply.cost == 0.04 && reply.transcript == "♪" && reply.id == "gen-1")
        // Pieces split inside a base64 quad decode once joined.
        #expect(try OpenRouter.parseAudioStream(audioStream(wav, splitMidQuad: true)).audio == wav)
        // Raw pcm16 is wrapped as WAV; WAV runs from several chunks become one file.
        let pcm = Data(repeating: 1, count: 4_800)
        #expect(MadeMedia.assemble(pcm).ext == "wav" && MadeMedia.assemble(pcm).data.count == 4_800 + 44)
        let joined = MadeMedia.assemble(toneWAV(seconds: 0.25) + toneWAV(seconds: 0.25))
        #expect(joined.ext == "wav" && joined.data.count == toneWAV(seconds: 0.5).count)
        #expect(MadeMedia.audioExtension(Data("ID3\u{4}".utf8)) == "mp3")
    }

    @Test func midStreamErrorsAndRefusalsCarryOpenRouterWords() async throws {
        let failing = Data("data: {\"error\":{\"code\":\"server_error\",\"message\":\"Provider disconnected unexpectedly\"},\"choices\":[{\"delta\":{},\"finish_reason\":\"error\"}]}\n\ndata: [DONE]\n\n".utf8)
        #expect(throws: DirectionError.self) { try OpenRouter.parseAudioStream(failing) }
        do { _ = try OpenRouter.parseAudioStream(failing) } catch let e as DirectionError { #expect(e.message.contains("Provider disconnected")) }
        #expect(throws: DirectionError.self) { try OpenRouter.parseAudioStream(Data("data: [DONE]\n\n".utf8)) }

        let stub = StubOpenRouter { _, _ in (402, json(.object(["error": .object(["code": .number(402), "message": .string("Insufficient credits")])])), [:]) }
        try await OpenRouter.$overrides.withValue(.init(transport: stub.transport, key: "sk-or-stub", service: "dev.direction.openrouter.test-none")) {
            do { _ = try await OpenRouter.chat(.object(["model": .string("x")])); Issue.record("402 must throw") }
            catch let e as DirectionError { #expect(e.code == "openrouter_credits" && e.message == "OpenRouter said: Insufficient credits (402)") }
        }
        // No key, no request.
        let none = StubOpenRouter { _, _ in (200, Data("{}".utf8), [:]) }
        await OpenRouter.$overrides.withValue(.init(transport: none.transport, service: "dev.direction.openrouter.test-none-\(UUID().uuidString)")) {
            do { _ = try await OpenRouter.chat(.object([:])); Issue.record("No key must throw") } catch let e as DirectionError { #expect(e.code == "no_openrouter_key") } catch {}
        }
        #expect(none.count == 0)
    }

    @Test func chatSendsTheKeyOnlyInTheHeaderAndRecordsLookingSpend() async throws {
        let ledger = temporaryFile("spend.json"); defer { try? FileManager.default.removeItem(at: ledger) }
        let stub = StubOpenRouter { _, _ in (200, json(.object(["choices": .array([.object(["message": .object(["content": .string("{\"description\":\"Medium on Maya.\"}")])])]), "usage": .object(["cost": .number(0.002)])])), [:]) }
        try await OpenRouter.$overrides.withValue(.init(transport: stub.transport, key: "sk-or-secret-123", service: "dev.direction.openrouter.test-none", ledger: ledger)) {
            let body: JSONValue = .object(["model": .string("google/gemini-3.1-flash"), "messages": .array([.object(["role": .string("user"), "content": .array([.object(["type": .string("image_url"), "image_url": .object(["url": .string("data:image/jpeg;base64,AA==")])])])])]),
                                           "response_format": .object(["type": .string("json_schema")])])
            let reply = try await OpenRouter.chat(body, spend: .looking)
            #expect(reply["choices"].array?.first?["message"]["content"].string?.contains("Maya") == true)
            _ = try await OpenRouter.chat(body)
        }
        let r = stub.requests[0]
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-secret-123")
        #expect(r.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions" && r.httpMethod == "POST")
        #expect(!(String(data: r.httpBody!, encoding: .utf8)!.contains("sk-or-secret")))
        let entries = await OpenRouter.$overrides.withValue(.init(ledger: ledger)) { SpendLedger.entries() }
        #expect(entries.count == 1 && entries[0].kind == .looking && entries[0].spend == 0.002)
    }

    @Test func estimatesFollowEachVersionsListedPrice() {
        let c = MadeCatalog.builtIn
        let lyria = c.version(.music)!, veo = c.version(.shot)!
        #expect(lyria.id == "google/lyria-3-clip-preview" && lyria.name == "Lyria 3 Clip")
        #expect(MadeEstimator.estimate(.music, version: lyria, seconds: 24).spend == 0.04)
        let bed = MadeEstimator.estimate(.music, version: lyria, seconds: 75)
        #expect(bed.requests == 3 && abs(bed.spend - 0.12) < 1e-9)
        #expect(MadeEstimator.estimate(.music, version: lyria, seconds: 24, ways: 2).spend == 0.08)
        let shot = MadeEstimator.estimate(.changedShot, version: veo, seconds: 7)
        #expect(shot.duration == 8 && shot.resolution == "1080p" && abs(shot.spend - 3.20) < 1e-9)
        #expect(MadeFormat.priceLine(.music, lyria) == "About $0.04 a 30 s clip")
        #expect(MadeFormat.priceLine(.shot, veo) == "About $0.40 a second at 1080p")
        // SKUs in cents and per resolution, and image-to-video tiers.
        let kling = MadeVersion(id: "kwaivgi/kling-v3.0-pro", name: "Kling", listing: .video, skus: ["duration_seconds": "0.112", "duration_seconds_with_audio": "0.168", "image_to_video_duration_seconds_720p": "0.112"], durations: [5, 10], resolutions: ["720p"])
        #expect(MadeEstimator.perSecond(kling, resolution: "720p", audio: true, fromImage: true) == 0.112)
        let grok = MadeVersion(id: "x-ai/grok", name: "Grok", listing: .video, skus: ["cents_per_video_output_second_720p": "14", "cents_per_video_output_second_1080p": "25"], durations: [1, 15], resolutions: ["480p", "720p", "1080p"])
        #expect(MadeEstimator.perSecond(grok, resolution: "1080p", audio: true, fromImage: false) == 0.25)
        let speech = MadeVersion(id: "a/tts", name: "TTS", listing: .speech, pricing: ["prompt": "0.00001", "completion": "0"])
        #expect(abs(MadeEstimator.estimate(.voice, version: speech, seconds: nil, words: String(repeating: "a", count: 100)).spend - 0.001) < 1e-9)
        #expect(MadeFormat.money(3.2) == "$3.20" && MadeFormat.length(24) == "0:24")
        #expect(MadeVersion.displayName("Google: Nano Banana 2 (Gemini 3.1 Flash Image)", id: "x") == "Nano Banana 2")
    }

    @Test func versionsAreFetchedThenCachedForADay() async throws {
        let cache = temporaryFile("openrouter-models.json"); defer { try? FileManager.default.removeItem(at: cache) }
        let stub = StubOpenRouter { r, _ in
            let output = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            switch (r.url!.path, output) {
            case ("/api/v1/models", "audio"?): return (200, json(.object(["data": .array([.object(["id": .string("google/lyria-3-clip-preview"), "name": .string("Google: Lyria 3 Clip Preview"), "pricing": .object(["prompt": .string("0"), "completion": .string("0")]), "architecture": .object(["output_modalities": .array([.string("text"), .string("audio")])])])])])), [:])
            case ("/api/v1/models", "speech"?): return (200, json(.object(["data": .array([.object(["id": .string("assemblyai/assemblyai-tts-1"), "name": .string("AssemblyAI: TTS 1"), "pricing": .object(["prompt": .string("0.000015")]), "supported_voices": .array([.string("aai-jane")])]), .object(["id": .string("later/tts"), "name": .string("Later")])])])), [:])
            case ("/api/v1/models", "image"?): return (200, json(.object(["data": .array([.object(["id": .string("google/gemini-3.1-flash-image"), "name": .string("Google: Nano Banana 2 (Gemini 3.1 Flash Image)"), "pricing": .object(["image_output": .string("0.00006")])])])])), [:])
            case ("/api/v1/videos/models", _): return (200, json(.object(["data": .array([.object(["id": .string("google/veo-3.1"), "name": .string("Google: Veo 3.1"), "supported_durations": .array([4, 6, 8].map { .number($0) }), "supported_resolutions": .array([.string("720p"), .string("1080p")]), "pricing_skus": .object(["duration_seconds_with_audio": .string("0.40")])])])])), [:])
            default: return (404, Data(), [:])
            }
        }
        let now = Date()
        try await OpenRouter.$overrides.withValue(.init(transport: stub.transport, service: "dev.direction.openrouter.test-none-\(UUID().uuidString)", catalog: cache)) {
            let first = await MadeVersions.load(now: now)
            #expect(stub.count == 4 && FileManager.default.fileExists(atPath: cache.path))
            // The model lists are public: no key, no Authorization header.
            #expect(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
            #expect(first.version(.music)?.name == "Lyria 3 Clip" && first.version(.voice)?.id == "assemblyai/assemblyai-tts-1" && first.version(.voice)?.voices == ["aai-jane"])
            #expect(first.version(.still)?.name == "Nano Banana 2" && first.version(.shot)?.durations == [4, 6, 8])
            #expect(first.choices(.voice).map(\.id) == ["assemblyai/assemblyai-tts-1", "later/tts"])
            #expect(first.version(.music, chosen: "google/lyria-3-clip")?.id == "google/lyria-3-clip-preview")
            _ = await MadeVersions.load(now: now.addingTimeInterval(3_600))
            #expect(stub.count == 4)
            _ = await MadeVersions.load(now: now.addingTimeInterval(MadeVersions.maxAge + 60))
            #expect(stub.count == 8)
            // Offline: the stale cache stands.
            stub.respond = { _, _ in throw URLError(.notConnectedToInternet) }
            let offline = await MadeVersions.load(now: now.addingTimeInterval(3 * MadeVersions.maxAge))
            #expect(offline.version(.shot)?.id == "google/veo-3.1")
        }
    }

    @Test func spendAsksAboveTheTurnoverLimitAndStopsAtTheCap() {
        #expect(SpendCheck.of(estimate: 3.2, turnoverSpent: 0, monthSpent: 0, askAbove: 5, stopAt: 50, approved: false) == .ok)
        #expect(SpendCheck.of(estimate: 3.2, turnoverSpent: 2.9, monthSpent: 2.9, askAbove: 5, stopAt: 50, approved: false) == .overLimit(estimate: 3.2, spent: 2.9, limit: 5))
        #expect(SpendCheck.of(estimate: 3.2, turnoverSpent: 2.9, monthSpent: 2.9, askAbove: 5, stopAt: 50, approved: true) == .ok)
        #expect(SpendCheck.of(estimate: 3.2, turnoverSpent: 0, monthSpent: 48, askAbove: 5, stopAt: 50, approved: true) == .cap(estimate: 3.2, spent: 48, cap: 50))
        #expect(SpendCheck.of(estimate: 3.2, turnoverSpent: 0, monthSpent: 480, askAbove: 5, stopAt: nil, approved: false) == .ok)
        // Exactly at the limit is under it.
        #expect(SpendCheck.of(estimate: 2.1, turnoverSpent: 2.9, monthSpent: 2.9, askAbove: 5, stopAt: 50, approved: false) == .ok)
    }

    @Test func theLedgerHoldsEstimatesAndLetsEachYesThroughOnce() throws {
        let ledger = temporaryFile("spend.json"); defer { try? FileManager.default.removeItem(at: ledger); try? FileManager.default.removeItem(atPath: ledger.path + ".lock") }
        try OpenRouter.$overrides.withValue(.init(ledger: ledger)) {
            func shot(_ t: String = "turnover-1") -> SpendEntry { SpendEntry(kind: .shot, version: "google/veo-3.1", estimate: 3.2, filmID: "film-1", turnoverID: t) }
            let first = shot()
            #expect(try SpendLedger.reserve(first, askAbove: 5, stopAt: 50) == .ok)
            #expect(try SpendLedger.reserve(shot(), askAbove: 5, stopAt: 50) == .overLimit(estimate: 3.2, spent: 3.2, limit: 5))
            // Another turnover starts at zero.
            #expect(try SpendLedger.reserve(shot("turnover-2"), askAbove: 5, stopAt: 50) == .ok)
            #expect(try SpendLedger.reserve(shot(), approvedBy: "question-1", askAbove: 5, stopAt: 50) == .ok)
            expectError("spend_question_used") { _ = try SpendLedger.reserve(shot(), approvedBy: "question-1", askAbove: 5, stopAt: 50) }
            try SpendLedger.settle(first.id, spend: 2.75, assetIDs: ["asset-1"])
            let all = SpendLedger.entries()
            #expect(abs(SpendLedger.turnoverSpent(all, filmID: "film-1", turnoverID: "turnover-1") - 5.95) < 1e-9)
            #expect(abs(SpendLedger.monthSpent(all) - 9.15) < 1e-9)
            #expect(SpendLedger.byGroup(all).map(\.group) == ["New shots"])
            // The cap stops even an approved request.
            #expect(try SpendLedger.reserve(SpendEntry(kind: .music, version: "lyria", estimate: 1, filmID: "film-1", turnoverID: "turnover-3"), approvedBy: "question-2", askAbove: 5, stopAt: 10) == .cap(estimate: 1, spent: 9.15, cap: 10))
            // A failed request gives its hold back.
            let failed = shot("turnover-4")
            _ = try SpendLedger.reserve(failed, askAbove: 5, stopAt: 50)
            try SpendLedger.release(failed.id)
            #expect(!SpendLedger.entries().contains { $0.id == failed.id })
            // Last month doesn't count.
            let old = SpendEntry(at: Calendar.current.date(byAdding: .month, value: -1, to: Date())!, kind: .music, version: "lyria", estimate: 40, spend: 40)
            try SpendLedger.record(old)
            #expect(abs(SpendLedger.monthSpent(SpendLedger.entries()) - 9.15) < 1e-9)
        }
    }

    /// Two writers at once: this process and a second one (python, holding the same flock) each add 60 entries.
    @Test func theLedgerIsSafeAcrossTwoWriters() async throws {
        let ledger = temporaryFile("spend.json"); defer { try? FileManager.default.removeItem(at: ledger); try? FileManager.default.removeItem(atPath: ledger.path + ".lock") }
        let script = """
        import fcntl, json, os, sys, time, uuid
        path = sys.argv[1]
        for i in range(60):
            with open(path + ".lock", "a+") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                try:
                    with open(path) as f: data = json.load(f)
                except Exception: data = {"entries": []}
                time.sleep(0.002)
                data["entries"].append({"id": "py-" + str(uuid.uuid4()), "at": time.time(), "kind": "music", "service": "openrouter", "version": "lyria", "estimate": 0.04, "spend": 0.04})
                with open(path + ".tmp", "w") as f: json.dump(data, f)
                os.replace(path + ".tmp", path)
                fcntl.flock(lock, fcntl.LOCK_UN)
        """
        let python = Process()
        python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        python.arguments = ["-I", "-c", script, ledger.path]
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3"), (try? python.run()) != nil else { return }
        try await OpenRouter.$overrides.withValue(.init(ledger: ledger)) {
            for _ in 0..<60 { try SpendLedger.record(SpendEntry(kind: .shot, version: "veo", estimate: 0.4, spend: 0.4)); try await Task.sleep(for: .milliseconds(1)) }
        }
        python.waitUntilExit()
        #expect(python.terminationStatus == 0)
        let entries = OpenRouter.$overrides.withValue(.init(ledger: ledger)) { SpendLedger.entries() }
        #expect(entries.count == 120)
        #expect(entries.filter { $0.id.hasPrefix("py-") }.count == 60)
    }

    /// The app's copy and the helper's copy, on a test service name. The helper is a second process; neither raises a dialog.
    @Test func theKeyRoundTripsThroughTheKeychainAndTheHelper() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = [".build/debug/direction", ".build/arm64-apple-macosx/debug/direction"].map { root.appendingPathComponent($0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        let service = "dev.direction.openrouter.test-\(UUID().uuidString.prefix(8))"
        let saved = OpenRouter.Key.helper
        OpenRouter.Key.helper = helper
        defer { OpenRouter.Key.helper = saved }
        try OpenRouter.$overrides.withValue(.init(service: service)) {
            defer { OpenRouter.Key.remove() }
            #expect(OpenRouter.Key.read() == nil)
            try OpenRouter.Key.save("  sk-or-v1-test-round-trip \n")
            #expect(OpenRouter.Key.read() == "sk-or-v1-test-round-trip")
            #expect(OpenRouter.Key.exists(.app))
            if helper != nil {
                let status = try JSONDecoder().decode(JSONValue.self, from: OpenRouter.Key.runHelper(["key", "status"], input: nil))
                #expect(status["present"].bool == true && status["readable"].bool == true)
                // The helper's copy belongs to the helper: this process is refused at once, with no dialog.
                let started = Date()
                #expect(OpenRouter.Key.item(.tools) == nil)
                #expect(Date().timeIntervalSince(started) < 5)
            }
            OpenRouter.Key.remove()
            #expect(OpenRouter.Key.read() == nil && !OpenRouter.Key.exists(.app))
            if helper != nil {
                let status = try JSONDecoder().decode(JSONValue.self, from: OpenRouter.Key.runHelper(["key", "status"], input: nil))
                #expect(status["present"].bool == false)
            }
        }
    }
}
