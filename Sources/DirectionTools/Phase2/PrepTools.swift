import Foundation
import DirectionCore

// Prep (specs/script.md, specs/breakdown.md): the A/V script and the breakdown, for the editor to write the
// picture, break it into shots by setup, and answer the director's notes on both.
extension ToolCatalog {
    static var prepDefinitions: [ToolDefinition] {
        let sizes = strings(ShotSize.allCases.map(\.rawValue)), moves = strings(ShotMove.allCases.map(\.rawValue)), boards = strings(BoardKind.allCases.map(\.rawValue))
        let choice = record(["id": string, "label": string, "detail": string, "recommended": bool], required: ["label"])
        let reply = record(["noteID": string, "reply": string], required: ["noteID", "reply"])
        return [
            definition("direction_script", "Read the film's A/V script a page at a time (from: the first row number, default 1; count: rows, default 40; next is where the following page starts, null at the end): each row in order, its picture (what we see: text, size wide|medium|close|detail, move, board, yours: true when the director wrote it) and its sound (kind voice|onCamera|effect|music|silence, speaker, the words, ownWords: true when the speaker finds the words on the day and the text says what about), its seconds, the writer's picture idea (hint) and any question you asked. kind is script (the sound is the script's words) or story (Direction laid out a story as beats: each row has its part of the story, and what we hear is yours to write too). storyNotes, on the first page, is what the story's writer wrote around the beats they numbered (the idea, its rules, questions for the director): follow it, and ask the director what only they can answer. notes are the director's notes on rows; the turned-over ones are yours to answer this pass. okAt is set once the director OKs it.", ["from": integer, "count": integer]),
            definition("direction_script_update", "Write the A/V script's picture column and answer notes on it. pictures: [{rowID, text (what the viewer sees, one or two sentences, never how to shoot it), size?, move?, board? (the drawn board: title, screen, wide, medium, close, detail, onCamera, action, made, empty)}]. Follow the film's style (direction_style) for what each kind of line reaches for. A picture the director wrote (yours) and the words of the script change only where a turned-over note on that row asks; anything else comes back in refused. sounds: [{rowID, kind?, speaker?, text?, ownWords?, seconds?}] fixes what a row's sound is; in a film from a story it's what we hear, yours to write on every row: never words for anyone to say (the text says who talks and what about, with ownWords: true), except words the story quotes, and seconds for how long the beat plays. replies: [{noteID, reply}] answers a turned-over note, first person and concrete (\"Row 4 is your hands now.\"). questions: [{rowID, text, choices: [{id?, label, detail?, recommended?}]}] when only the director can say what a row should show: 2–3 concrete choices.", [
                "pictures": list(record(["rowID": string, "text": string, "size": sizes, "move": moves, "board": boards], required: ["rowID", "text"])),
                "sounds": list(record(["rowID": string, "kind": strings(HeardKind.allCases.map(\.rawValue)), "speaker": string, "text": string, "ownWords": bool, "seconds": number], required: ["rowID"])),
                "replies": list(reply),
                "questions": list(record(["rowID": string, "text": string, "choices": list(choice)], required: ["rowID", "text", "choices"])),
            ], readOnly: false),
            definition("direction_breakdown", "Read the breakdown: setups (number, name, needs, noCamera) and their shots (code: the slate, like 2C; the rows it plays under; what we see; how to shoot it; what it's for; size; move; seconds; source shoot|screen|make|have|sound; makePlan and estimate for made shots; coverage: planned, got with its takes, missing, needsFootage or toMake; the director's choice for a missing shot). scriptChanged says the script moved on since the breakdown was last made. notes are the director's notes on shots. includeScript adds a page of the A/V script (from: the first row, default 1; count: rows, default 40; its next is where the following page starts) with each row's picture as words (and, in a film from a story, its kind story and each beat's part of the story; talk with ownWords is found on the day, so it's shot with sound): add that page's shots before reading the next.", ["includeScript": bool, "from": integer, "count": integer]),
            definition("direction_breakdown_update", "Lay out the breakdown, or change it. setups: [{id?, name, needs? (what it takes: time of day, light, props, what's on the screen), noCamera? (screen recordings, made shots, footage the director has)}]: group shots by place and light, so each setup is set up once. shots: [{id? (to change one), setupID or setup (a setup's name), rowIDs (the rows it plays under, in order), what (what we see and what happens, in plain words), how? (how to get it on the day, for a director who's never been on a set: where the camera goes and whether it moves, how long to record, what to get right; not for made shots), why? (what it's for, in a line, when what we see doesn't say), size?, move?, seconds?, source (shoot, screen for a screen recording, make, have when the director said they have it, sound for sound only like a narration), board?, makePlan? and estimate? (dollars, nil when it's free like a graphic) for source make}]. No crew shorthand in the words (locked off, plate, cover, matte, layer, roll). Direction numbers setups in the order they're needed and letters shots by row; once the director OKs the breakdown the numbers are slates and never change, and a new shot takes the next letter. Name another shot by the number Direction last gave it: when Direction numbers shots again, the numbers in the words follow, and toFix lists any number that names no shot. remove: shot ids. Fields the director set, and footage they added, change only where a turned-over note asks. replies: [{noteID, reply}]; questions: [{shotID, text, choices}].", [
                "setups": list(record(["id": string, "name": string, "needs": string, "noCamera": bool], required: ["name"])),
                "shots": list(record(["id": string, "setupID": string, "setup": string, "rowIDs": list(string), "what": string, "how": string, "why": string, "size": sizes, "move": moves, "seconds": number, "source": strings(ShotSource.allCases.map(\.rawValue)), "board": boards, "makePlan": string, "estimate": number])),
                "remove": list(string),
                "replies": list(reply),
                "questions": list(record(["shotID": string, "text": string, "choices": list(choice)], required: ["shotID", "text", "choices"])),
            ], readOnly: false),
        ]
    }
}

