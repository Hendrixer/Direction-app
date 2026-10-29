import Testing
import Foundation
import DirectionCore
@testable import DirectionTools

// direction_services and direction_make against a stubbed OpenRouter. No request leaves this Mac.

private final class OpenRouterStub: @unchecked Sendable {
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
    func bodies(_ path: String) -> [JSONValue] { lock.withLock { requests.filter { $0.url!.path.hasSuffix(path) && $0.httpBody != nil }.map { try! JSONDecoder().decode(JSONValue.self, from: $0.httpBody!) } } }
    func count(_ path: String) -> Int { lock.withLock { requests.filter { $0.url!.path.hasSuffix(path) }.count } }
}

private func data(_ v: JSONValue) -> Data { try! v.data() }
private func tone(seconds: Double, rate: Int = 8_000) -> Data {
    let n = Int(seconds * Double(rate)); var pcm = Data(capacity: n * 2)
    for i in 0..<n { var v = Int16(sin(Double(i) * 2 * .pi * 330 / Double(rate)) * 5_000).littleEndian; pcm.append(Data(bytes: &v, count: 2)) }
    return MadeMedia.wav(pcm16: pcm, sampleRate: rate)
}
private func sse(_ audio: Data, cost: Double) -> Data {
    let b64 = audio.base64EncodedString(), third = b64.count / 3 / 4 * 4
    let pieces = [String(b64.prefix(third)), String(b64.dropFirst(third).prefix(third)), String(b64.dropFirst(2 * third))]
    var out = ": OPENROUTER PROCESSING\n\n"
    for p in pieces { out += "data: " + String(decoding: data(.object(["choices": .array([.object(["delta": .object(["audio": .object(["data": .string(p)])])])])])), as: UTF8.self) + "\n\n" }
    out += "data: " + String(decoding: data(.object(["choices": .array([.object(["delta": .object([:]), "finish_reason": .string("stop")])]), "usage": .object(["cost": .number(cost)])])), as: UTF8.self) + "\n\ndata: [DONE]\n\n"
    return Data(out.utf8)
}

/// A film with a take, a Sound note and an open turnover, plus a sandbox: temp ledger, fresh built-in versions, a stub key.
private struct MadeFixture {
    var media: MediaFixture
    var note: ReviewComment
    var turnover: Turnover
    var overrides: OpenRouter.Overrides
    var assetID: String

