import Foundation
import DirectionCore

// Handlers for the director–editor protocol. The editor reads turnovers, reads back,
// asks, and delivers cuts with answers; it never circles, accepts or unlocks.

private struct SceneInput: Decodable { var id: String?; var number: Int; var title: String; var setups: [DailiesSetup]? }
private struct TakeInput: Decodable {
    var assetID: String; var sceneID: String?; var sceneNumber: Int?; var setupCode: String?; var code: String?
    var caption: String?; var suggestion: String?; var guessSceneNumber: Int?; var flags: [String]?; var unusable: Bool?
}
private struct ReadBackInput: Decodable {
    var noteID: String; var plan: String; var delta: String?; var twoWays: Bool?
    var conflictWithNoteID: String?; var following: String?; var range: String?; var detail: String?; var cantYet: String?
}
private struct ChoiceInput: Decodable { var id: String?; var label: String; var detail: String?; var assetID: String?; var recommended: Bool? }
private struct FinishingInput: Decodable { var id: String; var title: String?; var detail: String?; var state: String?; var by: [String]?; var progress: Double? }

extension ToolRuntime {
    /// Check your work (footage-index.md › What the editor gets): a notes turnover is delivered only
    /// once every passage its edits changed has been watched with `direction_watch` at or after the
    /// revision that changed it. Ranges get a half-second of slack, since later edits can shift them.
    func checkWatched(turnoverID: String, revision: Int?) throws {
        guard let t = try store.turnovers().first(where: { $0.id == turnoverID }), t.kind == "notes" else { return }
        let final = try revision ?? store.read().editRevision
        let watched = try store.watchedRanges(since: t.createdAt)
        var missing: [JSONValue] = []
        for record in try store.editRecords(after: t.baseRevision, through: final) where record.committed {
            for change in record.operations.flatMap(\.changes) {
                let start = change.new.start - 0.5, end = change.new.end + 0.5
                guard !watched.contains(where: { $0.revision >= record.editRevision && $0.start < end && $0.end > start }) else { continue }
                missing.append(.object(["start": .number(change.new.start), "end": .number(change.new.end), "revision": .number(Double(record.editRevision))]))
            }
        }
        guard missing.isEmpty else {
            throw DirectionError("not_watched", "Watch every passage you changed with direction_watch before delivering. Not watched: \(missing.count) passage\(missing.count == 1 ? "" : "s"), starting \(missing.compactMap { $0["start"].double }.map { String(format: "%.1f s", $0) }.prefix(4).joined(separator: ", ")).")
        }
    }

