import Testing
import Foundation
@preconcurrency import AVFoundation
import DirectionCore
import DirectionMedia
@testable import DirectionTools

/// The paid trials of made-media versions (docs/speed-and-quality.md › Still to test), run against OpenRouter
/// with the director's key. Off unless DIRECTION_LIVE_MADE names a folder for the results; run them with
/// scripts/live-made.sh, which asks for the key and never prints it. DIRECTION_LIVE_MADE_ESTIMATE=1 prices every
/// trial without sending anything (no key needed).
///
/// Each trial goes through the real direction_make on a film of its own, the version pinned
/// (OpenRouter.Overrides.version): routing, the request, waiting, refusals, importing and Direction's check of
/// what came back are as the app does them. Whether a version takes a take as video is sent as a changed shot
/// sends it. The film, every made file, three frames of each shot, the spend and `results.json` land in the folder.
struct LiveMadeTrials {
    static let env = ProcessInfo.processInfo.environment
    static let folder = env["DIRECTION_LIVE_MADE"].map { URL(fileURLWithPath: $0) }

    @Test(.enabled(if: LiveMadeTrials.folder != nil), .timeLimit(.minutes(90)))
    func trials() async throws {
        let run = try await Trials.start(folder: Self.folder!, estimateOnly: Self.env["DIRECTION_LIVE_MADE_ESTIMATE"] == "1")
        // Round 1 (8 Nov 2026) is the first set; round 2 asks what round 1 couldn't answer.
        if Self.env["DIRECTION_LIVE_MADE_ROUND"] == "2" { try await run.round2() } else { try await run.all() }
    }
}