    static func make(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse), key: String? = "sk-or-v1-stub-secret") async throws -> MadeFixture {
        let media = try await MediaFixture.make()
        let p = try media.store.read()
        let note = try media.store.addComment(text: "Music is too sure of itself here.", sequenceID: nil, revision: p.editRevision, time: .init(seconds: 1), extra: NoteFields(kind: .sound))
        let turnover = try media.store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        let catalog = media.directory.appendingPathComponent("openrouter-models.json")
        var fresh = MadeCatalog.builtIn; fresh.fetchedAt = Date().timeIntervalSince1970
        try JSONEncoder.direction.encode(fresh).write(to: catalog)
        let overrides = OpenRouter.Overrides(transport: transport, key: key, service: "dev.direction.openrouter.test-none-\(UUID().uuidString.prefix(8))", ledger: media.directory.appendingPathComponent("spend.json"),
                                             catalog: catalog, limits: SpendLimits(askAbove: 5, stopAt: 50), pollInterval: 0.01)
        return MadeFixture(media: media, note: note, turnover: turnover, overrides: overrides, assetID: p.assets[0].id)
    }
    func call(_ name: String, _ args: [String: JSONValue] = [:]) async throws -> JSONValue {
        try await OpenRouter.$overrides.withValue(overrides) { try await media.runtime.invoke(name, arguments: .object(args)).value }
    }
    func make(_ args: [String: JSONValue]) async throws -> JSONValue {
        try await call("direction_make", ["note": .string(note.id), "turnover": .string(turnover.id)].merging(args) { _, b in b })
    }
    func finish(_ job: JSONValue) async throws -> JobRecord {
        let id = try #require(job["id"].string)
        while true {
            let j = try await call("direction_job", ["jobID": .string(id)]).decode(JobRecord.self)
            if j.isTerminal { return j }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    var ledger: [SpendEntry] { OpenRouter.$overrides.withValue(overrides) { SpendLedger.entries() } }
}

@Suite(.serialized) struct MadeToolTests {
    @Test func aLongerBedIsMadeFromStreamedClipsJoinedAndImportedWithItsProvenance() async throws {
        let clip = tone(seconds: 30)
        let stub = OpenRouterStub { r, _ in
            guard r.url!.path.hasSuffix("chat/completions") else { return (404, Data(), [:]) }
            return (200, sse(clip, cost: 0.04), ["Content-Type": "text/event-stream"])
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let ask = "Sparse felt piano, unresolved, around 70 bpm. No swell."
        let job = try await f.make(["kind": .string("music"), "ask": .string(ask), "seconds": .number(75)])
        let done = try await f.finish(job)
        #expect(done.status == "completed", "\(done.error ?? "")")

        // Three 30 s clips joined with a short crossfade, cut to 75 s.
        let chats = stub.bodies("chat/completions")
        #expect(chats.count == 3)
        #expect(chats.allSatisfy { $0["stream"].bool == true && $0["modalities"] == .array([.string("text"), .string("audio")]) && $0["model"].string == "google/lyria-3-clip-preview" })
        #expect(chats[1]["messages"].array?.first?["content"].string?.contains("Part 2 of 3") == true)
        #expect(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-stub-secret" })

        let result = try #require(done.result)
        let assetID = try #require(result["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(assetID))
        #expect(record.kind == .music && record.versionName == "Lyria 3 Clip" && record.asked == ask && record.noteID == f.note.id && record.turnoverID == f.turnover.id)
        #expect(abs(record.spend - 0.12) < 1e-9 && record.service == "openrouter" && record.file.hasPrefix("Made/music-"))
        let asset = try f.media.store.read().asset(assetID)
        #expect(asset.path == f.media.store.madeDirectory.appendingPathComponent(String(record.file.dropFirst(5))).path)
        #expect(abs(asset.duration.seconds - 75) < 0.1 && !asset.audio.isEmpty)
        // The ledger holds what OpenRouter reported, tied to the clip.
        let entry = try #require(f.ledger.first)
        #expect(f.ledger.count == 1 && abs((entry.spend ?? 0) - 0.12) < 1e-9 && entry.assetIDs == [assetID] && entry.turnoverID == f.turnover.id)
        // The key appears in no result, record or event.
        let everything = try String(decoding: JSONValue.wrapping(f.media.store.jobs()).data(), as: UTF8.self) + String(decoding: JSONValue.wrapping(f.media.store.madeRecords()).data(), as: UTF8.self) + String(decoding: JSONValue.wrapping(f.media.store.events()).data(), as: UTF8.self)
        #expect(!everything.contains("sk-or-v1-stub-secret"))

        // Short music: one clip, trimmed with a fade.
        let short = try await f.finish(try await f.make(["kind": .string("music"), "ask": .string("A held note."), "seconds": .number(24)]))
        let shortAsset = try f.media.store.read().asset(try #require(short.result?["assetID"].string))
        #expect(abs(shortAsset.duration.seconds - 24) < 0.1 && stub.count("chat/completions") == 4)
    }

    @Test func aShotFromOneYouHaveRunsPendingToCompletedThenDownloads() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let stub = OpenRouterStub { r, _ in
            let path = r.url!.path
            if r.httpMethod == "POST" && path.hasSuffix("/videos") { return (202, data(.object(["id": .string("vid-1"), "polling_url": .string("https://openrouter.ai/api/v1/videos/vid-1"), "status": .string("pending")])), [:]) }
            if path.hasSuffix("/videos/vid-1/content") { return (200, movie, ["Content-Type": "video/mp4"]) }
            return (404, Data(), [:])
        }
        let polls = PollScript(["pending", "in_progress", "in_progress", "completed"])
        let wrapped: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { r in
            if r.httpMethod == "GET", r.url!.path.hasSuffix("/videos/vid-1") {
                let status = polls.next()
                var o: [String: JSONValue] = ["id": .string("vid-1"), "status": .string(status)]
                if status == "completed" { o["unsigned_urls"] = .array([.string("https://openrouter.ai/api/v1/videos/vid-1/content?index=0")]); o["usage"] = .object(["cost": .number(3.2), "is_byok": .bool(false)]) }
                return (data(.object(o)), HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return try await stub.transport(r)
        }
        let f = try await MadeFixture.make(transport: wrapped); defer { f.media.cleanup() }
        let estimate = try await f.make(["kind": .string("changedShot"), "ask": .string("The same frame, the sky turning to dusk cloud."), "seconds": .number(8), "from": .object(["assetID": .string(f.assetID), "start": .number(1)]), "estimateOnly": .bool(true)])
        #expect(abs((estimate["spend"].double ?? 0) - 3.20) < 1e-9 && estimate["seconds"].double == 8)
        #expect(stub.requests.isEmpty)

        let done = try await f.finish(try await f.make(["kind": .string("changedShot"), "ask": .string("The same frame, the sky turning to dusk cloud."), "seconds": .number(8), "from": .object(["assetID": .string(f.assetID), "start": .number(1)])]))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let submit = try #require(stub.bodies("/videos").first)
        #expect(submit["model"].string == "google/veo-3.1" && submit["duration"].double == 8 && submit["resolution"].string == "1080p" && submit["aspect_ratio"].string == "16:9")
        let frame = submit["frame_images"].array?.first
        #expect(frame?["frame_type"].string == "first_frame" && frame?["image_url"]["url"].string?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(polls.used == 4 && stub.requests.last?.url?.query == "index=0")
        let shotID = try #require(done.result?["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(shotID))
        #expect(record.kind == .changedShot && record.from == MadeFrom(assetID: f.assetID, start: 1) && record.spend == 3.2 && record.file.hasSuffix(".mp4"))
        #expect(!(try f.media.store.read().asset(record.assetID).video.isEmpty))
    }

    @Test func spendAsksAboveTheTurnoverLimitAndStopsForTheMonth() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let stub = OpenRouterStub { r, n in
            let path = r.url!.path
            if r.httpMethod == "POST" && path.hasSuffix("/videos") { return (202, data(.object(["id": .string("vid-\(n)"), "status": .string("pending")])), [:]) }
            if path.hasSuffix("/content") { return (200, movie, [:]) }
            return (200, data(.object(["id": .string("vid"), "status": .string("completed"), "usage": .object(["cost": .number(3.2)])])), [:])
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("An establishing shot of the ridge at dusk."), "seconds": .number(8)]
        #expect(try await f.finish(try await f.make(shot)).status == "completed")

        // $3.20 spent; another $3.20 passes the $5.00 turnover limit, and nothing goes out.
        let submitted = stub.count("/videos")
        let over = try await f.make(shot)
        #expect(over["status"].string == "spend_over_limit" && abs((over["estimate"].double ?? 0) - 3.2) < 1e-9 && abs((over["left"].double ?? 0) - 1.8) < 1e-9 && over["turnoverLimit"].double == 5)
        #expect(stub.count("/videos") == submitted)

        // The spend question: Direction writes the money line from its own record.
        let asked = try await f.call("direction_ask", ["turnoverID": .string(f.turnover.id), "kind": .string("spend"), "noteIDs": .array([.string(f.note.id)]),
                                                       "text": .string("Note 3 wants less sky. To change the sky itself to dusk cloud, I\u{2019}d make a new shot from this frame with Veo 3.1."),
                                                       "choices": .array([.object(["id": .string("reframe"), "label": .string("Reframe only"), "detail": .string("No spend"), "recommended": .bool(true)]),
                                                                          .object(["id": .string("make"), "label": .string("Make a new shot from this frame"), "detail": .string("About $3.20")]),
                                                                          .object(["id": .string("find"), "label": .string("Find another take"), "detail": .string("I\u{2019}ll search the ridge footage first")])]),
                                                       "spend": .object(["estimate": .number(3.2), "choiceID": .string("make"), "kind": .string("shot")])])
        let q = try asked.decode(EditorQuestion.self)
        #expect(q.kind == "spend" && q.spend?.choiceID == "make" && abs((q.spend?.turnoverSpent ?? 0) - 3.2) < 1e-9 && q.spend?.limit == 5 && abs((q.spend?.total ?? 0) - 6.4) < 1e-9)
        await #expect(throws: DirectionError.self) { _ = try await f.call("direction_ask", ["kind": .string("spend"), "noteIDs": .array([]), "text": .string("Spend?"), "choices": .array([.object(["label": .string("Yes")]), .object(["label": .string("No")])])]) }

        let approved = shot.merging(["spendQuestionID": .string(q.id)]) { _, b in b }
        await expectCode("spend_not_agreed") { _ = try await f.make(approved) }
        _ = try f.media.store.answerQuestion(id: q.id, choiceID: "reframe", text: nil)
        await expectCode("spend_not_agreed") { _ = try await f.make(approved) }
        _ = try f.media.store.answerQuestion(id: q.id, choiceID: "make", text: nil)
        await expectCode("spend_over_question") { _ = try await f.make(shot.merging(["spendQuestionID": .string(q.id), "ways": .number(2)]) { _, b in b }) }
        #expect(try await f.finish(try await f.make(approved)).status == "completed")
        // One yes, one request.
        await expectCode("spend_question_used") { _ = try await f.make(approved) }

        // The month: $43.70 spent elsewhere this month puts the next shot past $50.00, and a yes doesn't help.
        try OpenRouter.$overrides.withValue(f.overrides) { try SpendLedger.record(SpendEntry(kind: .shot, version: "google/veo-3.1", estimate: 43.7, spend: 43.7, filmID: "another-film", turnoverID: "turnover-x")) }
        let q2 = try f.media.store.ask(EditorQuestion(id: "question-2", turnoverID: f.turnover.id, kind: "spend", noteIDs: [], text: "Again?", detail: nil,
                                                       choices: [.init(id: "yes", label: "Make it"), .init(id: "no", label: "Don\u{2019}t")], allowsText: false, answer: nil, createdAt: 0).withSpend(SpendAsk(estimate: 3.2, turnoverSpent: 6.4, limit: 5, choiceID: "yes")))
        _ = try f.media.store.answerQuestion(id: q2.id, choiceID: "yes", text: nil)
        let cap = try await f.make(shot.merging(["spendQuestionID": .string(q2.id)]) { _, b in b })
        #expect(cap["status"].string == "spend_cap" && cap["monthLimit"].double == 50 && abs((cap["left"].double ?? 0) - 0) < 1e-9)
        #expect(stub.count("/videos") == submitted + 1)

        // direction_services tells the editor the same.
        let services = try await f.call("direction_services")
        #expect(services["services"].array?.first?["state"].string == "ready")
        #expect(services["limits"]["askAbovePerTurnover"].double == 5 && services["limits"]["stopAtPerMonth"].double == 50)
        #expect(abs((services["month"]["spent"].double ?? 0) - 50.1) < 1e-9 && abs((services["turnover"]["spent"].double ?? 0) - 6.4) < 1e-9)
        let kinds = services["services"].array?.first?["kinds"].array ?? []
        #expect(kinds.first { $0["kind"].string == "shot" }?["price"].string == "About $0.40 a second at 1080p")
    }

    @Test func failuresGiveTheHoldBackAndNothingGoesOutWithoutAKey() async throws {
        let stub = OpenRouterStub { r, _ in
            if r.url!.path.hasSuffix("chat/completions") { return (402, data(.object(["error": .object(["message": .string("Insufficient credits")])])), [:]) }
            if r.httpMethod == "POST" { return (202, data(.object(["id": .string("vid-9"), "status": .string("pending")])), [:]) }
            return (200, data(.object(["id": .string("vid-9"), "status": .string("failed"), "error": .string("Content policy")])), [:])
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let music = try await f.finish(try await f.make(["kind": .string("music"), "ask": .string("Rain on a tin roof."), "seconds": .number(10)]))
        #expect(music.status == "failed" && music.error == "OpenRouter said: Insufficient credits (402)")
        let shot = try await f.finish(try await f.make(["kind": .string("shot"), "ask": .string("A ridge."), "seconds": .number(4)]))
        #expect(shot.status == "failed" && shot.error?.contains("Content policy") == true)
        #expect(f.ledger.isEmpty)
        #expect(try f.media.store.madeRecords().isEmpty)

        var keyless = f; keyless.overrides.key = nil
        let before = stub.requests.count
        await expectCode("no_openrouter_key") { _ = try await keyless.make(["kind": .string("still"), "ask": .string("A plate of dusk sky.")]) }
        #expect(stub.requests.count == before)
        // Arguments the editor gets wrong.
        await expectCode("invalid_arguments") { _ = try await f.make(["kind": .string("changedShot"), "ask": .string("Dusk."), "seconds": .number(8)]) }
        await expectCode("invalid_arguments") { _ = try await f.make(["kind": .string("music"), "ask": .string("Piano.")]) }
        await expectCode("unknown_version") { _ = try await f.make(["kind": .string("music"), "ask": .string("Piano."), "seconds": .number(10), "version": .string("nobody/nothing")]) }
        await expectCode("feedback_not_found") { _ = try await f.call("direction_make", ["kind": .string("music"), "ask": .string("Piano."), "seconds": .number(10), "note": .string("note-x"), "turnover": .string(f.turnover.id)]) }
    }
}

/// Answers each poll of a video job with the next status.
private final class PollScript: @unchecked Sendable {
    private let lock = NSLock(); private var statuses: [String]; private(set) var used = 0
    init(_ statuses: [String]) { self.statuses = statuses }
    func next() -> String { lock.withLock { used += 1; return statuses.count > 1 ? statuses.removeFirst() : statuses[0] } }
}

private func expectCode(_ code: String, _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(code)") }
    catch let e as DirectionError { #expect(e.code == code, "\(e.message)") }
    catch { Issue.record("Unexpected \(error)") }
}

private extension EditorQuestion {
    func withSpend(_ s: SpendAsk) -> EditorQuestion { var q = self; q.spend = s; return q }
}
