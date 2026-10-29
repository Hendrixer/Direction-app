import Foundation
import Darwin
import DirectionCore
import DirectionMedia

// Made picture and sound (specs/made-media.md). Direction makes every request with the director's key;
// the editor only says what it wants. Nothing here ever puts the key in an argument, result or log.
extension ToolCatalog {
    static var madeDefinitions: [ToolDefinition] { [
        definition("direction_services", "Read the services you can make picture and sound with: whether OpenRouter is ready, the version used for each kind with its price, the director's limits, and what's left in the open turnover and this month. Use the footage first (direction_search_footage); make something only when a note asks for what the footage doesn't have, and say so in the read-back with the version and about how much it costs."),
        definition("direction_make", "Make music, a sound effect, a voice, a new shot, a shot from one you have (changedShot) or a still through OpenRouter. ask is what to make in plain words (for voice, the words to say). seconds is the length for music, sound effects and shots. from {assetID, start, end?} (source seconds) gives a changed shot its first frame; references are asset ids of stills or takes. ways 1 or 2 makes it once or twice (for options A and B). note is the note ID it's for (or \"unasked\"), turnover the turnover ID. estimateOnly returns {spend, seconds} and spends nothing. Over the turnover's limit you get status spend_over_limit with the estimate: ask a spend question (direction_ask kind spend) and call again with spendQuestionID once the director agrees. Past the monthly cap you get spend_cap, with no override. Otherwise a job: poll direction_job; its result has each made clip's assetID and provenance. Made clips are footage: place them with the edit functions.",
                   ["kind": strings(MadeKind.allCases.map(\.rawValue)), "service": strings(["openrouter"]), "version": string, "ask": string, "seconds": number,
                    "from": record(["assetID": string, "start": number, "end": number, "range": record(["start": number, "end": number])], required: ["assetID"]),
                    "references": list(string), "ways": integer, "note": string, "turnover": string, "estimateOnly": bool, "spendQuestionID": string],
                   required: ["kind", "ask", "note", "turnover"], readOnly: false),
    ] }

    /// direction_ask's `spend` field for kind spend (frame 62).
    static let spendQuestionSchema = record(["estimate": number, "choiceID": string, "kind": strings(MadeKind.allCases.map(\.rawValue)), "version": string], required: ["estimate", "choiceID"])
}

/// One direction_make, everything the job needs.
struct MadeRequest: Sendable {
    var kind: MadeKind
    var version: MadeVersion
    var ask: String
    var seconds: Double?
    var ways: Int
    var noteID: String?
    var turnoverID: String
    var from: MadeFrom?
    var fromAsset: MediaAsset?
    var references: [MediaAsset]
    var estimate: MadeEstimate
    var aspect: String
    var spendID: String
}

