import Testing
import Foundation
import ImageIO
import DirectionCore
import DirectionMedia
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

    @Test func aNewShotFromATakesFrameRunsPendingToCompletedThenDownloads() async throws {
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
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("The ridge at dusk, cloud moving. Camera holds."), "seconds": .number(8), "first": .object(["assetID": .string(f.assetID), "at": .number(1)])]
        let estimate = try await f.make(shot.merging(["estimateOnly": .bool(true)]) { _, b in b })
        // Silent unless asked: $0.20 a second.
        #expect(abs((estimate["spend"].double ?? 0) - 1.60) < 1e-9 && estimate["seconds"].double == 8)
        #expect(stub.requests.isEmpty)

        let done = try await f.finish(try await f.make(shot))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let submit = try #require(stub.bodies("/videos").first)
        // Balanced makes 720p, which this Mac sharpens to the cut; Best, or a Mac that can't sharpen, asks for 1080p.
        let made = MadeProcessing.sharpeningStatus(width: 1280, height: 720) == .unsupported ? "1080p" : "720p"
        #expect(submit["model"].string == "google/veo-3.1" && submit["duration"].double == 8 && submit["resolution"].string == made && submit["aspect_ratio"].string == "16:9" && submit["generate_audio"].bool == false)
        let frame = submit["frame_images"].array?.first
        #expect(submit["frame_images"].array?.count == 1 && frame?["frame_type"].string == "first_frame" && frame?["image_url"]["url"].string?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(polls.used == 4 && stub.requests.contains { $0.url?.path.hasSuffix("/videos/vid-1/content") == true && $0.url?.query == "index=0" })
        // This stub has no answers for the check, so the shot comes in unchecked and says why.
        #expect(done.result?["made"].array?.first?["check"]["verdict"].string == "unchecked")
        let shotID = try #require(done.result?["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(shotID))
        // As big as the cut already, so it comes in as made.
        #expect(record.kind == .shot && record.first == MadeFrame(assetID: f.assetID, at: 1) && record.spend == 3.2 && record.file.hasSuffix(".mp4") && record.sharpenedFrom == nil)
        #expect(!(try f.media.store.read().asset(record.assetID).video.isEmpty))
        // It came back with sound (the take it's made of has some); a shot is silent unless sound is asked for.
        #expect(try f.media.store.read().asset(record.assetID).audio.isEmpty)
    }

    /// Gemini Omni always makes sound and turns down `generate_audio: false` (the paid trials): it's never sent,
    /// and the sound comes off on this Mac. A version that turns it down unlisted gets the request again without it.
    @Test func aVersionThatAlwaysMakesSoundIsNeverAskedForNone() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let turnedDown = data(.object(["error": .object(["message": .string("This model always generates audio with the video. generate_audio cannot be set to false.")])]))
        let stub = OpenRouterStub { r, n in
            let path = r.url!.path
            if r.httpMethod == "POST" && path.hasSuffix("/videos") {
                let body = (try? JSONDecoder().decode(JSONValue.self, from: r.httpBody ?? Data())) ?? .null
                return body["generate_audio"] != .null ? (400, turnedDown, [:]) : (202, data(.object(["id": .string("vid-\(n)"), "status": .string("pending")])), [:])
            }
            if path.hasSuffix("/content") { return (200, movie, ["Content-Type": "video/mp4"]) }
            // Omni reports $0 for a shot it made (the paid trials, round 2); the generation record has the cost.
            if path.hasSuffix("/generation") { return (200, data(.object(["data": .object(["total_cost": .number(0.35)])])), [:]) }
            return (200, data(.object(["id": .string("vid"), "status": .string("completed"), "generation_id": .string("gen-1"), "usage": .object(["cost": .number(0)])])), [:])
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        var catalog = MadeCatalog.builtIn; catalog.fetchedAt = Date().timeIntervalSince1970
        catalog.versions.append(MadeVersion(id: "google/gemini-omni-1.2-flash", name: "Gemini Omni 1.2 Flash", listing: .video, skus: ["duration_seconds_with_audio": "0.104256", "duration_seconds_with_audio_720p": "0.069504"],
                                            durations: Array(3...15), resolutions: ["720p", "1080p"], aspectRatios: ["16:9", "9:16"], frames: ["first_frame", "last_frame"], makesSound: true))
        try JSONEncoder.direction.encode(catalog).write(to: try #require(f.overrides.catalog))
        // From words alone, Balanced picks Gemini Omni.
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("Rain on a window at night."), "seconds": .number(5)]
        let done = try await f.finish(try await f.make(shot))
        #expect(done.status == "completed", "\(done.error ?? "")")
        #expect(stub.bodies("/videos").map { $0["model"].string ?? "" } == ["google/gemini-omni-1.2-flash"] && stub.bodies("/videos")[0]["generate_audio"] == .null)
        let madeID = try #require(done.result?["assetID"].string)
        let made = try f.media.store.read().asset(madeID)
        #expect(made.audio.isEmpty && !made.video.isEmpty)
        #expect(abs((try f.media.store.madeRecord(madeID)?.spend ?? 0) - 0.35) < 1e-9)

        // Veo is listed with prices without sound, so it's told; turned down, it's asked again without the setting.
        var pinned = f; pinned.overrides.version = "google/veo-3.1"
        let again = try await pinned.finish(try await pinned.make(shot))
        #expect(again.status == "completed", "\(again.error ?? "")")
        let veo = stub.bodies("/videos").dropFirst()
        #expect(veo.map { $0["generate_audio"] } == [.bool(false), .null] && veo.allSatisfy { $0["model"].string == "google/veo-3.1" })
    }

    /// Sound effects are Seed Audio's, made through the speech list and cut to the length asked; one it turns down
    /// goes to Lyria, and the result says so.
    @Test func aSoundEffectIsSeedAudiosAndLyriaTakesWhatItTurnsDown() async throws {
        let effect = tone(seconds: 6), clip = tone(seconds: 30)
        let moderated = data(.object(["error": .object(["message": .string("The generated audio was rejected by the provider content moderation.")])]))
        let stub = OpenRouterStub { r, _ in
            let path = r.url!.path
            if path.hasSuffix("audio/speech") {
                let input = (try? JSONDecoder().decode(JSONValue.self, from: r.httpBody ?? Data()))?["input"].string ?? ""
                return input.contains("door") ? (400, moderated, [:]) : (200, effect, ["Content-Type": "audio/wav"])
            }
            if path.hasSuffix("chat/completions") { return (200, sse(clip, cost: 0.04), ["Content-Type": "text/event-stream"]) }
            return (404, Data(), [:])
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let glass: [String: JSONValue] = ["kind": .string("soundEffect"), "ask": .string("A glass shatters on a tile floor."), "seconds": .number(4)]
        let estimate = try await f.make(glass.merging(["estimateOnly": .bool(true)]) { _, b in b })
        // Priced as the longest it has made (10 s), since it chooses the length and is paid by the second made.
        #expect(estimate["version"].string == "bytedance-seed/seed-audio-1-0" && abs((estimate["spend"].double ?? 0) - 0.025) < 1e-9)
        let done = try await f.finish(try await f.make(glass))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let sent = try #require(stub.bodies("audio/speech").first)
        #expect(sent["model"].string == "bytedance-seed/seed-audio-1-0" && sent["input"].string == "A sound effect, not speech: A glass shatters on a tile floor." && sent["voice"] == .null)
        let effectID = try #require(done.result?["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(effectID))
        let asset = try f.media.store.read().asset(record.assetID)
        // 6 s made, 4 s asked: cut to 4 with a fade. No cost came back, so the estimate is counted.
        #expect(record.kind == .soundEffect && record.version == "bytedance-seed/seed-audio-1-0" && abs(asset.duration.seconds - 4) < 0.05 && abs(record.spend - 0.025) < 1e-9)

        let door = try await f.finish(try await f.make(["kind": .string("soundEffect"), "ask": .string("A heavy wooden door creaks slowly open."), "seconds": .number(4)]))
        #expect(door.status == "completed", "\(door.error ?? "")")
        #expect(door.result?["note"].string == "Seed Audio 1.0 wouldn\u{2019}t take what was asked, so this used Lyria 3 Clip.")
        #expect(stub.bodies("chat/completions").first?["model"].string == "google/lyria-3-clip-preview")
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
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("An establishing shot of the ridge at dusk."), "seconds": .number(8), "sound": .bool(true)]
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
        // The yes covered about $3.52; a second $3.20 shot is more than the director agreed to.
        await expectCode("spend_over_question") { _ = try await f.make(approved) }

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
        #expect(services["services"].array?.first?["state"].string == "ready" && services["services"].array?.last?["service"].string == "local")
        #expect(services["limits"]["askAbovePerTurnover"].double == 5 && services["limits"]["stopAtPerMonth"].double == 50)
        #expect(abs((services["month"]["spent"].double ?? 0) - 50.1) < 1e-9 && abs((services["turnover"]["spent"].double ?? 0) - 6.4) < 1e-9)
        let kinds = services["kinds"].array ?? []
        // Balanced makes 720p for this Mac to sharpen; a Mac that can't sharpen makes the full 1080p.
        let made = MadeProcessing.sharpeningStatus(width: 1280, height: 720) == .unsupported ? "1080p" : "720p"
        #expect(kinds.first { $0["kind"].string == "shot" }?["price"].string == "About $0.20 a second at \(made)")
        #expect(services["quality"].string == "balanced")
        #expect(kinds.first { $0["kind"].string == "changedShot" }?["version"].string == "runway/aleph-2" && kinds.first { $0["kind"].string == "slowMotion" }?["service"].string == "local")
    }

    @Test func aPlanIsPricedOnceAndAskedAboutOnlyOverTheLimit() async throws {
        let stub = OpenRouterStub { _, _ in (500, Data(), [:]) }
        let f = try await MadeFixture.make(transport: stub.transport, key: nil); defer { f.media.cleanup() }
        let take = JSONValue.string(f.assetID)
        let steps: JSONValue = .array([
            .object(["kind": .string("still"), "ask": .string("The diner at dusk, neon on wet asphalt, 35 mm."), "references": .array([.object(["assetID": take, "at": .number(1)])]), "ways": .number(2)]),
            .object(["kind": .string("shot"), "ask": .string("Slow push in. Steam from the vent."), "seconds": .number(6), "first": .object(["assetID": take, "at": .number(2)])]),
            .object(["kind": .string("changedShot"), "ask": .string("Dusk sky with cloud. Keep everything else."), "from": .object(["assetID": take, "start": .number(0.5), "end": .number(2.5)])]),
            .object(["kind": .string("slowMotion"), "from": .object(["assetID": take, "start": .number(1), "end": .number(2)]), "factor": .number(2)]),
        ])
        let plan = try await f.call("direction_estimate", ["turnover": .string(f.turnover.id), "steps": steps])
        let priced = plan["steps"].array ?? []
        #expect(priced.map { $0["version"].string ?? "" } == ["google/gemini-3.1-flash-image", "google/veo-3.1", "runway/aleph-2", "local/frame-interpolation"])
        // Two stills at about 8¢, a silent 6 s shot at $0.20 a second, 2 s of Aleph at its 56¢ minimum, slow motion for nothing.
        #expect(abs((priced[1]["spend"].double ?? 0) - 1.20) < 1e-9 && abs((priced[2]["spend"].double ?? 0) - 0.56) < 1e-9 && priced[3]["spend"].double == 0)
        let total = try #require(plan["total"].double)
        #expect(abs(total - (0.0774 * 2 + 1.20 + 0.56)) < 1e-6 && plan["needsQuestion"].bool == false && plan["limit"].double == 5)
        // Nothing was sent and no key was needed to price it.
        #expect(stub.requests.isEmpty && f.ledger.isEmpty)

        // With a $1.00 limit the same plan needs one question.
        var tight = f; tight.overrides.limits = SpendLimits(askAbove: 1, stopAt: 50)
        let over = try await tight.call("direction_estimate", ["turnover": .string(f.turnover.id), "steps": steps])
        #expect(over["needsQuestion"].bool == true && over["message"].string?.contains("one spend question") == true)
        // A step that can't be made says which.
        await expectCode("invalid_arguments") { _ = try await f.call("direction_estimate", ["turnover": .string(f.turnover.id), "steps": .array([.object(["kind": .string("bridge"), "ask": .string("Car to door."), "seconds": .number(4), "first": .object(["assetID": take, "at": .number(0)])])])]) }
    }

    @Test func aBridgeSendsBothFramesAndNeedsAVersionThatTakesALastFrame() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let stub = videoStub(movie, cost: 0.8)
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        var catalog = MadeCatalog.builtIn; catalog.fetchedAt = Date().timeIntervalSince1970
        catalog.versions.append(MadeVersion(id: "runway/gen-4.5", name: "Gen-4.5", listing: .video, skus: ["cents_per_second_output": "12"], durations: [2, 3, 4, 5], resolutions: ["720p"], frames: ["first_frame"]))
        try JSONEncoder.direction.encode(catalog).write(to: try #require(f.overrides.catalog))
        let take = JSONValue.string(f.assetID)
        let bridge: [String: JSONValue] = ["kind": .string("bridge"), "ask": .string("The camera drifts from the car to the front door."), "seconds": .number(4),
                                           "first": .object(["assetID": take, "at": .number(0.5)]), "last": .object(["assetID": take, "at": .number(2.5)])]
        // The editor doesn't name versions; Direction picks one that takes a last frame.
        await expectCode("invalid_arguments") { _ = try await f.make(bridge.merging(["version": .string("runway/gen-4.5")]) { _, b in b }) }
        await expectCode("invalid_arguments") { _ = try await f.make(bridge.merging(["last": .null]) { _, b in b }) }
        let done = try await f.finish(try await f.make(bridge))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let submit = try #require(stub.bodies("/videos").first)
        #expect(submit["model"].string == "google/veo-3.1" && submit["duration"].double == 4 && submit["generate_audio"].bool == false)
        #expect(submit["frame_images"].array?.map { $0["frame_type"].string ?? "" } == ["first_frame", "last_frame"])
        let madeID = try #require(done.result?["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(madeID))
        #expect(record.kind == .bridge && record.first == MadeFrame(assetID: f.assetID, at: 0.5) && record.last == MadeFrame(assetID: f.assetID, at: 2.5) && record.spend == 0.8)
    }

    /// A version that turns a request down for what's in it hands it to the next-best one, and the
    /// result says so (made-media.md › Choosing a version).
    @Test func eachWayIsCheckedByBothVersionsAndEitherCanStandIn() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let lunaAsked = Counter()
        let stub = OpenRouterStub { r, n in
            let path = r.url!.path
            if path.hasSuffix("/api/alpha/decisions") {
                let model = (try? JSONDecoder().decode(JSONValue.self, from: r.httpBody ?? Data()))?["model"].string
                // Luna can't answer its first request and finds the three-quarter frame broken after that
                // (0:02 of the 3 s fixture); Jev finds every way clean.
                if model == Decisions.luna, lunaAsked.next() == 0 { return (502, data(.object(["error": .object(["message": .string("Provider returned error")])])), [:]) }
                let broken = model == Decisions.luna
                let answers: [String: JSONValue] = ["look1": "clean", "look2": "clean", "look3": "clean", "look4": broken ? "broken" : "clean", "look5": "clean", "morph": "moves", "same": "same", "asked": "yes"].mapValues { .object(["type": .string("choice"), "choice": .string($0)]) }
                return (200, data(.object(["model": .string(model ?? ""), "answers": .object(answers), "usage": .object(["cost": .number(broken ? 0.002 : 0.0004)])])), [:])
            }
            if r.httpMethod == "POST" && path.hasSuffix("/videos") { return (202, data(.object(["id": .string("vid-\(n)"), "status": .string("pending")])), [:]) }
            if path.hasSuffix("/content") { return (200, movie, ["Content-Type": "video/mp4"]) }
            return (200, data(.object(["id": .string("vid"), "status": .string("completed"), "usage": .object(["cost": .number(0.4)])])), [:])
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("Static camera. Light moves across the wall."), "seconds": .number(4), "ways": .number(2), "first": .object(["assetID": .string(f.assetID), "at": .number(1)])]
        let done = try await f.finish(try await f.make(shot))
        #expect(done.status == "completed", "\(done.error ?? "")")

        // Each way goes to both versions: five frames inline, each a JPEG they'll take (256 to 1,568 px a side).
        let sent = stub.bodies("/api/alpha/decisions")
        #expect(sent.map { $0["model"].string ?? "" }.sorted() == [Decisions.luna, Decisions.luna, Decisions.jev, Decisions.jev])
        for body in sent {
            let images = (body["state"].array ?? []).compactMap { $0["image_url"]["url"].string }
            #expect(images.count == 5 && body["questions"]["asked"] != .null && body["assets"] == .null)
            for url in images {
                let jpeg = try #require(Data(base64Encoded: String(url.dropFirst("data:image/jpeg;base64,".count))))
                let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
                let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
                let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
                #expect(min(w, h) >= 256 && max(w, h) <= 1568, "a frame is \(w) × \(h)")
            }
        }
        // Luna's answer is the check where it gave one; where it couldn't, Jev's stands in.
        let checks = try #require(done.result?["made"].array).map { $0["check"] }
        #expect(checks.compactMap { $0["verdict"].string }.sorted() == ["broken", "clean"])
        #expect(checks.contains { $0["findings"].array?.first?.string == "Something looks broken at 0:02." })
        let records = try f.media.store.madeRecords()
        let byLuna = try #require(records.first { $0.check?.version == Decisions.luna }), byJev = try #require(records.first { $0.check?.version == Decisions.jev })
        #expect(byLuna.check?.short == "Looks broken at 0:02" && byLuna.otherChecks?.map(\.version) == [Decisions.jev] && byLuna.otherChecks?.first?.verdict == .clean)
        #expect(byJev.check?.verdict == .clean && byJev.otherChecks == nil)
        // Every answer's spend is in the month, under Checking, by the version that gave it.
        #expect(f.ledger.filter { $0.kind == .checking }.map(\.version).sorted() == [Decisions.luna, Decisions.jev, Decisions.jev])
        #expect(f.ledger.filter { $0.kind == .shot }.reduce(0) { $0 + $1.amount } == 0.8)
    }

    @Test func aVersionThatTurnsItDownHandsItToTheNext() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let refusal = data(.object(["error": .object(["code": .string("InputImageSensitiveContentDetected.PrivacyInformation"), "message": .string("The request failed because the input image 'content[1]' may contain real person.")])]))
        let stub = OpenRouterStub { r, n in
            let path = r.url!.path
            if r.httpMethod == "POST" && path.hasSuffix("/videos") {
                let model = (try? JSONDecoder().decode(JSONValue.self, from: r.httpBody ?? Data()))?["model"].string
                return model == "bytedance/seedance-2.5" ? (400, refusal, [:]) : (202, data(.object(["id": .string("vid-\(n)"), "status": .string("pending")])), [:])
            }
            if path.hasSuffix("/content") { return (200, movie, ["Content-Type": "video/mp4"]) }
            return (200, data(.object(["id": .string("vid"), "status": .string("completed"), "usage": .object(["cost": .number(0.65)])])), [:])
        }
        var f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        f.overrides.quality = .best
        f.overrides.refusals = f.media.directory.appendingPathComponent("refusals.json")
        var catalog = MadeCatalog.builtIn; catalog.fetchedAt = Date().timeIntervalSince1970
        catalog.versions += [MadeVersion(id: "bytedance/seedance-2.5", name: "Seedance 2.5", listing: .video, skus: ["duration_seconds": "0.23"], durations: Array(4...30), resolutions: ["720p"], frames: ["first_frame", "last_frame"]),
                             MadeVersion(id: "minimax/hailuo-3", name: "H3", listing: .video, skus: ["duration_seconds": "0.13"], durations: Array(5...15), resolutions: ["2K"], frames: ["first_frame", "last_frame"])]
        try JSONEncoder.direction.encode(catalog).write(to: try #require(f.overrides.catalog))
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("Hands typing at the desk."), "seconds": .number(5), "first": .object(["assetID": .string(f.assetID), "at": .number(1)])]
        // The fixture's frames show no one, so the best-rated version is tried first.
        #expect(try await f.call("direction_estimate", ["turnover": .string(f.turnover.id), "steps": .array([.object(shot)])])["steps"].array?.first?["version"].string == "bytedance/seedance-2.5")
        let done = try await f.finish(try await f.make(shot))
        #expect(done.status == "completed", "\(done.error ?? "")")
        #expect(stub.bodies("/videos").map { $0["model"].string ?? "" } == ["bytedance/seedance-2.5", "minimax/hailuo-3"])
        #expect(done.result?["note"].string == "Seedance 2.5 wouldn\u{2019}t take a frame with a person in it, so this used H3.")
        let madeID = try #require(done.result?["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(madeID))
        #expect(record.version == "minimax/hailuo-3" && record.spend == 0.65)
        // It said a person, so it's skipped for a week when a frame shows one.
        #expect(OpenRouter.$overrides.withValue(f.overrides) { MadeRefusals.refusedPeople() } == ["bytedance/seedance-2.5"])
    }

    /// The next version after a refusal usually costs more: it's held to the limits like the first.
    @Test func aDearerVersionAfterARefusalStopsAtTheLimit() async throws {
        let refusal = data(.object(["error": .object(["message": .string("The request was flagged by moderation.")])]))
        let stub = OpenRouterStub { r, _ in
            if r.httpMethod == "POST" && r.url!.path.hasSuffix("/videos") { return (400, refusal, [:]) }
            return (404, Data(), [:])
        }
        var f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        f.overrides.quality = .best
        f.overrides.refusals = f.media.directory.appendingPathComponent("refusals.json")
        var catalog = MadeCatalog.builtIn; catalog.fetchedAt = Date().timeIntervalSince1970
        catalog.versions += [MadeVersion(id: "bytedance/seedance-2.5", name: "Seedance 2.5", listing: .video, skus: ["duration_seconds": "0.23"], durations: Array(4...30), resolutions: ["720p"], frames: ["first_frame", "last_frame"]),
                             MadeVersion(id: "minimax/hailuo-3", name: "H3", listing: .video, skus: ["duration_seconds": "1.2"], durations: Array(5...15), resolutions: ["2K"], frames: ["first_frame", "last_frame"])]
        try JSONEncoder.direction.encode(catalog).write(to: try #require(f.overrides.catalog))
        // $1.15 at Seedance is under the $5.00 limit; H3 would be $6.00.
        let done = try await f.finish(try await f.make(["kind": .string("shot"), "ask": .string("Hands typing at the desk."), "seconds": .number(5)]))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let result = try #require(done.result)
        #expect(result["status"].string == "spend_over_limit" && abs((result["estimate"].double ?? 0) - 6) < 1e-9 && result["versionName"].string == "H3")
        #expect(result["note"].string == "Seedance 2.5 wouldn\u{2019}t take what was asked. H3 would make it instead.")
        // Only the refused request went out, and the hold went back.
        #expect(stub.bodies("/videos").map { $0["model"].string ?? "" } == ["bytedance/seedance-2.5"])
        #expect(try f.ledger.isEmpty && f.media.store.madeRecords().isEmpty)
    }

    /// Once a shot is sent it's paid for: stopping it or losing it keeps the charge. Only OpenRouter saying
    /// it couldn't make it gives the hold back, unless it charged anyway.
    @Test func aShotThatWasSentKeepsItsChargeWhenStoppedOrLost() async throws {
        let mode = Mode("making")
        let stub = OpenRouterStub { r, n in
            if r.httpMethod == "POST" && r.url!.path.hasSuffix("/videos") { return (202, data(.object(["id": .string("vid-\(n)"), "status": .string("pending")])), [:]) }
            switch mode.value {
            case "lost": return (502, data(.object(["error": .object(["message": .string("Bad gateway")])])), [:])
            case "charged": return (200, data(.object(["id": .string("vid"), "status": .string("failed"), "error": .string("Content policy"), "usage": .object(["cost": .number(0.3)])])), [:])
            default: return (200, data(.object(["id": .string("vid"), "status": .string("in_progress")])), [:])
            }
        }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("A ridge at dusk."), "seconds": .number(4)]

        // Stopped while it's being made: the job is the runtime's own, so it can be cancelled, and the $0.80 stays.
        let job = try await f.make(shot)
        let id = try #require(job["id"].string)
        for _ in 0..<200 {
            if (try await f.call("direction_job", ["jobID": .string(id)]))["phase"].string?.contains("making the shot") == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await f.call("direction_cancel_job", ["jobID": .string(id)])["cancellationRequested"].bool == true)
        #expect(try await f.finish(job).status == "cancelled")
        #expect(f.ledger.map(\.spend) == [0.8])

        // Lost while it's being made: the polls fail, and the $0.80 still stays.
        mode.value = "lost"
        #expect(try await f.finish(try await f.make(shot)).status == "failed")
        #expect(f.ledger.map(\.spend) == [0.8, 0.8])

        // OpenRouter says it failed and charged 30¢: that's what's kept.
        mode.value = "charged"
        let failed = try await f.finish(try await f.make(shot))
        #expect(failed.status == "failed" && failed.error?.contains("Content policy") == true)
        #expect(f.ledger.map(\.spend) == [0.8, 0.8, 0.3])
    }

    /// A version OpenRouter lists no price for would pass every check at $0; the director says yes first.
    @Test func aVersionWithNoPriceNeedsTheDirectorsYes() async throws {
        let stub = OpenRouterStub { _, _ in (500, Data(), [:]) }
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        var catalog = MadeCatalog.builtIn; catalog.fetchedAt = Date().timeIntervalSince1970
        catalog.versions.removeAll { $0.id == "google/veo-3.1" }
        catalog.versions.append(MadeVersion(id: "someone/new-shots", name: "New Shots", listing: .video, durations: Array(4...10), resolutions: ["1080p"], frames: ["first_frame"]))
        try JSONEncoder.direction.encode(catalog).write(to: try #require(f.overrides.catalog))
        let shot: [String: JSONValue] = ["kind": .string("shot"), "ask": .string("A ridge at dusk."), "seconds": .number(4)]
        let plan = try await f.call("direction_estimate", ["turnover": .string(f.turnover.id), "steps": .array([.object(shot)])])
        #expect(plan["steps"].array?.first?["version"].string == "someone/new-shots" && plan["steps"].array?.first?["priced"].bool == false)
        #expect(plan["needsQuestion"].bool == true && plan["unpricedSteps"].double == 1 && plan["message"].string?.contains("no price") == true)
        let over = try await f.make(shot)
        #expect(over["status"].string == "spend_over_limit" && over["priced"].bool == false && over["message"].string?.contains("lists no price for New Shots") == true)
        #expect(stub.requests.isEmpty && f.ledger.isEmpty)
    }

    @Test func aChangedShotSendsTheRangeItself() async throws {
        let movie = try Data(contentsOf: try await MediaFixture.make().source)
        let stub = videoStub(movie, cost: 0.56)
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let change: [String: JSONValue] = ["kind": .string("changedShot"), "ask": .string("Replace the red wall with dusk sky. Keep the square exactly as it moves."), "from": .object(["assetID": .string(f.assetID), "start": .number(0.5), "end": .number(2.5)])]
        let estimate = try await f.make(change.merging(["estimateOnly": .bool(true)]) { _, b in b })
        #expect(abs((estimate["spend"].double ?? 0) - 0.56) < 1e-9 && estimate["version"].string == "runway/aleph-2" && estimate["seconds"].double == 2)
        await expectCode("invalid_arguments") { _ = try await f.make(change.merging(["from": .object(["assetID": .string(f.assetID), "start": .number(1)])]) { _, b in b }) }
        // A changed shot keeps the take's own sound, so asking for sound doesn't rule out a version that makes none.
        var catalog = MadeCatalog.builtIn; catalog.fetchedAt = Date().timeIntervalSince1970
        if let i = catalog.versions.firstIndex(where: { $0.id == "runway/aleph-2" }) { catalog.versions[i].makesSound = false }
        try JSONEncoder.direction.encode(catalog).write(to: try #require(f.overrides.catalog))
        #expect(try await f.make(change.merging(["estimateOnly": .bool(true), "sound": .bool(true)]) { _, b in b })["version"].string == "runway/aleph-2")

        let done = try await f.finish(try await f.make(change))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let submit = try #require(stub.bodies("/videos").first)
        #expect(submit["model"].string == "runway/aleph-2" && submit["prompt"].string == change["ask"]?.string && submit["frame_images"] == .null && submit["duration"] == .null)
        let reference = try #require(submit["input_references"].array?.first)
        #expect(reference["type"].string == "video_url")
        let url = try #require(reference["video_url"]["url"].string)
        #expect(url.hasPrefix("data:video/mp4;base64,"))
        // The range itself, about 2 s, without sound.
        let sent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4"); defer { try? FileManager.default.removeItem(at: sent) }
        try Data(base64Encoded: String(url.dropFirst("data:video/mp4;base64,".count)))!.write(to: sent)
        let probed = try await MediaInspector.inspect(url: sent, thumbnailDirectory: nil)
        #expect(abs(probed.duration.seconds - 2) < 0.1 && probed.audio.isEmpty && !probed.video.isEmpty)
        let madeID = try #require(done.result?["assetID"].string)
        let record = try #require(try f.media.store.madeRecord(madeID))
        #expect(record.kind == .changedShot && record.from == MadeFrom(assetID: f.assetID, start: 0.5, end: 2.5) && record.versionName == "Aleph 2.0")
    }

    @Test func anExtendedShotStartsOnTheTakesLastFrameAndDropsTheRepeat() async throws {
        let media = try await MediaFixture.make(); defer { media.cleanup() }
        let movie = try Data(contentsOf: media.source)
        let stub = videoStub(movie, cost: 0.8)
        let f = try await MadeFixture.make(transport: stub.transport); defer { f.media.cleanup() }
        let done = try await f.finish(try await f.make(["kind": .string("extension"), "ask": .string("The square keeps drifting right. Camera holds."), "seconds": .number(4),
                                                        "from": .object(["assetID": .string(f.assetID), "end": .number(2), "side": .string("tail")])]))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let frame = try #require(stub.bodies("/videos").first?["frame_images"].array?.first)
        #expect(frame["frame_type"].string == "first_frame")
        let madeID = try #require(done.result?["assetID"].string)
        let made = try f.media.store.read().asset(madeID)
        let source = try f.media.store.read().asset(f.assetID)
        let fps = try #require(source.video.first?.frameRate)
        // The downloaded clip less its first frame.
        #expect(abs(made.duration.seconds - (source.duration.seconds - 1 / fps)) < 0.5 / fps, "\(made.duration.seconds)")
        let record = try #require(try f.media.store.madeRecord(made.id))
        #expect(record.kind == .extension && record.from?.side == "tail" && record.file.hasSuffix(".mov"))
    }

    @Test func slowMotionIsMadeOnThisMacWithoutAKeyOrSpend() async throws {
        let stub = OpenRouterStub { _, _ in (500, Data(), [:]) }
        let f = try await MadeFixture.make(transport: stub.transport, key: nil); defer { f.media.cleanup() }
        let done = try await f.finish(try await f.make(["kind": .string("slowMotion"), "from": .object(["assetID": .string(f.assetID), "start": .number(1), "end": .number(2)]), "factor": .number(2)]))
        #expect(done.status == "completed", "\(done.error ?? "")")
        let madeID = try #require(done.result?["assetID"].string)
        let made = try f.media.store.read().asset(madeID)
        #expect(abs(made.duration.seconds - 2) < 0.15 && made.audio.isEmpty, "\(made.duration.seconds)")
        let record = try #require(try f.media.store.madeRecord(made.id))
        #expect(record.isLocal && record.spend == 0 && record.factor == 2 && record.serviceName == "This Mac")
        #expect(stub.requests.isEmpty && f.ledger.isEmpty)
        // The cut is 320 × 180, as big as the take: nothing to sharpen.
        let sharpen: [String: JSONValue] = ["kind": .string("upscale"), "from": .object(["assetID": .string(f.assetID), "start": .number(0), "end": .number(1)])]
        await expectCode("nothing_to_sharpen") { _ = try await f.make(sharpen) }

        // In a 640 × 360 cut, this Mac sharpens it with Apple's super resolution, when its files are here (never fetched in tests).
        guard MadeProcessing.sharpeningStatus(width: 320, height: 180) == .ready else { return }
        var format = EditOperation("format"); format.width = 640; format.height = 360
        _ = try f.media.store.apply(.init(baseEditRevision: f.media.store.revision(), operations: [format]))
        let sharp = try await f.finish(try await f.make(sharpen))
        #expect(sharp.status == "completed", "\(sharp.error ?? "")")
        let sharpID = try #require(sharp.result?["assetID"].string)
        let sharpened = try f.media.store.read().asset(sharpID)
        #expect(sharpened.video.first?.width == 640 && sharpened.video.first?.height == 360 && abs(sharpened.duration.seconds - 1) < 0.1)
        let sharpRecord = try #require(try f.media.store.madeRecord(sharpID))
        #expect(sharpRecord.kind == .upscale && sharpRecord.sharpenedFrom == "320 \u{00D7} 180" && sharpRecord.isLocal && stub.requests.isEmpty)
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
        await expectCode("invalid_arguments") { _ = try await f.make(["kind": .string("music"), "ask": .string("Piano."), "seconds": .number(10), "version": .string("nobody/nothing")]) }
        // OpenRouter turns down a last frame without a first one: said before anything is spent.
        await expectCode("invalid_arguments") { _ = try await f.make(["kind": .string("shot"), "ask": .string("Push in."), "seconds": .number(5), "last": .object(["assetID": .string(f.assetID), "at": .number(1)])]) }
        await expectCode("feedback_not_found") { _ = try await f.call("direction_make", ["kind": .string("music"), "ask": .string("Piano."), "seconds": .number(10), "note": .string("note-x"), "turnover": .string(f.turnover.id)]) }
    }
}

/// A video service that takes any job, finishes it on the first poll, and sends `movie`.
private func videoStub(_ movie: Data, cost: Double) -> OpenRouterStub {
    OpenRouterStub { r, n in
        let path = r.url!.path
        if r.httpMethod == "POST" && path.hasSuffix("/videos") { return (202, data(.object(["id": .string("vid-\(n)"), "status": .string("pending")])), [:]) }
        if path.hasSuffix("/content") { return (200, movie, ["Content-Type": "video/mp4"]) }
        return (200, data(.object(["id": .string("vid"), "status": .string("completed"), "usage": .object(["cost": .number(cost)])])), [:])
    }
}

/// What a stub answers, changed between requests.
private final class Mode: @unchecked Sendable {
    private let lock = NSLock(); private var current: String
    init(_ value: String) { current = value }
    var value: String { get { lock.withLock { current } } set { lock.withLock { current = newValue } } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> Int { lock.withLock { defer { n += 1 }; return n } }
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
