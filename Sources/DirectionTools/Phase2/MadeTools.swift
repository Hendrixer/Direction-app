import Foundation
import Darwin
import os
import AVFoundation
import DirectionCore
import DirectionMedia

// Made picture and sound (specs/made-media.md). Direction makes every request with the director's key;
// the editor only says what it wants. Nothing here ever puts the key in an argument, result or log.
extension ToolCatalog {
    /// One `direction_make` call's arguments, also each step of `direction_estimate`.
    static var makeProperties: [String: JSONValue] {
        let frame = record(["assetID": string, "at": number], required: ["assetID"])
        return ["kind": strings(MadeKind.allCases.map(\.rawValue)), "service": strings(["openrouter", "local"]), "ask": string, "seconds": number,
                "from": record(["assetID": string, "start": number, "end": number, "side": strings(["tail", "head"]), "range": record(["start": number, "end": number])], required: ["assetID"]),
                "first": frame, "last": frame, "references": list(.object(["anyOf": .array([string, frame])])),
                "sound": bool, "factor": integer, "ways": integer, "note": string, "turnover": string, "estimateOnly": bool, "spendQuestionID": string]
    }

    static var madeDefinitions: [ToolDefinition] { [
        definition("direction_services", "Read what you can make picture and sound with: whether OpenRouter is ready, the version Direction uses for each kind right now (and when a frame shows a person) with its price, whether this Mac can sharpen, the director's limits, and what's left in the open turnover and this month. You don't choose versions: Direction picks one for each request from what it needs and the film's speed and quality (quality in the result), and moves to the next if a version turns it down. Use the footage first (direction_search_footage). The make-shot skill has the workflow."),
        definition("direction_estimate", "Price a plan before making any of it: steps is a list of direction_make arguments (kind, ask, seconds, from, first, last, references, sound, ways…), turnover the turnover ID. Returns each step's version, seconds and spend, the plan's total, what this turnover has spent, the director's limit and needsQuestion. Under the limit, make it without asking. Over it, ask one spend question for the whole plan (direction_ask kind spend, spend: {estimate: total, choiceID}) and pass its id as spendQuestionID on every step. Spends nothing.",
                   ["turnover": string, "steps": list(record(makeProperties))], required: ["steps"]),
        definition("direction_make", "Make something the footage doesn't have. Through OpenRouter: music, soundEffect, voice (ask is the words), still, shot (a new shot from words, a first frame, or first and last frames), extension (continues a take: from {assetID, end, side: tail}), bridge (first and last frames, from two takes; a last frame always needs a first), changedShot (changes a range of a take itself, up to 10 s: from {assetID, start, end}, ask is the change: \"remove the boom at top left\", \"dusk sky with cloud\"). On this Mac at no cost: slowMotion (from a range, factor 2–4) and upscale (sharpens a range to the cut's size). A frame is {assetID, at} (at is source seconds; omit for a still). references are up to 4 stills or takes ({assetID, at}) that ground it in the film. Shots are silent unless sound is true. seconds is the length for music, sound effects, shots, extensions and bridges. ways is 1 or 2 (up to 4 for stills). note is the note ID (or \"unasked\"), turnover the turnover ID. Price the whole plan first with direction_estimate. Over the turnover's limit you get spend_over_limit: ask one spend question and call again with spendQuestionID. Past the monthly cap you get spend_cap, with no override. Otherwise a job: poll direction_job; its result has each made clip's assetID and provenance, and note says when Direction used another version because one turned the request down. If the next version would pass a limit, the job's result is spend_over_limit or spend_cap instead, the same as this call's. Made shots are sharpened to the cut's size on this Mac and extensions join without a repeated frame. Watch what's made before placing it with placeMade (a changed shot goes on V2 over its own range).",
                   makeProperties, required: ["kind", "note", "turnover"], readOnly: false),
    ] }

    /// direction_ask's `spend` field for kind spend (frame 62).
    static let spendQuestionSchema = record(["estimate": number, "choiceID": string, "kind": strings(MadeKind.allCases.map(\.rawValue)), "version": string], required: ["estimate", "choiceID"])
}

/// A frame and the still or take it comes from.
struct MadeFrameSource: Sendable {
    var frame: MadeFrame
    var asset: MediaAsset
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
    var first: MadeFrameSource?
    var last: MadeFrameSource?
    var references: [MadeFrameSource]
    var sound: Bool
    var factor: Int?
    var estimate: MadeEstimate
    var aspect: String
    /// The cut's size: made shots are sharpened to it.
    var cut: MadeProcessing.Steps.Size
    /// Why Direction used another version than the one chosen, for the result.
    var versionNote: String?
    var spendID: String = ""
    /// The spend question whose yes this request goes ahead on, and how much that yes allows.
    var approval: String?
    var budget: Double?
    /// The versions to try next if this one turns the request down (a person in a frame, a policy).
    var alternatives: [MadeVersion] = []
    /// A frame or reference shows a person.
    var person = false
    /// The film's speed and quality as the resolution a shot is made at follows it (Best when this Mac can't sharpen).
    var quality: FilmQuality = .balanced
}