extension ToolRuntime {
    func invokeMade(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_services": return ToolResponse(try await madeServices())
        case "direction_make": return ToolResponse(try await make(a))
        default: return nil
        }
    }

    /// direction_ask kind spend: the editor names the estimate and the choice that agrees; Direction adds
    /// what this turnover has spent and the limit from its own record.
    func madeSpendAsk(_ a: JSONValue, kind: String, choices: [QuestionChoice], turnoverID: String?) throws -> SpendAsk? {
        let s = a["spend"]
        guard kind == "spend" else {
            if s != .null { throw DirectionError("invalid_question", "spend goes with kind spend.") }
            return nil
        }
        guard let estimate = s["estimate"].double, let named = s["choiceID"].string else { throw DirectionError("invalid_question", "A spend question needs spend: {estimate, choiceID}.") }
        guard let choice = choices.first(where: { $0.id == named || $0.label == named }) else { throw DirectionError("invalid_question", "spend.choiceID must name the choice that agrees to spend.") }
        let spent = SpendLedger.turnoverSpent(SpendLedger.entries(), filmID: try store.read().id, turnoverID: turnoverID)
        return SpendAsk(estimate: estimate, turnoverSpent: spent, limit: SharedSettings.spendAskAbove, choiceID: choice.id, kind: s["kind"].string.flatMap(MadeKind.init), version: s["version"].string)
    }

    private func madeServices() async throws -> JSONValue {
        let catalog = await MadeVersions.load()
        let entries = SpendLedger.entries(), filmID = try store.read().id
        let open = try store.turnovers().last { $0.state.isOpen }
        let ask = SharedSettings.spendAskAbove, cap = SharedSettings.spendStopAt
        let month = SpendLedger.monthSpent(entries), turnover = SpendLedger.turnoverSpent(entries, filmID: filmID, turnoverID: open?.id)
        let kinds: [JSONValue] = MadeKind.allCases.compactMap { k in
            guard let v = catalog.version(k, chosen: SharedSettings.madeVersion(k)) else { return nil }
            var o: [String: JSONValue] = ["kind": .string(k.rawValue), "version": .string(v.id), "versionName": .string(v.name)]
            if let line = MadeFormat.priceLine(k, v) { o["price"] = .string(line) }
            if v.listing == .video { o["durations"] = .array(v.durations.map { .number(Double($0)) }) }
            return .object(o)
        }
        return .object([
            "services": .array([.object(["name": .string("OpenRouter"), "service": .string("openrouter"), "state": .string(OpenRouter.Key.read() != nil ? "ready" : "notSet"), "kinds": .array(kinds)])]),
            "limits": .object(["askAbovePerTurnover": .number(ask), "stopAtPerMonth": cap.map(JSONValue.number) ?? .null]),
            "turnover": open.map { .object(["id": .string($0.id), "spent": .number(turnover), "left": .number(max(0, ask - turnover))]) } ?? .null,
            "month": .object(["spent": .number(month), "left": cap.map { .number(max(0, $0 - month)) } ?? .null]),
        ])
    }

    private func make(_ a: JSONValue) async throws -> JSONValue {
        guard let kind = MadeKind(rawValue: try a.requiredString("kind")) else { throw DirectionError("invalid_arguments", "kind is one of \(MadeKind.allCases.map(\.rawValue).joined(separator: ", ")).") }
        let ask = try a.requiredString("ask").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ask.count <= 4_000 else { throw DirectionError("invalid_arguments", "Say what to make in under 4,000 characters.") }
        if let s = a["service"].string, s != "openrouter" { throw DirectionError("unknown_service", "OpenRouter is the only service.") }
        let ways = a["ways"].int ?? 1
        guard [1, 2].contains(ways) else { throw DirectionError("invalid_arguments", "ways is 1 or 2.") }
        let seconds = a["seconds"].double
        if kind.needsSeconds { guard let seconds, seconds > 0, seconds <= (kind.isPicture ? 60 : 600) else { throw DirectionError("invalid_arguments", kind.isPicture ? "seconds is the shot's length, up to 60." : "seconds is the length, up to 600.") } }

        // What it's for: a note (by ID, or its number) or "unasked", and the turnover.
        let noteArg = try a.requiredString("note"), notes = try store.notes()
        var noteID: String?
        if noteArg.lowercased() != "unasked" {
            guard let n = notes.first(where: { $0.id == noteArg }) ?? Int(noteArg).flatMap({ num in notes.first { $0.number == num } }) else { throw DirectionError("feedback_not_found", "Note \(noteArg) not found.") }
            noteID = n.id
        }
        let turnoverID = try a.requiredString("turnover")
        guard try store.turnovers().contains(where: { $0.id == turnoverID }) else { throw DirectionError("turnover_not_found", "Turnover \(turnoverID) not found.") }

        let p = try store.read()
        var from: MadeFrom?, fromAsset: MediaAsset?
        if a["from"] != .null {
            let f = a["from"], asset = try p.asset(try f.requiredString("assetID"))
            let start = f["start"].double ?? f["range"]["start"].double ?? 0, end = f["end"].double ?? f["range"]["end"].double
            guard start >= 0, start <= max(0, asset.duration.seconds), asset.isImage || !asset.video.isEmpty else { throw DirectionError("invalid_arguments", "from needs a take with picture and a start inside it.") }
            from = MadeFrom(assetID: asset.id, start: start, end: end); fromAsset = asset
        }
        if kind == .changedShot && from == nil { throw DirectionError("invalid_arguments", "A changed shot needs from: {assetID, start}.") }
        let references = try (a["references"].array ?? []).compactMap(\.string).map { try p.asset($0) }
        guard references.allSatisfy({ $0.isImage || !$0.video.isEmpty }) else { throw DirectionError("invalid_arguments", "References are stills or takes with picture.") }

        let catalog = await MadeVersions.load()
        let chosen = a["version"].string ?? SharedSettings.madeVersion(kind)
        guard let version = catalog.version(kind, chosen: chosen) else { throw DirectionError("unknown_version", "OpenRouter lists no version for \(kind.label.lowercased()).") }
        if let asked = a["version"].string, version.id != asked && !version.id.hasPrefix(asked + "-") { throw DirectionError("unknown_version", "\(asked) isn\u{2019}t a \(kind.label.lowercased()) version on OpenRouter. direction_services lists them.") }
        let estimate = MadeEstimator.estimate(kind, version: version, seconds: seconds, words: ask, ways: ways)
        if a["estimateOnly"].bool == true {
            return .object(["spend": .number(estimate.spend), "seconds": estimate.seconds.map(JSONValue.number) ?? .null, "version": .string(version.id), "versionName": .string(version.name), "requests": .number(Double(estimate.requests)), "priced": .bool(estimate.priced)])
        }
        // No request reaches a service without a key saved in Settings.
        guard OpenRouter.Key.read() != nil else { throw DirectionError("no_openrouter_key", "OpenRouter isn\u{2019}t set up. Ask the director to add a key in Settings \u{203A} Services.") }

        // A yes to a spend question lets this one request past the turnover's limit, never past the month's cap.
        var approval: String?
        if let qid = a["spendQuestionID"].string {
            guard let q = try store.questions().first(where: { $0.id == qid }), q.kind == "spend", let s = q.spend else { throw DirectionError("question_not_found", "Spend question \(qid) not found.") }
            guard q.agreedToSpend else { throw DirectionError("spend_not_agreed", q.answer == nil ? "The director hasn\u{2019}t answered that spend question yet." : "The director didn\u{2019}t agree to that spend.") }
            guard q.turnoverID == nil || q.turnoverID == turnoverID else { throw DirectionError("spend_not_agreed", "That spend question was for another turnover.") }
            guard estimate.spend <= s.estimate * 1.1 + 0.01 else { throw DirectionError("spend_over_question", "This costs about \(MadeFormat.money(estimate.spend)), more than the \(MadeFormat.money(s.estimate)) the director agreed to. Ask again.") }
            approval = qid
        }
        let entry = SpendEntry(kind: kind.spendKind, version: version.id, estimate: estimate.spend, filmID: p.id, turnoverID: turnoverID)
        switch try SpendLedger.reserve(entry, approvedBy: approval) {
        case .ok: break
        case let .overLimit(e, spent, limit):
            return .object(["status": .string("spend_over_limit"), "estimate": .number(e), "seconds": estimate.seconds.map(JSONValue.number) ?? .null, "turnoverSpent": .number(spent), "turnoverLimit": .number(limit), "left": .number(max(0, limit - spent)), "version": .string(version.id), "versionName": .string(version.name),
                            "message": .string("About \(MadeFormat.money(e)) would take this turnover to \(MadeFormat.money(spent + e)) of the director\u{2019}s \(MadeFormat.money(limit)) limit. Ask a spend question (direction_ask kind spend, spend: {estimate, choiceID}) and call again with spendQuestionID once the director agrees.")])
        case let .cap(e, spent, cap):
            return .object(["status": .string("spend_cap"), "estimate": .number(e), "monthSpent": .number(spent), "monthLimit": .number(cap), "left": .number(max(0, cap - spent)),
                            "message": .string("Nothing more can be made this month: \(MadeFormat.money(spent)) of the director\u{2019}s \(MadeFormat.money(cap)) is spent and this would cost about \(MadeFormat.money(e)). Only the director can change the limit, in Settings \u{203A} Services.")])
        }

        let request = MadeRequest(kind: kind, version: version, ask: ask, seconds: seconds, ways: ways, noteID: noteID, turnoverID: turnoverID, from: from, fromAsset: fromAsset, references: references, estimate: estimate, aspect: Self.aspect(try p.sequence(nil), listed: version.aspectRatios), spendID: entry.id)
        let now = Date().timeIntervalSince1970
        let job = JobRecord(id: newID("job"), kind: "make", revision: p.editRevision, ownerPID: getpid(), status: "running", phase: "Asking \(version.name) for \(kind.label.lowercased())", progress: 0, result: nil, error: nil, createdAt: now, updatedAt: now)
        try store.saveJob(job)
        // ToolRuntime's own job runner is private to it; this one keeps the same record so direction_job reads it.
        Task { [store] in
            var record = job
            do {
                record.result = try await self.perform(request, job: job)
                record.status = "completed"; record.phase = "Completed"; record.progress = 1
            } catch {
                record.status = Task.isCancelled || error is CancellationError ? "cancelled" : "failed"
                record.error = error.localizedDescription; record.phase = record.status == "cancelled" ? "Cancelled" : "Failed"
            }
            record.updatedAt = Date().timeIntervalSince1970
            try? store.saveJob(record)
        }
        return try .wrapping(job)
    }

    /// The film's shape as one of the version's ratios.
    static func aspect(_ s: DirectionCore.Sequence, listed: [String]) -> String {
        let ratio = Double(s.width) / Double(max(1, s.height))
        let options = listed.isEmpty ? ["16:9", "9:16", "1:1", "4:3", "3:4", "21:9"] : listed
        func value(_ r: String) -> Double { let p = r.split(separator: ":").compactMap { Double($0) }; return p.count == 2 && p[1] > 0 ? p[0] / p[1] : 1 }
        return options.min { abs(value($0) - ratio) < abs(value($1) - ratio) } ?? "16:9"
    }

    // MARK: Making

    private nonisolated func progress(_ job: JobRecord, _ phase: String, _ value: Double?) {
        var j = job; j.phase = phase; j.progress = value; j.updatedAt = Date().timeIntervalSince1970
        try? store.saveJob(j)
    }

    private func perform(_ r: MadeRequest, job: JobRecord) async throws -> JSONValue {
        let folder = store.madeDirectory, scratch = cacheDirectory.appendingPathComponent("Made")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var made: [(url: URL, cost: Double?, way: Int)] = []
        var spent = 0.0
        do {
            for way in 1...r.ways {
                let label = r.ways > 1 ? " (\(way == 1 ? "A" : "B"))" : ""
                let piece: (URL, Double?)
                switch r.kind {
                case .music, .soundEffect: piece = try await makeAudio(r, folder: folder, scratch: scratch, job: job, label: label)
                case .voice: piece = try await makeVoice(r, folder: folder, job: job, label: label)
                case .shot, .changedShot: piece = try await makeShot(r, folder: folder, job: job, label: label)
                case .still: piece = try await makeStill(r, folder: folder, job: job, label: label)
                }
                made.append((piece.0, piece.1, way)); spent += piece.1 ?? r.estimate.spend / Double(r.ways)
            }
        } catch {
            // Clips already made were paid for; the rest of the hold goes back.
            try? SpendLedger.release(r.spendID, charged: made.isEmpty ? nil : spent)
            throw error
        }
        progress(job, "Bringing it into the film", 0.95)
        var results: [JSONValue] = [], ids: [String] = []
        for m in made {
            let asset = try await importMade(m.url)
            let seconds = asset.duration.seconds > 0 ? asset.duration.seconds : nil
            let record = MadeRecord(assetID: asset.id, kind: r.kind, version: r.version.id, versionName: r.version.name, asked: r.ask, seconds: seconds ?? r.seconds, spend: m.cost ?? r.estimate.spend / Double(r.ways), estimate: r.estimate.spend / Double(r.ways),
                                    noteID: r.noteID, turnoverID: r.turnoverID, from: r.from, references: r.references.map(\.id), file: "Made/" + m.url.lastPathComponent, way: r.ways > 1 ? m.way : nil, jobID: job.id)
            try store.saveMade(record)
            ids.append(asset.id)
            results.append(.object(["assetID": .string(asset.id), "file": .string(record.file), "provenance": try .wrapping(record)]))
        }
        let reported = made.allSatisfy { $0.cost != nil }
        try SpendLedger.settle(r.spendID, spend: reported ? spent : nil, assetIDs: ids)
        return .object(["assetID": .string(ids.first ?? ""), "made": .array(results), "spend": .number(spent), "estimate": .number(r.estimate.spend)])
    }

    /// Made files enter the film through the same import as footage (`direction_import`).
    private func importMade(_ url: URL) async throws -> MediaAsset {
        for attempt in 0..<4 {
            do {
                let out = try await invoke("direction_import", arguments: .object(["path": .string(url.path), "idempotencyKey": .string("made-" + url.lastPathComponent)]))
                return try out.value["asset"].decode(MediaAsset.self)
            } catch let e as DirectionError where e.code == "revision_conflict" && attempt < 3 {
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        throw DirectionError("import_failed", "The made file is at \(url.path) but couldn\u{2019}t be brought in.")
    }

    /// Music and sound effects: audio out of chat. Lyria makes 30 s clips; longer beds are clips joined with a short crossfade.
    private func makeAudio(_ r: MadeRequest, folder: URL, scratch: URL, job: JobRecord, label: String) async throws -> (URL, Double?) {
        let clipVersion = r.version.id.contains("lyria"), seconds = r.seconds ?? MadeEstimator.clipSeconds
        let clips = clipVersion ? MadeEstimator.clips(for: seconds) : 1
        var files: [URL] = [], cost = 0.0, reported = true
        defer { for f in files { try? FileManager.default.removeItem(at: f) } }
        for i in 0..<clips {
            progress(job, "Making \(r.kind == .music ? "music" : "the sound") with \(r.version.name)\(label)" + (clips > 1 ? ", clip \(i + 1) of \(clips)" : ""), Double(i) / Double(clips) * 0.9)
            var prompt = r.kind == .soundEffect ? "A sound effect, not music: \(r.ask)" : r.ask
            if clips > 1 { prompt += i == 0 ? " (Part 1 of \(clips) of one longer piece.)" : " (Part \(i + 1) of \(clips): continue the same piece in the same tempo, key and instruments.)" }
            let audio: JSONValue = clipVersion ? .object(["format": .string("wav")]) : .object(["voice": .string("alloy"), "format": .string("pcm16")])
            let body: JSONValue = .object(["model": .string(r.version.id), "modalities": .array([.string("text"), .string("audio")]), "audio": audio,
                                           "messages": .array([.object(["role": .string("user"), "content": .string(prompt)])])])
            let reply = try await OpenRouter.audioChat(body)
            let (data, ext) = MadeMedia.assemble(reply.audio)
            let file = scratch.appendingPathComponent(UUID().uuidString + "." + ext)
            try data.write(to: file)
            files.append(file)
            if let c = reply.cost { cost += c } else { reported = false }
        }
        let output = folder.appendingPathComponent(MadeMedia.fileName(r.kind, asked: r.ask, ext: "wav"))
        try MadeMedia.join(files, crossfade: MadeEstimator.crossfade, length: r.seconds, to: output)
        return (output, reported ? cost : nil)
    }

    /// Voice: `POST /audio/speech` with the words. mp3 where the version offers it, else raw PCM wrapped as WAV.
    private func makeVoice(_ r: MadeRequest, folder: URL, job: JobRecord, label: String) async throws -> (URL, Double?) {
        progress(job, "Recording the voice with \(r.version.name)\(label)", 0.2)
        func body(_ format: String) -> JSONValue {
            var o: [String: JSONValue] = ["model": .string(r.version.id), "input": .string(r.ask), "response_format": .string(format)]
            if let v = r.version.voices.first { o["voice"] = .string(v) }
            return .object(o)
        }
        let reply: (audio: Data, contentType: String, cost: Double?)
        do { reply = try await OpenRouter.speech(body("mp3")) }
        catch let e as DirectionError where e.message.localizedCaseInsensitiveContains("format") { reply = try await OpenRouter.speech(body("pcm")) }
        let (data, ext) = MadeMedia.assemble(reply.audio, contentType: reply.contentType)
        let output = folder.appendingPathComponent(MadeMedia.fileName(.voice, asked: r.ask, ext: ext))
        try data.write(to: output)
        return (output, reply.cost)
    }

    /// New shots: submit, poll, download. A shot from one you have starts on that take's frame (`first_frame`).
    private func makeShot(_ r: MadeRequest, folder: URL, job: JobRecord, label: String) async throws -> (URL, Double?) {
        var body: [String: JSONValue] = ["model": .string(r.version.id), "prompt": .string(r.ask), "aspect_ratio": .string(r.aspect)]
        if let d = r.estimate.duration { body["duration"] = .number(Double(d)) }
        if let res = r.estimate.resolution { body["resolution"] = .string(res) }
        if let from = r.from, let asset = r.fromAsset {
            progress(job, "Taking the frame from \(asset.name)", 0.02)
            let frame = try await MadeMedia.frame(of: asset.path, at: from.start, isImage: asset.isImage)
            body["frame_images"] = .array([.object(["type": .string("image_url"), "image_url": .object(["url": .string(MadeMedia.dataURL(frame, mime: "image/jpeg"))]), "frame_type": .string("first_frame")])])
        }
        if !r.references.isEmpty { body["input_references"] = .array(try await references(r)) }
        let submitted = try await OpenRouter.submitVideo(.object(body))
        progress(job, "Waiting for \(r.version.name)\(label)", 0.1)
        let name = r.version.name
        let done = try await OpenRouter.waitForVideo(submitted.id) { [weak self] j in
            self?.progress(job, j.status == "in_progress" ? "\(name) is making the shot\(label)" : "Waiting for \(name)\(label)", j.status == "in_progress" ? 0.5 : 0.1)
        }
        progress(job, "Downloading the shot\(label)", 0.85)
        let data = try await OpenRouter.videoContent(submitted.id)
        let output = folder.appendingPathComponent(MadeMedia.fileName(r.kind, asked: r.ask, ext: "mp4"))
        try data.write(to: output)
        return (output, done.cost)
    }

    /// Stills: `POST /images`, shaped like the film.
    private func makeStill(_ r: MadeRequest, folder: URL, job: JobRecord, label: String) async throws -> (URL, Double?) {
        progress(job, "Making the still with \(r.version.name)\(label)", 0.2)
        var body: [String: JSONValue] = ["model": .string(r.version.id), "prompt": .string(r.ask), "aspect_ratio": .string(r.aspect)]
        if !r.references.isEmpty { body["input_references"] = .array(try await references(r)) }
        let reply = try await OpenRouter.image(.object(body))
        let ext = reply.mediaType.contains("jpeg") ? "jpg" : reply.mediaType.contains("webp") ? "webp" : "png"
        let output = folder.appendingPathComponent(MadeMedia.fileName(.still, asked: r.ask, ext: ext))
        try reply.image.write(to: output)
        return (output, reply.cost)
    }

    private nonisolated func references(_ r: MadeRequest) async throws -> [JSONValue] {
        var out: [JSONValue] = []
        for asset in r.references.prefix(4) {
            let frame = try await MadeMedia.frame(of: asset.path, at: min(1, asset.duration.seconds / 2), isImage: asset.isImage)
            out.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string(MadeMedia.dataURL(frame, mime: "image/jpeg"))])]))
        }
        return out
    }
}