private actor Trials {
    let folder: URL, estimateOnly: Bool, budget: Double, only: Set<String>?
    let store: ProjectStore, runtime: ToolRuntime, overrides: OpenRouter.Overrides
    let note: String, turnover: String, camera: String, desk: String, deskURL: URL
    /// Planned is every trial's price; committed holds each running one's price until it's paid, so trials running
    /// at once can't pass the budget together.
    var results: [String: JSONValue] = [:], planned = 0.0, spent = 0.0, committed = 0.0

    init(folder: URL, estimateOnly: Bool, budget: Double, only: Set<String>?, store: ProjectStore, runtime: ToolRuntime, overrides: OpenRouter.Overrides, note: String, turnover: String, camera: String, desk: String, deskURL: URL) {
        self.folder = folder; self.estimateOnly = estimateOnly; self.budget = budget; self.only = only; self.store = store; self.runtime = runtime
        self.overrides = overrides; self.note = note; self.turnover = turnover; self.camera = camera; self.desk = desk; self.deskURL = deskURL
    }

    /// The trials' own film: the director on camera and at the desk, cut at 1280 × 720 so nothing made at Balanced
    /// is sharpened (which would fetch Apple's sharpening files).
    static func start(folder: URL, estimateOnly: Bool) async throws -> Trials {
        let env = LiveMadeTrials.env
        guard let cameraPath = env["DIRECTION_LIVE_MADE_CAMERA"], let deskPath = env["DIRECTION_LIVE_MADE_DESK"] else {
            throw DirectionError("live_made", "Set DIRECTION_LIVE_MADE_CAMERA and DIRECTION_LIVE_MADE_DESK to two takes with the director in them.")
        }
        let key = env["DIRECTION_OPENROUTER_KEY"].flatMap { $0.isEmpty ? nil : $0 }
        guard estimateOnly || key != nil else { throw DirectionError("live_made", "No key: run scripts/live-made.sh.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let film = folder.appendingPathComponent("Trials.direction")
        if FileManager.default.fileExists(atPath: film.path) { try FileManager.default.trashItem(at: film, resultingItemURL: nil) }
        let store = try ProjectStore.create(at: film, name: "Made trials")
        let runtime = try ToolRuntime(store: store)
        var ids: [String] = []
        for path in [cameraPath, deskPath] {
            let out = try await runtime.invoke("direction_import", arguments: .object(["path": .string(path), "append": .bool(true)]))
            ids.append(try out.value["asset"]["id"].decode(String.self))
        }
        var format = EditOperation("format"); format.width = 1280; format.height = 720
        _ = try store.apply(.init(baseEditRevision: store.revision(), operations: [format]))
        let p = try store.read()
        let note = try store.addComment(text: "Trials of made versions.", sequenceID: nil, revision: p.editRevision, time: .init(seconds: 1), extra: NoteFields(kind: .picture))
        let turnover = try store.turnOver(noteIDs: [note.id], latitude: .faithful, waitForOK: false, cutID: nil, sequenceID: nil)
        let overrides = OpenRouter.Overrides(key: key, service: "dev.direction.openrouter.live-trials", ledger: folder.appendingPathComponent("spend.json"),
                                             catalog: folder.appendingPathComponent("openrouter-models.json"), limits: SpendLimits(askAbove: 1_000, stopAt: 1_000),
                                             quality: .balanced, refusals: folder.appendingPathComponent("refusals.json"))
        let budget = Double(env["DIRECTION_LIVE_MADE_BUDGET"] ?? "") ?? 12
        let only = env["DIRECTION_LIVE_MADE_ONLY"].map { Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }) }
        return Trials(folder: folder, estimateOnly: estimateOnly, budget: budget, only: only, store: store, runtime: runtime, overrides: overrides,
                      note: note.id, turnover: turnover.id, camera: ids[0], desk: ids[1], deskURL: URL(fileURLWithPath: deskPath))
    }

    // MARK: The trials

    func all() async throws {
        let catalog = await OpenRouter.$overrides.withValue(overrides) { await MadeVersions.load(refresh: true) }
        let listed = Set(catalog.versions.map(\.id))
        let seedAudio = catalog.versions.first { $0.id.contains("seed-audio") }?.id
        results["catalog"] = .object([
            "versions": .number(Double(catalog.versions.count)),
            "seedAudio": seedAudio.map(JSONValue.string) ?? .null,
            "missing": .array(Self.wanted.filter { !listed.contains($0) }.map(JSONValue.string)),
        ])

        let cameraFrame: JSONValue = .object(["assetID": .string(camera), "at": .number(25)])
        let deskFrame: JSONValue = .object(["assetID": .string(desk), "at": .number(20)])

        // 6. GPT Image: what Direction asks for, gets and pays. The Flare still is the reference in 5.
        let mug = "A bright red ceramic coffee mug with a white lightning bolt painted on its side, on a plain white table, soft studio light, product photo."
        for (id, version) in [("6-flare", "openai/gpt-image-2.6-flare"), ("6-sunburst", "openai/gpt-image-2.6-sunburst")] {
            await make(id, test: 6, version: version, ["kind": .string("still"), "ask": .string(mug)])
        }

        var jobs: [(String, @Sendable () async -> Void)] = []
        // 1. Gemini Omni 1.2 and a real person: a shot from a frame of the director.
        jobs.append(("1-omni-shot", { await self.make("1-omni-shot", test: 1, version: "google/gemini-omni-1.2-flash", ["kind": .string("shot"), "seconds": .number(5), "first": cameraFrame,
            "ask": .string("He looks up from his phone toward the camera and gives a small smile. The camera holds still.")]) }))
        // 1 and 2. A take sent as video to versions that make shots, as a changed shot sends it.
        let change = "Warm late-afternoon sunlight now comes through a window at the left, lighting his face and the wall behind him. Keep him and his movements exactly as they are."
        for (id, version) in [("2-omni-video", "google/gemini-omni-1.2-flash"), ("2-hailuo3-video", "minimax/hailuo-3"), ("2-seedance-video", "bytedance/seedance-2.5")] {
            jobs.append((id, { await self.videoInput(id, version: version, ask: change, start: 18, end: 23) }))
        }
        // 3. Bridges with the director at both ends.
        let bridge = "He moves naturally from the first pose to the last. The camera holds still and the light stays as it is."
        for (id, version) in [("3-bridge-hailuo3max", "minimax/hailuo-3-max"), ("3-bridge-wan3", "alibaba/wan-3.0"), ("3-bridge-omni", "google/gemini-omni-1.2-flash"), ("3-bridge-kling3pro", "kwaivgi/kling-v3.0-pro")] {
            jobs.append((id, { await self.make(id, test: 3, version: version, ["kind": .string("bridge"), "seconds": .number(5), "ask": .string(bridge),
                "first": .object(["assetID": .string(self.camera), "at": .number(5)]), "last": .object(["assetID": .string(self.camera), "at": .number(45)])]) }))
        }
        // 4. Hailuo 3 Max on what failed on Hailuo 3: the orbit and the wall turning into a cockpit.
        jobs.append(("4-orbit", { await self.make("4-orbit", test: 4, version: "minimax/hailuo-3-max", ["kind": .string("shot"), "seconds": .number(5), "first": deskFrame,
            "ask": .string("Camera smoothly orbits around the seated speaker to behind him while slowly pulling out, revealing his desk. He continues talking naturally. Preserve the room and person.")]) }))
        jobs.append(("4-cockpit", { await self.make("4-cockpit", test: 4, version: "minimax/hailuo-3-max", ["kind": .string("shot"), "seconds": .number(5), "first": deskFrame,
            "ask": .string("The wall behind him breaks away and transforms into a realistic spacecraft cockpit with broad windows looking into space. He remains seated, talking.")]) }))
        // 5. A reference beside a first frame: does the mug reach the shot?
        jobs.append(("5-reference", {
            let reference = await self.madeAsset("6-flare")
            await self.make("5-reference", test: 5, version: "minimax/hailuo-3-max", ["kind": .string("shot"), "seconds": .number(5), "first": deskFrame,
                "references": reference.map { .array([.string($0)]) } ?? .array([]),
                "ask": .string("He keeps talking to camera. On the desk in front of him sits the red mug with the white lightning bolt from the reference.")])
        }))
        // 7. Sound effects: Seed Audio against Lyria 3 Clip, the same five.
        let effects = ["A heavy wooden door creaks slowly open.", "A glass shatters on a tile floor.", "A single clap of thunder, then a long rolling rumble.",
                       "Footsteps walking on gravel.", "A camera shutter clicks once."]
        let lyria = catalog.versions.first { $0.listing == .audio && $0.id.hasPrefix("google/lyria-3-clip") }?.id ?? "google/lyria-3-clip-preview"
        for (n, effect) in effects.enumerated() {
            jobs.append(("7-lyria-\(n + 1)", { await self.make("7-lyria-\(n + 1)", test: 7, version: lyria, ["kind": .string("soundEffect"), "seconds": .number(4), "ask": .string(effect)]) }))
            // Seed Audio is listed for speech: it's asked as a voice is, the effect in words.
            jobs.append(("7-seed-\(n + 1)", { await self.speechEffect("7-seed-\(n + 1)", version: seedAudio ?? "bytedance-seed/seed-audio-1-0", effect: effect) }))
        }
        // Four at once: each waits minutes on OpenRouter, not on this Mac.
        await withTaskGroup(of: Void.self) { group in
            var queue = jobs[...]
            for _ in 0..<4 { if let next = queue.popFirst() { group.addTask { await next.1() } } }
            while await group.next() != nil { if let next = queue.popFirst() { group.addTask { await next.1() } } }
        }
        // Direction's own record of the spend, the checks and anything paid for that then failed included.
        let ledger = OpenRouter.$overrides.withValue(overrides) { SpendLedger.entries() }.reduce(0.0) { $0 + ($1.spend ?? $1.estimate) }
        results["total"] = .object(["planned": .number(planned), "spent": .number(spent), "ledger": .number(ledger), "budget": .number(budget), "estimateOnly": .bool(estimateOnly)])
        try save()
        print("LIVE-MADE planned $\(String(format: "%.2f", planned)) spent $\(String(format: "%.2f", spent)) → \(folder.path)/results.json")
    }

    static let wanted = ["openai/gpt-image-2.6-flare", "openai/gpt-image-2.6-sunburst", "google/gemini-omni-1.2-flash", "minimax/hailuo-3", "minimax/hailuo-3-max",
                         "bytedance/seedance-2.5", "alibaba/wan-3.0", "kwaivgi/kling-v3.0-pro", "google/lyria-3-clip-preview", "bytedance-seed/seed-audio-1-0"]

    // MARK: Round 2

    /// What round 1 left open (docs/speed-and-quality.md › Still to test), through Direction's own request path
    /// with its fixes: Omni and a person now that it isn't asked for silence, the changing versions with a take
    /// sent as data, references beside a first frame, what a still and a Lyria clip cost, and sound effects as
    /// Direction now makes them (Seed Audio, Lyria for what it turns down).
    func round2() async throws {
        let catalog = await OpenRouter.$overrides.withValue(overrides) { await MadeVersions.load(refresh: true) }
        let wanted = ["google/gemini-omni-1.2-flash", "black-forest-labs/flux-video-edit", "runway/aleph-2", "minimax/hailuo-3", "openai/gpt-image-2.6-flare", "bytedance-seed/seed-audio-1-0"]
        results["catalog"] = .object(["versions": .number(Double(catalog.versions.count)), "missing": .array(wanted.filter { id in !catalog.versions.contains { $0.id == id } }.map(JSONValue.string))])
        let deskFrame: JSONValue = .object(["assetID": .string(desk), "at": .number(20)])

        // 4 (cost). A still, its cost read back; it's the reference in 3.
        await make("r2-6-still", test: 6, version: "openai/gpt-image-2.6-flare", ["kind": .string("still"),
            "ask": .string("A bright red ceramic coffee mug with a white lightning bolt painted on its side, on a plain white table, soft studio light, product photo.")])

        var jobs: [(String, @Sendable () async -> Void)] = []
        // 1. Gemini Omni 1.2 and a real person, asked without the sound setting; its sound comes off.
        jobs.append(("r2-1-omni-shot", { await self.make("r2-1-omni-shot", test: 1, version: "google/gemini-omni-1.2-flash", ["kind": .string("shot"), "seconds": .number(5),
            "first": .object(["assetID": .string(self.camera), "at": .number(25)]),
            "ask": .string("The person looks up from the phone toward the camera and gives a small smile. The camera holds still.")]) }))
        // 2. The changing versions with a take sent as data, as every changed shot is sent: 2 s each.
        let change = "Warm late-afternoon sunlight now comes through a window at the left, lighting the person's face and the wall behind them. Keep the person and their movements exactly as they are."
        for (id, version) in [("r2-2-flux-edit", "black-forest-labs/flux-video-edit"), ("r2-2-aleph", "runway/aleph-2")] {
            jobs.append((id, { await self.make(id, test: 2, version: version, ["kind": .string("changedShot"), "ask": .string(change),
                "from": .object(["assetID": .string(self.desk), "start": .number(18), "end": .number(20)])]) }))
        }
        // 3. A reference beside a first frame, on a version listed with a price for references.
        jobs.append(("r2-3-reference", {
            let reference = await self.madeAsset("r2-6-still")
            await self.make("r2-3-reference", test: 5, version: "minimax/hailuo-3", ["kind": .string("shot"), "seconds": .number(5), "first": deskFrame,
                "references": reference.map { .array([.string($0)]) } ?? .array([]),
                "ask": .string("The person keeps talking to camera. On the desk in front of them sits the red mug with the white lightning bolt from the reference.")])
        }))
        // 4 (cost) and 7. Sound as Direction now makes it, the version not pinned: two effects (the door was turned
        // down in round 1) and a Lyria clip, its cost read back.
        for (id, ask) in [("r2-7-door", "A heavy wooden door creaks slowly open."), ("r2-7-rain", "Steady rain on a window pane.")] {
            jobs.append((id, { await self.make(id, test: 7, version: nil, ["kind": .string("soundEffect"), "seconds": .number(4), "ask": .string(ask)]) }))
        }
        jobs.append(("r2-7-music", { await self.make("r2-7-music", test: 6, version: nil, ["kind": .string("music"), "seconds": .number(10),
            "ask": .string("A short, warm acoustic guitar sting, two bars, ending on a held chord.")]) }))
        await withTaskGroup(of: Void.self) { group in
            var queue = jobs[...]
            for _ in 0..<4 { if let next = queue.popFirst() { group.addTask { await next.1() } } }
            while await group.next() != nil { if let next = queue.popFirst() { group.addTask { await next.1() } } }
        }
        let ledger = OpenRouter.$overrides.withValue(overrides) { SpendLedger.entries() }.reduce(0.0) { $0 + ($1.spend ?? $1.estimate) }
        results["total"] = .object(["planned": .number(planned), "spent": .number(spent), "ledger": .number(ledger), "budget": .number(budget), "estimateOnly": .bool(estimateOnly)])
        try save()
        print("LIVE-MADE planned $\(String(format: "%.2f", planned)) spent $\(String(format: "%.2f", spent)) → \(folder.path)/results.json")
    }

    // MARK: One trial

    func runs(_ id: String) -> Bool { only.map { $0.contains(id) || $0.contains(String(id.prefix(1))) } ?? true }

    /// A direction_make with its version pinned: priced first, then made unless that would pass the budget.
    /// With no version, Direction picks it as the app would.
    func make(_ id: String, test: Int, version: String?, _ args: [String: JSONValue]) async {
        guard runs(id) else { return }
        var o = overrides; o.version = version
        var record: [String: JSONValue] = ["test": .number(Double(test)), "version": version.map(JSONValue.string) ?? .null, "ask": args["ask"] ?? .null, "kind": args["kind"] ?? .null]
        let base: [String: JSONValue] = ["note": .string(note), "turnover": .string(turnover)]
        do {
            let estimate = try await OpenRouter.$overrides.withValue(o) {
                try await runtime.invoke("direction_make", arguments: .object(base.merging(args) { $1 }.merging(["estimateOnly": .bool(true)]) { $1 })).value
            }
            let price = estimate["spend"].double ?? 0
            record["estimate"] = .number(price); record["priced"] = estimate["priced"]
            if version == nil { record["version"] = estimate["version"] }
            planned += price
            guard !estimateOnly else { results[id] = .object(record); return }
            guard committed + price <= budget else { record["skipped"] = .string("would pass the budget"); results[id] = .object(record); return }
            committed += price
            let started = Date()
            let job = try await OpenRouter.$overrides.withValue(o) { try await runtime.invoke("direction_make", arguments: .object(base.merging(args) { $1 })).value }
            let done = try await finish(try job["id"].decode(String.self), o)
            record["seconds"] = .number(Date().timeIntervalSince(started).rounded())
            record["status"] = .string(done.status)
            if let e = done.error {
                record["error"] = .string(e); record["errorCode"] = done.errorCode.map(JSONValue.string) ?? .null
                // Would Direction have handed it to the next version (MadeRefusals)?
                record["readAsRefusal"] = .bool(MadeRefusals.isRefusal(DirectionError(done.errorCode ?? "", e)))
            }
            let paid = done.result?["spend"].double ?? (done.status == "completed" ? price : 0)
            spent += paid; committed += paid - price
            if let result = done.result {
                record["spend"] = .number(paid); record["note"] = result["note"]
                for (i, made) in (result["made"].array ?? []).enumerated() {
                    record["check"] = made["check"]
                    if let file = made["file"].string {
                        let url = store.url.appendingPathComponent(file)
                        record["file"] = .string(try await keep(url, as: "\(id)\(i > 0 ? "-\(i + 1)" : "")"))
                        record["hasSound"] = .bool(await MadeProcessing.hasSound(url))
                        record["length"] = .number(await MadeMedia.duration(url) ?? 0)
                    }
                    record["assetID"] = made["assetID"]
                    record["version"] = made["provenance"]["version"]
                    // What Direction's own record holds (the estimate when no cost came back: the log says which).
                    if let asset = made["assetID"].string, let entry = OpenRouter.$overrides.withValue(o, operation: { SpendLedger.entries() }).first(where: { $0.assetIDs?.contains(asset) == true }) {
                        record["ledgerSpend"] = entry.spend.map(JSONValue.number) ?? .null; record["ledgerEstimate"] = .number(entry.estimate)
                    }
                }
            }
        } catch {
            record["error"] = .string(error.localizedDescription)
            record["readAsRefusal"] = .bool(MadeRefusals.isRefusal(error))
        }
        results[id] = .object(record)
        try? save()
    }

    /// A take sent as video to a version that makes shots, in the body a changed shot sends: does it take it?
    func videoInput(_ id: String, version: String, ask: String, start: Double, end: Double) async {
        guard runs(id) else { return }
        var record: [String: JSONValue] = ["test": .number(2), "version": .string(version), "ask": .string(ask), "kind": .string("video input")]
        do {
            let catalog = await OpenRouter.$overrides.withValue(overrides) { await MadeVersions.load() }
            guard let v = catalog.versions.first(where: { $0.id == version }) else { throw DirectionError("unknown_version", "OpenRouter lists no \(version).") }
            let resolution = MadeEstimator.videoResolution(v, quality: .balanced)
            let estimate = MadeEstimator.estimate(.changedShot, version: v, seconds: end - start, words: ask, ways: 1, resolution: resolution, sound: false, fromImage: false, outputPixels: 1280 * 720)
            record["estimate"] = .number(estimate.spend); record["priced"] = .bool(estimate.priced)
            record["takesVideoListed"] = .bool(v.takesVideo)
            planned += estimate.spend
            guard !estimateOnly else { results[id] = .object(record); return }
            guard committed + estimate.spend <= budget else { record["skipped"] = .string("would pass the budget"); results[id] = .object(record); return }
            committed += estimate.spend
            let clip = folder.appendingPathComponent("\(id)-input.mp4")
            try? FileManager.default.removeItem(at: clip)
            try await MadeProcessing.exportRange(deskURL.path, start: start, end: end, maxDimension: 1280, to: clip)
            var body: [String: JSONValue] = ["model": .string(version), "prompt": .string(ask),
                                             "input_references": .array([.object(["type": .string("video_url"), "video_url": .object(["url": .string(MadeMedia.dataURL(try Data(contentsOf: clip), mime: "video/mp4"))])])])]
            if !v.aspectRatios.isEmpty { body["aspect_ratio"] = .string("16:9") }
            if let d = estimate.duration { body["duration"] = .number(Double(d)) }
            if let resolution { body["resolution"] = .string(resolution) }
            let started = Date()
            let done: OpenRouter.VideoJob = try await OpenRouter.$overrides.withValue(overrides) {
                let submitted = try await OpenRouter.submitVideo(.object(body))
                return try await OpenRouter.waitForVideo(submitted.id)
            }
            record["seconds"] = .number(Date().timeIntervalSince(started).rounded())
            let paid = done.cost ?? estimate.spend
            spent += paid; committed += paid - estimate.spend
            record["spend"] = .number(paid); record["costReported"] = .bool(done.cost != nil)
            let data = try await OpenRouter.$overrides.withValue(overrides) { try await OpenRouter.videoContent(done.id) }
            let out = folder.appendingPathComponent("\(id).mp4")
            try data.write(to: out)
            record["file"] = .string(out.lastPathComponent)
            try await frames(of: out, as: id)
            // Direction's own look at it, as it looks at every made shot.
            let check = try? await OpenRouter.$overrides.withValue(overrides) { try await MadeChecker.check(out, kind: .changedShot, ask: ask, filmID: nil, turnoverID: nil) }
            if let check { record["check"] = check.check.forEditor; spent += check.check.spend ?? 0 }
        } catch {
            record["status"] = .string("failed")
            record["error"] = .string(error.localizedDescription)
            record["readAsRefusal"] = .bool(MadeRefusals.isRefusal(error))
        }
        results[id] = .object(record)
        try? save()
    }

    /// A sound effect from a version listed for speech, sent as makeVoice sends words: mp3, else PCM.
    func speechEffect(_ id: String, version: String, effect: String) async {
        guard runs(id) else { return }
        var record: [String: JSONValue] = ["test": .number(7), "version": .string(version), "ask": .string(effect), "kind": .string("soundEffect (speech)")]
        // Priced per character at the listing's rate; a few words cost well under a cent.
        let words = "A sound effect, not speech: \(effect)"
        let price = 0.0025 * Double(words.count) / 1_000 * 4
        record["estimate"] = .number(price)
        planned += price
        guard !estimateOnly else { results[id] = .object(record); return }
        guard committed + price <= budget else { record["skipped"] = .string("would pass the budget"); results[id] = .object(record); return }
        committed += price
        do {
            func body(_ format: String) -> JSONValue { .object(["model": .string(version), "input": .string(words), "response_format": .string(format)]) }
            let reply: (audio: Data, contentType: String, cost: Double?) = try await OpenRouter.$overrides.withValue(overrides) {
                do { return try await OpenRouter.speech(body("mp3")) }
                catch let e as DirectionError where e.message.localizedCaseInsensitiveContains("format") { return try await OpenRouter.speech(body("pcm")) }
            }
            let (data, ext) = MadeMedia.assemble(reply.audio, contentType: reply.contentType)
            let out = folder.appendingPathComponent("\(id).\(ext)")
            try data.write(to: out)
            let paid = reply.cost ?? price
            spent += paid; committed += paid - price
            record["spend"] = .number(paid); record["costReported"] = .bool(reply.cost != nil)
            record["file"] = .string(out.lastPathComponent); record["status"] = .string("completed")
            record["length"] = .number(await MadeMedia.duration(out) ?? 0)
        } catch {
            committed -= price
            record["status"] = .string("failed"); record["error"] = .string(error.localizedDescription)
        }
        results[id] = .object(record)
        try? save()
    }

    // MARK: Helpers

    func madeAsset(_ id: String) -> String? { results[id]?["assetID"].string }

    func finish(_ job: String, _ o: OpenRouter.Overrides) async throws -> JobRecord {
        while true {
            let j = try await OpenRouter.$overrides.withValue(o) { try await runtime.invoke("direction_job", arguments: .object(["jobID": .string(job)])).value.decode(JobRecord.self) }
            if j.isTerminal { return j }
            try await Task.sleep(for: .seconds(2))
        }
    }

    /// A copy beside the results, and for a shot three frames to look at.
    func keep(_ file: URL, as name: String) async throws -> String {
        let out = folder.appendingPathComponent(name + "." + file.pathExtension)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.copyItem(at: file, to: out)
        if ["mp4", "mov"].contains(file.pathExtension.lowercased()) { try await frames(of: out, as: name) }
        return out.lastPathComponent
    }

    func frames(of video: URL, as name: String) async throws {
        let length = await MadeMedia.duration(video) ?? 5
        for (label, t) in [("a", 0.1), ("b", length / 2), ("c", max(0, length - 0.2))] {
            let jpeg = try await MadeMedia.frame(of: video.path, at: t, isImage: false, maxDimension: 640)
            try jpeg.write(to: folder.appendingPathComponent("\(name)-\(label).jpg"))
        }
    }

    func save() throws {
        try JSONValue.object(results).data().write(to: folder.appendingPathComponent("results.json"))
    }
}