extension ToolRuntime {
    func invokeMade(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_services": return ToolResponse(try await madeServices())
        case "direction_estimate": return ToolResponse(try await estimatePlan(a))
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
        func describe(_ k: MadeKind, _ v: MadeVersion) -> [String: JSONValue] {
            var o: [String: JSONValue] = ["id": .string(v.id), "name": .string(v.name)]
            if let line = MadeFormat.priceLine(k, v, resolution: MadeEstimator.videoResolution(v, quality: quality, sharpensHere: sharpensHere)) { o["price"] = .string(line) }
            if v.listing == .video && !v.isLocal {
                if !v.durations.isEmpty { o["durations"] = .array(v.durations.map { .number(Double($0)) }) }
                o["lastFrame"] = .bool(v.takesLastFrame)
                if v.takesVideo { o["takesVideo"] = .bool(true) }
            }
            return o
        }
        let quality = FilmQuality.forMade(try? store.directingState()), refused = MadeRefusals.refusedPeople()
        let sharpensHere = MadeProcessing.sharpeningStatus(width: 1280, height: 720) != .unsupported
        let kinds: [JSONValue] = MadeKind.allCases.compactMap { k in
            // A typical request of the kind: shots and their kin start from a frame of the film.
            let framed = [.shot, .extension, .bridge].contains(k)
            let needs = MadeNeeds(kind: k, firstFrame: framed, lastFrame: k == .bridge, seconds: k.needsSeconds ? 5 : nil)
            guard let v = catalog.route(needs, quality: quality).first else { return nil }
            var o = describe(k, v)
            o["kind"] = .string(k.rawValue); o["label"] = .string(k.label); o["version"] = .string(v.id); o["versionName"] = .string(v.name); o["service"] = .string(v.isLocal ? "local" : "openrouter")
            o.removeValue(forKey: "id"); o.removeValue(forKey: "name")
            if k.isPicture && k != .slowMotion && k != .upscale {
                var withPerson = needs; withPerson.person = true
                if let p = catalog.route(withPerson, quality: quality, refusedPeople: refused).first, p.id != v.id { o["withAPerson"] = .object(describe(k, p)) }
            }
            return .object(o)
        }
        let sharpening: String = switch MadeProcessing.sharpeningStatus(width: 1280, height: 720) {
        case .ready: "ready"; case .needsDownload: "downloadsOnFirstUse"; case .downloading: "downloading"; case .unsupported: "unavailable"
        }
        return .object([
            "services": .array([.object(["name": .string("OpenRouter"), "service": .string("openrouter"), "state": .string(OpenRouter.Key.read() != nil ? "ready" : "notSet")]),
                                .object(["name": .string("This Mac"), "service": .string("local"), "state": .string("ready"), "kinds": .array([.string("slowMotion"), .string("upscale")]), "sharpening": .string(sharpening)])]),
            "kinds": .array(kinds),
            "quality": .string(quality.rawValue),
            "limits": .object(["askAbovePerTurnover": .number(ask), "stopAtPerMonth": cap.map(JSONValue.number) ?? .null]),
            "turnover": open.map { .object(["id": .string($0.id), "spent": .number(turnover), "left": .number(max(0, ask - turnover))]) } ?? .null,
            "month": .object(["spent": .number(month), "left": cap.map { .number(max(0, $0 - month)) } ?? .null]),
        ])
    }

    /// direction_estimate: the whole plan's price, so the director is asked once or not at all.
    private func estimatePlan(_ a: JSONValue) async throws -> JSONValue {
        guard let steps = a["steps"].array, !steps.isEmpty else { throw DirectionError("invalid_arguments", "steps lists what you plan to make, each as direction_make arguments.") }
        guard steps.count <= 24 else { throw DirectionError("invalid_arguments", "Price up to 24 steps at a time.") }
        let turnoverArg = a["turnover"].string
        var priced: [JSONValue] = [], total = 0.0, unpriced = 0
        for (i, step) in steps.enumerated() {
            guard case .object(var fields) = step else { throw DirectionError("invalid_arguments", "Step \(i + 1) isn\u{2019}t a set of direction_make arguments.") }
            if fields["turnover"] == nil, let t = turnoverArg { fields["turnover"] = .string(t) }
            if fields["note"] == nil { fields["note"] = .string("unasked") }
            let r: MadeRequest
            do { r = try await makeRequest(.object(fields)) }
            catch let e as DirectionError { throw DirectionError(e.code, "Step \(i + 1): \(e.message)") }
            total += r.estimate.spend
            if !r.estimate.priced { unpriced += 1 }
            var o: [String: JSONValue] = ["kind": .string(r.kind.rawValue), "version": .string(r.version.id), "versionName": .string(r.version.name), "spend": .number(r.estimate.spend), "requests": .number(Double(r.estimate.requests))]
            if let sec = r.estimate.seconds { o["seconds"] = .number(sec) }
            if let note = r.versionNote { o["note"] = .string(note) }
            if !r.estimate.priced { o["priced"] = .bool(false) }
            priced.append(.object(o))
        }
        let entries = SpendLedger.entries(), filmID = try store.read().id
        let turnoverID = turnoverArg ?? steps.first?["turnover"].string
        let spent = SpendLedger.turnoverSpent(entries, filmID: filmID, turnoverID: turnoverID), limit = SharedSettings.spendAskAbove
        let month = SpendLedger.monthSpent(entries), cap = SharedSettings.spendStopAt
        // A step with no listed price could cost anything, so the director says yes to the plan first.
        let needsQuestion = spent + total > limit + 0.005 || unpriced > 0, overCap = cap.map { month + total > $0 + 0.005 || (unpriced > 0 && month >= $0 - 0.005) } ?? false
        let ask = "Ask one spend question for the plan (spend: {estimate: \(String(format: "%.2f", total)), choiceID}) and pass its id as spendQuestionID on every step."
        let message: String
        if overCap { message = "This plan would pass the director\u{2019}s \(MadeFormat.money(cap ?? 0)) for the month (\(MadeFormat.money(month)) spent). Only the director can change that, in Settings \u{203A} Engines." }
        else if unpriced > 0 { message = "About \(MadeFormat.money(total)), but \(unpriced == 1 ? "one step uses a version" : "\(unpriced) steps use versions") OpenRouter lists no price for, so the director says yes first. \(ask)" }
        else if needsQuestion { message = "About \(MadeFormat.money(total)) would take this turnover to \(MadeFormat.money(spent + total)) of the director\u{2019}s \(MadeFormat.money(limit)) limit. \(ask)" }
        else { message = "About \(MadeFormat.money(total)), within the director\u{2019}s \(MadeFormat.money(limit)) limit for this turnover. Make it; say it in the read-back." }
        return .object(["steps": .array(priced), "total": .number(total), "turnoverSpent": .number(spent), "limit": .number(limit), "needsQuestion": .bool(needsQuestion),
                        "monthSpent": .number(month), "monthLeft": cap.map { .number(max(0, $0 - month)) } ?? .null, "overMonthlyCap": .bool(overCap),
                        "unpricedSteps": .number(Double(unpriced)), "message": .string(message)])
    }