    func invokeDirecting(_ name: String, _ a: JSONValue) throws -> ToolResponse? {
        switch name {
        case "direction_brief":
            let state = try store.directingState()
            return ToolResponse(.object(["brief": try .wrapping(store.brief()), "latitude": .string(state.latitude.rawValue), "pictureLocked": .bool(state.pictureLocked), "editorPaused": .bool(state.editorPaused), "preferences": try .wrapping(state.preferences ?? EditorPreferences()),
                                         "style": try store.style().map { .object(["id": .string($0.id), "name": .string($0.name), "summary": .string($0.summary), "read": .string("direction_style has its values, its guide and its parts. Follow it wherever the brief and the notes leave a choice open.")]) } ?? .null]))

        case "direction_dailies":
            let p = try store.read()
            // Each take's index (footage-index.md): waiting, looking, done or failed.
            autoIndexIfNeeded()
            let index = try indexStates()
            let assets: [JSONValue] = p.assets.map { .object(["id": .string($0.id), "name": .string($0.name), "durationSeconds": .number($0.duration.seconds), "hasAudio": .bool(!$0.audio.isEmpty), "index": .string((index[$0.id] ?? .done).rawValue)]) }
            return ToolResponse(.object(["dailies": try .wrapping(store.dailies()), "assets": .array(assets)]))

        case "direction_log_dailies":
            var d = try store.dailies()
            if let scenes = a["scenes"].array {
                let inputs = try scenes.map { try $0.decode(SceneInput.self) }
                d.scenes = inputs.map { s in
                    let existing = d.scenes.first { $0.id == s.id || $0.number == s.number }
                    return DailiesScene(id: s.id ?? existing?.id ?? newID("scene"), number: s.number, title: s.title, setups: s.setups ?? existing?.setups ?? [])
                }
            }
            func sceneID(_ number: Int?, _ id: String?) throws -> String? {
                if let id { guard d.scenes.contains(where: { $0.id == id }) else { throw DirectionError("scene_not_found", "Scene \(id) isn't logged.") }; return id }
                guard let number else { return nil }
                guard let s = d.scenes.first(where: { $0.number == number }) else { throw DirectionError("scene_not_found", "Scene \(number) isn't logged.") }
                return s.id
            }
            var takes: [String: TakeInfo] = [:]
            for value in a["takes"].array ?? [] {
                let t = try value.decode(TakeInput.self)
                var info = d.take(t.assetID)
                info.sceneID = try sceneID(t.sceneNumber, t.sceneID) ?? info.sceneID
                if let v = t.setupCode { info.setupCode = v }; if let v = t.code { info.code = v }; if let v = t.caption { info.caption = v }
                if let v = t.suggestion { info.suggestion = v.isEmpty ? nil : v }
                if let v = t.guessSceneNumber { info.guessSceneID = try sceneID(v, nil) }
                if let v = t.flags { info.flags = v }; if let v = t.unusable { info.unusable = v }
                takes[t.assetID] = info
            }
            return ToolResponse(try .wrapping(store.logDailies(Dailies(scenes: d.scenes, takes: takes))))

        case "direction_turnovers":
            let all = try store.turnovers(), notes = try store.notes(), questions = try store.questions()
            let shown = a["includeClosed"].bool == true ? all : all.filter(\.state.isOpen)
            // "@Name" in a note names something in the library: say what it is and how it's made.
            let library = LibraryCatalog.entries(techniques: TechniqueLibrary.list(in: SharedSettings.techniquesFolder))
            let items: [JSONValue] = try shown.map { t in
                let included = t.noteIDs.compactMap { id in notes.first { $0.id == id } }
                let named: [JSONValue] = included.compactMap { n in
                    let found = LibraryCatalog.mentions(in: n.text, entries: library)
                    return found.isEmpty ? nil : .object(["noteID": .string(n.id), "names": .string(LibraryCatalog.explain(found))])
                }
                return .object([
                    "turnover": try .wrapping(t),
                    "notes": try .wrapping(included),
                    "libraryNamed": .array(named),
                    "questions": try .wrapping(questions.filter { $0.turnoverID == t.id }),
                    "latitudeMeaning": .string(t.latitude.detail),
                    "mayStartCutting": .bool(!t.waitForOK || t.readBackApproved || t.kind == "assembly"),
                ])
            }
            return ToolResponse(.object(["turnovers": .array(items), "brief": try .wrapping(store.brief()), "preferences": try .wrapping(store.directingState().preferences ?? EditorPreferences())]))

        case "direction_turnover_update":
            let readBack: [ReadBackLine]? = try a["readBack"].array.map { lines in
                try lines.map { value in
                    let r = try value.decode(ReadBackInput.self)
                    let conflict = r.conflictWithNoteID.map { Conflict(withNoteID: $0, following: r.following ?? r.noteID, range: r.range, detail: r.detail) }
                    return ReadBackLine(noteID: r.noteID, plan: r.plan, delta: r.delta, twoWays: r.twoWays ?? false, conflict: conflict, cantYet: r.cantYet)
                }
            }
            var progress: [String: NoteProgress]?
            if case .object(let fields) = a["progress"] {
                progress = try fields.mapValues { v in guard let s = v.string, let p = NoteProgress(rawValue: s) else { throw DirectionError("invalid_arguments", "progress values are queued, working, done, cant or stopped.") }; return p }
            }
            let state = a["state"].string.flatMap(TurnoverState.init(rawValue:))
            return ToolResponse(try .wrapping(store.reportTurnover(id: a.requiredString("turnoverID"), state: state, readBack: readBack, progress: progress, phase: a["phase"].string, percent: a["percent"].double, message: a["message"].string)))

        case "direction_ask":
            let choices = try (a["choices"].array ?? []).enumerated().map { i, value in
                let c = try value.decode(ChoiceInput.self)
                return QuestionChoice(id: c.id ?? "choice-\(i + 1)", label: c.label, detail: c.detail, assetID: c.assetID, recommended: c.recommended ?? false)
            }
            let noteIDs = a["noteIDs"].array?.compactMap(\.string) ?? []
            let known = Set(try store.notes().map(\.id))
            for id in noteIDs where !known.contains(id) { throw DirectionError("feedback_not_found", "Note \(id) not found.") }
            var q = EditorQuestion(id: newID("question"), turnoverID: a["turnoverID"].string, kind: try a.requiredString("kind"), noteIDs: noteIDs, text: try a.requiredString("text"), detail: a["detail"].string, choices: choices, allowsText: a["allowsText"].bool ?? true, answer: nil, createdAt: 0)
            q.spend = try madeSpendAsk(a, kind: q.kind, choices: choices, turnoverID: q.turnoverID)
            return ToolResponse(try .wrapping(store.ask(q)))

        case "direction_questions":
            return ToolResponse(.object(["questions": try .wrapping(store.questions())]))

        case "direction_turnover_complete":
            try checkWatched(turnoverID: a.requiredString("turnoverID"), revision: a["revision"].int)
            let answers = try (a["answers"].array ?? []).map { try $0.decode(AnswerInput.self) }
            let (turnover, cut) = try store.completeTurnover(id: a.requiredString("turnoverID"), revision: a["revision"].int, sequenceID: a["sequenceID"].string, answers: answers)
            return ToolResponse(.object(["turnover": try .wrapping(turnover), "cut": try .wrapping(cut)]))

        case "direction_finishing":
            var state = try store.directingState()
            if let values = a["items"].array {
                guard state.pictureLocked else { throw DirectionError("picture_not_locked", "Finishing starts after picture lock.") }
                let current = state.finishing ?? FinishingItem.defaults
                let items = try values.map { value in
                    let f = try value.decode(FinishingInput.self)
                    var item = current.first { $0.id == f.id } ?? FinishingItem(id: f.id, title: f.title ?? f.id.capitalized, detail: f.detail ?? "", by: f.by ?? ["editor"])
                    if let v = f.title { item.title = v }; if let v = f.detail { item.detail = v }; if let v = f.state { item.state = v }
                    if let v = f.by { item.by = v }; if let v = f.progress { item.progress = v }
                    return item
                }
                state = try store.updateFinishing(items)
            }
            return ToolResponse(.object(["pictureLocked": .bool(state.pictureLocked), "items": try .wrapping(state.finishing ?? [])]))

        case "direction_add_outside_note":
            let p = try store.read(revision: a["revision"].int)
            let range = a["end"].double != nil ? MediaRange(start: a["start"].double ?? 0, end: a["end"].double!) : nil
            let time = range == nil ? a["time"].double.map { MediaTime(seconds: $0) } : nil
            let person = Person(name: try a.requiredString("name"), role: a["role"].string)
            let c = try store.addComment(text: a.requiredString("text"), author: person.name, sequenceID: nil, revision: p.editRevision, cutID: a["cutID"].string, range: range, time: time, extra: NoteFields(authorRole: "outside", person: person, sceneID: a["sceneID"].string, assignNumber: false))
            return ToolResponse(try .wrapping(c))

        case "direction_editor_status":
            try store.setEditorStatus(phase: a.requiredString("phase"), detail: a["detail"].string, progress: a["progress"].double, agent: a["agent"].string)
            return ToolResponse(.object(["ok": .bool(true)]))

        default: return nil
        }
    }
}