extension ToolRuntime {
    func invokePrep(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_script":
            guard let s = try store.script() else { return ToolResponse(.object(["script": .null, "note": .string("This film has no script. The director brings one in from the Script room.")])) }
            return ToolResponse(try Self.scriptJSON(s, from: a["from"].int ?? 1, count: a["count"].int ?? 40))

        case "direction_script_update":
            let pictures = try a["pictures"].array.map { try JSONValue.array($0).decode([PictureInput].self) } ?? []
            let sounds = try a["sounds"].array.map { try JSONValue.array($0).decode([SoundInput].self) } ?? []
            let (replies, questions) = try Self.repliesAndQuestions(a, key: "rowID")
            guard try store.script() != nil else { throw DirectionError("script_not_found", "This film has no script yet.") }
            let (s, refused) = try store.updateScript(pictures: pictures, sounds: sounds, replies: replies, questions: questions)
            var out: [String: JSONValue] = [
                "revision": .number(Double(s.revision)), "pass": .number(Double(s.pass)),
                "rowsWithoutPicture": .array(s.rows.enumerated().filter { $0.element.picture.isEmpty }.map { .number(Double($0.offset + 1)) }),
                "notesWaiting": .array(s.turnedOver.map { .number(Double($0.number)) }),
                "refused": .array(refused.map(JSONValue.string)),
            ]
            if s.isStory { out["rowsWithoutSound"] = .array(s.rows.enumerated().filter { $0.element.soundUndecided }.map { .number(Double($0.offset + 1)) }) }
            return ToolResponse(.object(out))

        case "direction_breakdown":
            guard let b = try store.breakdown() else {
                return ToolResponse(.object(["breakdown": .null, "note": .string(try store.script()?.isOK == true ? "Not broken down yet." : "The script isn't OK'd yet.")]))
            }
            var value = try Self.breakdownJSON(b, script: try store.script(), coverage: ProjectStore.coverage(b, dailies: try store.dailies()))
            if a["includeScript"].bool == true, let s = try store.script(), case .object(var o) = value { o["script"] = try Self.scriptJSON(s, from: a["from"].int ?? 1, count: a["count"].int ?? 40, compact: true); value = .object(o) }
            return ToolResponse(value)

        case "direction_breakdown_update":
            let setups = try a["setups"].array.map { try JSONValue.array($0).decode([SetupInput].self) } ?? []
            let shots = try a["shots"].array.map { try JSONValue.array($0).decode([ShotInput].self) } ?? []
            let remove = a["remove"].array?.compactMap(\.string) ?? []
            let (replies, questions) = try Self.repliesAndQuestions(a, key: "shotID")
            guard try store.script() != nil else { throw DirectionError("script_not_found", "This film has no script to break down.") }
            let (b, refused, toFix) = try store.updateBreakdown(setups: setups, shots: shots, remove: remove, replies: replies, questions: questions)
            let covered = Set(b.shots.flatMap(\.rowIDs))
            let script = try store.script()
            return ToolResponse(.object([
                "setups": .number(Double(b.setups.count)), "shots": .array(b.shots.map { .string("\($0.code) \($0.what)") }),
                "rowsWithoutShot": .array((script?.rows ?? []).enumerated().filter { !covered.contains($0.element.id) }.map { .number(Double($0.offset + 1)) }),
                "notesWaiting": .array(b.turnedOver.map { .number(Double($0.number)) }),
                "refused": .array(refused.map(JSONValue.string)),
                "toFix": .array(toFix.map(JSONValue.string)),
            ]))
        default: return nil
        }
    }

    static func repliesAndQuestions(_ a: JSONValue, key: String) throws -> ([String: String], [String: PrepQuestion]) {
        var replies: [String: String] = [:], questions: [String: PrepQuestion] = [:]
        for r in a["replies"].array ?? [] {
            guard let id = r["noteID"].string ?? r["noteID"].int.map(String.init), let text = r["reply"].string else { throw DirectionError("invalid_arguments", "Each reply is {noteID, reply}.") }
            replies[id] = text
        }
        for q in a["questions"].array ?? [] {
            guard let id = q[key].string, let text = q["text"].string, let choices = q["choices"].array, (1...4).contains(choices.count) else { throw DirectionError("invalid_arguments", "Each question is {\(key), text, choices: 1–4 of {label, detail?}}.") }
            questions[id] = PrepQuestion(text: text, choices: choices.enumerated().map { i, c in PrepQuestion.Choice(id: c["id"].string ?? "choice-\(i + 1)", label: c["label"].string ?? "Choice \(i + 1)", detail: c["detail"].string, recommended: c["recommended"].bool) })
        }
        return (replies, questions)
    }

    /// A page of rows, compact: a picture only when it has one, the sound as kind, speaker and words.
    static func scriptJSON(_ s: AVScript, from: Int, count: Int, compact: Bool = false) throws -> JSONValue {
        let sections = Dictionary(s.sections.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let first = max(1, from), last = min(s.rows.count, first + max(1, count) - 1)
        let page = first <= last ? Array(Array(s.rows.enumerated())[(first - 1)...(last - 1)]) : []
        let rows: [JSONValue] = try page.map { i, r in
            var sound: [String: JSONValue] = ["kind": .string(r.sound.kind.rawValue), "text": .string(r.sound.text)]
            if let sp = r.sound.speaker { sound["speaker"] = .string(sp) }
            if r.sound.ownWords == true { sound["ownWords"] = .bool(true) }
            if r.sound.yours == true { sound["yours"] = .bool(true) }
            var o: [String: JSONValue] = ["id": .string(r.id), "number": .number(Double(i + 1)), "sound": .object(sound), "seconds": .number(r.seconds)]
            if let st = r.story { o["story"] = .string(st) }
            if !r.picture.isEmpty { o["picture"] = compact ? .string(r.picture.text) : try .wrapping(r.picture) }
            if let sec = r.section.flatMap({ sections[$0] }) { o["section"] = .string(sec) }
            if let h = r.hint { o["hint"] = .string(h) }
            if let q = r.question { o["question"] = try .wrapping(q) }
            return .object(o)
        }
        let notes: [JSONValue] = s.notes.filter { $0.state != .dropped && $0.state != .written }.map { n in
            .object(["id": .string(n.id), "number": .number(Double(n.number)), "rows": .array((n.rowIDs ?? []).compactMap { s.number(of: $0) }.map { .number(Double($0)) }),
                     "kind": n.kind.map { .string($0.rawValue) } ?? .null, "text": .string(n.text), "state": .string(n.state.rawValue), "reply": n.reply.map(JSONValue.string) ?? .null])
        }
        return .object([
            "kind": .string((s.kind ?? .script).rawValue),
            // Long, so only with the first page.
            "storyNotes": first == 1 ? s.storyNotes.map(JSONValue.string) ?? .null : .null,
            "source": s.source.map { .string("\($0.fileName), \($0.words) words") } ?? .null,
            "sections": .array(s.sections.map { .string($0.title) }),
            "rows": .array(rows), "total": .number(Double(s.rows.count)), "next": last < s.rows.count ? .number(Double(last + 1)) : .null,
            "withoutPicture": .number(Double(s.rows.filter { $0.picture.isEmpty }.count)),
            "withoutSound": s.isStory ? .number(Double(s.rows.filter(\.soundUndecided).count)) : .null,
            "notes": .array(notes), "pass": .number(Double(s.pass)), "revision": .number(Double(s.revision)),
            "seconds": .number(s.seconds), "okAt": s.okAt.map(JSONValue.number) ?? .null,
        ])
    }

    static func breakdownJSON(_ b: Breakdown, script: AVScript?, coverage: [String: ShotCoverage]) throws -> JSONValue {
        let setups: [JSONValue] = b.setups.sorted { $0.number < $1.number }.map { setup in
            let shots: [JSONValue] = b.shots(in: setup.id).map { shot in
                var o: [String: JSONValue] = ["id": .string(shot.id), "code": .string(shot.code), "what": .string(shot.what), "seconds": .number(shot.seconds), "source": .string(shot.source.rawValue),
                                              "rows": .array(shot.rowIDs.compactMap { script?.number(of: $0) }.map { .number(Double($0)) }), "rowIDs": .array(shot.rowIDs.map(JSONValue.string))]
                if let v = shot.how { o["how"] = .string(v) }
                if let v = shot.why { o["why"] = .string(v) }
                if let v = shot.size { o["size"] = .string(v.rawValue) }
                if let v = shot.move { o["move"] = .string(v.rawValue) }
                if let v = shot.makePlan { o["makePlan"] = .string(v) }
                if let v = shot.estimate { o["estimate"] = .number(v) }
                if let v = shot.haveAssetID { o["haveAssetID"] = .string(v) }
                if let v = shot.missing { o["missingChoice"] = .string(v.rawValue) }
                if let v = shot.yours, !v.isEmpty { o["yours"] = .array(v.map(JSONValue.string)) }
                switch coverage[shot.id] ?? .planned {
                case .planned: o["coverage"] = .string("planned")
                case .got(let ids): o["coverage"] = .string("got"); o["takes"] = .array(ids.map(JSONValue.string))
                case .missing: o["coverage"] = .string("missing")
                case .needsFootage: o["coverage"] = .string("needsFootage")
                case .toMake: o["coverage"] = .string("toMake")
                }
                if let q = shot.question { o["question"] = (try? .wrapping(q)) ?? .null }
                return .object(o)
            }
            return .object(["id": .string(setup.id), "number": .number(Double(setup.number)), "name": .string(setup.name), "needs": setup.needs.map(JSONValue.string) ?? .null, "noCamera": .bool(setup.noCamera == true), "shots": .array(shots)])
        }
        let notes: [JSONValue] = b.notes.filter { $0.state != .dropped && $0.state != .written }.map { n in
            .object(["id": .string(n.id), "number": .number(Double(n.number)), "shots": .array((n.shotIDs ?? []).compactMap { b.shot($0)?.code }.map(JSONValue.string)),
                     "kind": n.kind.map { .string($0.rawValue) } ?? .null, "text": .string(n.text), "state": .string(n.state.rawValue), "reply": n.reply.map(JSONValue.string) ?? .null])
        }
        return .object([
            "setups": .array(setups), "notes": .array(notes), "okAt": b.okAt.map(JSONValue.number) ?? .null,
            "scriptChanged": .bool((script?.revision ?? 0) > (b.scriptRevision ?? 0)), "estimate": .number(b.estimate),
        ])
    }
}