    /// Reads and checks one direction_make call's arguments, and prices it.
    private func makeRequest(_ a: JSONValue) async throws -> MadeRequest {
        guard let kind = MadeKind(rawValue: try a.requiredString("kind")) else { throw DirectionError("invalid_arguments", "kind is one of \(MadeKind.allCases.map(\.rawValue).joined(separator: ", ")).") }
        let ask = (a["ask"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if ask.isEmpty && ![.slowMotion, .upscale].contains(kind) { throw DirectionError("invalid_arguments", kind == .changedShot ? "Say what to change in ask." : "Say what to make in ask.") }
        guard ask.count <= 4_000 else { throw DirectionError("invalid_arguments", "Say what to make in under 4,000 characters.") }
        if let s = a["service"].string, !["openrouter", "local"].contains(s) { throw DirectionError("unknown_service", "OpenRouter and this Mac are the only services.") }
        let ways = a["ways"].int ?? 1, maxWays = kind == .still ? 4 : kind.worksOnRange && kind != .changedShot ? 1 : 2
        guard (1...maxWays).contains(ways) else { throw DirectionError("invalid_arguments", maxWays == 1 ? "\(kind.label) is made one way." : "ways is 1 to \(maxWays).") }
        var seconds = a["seconds"].double
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
        func source(_ v: JSONValue, _ name: String) throws -> MadeFrameSource? {
            if v == .null { return nil }
            let asset = try p.asset(v.string ?? (try v.requiredString("assetID")))
            guard asset.isImage || !asset.video.isEmpty else { throw DirectionError("invalid_arguments", "\(name) needs a still or a take with picture.") }
            let at = asset.isImage ? nil : v["at"].double ?? (v.string != nil ? min(1, asset.duration.seconds / 2) : 0)
            if let at, at < 0 || at > max(0, asset.duration.seconds) + 0.001 { throw DirectionError("invalid_arguments", "\(name).at is outside \(asset.name).") }
            return MadeFrameSource(frame: MadeFrame(assetID: asset.id, at: at), asset: asset)
        }
        var first = try source(a["first"], "first"), last = try source(a["last"], "last")
        var from: MadeFrom?, fromAsset: MediaAsset?
        if a["from"] != .null {
            let f = a["from"], asset = try p.asset(try f.requiredString("assetID")), length = asset.duration.seconds
            guard !asset.video.isEmpty || asset.isImage else { throw DirectionError("invalid_arguments", "from needs a take with picture.") }
            let start = f["start"].double ?? f["range"]["start"].double, end = f["end"].double ?? f["range"]["end"].double
            let side = f["side"].string ?? "tail"
            if let start, start < 0 || start > length + 0.001 { throw DirectionError("invalid_arguments", "from.start is outside \(asset.name).") }
            if let end, end <= (start ?? 0) || end > length + 0.001 { throw DirectionError("invalid_arguments", "from.end must be after from.start and inside \(asset.name).") }
            from = MadeFrom(assetID: asset.id, start: start ?? 0, end: end, side: kind == .extension ? side : nil); fromAsset = asset
        }
        switch kind {
        case .changedShot, .slowMotion, .upscale:
            guard let f = from, let end = f.end, let asset = fromAsset, !asset.isImage else { throw DirectionError("invalid_arguments", "\(kind.label) needs from: {assetID, start, end}, a range of a take.") }
            let length = end - f.start, longest: Double = kind == .changedShot ? 10 : kind == .slowMotion ? 20 : 60
            guard length <= longest + 0.001 else { throw DirectionError("invalid_arguments", "\(kind.label) works on up to \(Int(longest)) seconds at a time.") }
            seconds = length
        case .extension:
            guard let f = from, let asset = fromAsset, !asset.isImage else { throw DirectionError("invalid_arguments", "An extended shot needs from: {assetID, end, side: \"tail\"} or {assetID, start, side: \"head\"}.") }
            guard ["tail", "head"].contains(f.side ?? "") else { throw DirectionError("invalid_arguments", "from.side is tail or head.") }
            // Tail: the take's frame at its out point starts the new shot. Head: the frame at its in point ends it.
            let fps = asset.video.first?.frameRate ?? 24
            if f.side == "head" { last = MadeFrameSource(frame: MadeFrame(assetID: asset.id, at: f.start), asset: asset); first = nil }
            else { first = MadeFrameSource(frame: MadeFrame(assetID: asset.id, at: max(0, (f.end ?? asset.duration.seconds) - 0.5 / max(1, fps))), asset: asset); last = nil }
        case .bridge:
            guard first != nil, last != nil else { throw DirectionError("invalid_arguments", "A bridge needs first and last frames: {assetID, at}.") }
        case .shot:
            // A shot from a take's moment, as before: from sets its first frame.
            if first == nil, let f = from, let asset = fromAsset { first = MadeFrameSource(frame: MadeFrame(assetID: asset.id, at: asset.isImage ? nil : f.start), asset: asset) }
        default: break
        }
        let factor = kind == .slowMotion ? (a["factor"].int ?? 2) : nil
        if let factor, !(2...4).contains(factor) { throw DirectionError("invalid_arguments", "factor is 2, 3 or 4.") }
        let references = try (a["references"].array ?? []).enumerated().compactMap { try source($1, "references[\($0)]") }
        guard references.count <= 4 else { throw DirectionError("invalid_arguments", "Up to 4 references.") }

        // OpenRouter turns down a last frame without a first one, so say so before anything is spent.
        if last != nil && first == nil {
            throw DirectionError("invalid_arguments", kind == .extension ? "Leading into a take needs a first frame too, and an extension has none: make a still for the first frame and a bridge from it to the take." : "A last frame needs a first frame too. Make a still for the first frame, or start from words alone.")
        }
        // Direction chooses the version (made-media.md › Choosing a version): from what this request needs,
        // and how good against how cheap the director chose.
        let catalog = await MadeVersions.load()
        let person = kind.isPicture && kind != .slowMotion && kind != .upscale ? await PeopleCheck.anyPerson(in: try await frameData([first, last].compactMap { $0 } + references)) : false
        var sharpenHere = true
        if kind == .upscale, let stream = fromAsset?.video.first { sharpenHere = MadeProcessing.sharpeningStatus(width: stream.width, height: stream.height) != .unsupported }
        // A changed shot keeps the take's own sound, so it never asks for any.
        let sound = kind.isMadeShot && kind != .changedShot && a["sound"].bool == true
        let needs = MadeNeeds(kind: kind, firstFrame: first != nil, lastFrame: last != nil, person: person, seconds: seconds, sound: sound, sharpenHere: sharpenHere,
                              lettering: kind == .still && MadeNeeds.hasLettering(ask), camera: [.shot, .extension].contains(kind) && MadeNeeds.isCameraMove(ask))
        let quality = FilmQuality.forMade(try? store.directingState())
        // Shots made smaller than the cut need this Mac to sharpen them; one that can't asks for the full size.
        let madeSharpensHere = MadeProcessing.sharpeningStatus(width: 1280, height: 720) != .unsupported
        let route = catalog.route(needs, quality: quality, refusedPeople: person ? MadeRefusals.refusedPeople() : [])
        guard let version = route.first else {
            let why = person && kind.isPicture ? " that takes a frame with a person in it" : last != nil ? " that takes a last frame" : seconds.map { " that makes \(Int($0)) seconds" } ?? ""
            throw DirectionError("unknown_version", "OpenRouter lists no version for \(kind.label.lowercased())\(why). Try it shorter, or without the frame.")
        }
        let versionNote: String? = nil
        let sequence = try p.sequence(nil)
        let cut = MadeProcessing.Steps.Size(width: sequence.width, height: sequence.height)
        if kind == .upscale, let asset = fromAsset, let stream = asset.video.first {
            guard cut.height > stream.height else { throw DirectionError("nothing_to_sharpen", "\(asset.name) is already \(stream.width) \u{00D7} \(stream.height), as big as the cut.") }
        }
        let estimate = MadeEstimator.estimate(kind, version: version, seconds: seconds, words: ask, ways: ways, resolution: MadeEstimator.videoResolution(version, quality: quality, sharpensHere: madeSharpensHere), sound: sound, fromImage: first != nil || last != nil, outputPixels: Double(cut.width * cut.height))
        return MadeRequest(kind: kind, version: version, ask: ask, seconds: seconds, ways: ways, noteID: noteID, turnoverID: turnoverID, from: from, fromAsset: fromAsset, first: first, last: last,
                           references: references, sound: sound, factor: factor, estimate: estimate, aspect: Self.aspect(sequence, listed: version.aspectRatios), cut: cut, versionNote: versionNote,
                           alternatives: Array(route.dropFirst().prefix(2)), person: person, quality: madeSharpensHere ? quality : .best)
    }

    private func make(_ a: JSONValue) async throws -> JSONValue {
        var request = try await makeRequest(a)
        let estimate = request.estimate, version = request.version
        if a["estimateOnly"].bool == true {
            var o: [String: JSONValue] = ["spend": .number(estimate.spend), "seconds": estimate.seconds.map(JSONValue.number) ?? .null, "version": .string(version.id), "versionName": .string(version.name), "requests": .number(Double(estimate.requests)), "priced": .bool(estimate.priced)]
            if let note = request.versionNote { o["note"] = .string(note) }
            return .object(o)
        }
        let p = try store.read()
        if !version.isLocal {
            // No request reaches a service without a key saved in Settings.
            guard OpenRouter.Key.read() != nil else { throw DirectionError("no_openrouter_key", "OpenRouter isn\u{2019}t set up. Ask the director to add a key in Settings \u{203A} Engines.") }

            // A yes to a spend question lets that plan's requests past the turnover's limit, never past the month's cap.
            var approval: String?, budget: Double?
            if let qid = a["spendQuestionID"].string {
                guard let q = try store.questions().first(where: { $0.id == qid }), q.kind == "spend", let s = q.spend else { throw DirectionError("question_not_found", "Spend question \(qid) not found.") }
                guard q.agreedToSpend else { throw DirectionError("spend_not_agreed", q.answer == nil ? "The director hasn\u{2019}t answered that spend question yet." : "The director didn\u{2019}t agree to that spend.") }
                guard q.turnoverID == nil || q.turnoverID == request.turnoverID else { throw DirectionError("spend_not_agreed", "That spend question was for another turnover.") }
                approval = qid; budget = SpendLedger.budget(forEstimate: s.estimate)
            }
            let entry = SpendEntry(kind: request.kind.spendKind, version: version.id, estimate: estimate.spend, filmID: p.id, turnoverID: request.turnoverID)
            if let stop = Self.spendStop(try SpendLedger.reserve(entry, approvedBy: approval, budget: budget, priced: estimate.priced), estimate, version) { return stop }
            request.spendID = entry.id; request.approval = approval; request.budget = budget
        }

        let r = request
        let phase = version.isLocal ? "\(r.kind == .slowMotion ? "Making slow motion" : "Sharpening") on this Mac" : "Asking \(version.name) for \(r.kind.label.lowercased())"
        // In the runtime's own jobs, so direction_cancel_job reaches it and closing the film stops it.
        let job = try startJob(kind: "make", revision: p.editRevision, phase: phase, progress: 0) { job in try await self.perform(r, job: job) }
        return try .wrapping(job)
    }

    /// What direction_make answers when a request would pass a limit, before or after a version turned it down.
    static func spendStop(_ check: SpendCheck, _ estimate: MadeEstimate, _ version: MadeVersion) -> JSONValue? {
        let ask = "Price the whole plan with direction_estimate, ask one spend question for it (direction_ask kind spend, spend: {estimate, choiceID}) and call again with spendQuestionID once the director agrees."
        switch check {
        case .ok: return nil
        case let .overLimit(e, spent, limit):
            let why = estimate.priced ? "About \(MadeFormat.money(e)) would take this turnover to \(MadeFormat.money(spent + e)) of the director\u{2019}s \(MadeFormat.money(limit)) limit." : "OpenRouter lists no price for \(version.name), so the director says yes before it\u{2019}s used."
            var o: [String: JSONValue] = ["status": .string("spend_over_limit"), "estimate": .number(e), "seconds": estimate.seconds.map(JSONValue.number) ?? .null, "turnoverSpent": .number(spent), "turnoverLimit": .number(limit), "left": .number(max(0, limit - spent)),
                                          "version": .string(version.id), "versionName": .string(version.name), "message": .string("\(why) \(ask)")]
            if !estimate.priced { o["priced"] = .bool(false) }
            return .object(o)
        case let .cap(e, spent, cap):
            let cost = estimate.priced ? "this would cost about \(MadeFormat.money(e))" : "OpenRouter lists no price for \(version.name)"
            return .object(["status": .string("spend_cap"), "estimate": .number(e), "monthSpent": .number(spent), "monthLimit": .number(cap), "left": .number(max(0, cap - spent)),
                            "message": .string("Nothing more can be made this month: \(MadeFormat.money(spent)) of the director\u{2019}s \(MadeFormat.money(cap)) is spent and \(cost). Only the director can change the limit, in Settings \u{203A} Engines.")])
        }
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

    /// One made file: where it is, what OpenRouter reported, which way it is, and the size it was sharpened from.
    private struct Piece { var url: URL; var cost: Double?; var way: Int; var sharpenedFrom: String? = nil }
    /// Something went wrong after the service had made (and charged for) it: the charge stays in the ledger.
    private struct PaidThenFailed: Error { var underlying: Error; var cost: Double? }
    /// The version next in line would pass a limit: the job ends with direction_make's own spend answer.
    private struct SpendStopped: Error { var result: JSONValue }

    private func perform(_ request: MadeRequest, job: JobRecord) async throws -> JSONValue {
        var r = request
        let folder = store.madeDirectory, scratch = cacheDirectory.appendingPathComponent("Made")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var made: [Piece] = []
        var spent = 0.0
        do {
            for way in 1...r.ways {
                let label = r.ways > 1 ? " (\(Character(UnicodeScalar(64 + way)!)))" : ""
                func once(_ r: MadeRequest) async throws -> Piece {
                    switch r.kind {
                    case .music, .soundEffect: try await makeAudio(r, folder: folder, scratch: scratch, job: job, label: label)
                    case .voice: try await makeVoice(r, folder: folder, job: job, label: label)
                    case .shot, .extension, .bridge, .changedShot: try await makeShot(r, folder: folder, scratch: scratch, job: job, label: label)
                    case .still: try await makeStill(r, folder: folder, job: job, label: label)
                    case .slowMotion: try await makeSlowMotion(r, folder: folder, job: job)
                    case .upscale: r.version.isLocal ? try await sharpenHere(r, folder: folder, job: job) : try await makeShot(r, folder: folder, scratch: scratch, job: job, label: label)
                    }
                }
                var piece: Piece
                // A version that turns the request down for what's in it hands it to the next one
                // (made-media.md › Choosing a version); one that refused a person is skipped for a week.
                while true {
                    do { piece = try await once(r); break }
                    catch where MadeRefusals.isRefusal(error) && !r.alternatives.isEmpty {
                        let refused = r.version, why = (error as? DirectionError)?.message.lowercased().contains("person") == true ? "a frame with a person in it" : "what was asked"
                        if r.person || why.contains("person") { MadeRefusals.record(refused.id) }
                        r.version = r.alternatives.removeFirst()
                        r.estimate = MadeEstimator.estimate(r.kind, version: r.version, seconds: r.seconds, words: r.ask, ways: r.ways, resolution: MadeEstimator.videoResolution(r.version, quality: r.quality), sound: r.sound, fromImage: r.first != nil || r.last != nil, outputPixels: Double(r.cut.width * r.cut.height))
                        // The next version often costs more: the hold moves to it only within the limits and the director's yes.
                        if !refused.isLocal && !r.version.isLocal {
                            let planned = spent + r.estimate.spend / Double(r.ways) * Double(r.ways - made.count)
                            let check = try SpendLedger.adjust(r.spendID, version: r.version.id, estimate: planned, priced: r.estimate.priced, approvedBy: r.approval, budget: r.budget)
                            if case .object(var stop)? = Self.spendStop(check, r.estimate, r.version) {
                                stop["note"] = .string("\(refused.name) wouldn\u{2019}t take \(why). \(r.version.name) would make it instead.")
                                throw SpendStopped(result: .object(stop))
                            }
                        }
                        r.aspect = Self.aspect(try store.read().sequence(nil), listed: r.version.aspectRatios)
                        r.versionNote = [r.versionNote, "\(refused.name) wouldn\u{2019}t take \(why), so this used \(r.version.name)."].compactMap { $0 }.joined(separator: " ")
                        progress(job, "Asking \(r.version.name) instead", 0.05)
                    }
                }
                piece.way = way
                made.append(piece); spent += piece.cost ?? r.estimate.spend / Double(r.ways)
            }
        } catch {
            // Clips already made were paid for, and so was one that failed after it was made; the rest of the hold goes back.
            var charged = made.isEmpty ? nil : spent, failure = error
            if let paid = error as? PaidThenFailed { charged = (charged ?? 0) + (paid.cost ?? r.estimate.spend / Double(r.ways)); failure = paid.underlying }
            if !r.version.isLocal { try? SpendLedger.release(r.spendID, charged: charged) }
            if let stopped = error as? SpendStopped { return stopped.result }
            throw failure
        }
        // Direction looks at each way itself before the editor does (decisions.md); a failed look never fails the job.
        var checks: [Int: Result<(check: MadeCheck, others: [MadeCheck]), Error>] = [:]
        if MadeChecker.checks(r.kind) {
            progress(job, "Checking what came back", 0.95)
            let filmID = try? store.read().id, kind = r.kind, ask = r.ask, turnoverID = r.turnoverID
            checks = await withTaskGroup(of: (Int, Result<(check: MadeCheck, others: [MadeCheck]), Error>).self) { group in
                for (i, m) in made.enumerated() {
                    group.addTask { do { return (i, .success(try await MadeChecker.check(m.url, kind: kind, ask: ask, filmID: filmID, turnoverID: turnoverID))) } catch { return (i, .failure(error)) } }
                }
                return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
            }
        }
        progress(job, "Bringing it into the film", 0.97)
        var results: [JSONValue] = [], ids: [String] = []
        // Paid for already: if bringing it in fails, the charge is still settled.
        do {
            for (i, m) in made.enumerated() {
                let asset = try await importMade(m.url)
                let seconds = asset.duration.seconds > 0 ? asset.duration.seconds : nil
                let each = r.version.isLocal ? 0 : m.cost ?? r.estimate.spend / Double(r.ways)
                var record = MadeRecord(assetID: asset.id, kind: r.kind, service: r.version.isLocal ? "local" : "openrouter", version: r.version.id, versionName: r.version.name, asked: r.ask, seconds: seconds ?? r.seconds,
                                        spend: each, estimate: r.estimate.spend / Double(r.ways), noteID: r.noteID, turnoverID: r.turnoverID, from: r.from, first: r.first?.frame, last: r.last?.frame,
                                        references: r.references.map(\.asset.id), factor: r.factor, sharpenedFrom: m.sharpenedFrom, file: "Made/" + m.url.lastPathComponent, way: r.ways > 1 ? m.way : nil, jobID: job.id)
                var check: JSONValue?
                switch checks[i] {
                case .success(let (c, others))?:
                    record.check = c
                    record.otherChecks = others.isEmpty ? nil : others
                    check = c.forEditor
                    let also = others.map { "; \($0.version) says \($0.verdict.rawValue)" }.joined()
                    DirectionLog.info("Checked \(record.file): \(c.verdict.rawValue)\(c.findings.isEmpty ? "" : " (" + c.findings.joined(separator: " ") + ")") by \(c.version)\(also)", "made")
                case .failure(let e)?:
                    check = .object(["verdict": .string("unchecked"), "why": .string(e.localizedDescription)])
                    DirectionLog.info("Couldn\u{2019}t check \(record.file): \(e.localizedDescription)", "made")
                case nil: break
                }
                try store.saveMade(record)
                ids.append(asset.id)
                var o: [String: JSONValue] = ["assetID": .string(asset.id), "file": .string(record.file), "provenance": try .wrapping(record)]
                if let check { o["check"] = check }
                if r.kind.isMadeShot && m.sharpenedFrom == nil && Double(r.cut.height) >= Double(asset.video.first?.height ?? r.cut.height) * 1.5 { o["sharpened"] = .bool(false) }
                results.append(.object(o))
            }
        } catch {
            if !r.version.isLocal { try? SpendLedger.settle(r.spendID, spend: spent, assetIDs: ids) }
            throw error
        }
        if !r.version.isLocal {
            let reported = made.allSatisfy { $0.cost != nil }
            try SpendLedger.settle(r.spendID, spend: reported ? spent : nil, assetIDs: ids)
        }
        var out: [String: JSONValue] = ["assetID": .string(ids.first ?? ""), "made": .array(results), "spend": .number(r.version.isLocal ? 0 : spent), "estimate": .number(r.estimate.spend)]
        if let note = r.versionNote { out["note"] = .string(note) }
        return .object(out)
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
    private func makeAudio(_ r: MadeRequest, folder: URL, scratch: URL, job: JobRecord, label: String) async throws -> Piece {
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
            let reply: OpenRouter.AudioReply
            do { reply = try await OpenRouter.audioChat(body) }
            catch where i > 0 { throw PaidThenFailed(underlying: error, cost: reported ? cost : nil) }
            let (data, ext) = MadeMedia.assemble(reply.audio)
            let file = scratch.appendingPathComponent(UUID().uuidString + "." + ext)
            try data.write(to: file)
            files.append(file)
            if let c = reply.cost { cost += c } else { reported = false }
        }
        let output = folder.appendingPathComponent(MadeMedia.fileName(r.kind, asked: r.ask, ext: "wav"))
        try MadeMedia.join(files, crossfade: MadeEstimator.crossfade, length: r.seconds, to: output)
        return Piece(url: output, cost: reported ? cost : nil, way: 1)
    }

    /// Voice: `POST /audio/speech` with the words. mp3 where the version offers it, else raw PCM wrapped as WAV.
    private func makeVoice(_ r: MadeRequest, folder: URL, job: JobRecord, label: String) async throws -> Piece {
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
        return Piece(url: output, cost: reply.cost, way: 1)
    }

    /// Shots through `POST /videos`: submit, poll, download, then finish on this Mac. New shots, extensions and bridges
    /// send their frames (`frame_images`); a changed shot and sharpening through a service send the range itself.
    private func makeShot(_ r: MadeRequest, folder: URL, scratch: URL, job: JobRecord, label: String) async throws -> Piece {
        var body: [String: JSONValue] = ["model": .string(r.version.id)]
        if !r.ask.isEmpty { body["prompt"] = .string(r.ask) }
        if r.version.changesVideo || r.version.upscales {
            guard let from = r.from, let end = from.end, let asset = r.fromAsset else { throw DirectionError("invalid_arguments", "\(r.kind.label) needs a range of a take.") }
            progress(job, "Taking \(Self.seconds(end - from.start)) of \(asset.name)", 0.02)
            let clip = scratch.appendingPathComponent(UUID().uuidString + ".mp4")
            defer { try? FileManager.default.removeItem(at: clip) }
            try await MadeProcessing.exportRange(asset.path, start: from.start, end: end, maxDimension: r.version.upscales ? 1920 : 1280, to: clip)
            var refs: [JSONValue] = [.object(["type": .string("video_url"), "video_url": .object(["url": .string(MadeMedia.dataURL(try Data(contentsOf: clip), mime: "video/mp4"))])])]
            if r.version.upscales {
                let height = Double(asset.video.first?.height ?? r.cut.height)
                body["upscale_factor"] = .number(min(3, max(1.5, (Double(r.cut.height) / max(1, height) * 10).rounded() / 10)))
            } else {
                refs += try await references(r)
                if !r.version.aspectRatios.isEmpty { body["aspect_ratio"] = .string(r.aspect) }
            }
            body["input_references"] = .array(refs)
        } else {
            body["aspect_ratio"] = .string(r.aspect)
            if let d = r.estimate.duration { body["duration"] = .number(Double(d)) }
            if let res = r.estimate.resolution { body["resolution"] = .string(res) }
            body["generate_audio"] = .bool(r.sound)
            var frames: [JSONValue] = []
            for (source, role) in [(r.first, "first_frame"), (r.last, "last_frame")] {
                guard let source else { continue }
                progress(job, "Taking the frame from \(source.asset.name)", 0.02)
                let frame = try await MadeMedia.frame(of: source.asset.path, at: source.frame.at ?? 0, isImage: source.asset.isImage)
                frames.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string(MadeMedia.dataURL(frame, mime: "image/jpeg"))]), "frame_type": .string(role)]))
            }
            if !frames.isEmpty { body["frame_images"] = .array(frames) }
            if !r.references.isEmpty { body["input_references"] = .array(try await references(r)) }
        }
        let submitted = try await OpenRouter.submitVideo(.object(body))
        // Sent, so paid for from here on, a cancel or a lost poll included, unless OpenRouter itself says it
        // couldn't make the shot. The cost is the last one a poll reported.
        let reported = OSAllocatedUnfairLock<Double?>(initialState: nil)
        do {
            progress(job, "Waiting for \(r.version.name)\(label)", 0.1)
            let name = r.version.name, making = r.kind == .changedShot ? "changing the shot" : r.kind == .upscale ? "sharpening the shot" : "making the shot"
            let done = try await OpenRouter.waitForVideo(submitted.id) { [weak self] j in
                if let c = j.cost { reported.withLock { $0 = c } }
                self?.progress(job, j.status == "in_progress" ? "\(name) is \(making)\(label)" : "Waiting for \(name)\(label)", j.status == "in_progress" ? 0.5 : 0.1)
            }
            progress(job, "Downloading the shot\(label)", 0.8)
            let data = try await OpenRouter.videoContent(submitted.id)
            let downloaded = scratch.appendingPathComponent(UUID().uuidString + ".mp4")
            try data.write(to: downloaded)
            defer { try? FileManager.default.removeItem(at: downloaded) }
            let (output, sharpenedFrom) = try await finish(downloaded, r, folder: folder, job: job, label: label)
            return Piece(url: output, cost: done.cost, way: 1, sharpenedFrom: sharpenedFrom)
        } catch let e as DirectionError where e.code == "shot_failed" {
            if let cost = reported.withLock({ $0 }), cost > 0 { throw PaidThenFailed(underlying: e, cost: cost) }
            throw e
        } catch { throw PaidThenFailed(underlying: error, cost: reported.withLock { $0 }) }
    }

    /// Finishing a made shot (made-media.md): sharpen it to the cut's size when the cut is 1.5× taller and this Mac can,
    /// and drop the frame an extended shot repeats. Returns the film's file and the size it was sharpened from.
    /// Without either, the file is kept as made.
    private func finish(_ input: URL, _ r: MadeRequest, folder: URL, job: JobRecord, label: String) async throws -> (URL, String?) {
        func named(_ ext: String) -> URL { folder.appendingPathComponent(MadeMedia.fileName(r.kind, asked: r.ask.isEmpty ? (r.fromAsset?.name ?? "") : r.ask, ext: ext)) }
        func asMade() throws -> URL { let out = named("mp4"); try FileManager.default.copyItem(at: input, to: out); return out }
        var steps = MadeProcessing.Steps()
        if r.kind == .extension { if r.from?.side == "head" { steps.dropLastFrame = true } else { steps.dropFirstFrame = true } }
        var size: MadeProcessing.Steps.Size?
        if r.kind != .upscale, let s = await Self.videoSize(input), Double(r.cut.height) >= Double(s.height) * 1.5, await sharpeningReady(s, job: job) {
            steps.sharpenTo = r.cut; size = s
        }
        if steps == MadeProcessing.Steps() { return (try asMade(), nil) }
        let output = named("mov")
        let phase = steps.sharpenTo != nil ? "Sharpening the shot on this Mac\(label)" : "Joining the shot\(label)"
        progress(job, phase, 0.85)
        do {
            let result = try await MadeProcessing.process(input, steps, to: output) { [weak self] p in self?.progress(job, phase, 0.85 + p * 0.1) }
            return (output, result.sharpened ? size.map { "\($0.width) \u{00D7} \($0.height)" } : nil)
        } catch {
            // Finishing is a nicety: the shot is paid for, so it comes in as made.
            try? FileManager.default.removeItem(at: output)
            return (try asMade(), nil)
        }
    }

    /// Whether Apple's sharpening can run for this size, fetching its files the first time.
    private func sharpeningReady(_ s: MadeProcessing.Steps.Size, job: JobRecord) async -> Bool {
        switch MadeProcessing.sharpeningStatus(width: s.width, height: s.height) {
        case .ready: return true
        case .unsupported: return false
        case .needsDownload, .downloading:
            do {
                try await MadeProcessing.prepareSharpening(width: s.width, height: s.height) { [weak self] p in self?.progress(job, "Getting this Mac\u{2019}s sharpening ready", 0.82 + p * 0.03) }
                return MadeProcessing.sharpeningStatus(width: s.width, height: s.height) == .ready
            } catch { return false }
        }
    }

    /// Slow motion on this Mac: Apple's frame interpolation over the range.
    private func makeSlowMotion(_ r: MadeRequest, folder: URL, job: JobRecord) async throws -> Piece {
        guard let from = r.from, let end = from.end, let asset = r.fromAsset, let factor = r.factor else { throw DirectionError("invalid_arguments", "Slow motion needs a range of a take.") }
        let output = folder.appendingPathComponent(MadeMedia.fileName(.slowMotion, asked: asset.name, ext: "mov"))
        _ = try await MadeProcessing.process(URL(fileURLWithPath: asset.path), MadeProcessing.Steps(range: from.start...end, slowMotion: factor, keepSound: false), to: output) { [weak self] p in
            self?.progress(job, "Making slow motion on this Mac", p * 0.95)
        }
        return Piece(url: output, cost: 0, way: 1)
    }

    /// Sharpening on this Mac: Apple's super resolution, fitted to the cut.
    private func sharpenHere(_ r: MadeRequest, folder: URL, job: JobRecord) async throws -> Piece {
        guard let from = r.from, let end = from.end, let asset = r.fromAsset, let stream = asset.video.first else { throw DirectionError("invalid_arguments", "Sharpening needs a range of a take.") }
        let size = MadeProcessing.Steps.Size(width: stream.width, height: stream.height)
        guard r.cut.height > stream.height else { throw DirectionError("nothing_to_sharpen", "\(asset.name) is already \(stream.width) \u{00D7} \(stream.height), as big as the cut.") }
        guard await sharpeningReady(size, job: job) else {
            throw DirectionError("cant_sharpen", "This Mac can\u{2019}t sharpen \(asset.name) (\(stream.width) \u{00D7} \(stream.height)); Apple\u{2019}s sharpening takes up to 1920 \u{00D7} 1080. FLUX Video Upscale through OpenRouter can.")
        }
        let output = folder.appendingPathComponent(MadeMedia.fileName(.upscale, asked: asset.name, ext: "mov"))
        let result = try await MadeProcessing.process(URL(fileURLWithPath: asset.path), MadeProcessing.Steps(range: from.start...end, sharpenTo: r.cut, keepSound: true), to: output) { [weak self] p in
            self?.progress(job, "Sharpening on this Mac", p * 0.95)
        }
        return Piece(url: output, cost: 0, way: 1, sharpenedFrom: result.sharpened ? "\(size.width) \u{00D7} \(size.height)" : nil)
    }

    /// Stills: `POST /images`, shaped like the film.
    private func makeStill(_ r: MadeRequest, folder: URL, job: JobRecord, label: String) async throws -> Piece {
        progress(job, "Making the still with \(r.version.name)\(label)", 0.2)
        var body: [String: JSONValue] = ["model": .string(r.version.id), "prompt": .string(r.ask), "aspect_ratio": .string(r.aspect)]
        if !r.references.isEmpty { body["input_references"] = .array(try await references(r)) }
        let reply = try await OpenRouter.image(.object(body))
        let ext = reply.mediaType.contains("jpeg") ? "jpg" : reply.mediaType.contains("webp") ? "webp" : "png"
        let output = folder.appendingPathComponent(MadeMedia.fileName(.still, asked: r.ask, ext: ext))
        try reply.image.write(to: output)
        return Piece(url: output, cost: reply.cost, way: 1)
    }

    /// Up to four frames of the film, each from its still or the take's moment.
    /// The frames a request sends, as the service will see them, to check for people first.
    private nonisolated func frameData(_ sources: [MadeFrameSource]) async throws -> [Data] {
        var out: [Data] = []
        for source in sources.prefix(6) { out.append(try await MadeMedia.frame(of: source.asset.path, at: source.frame.at ?? 0, isImage: source.asset.isImage)) }
        return out
    }

    private nonisolated func references(_ r: MadeRequest) async throws -> [JSONValue] {
        var out: [JSONValue] = []
        for source in r.references.prefix(4) {
            let frame = try await MadeMedia.frame(of: source.asset.path, at: source.frame.at ?? 0, isImage: source.asset.isImage)
            out.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string(MadeMedia.dataURL(frame, mime: "image/jpeg"))])]))
        }
        return out
    }

    static func videoSize(_ url: URL) async -> MadeProcessing.Steps.Size? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let size = natural.applying(transform)
        return MadeProcessing.Steps.Size(width: Int(abs(size.width).rounded()), height: Int(abs(size.height).rounded()))
    }

    /// "5 s", "2.4 s".
    static func seconds(_ s: Double) -> String { s.rounded() == s || s >= 10 ? "\(Int(s.rounded())) s" : String(format: "%.1f s", s) }
}
