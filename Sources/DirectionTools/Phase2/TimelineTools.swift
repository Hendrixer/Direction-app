import Foundation
import DirectionCore
import DirectionMedia

// The editor's timeline and edit functions (specs/agent-timeline.md). The editor reads the cut as
// OpenTimelineIO and changes it only through direction_edit; no tool takes a timeline document.
extension ToolCatalog {
    static var timelineDefinitions: [ToolDefinition] { [
        definition("direction_timeline", "Read the cut as OpenTimelineIO JSON (read-only) plus a compact outline. Every item carries its id in metadata.direction.id; edit functions refer to those ids, and an edit point is \"<left clip>|<right clip>\". V1 is the story, V2+ overlays (graphics, cutaways, made shots); A1 is V1's own sound, A2 music, A3 effects. Effect params are in metadata.direction.params and keys (cut seconds) in metadata.direction.keys. Markers carry scenes and notes. cut names a saved cut (\"Cut 3\" or its id); revision pins one; range limits the items to those overlapping {start, end} seconds. You may save the document and analyze it in a script, but changes go only through direction_edit.", ["cut": string, "revision": integer, "sequenceID": string, "range": record(["start": number, "end": number], required: ["start", "end"]), "outlineOnly": bool]),
        definition("direction_edit_catalog", "Every edit function with its arguments, every effect and transition with its parameters' ranges and defaults, the error codes, and the custom shader effects in the film's Effects folder that compile."),
    ] }
}

extension ToolRuntime {
    func invokeTimeline(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_timeline":
            let cuts = try store.cuts()
            var revision = a["revision"].int, cutName: String, sequenceID = a["sequenceID"].string
            if let wanted = a["cut"].string {
                guard let cut = cuts.first(where: { $0.id == wanted || $0.name.lowercased() == wanted.lowercased() || "cut \($0.name.lowercased())" == wanted.lowercased() }) else { throw DirectionError("bad_argument", "There's no cut \(wanted). direction_cuts lists them.") }
                revision = cut.editRevision; cutName = cut.name; sequenceID = sequenceID ?? cut.sequenceID
            } else {
                let current = try store.revision(), at = revision ?? current
                let named = cuts.filter { $0.editRevision == at }.max { $0.createdAt < $1.createdAt }
                cutName = named?.name ?? (at == current ? (cuts.isEmpty ? "Assembly" : "Cut \(cuts.count + 1)") + " (working)" : "Revision \(at)")
            }
            let p = try store.read(revision: revision), s = try p.sequence(sequenceID)
            var range: MediaRange?
            if a["range"] != .null {
                guard let start = a["range"]["start"].double, let end = a["range"]["end"].double, start >= 0, end > start else { throw DirectionError("bad_argument", "range is {start, end} in seconds.") }
                range = MediaRange(start: start, end: end)
            }
            let doc = TimelineExport.document(.init(project: p, sequence: s, cutName: cutName, dailies: try store.dailies(), notes: try store.notes(), looks: try? store.lookContext(), range: range))
            var value: [String: JSONValue] = ["cut": .string(cutName), "editRevision": .number(Double(p.editRevision)), "sequenceID": .string(s.id), "outline": .string(doc.outline)]
            if a["outlineOnly"].bool != true { value["otio"] = doc.otio }
            return ToolResponse(.object(value))

        case "direction_edit_catalog":
            var custom: [JSONValue] = [], problems: [JSONValue] = []
            let folder = store.url.appendingPathComponent("Effects")
            for file in ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter({ $0.pathExtension == "metal" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let path = "Effects/" + file.lastPathComponent
                do {
                    let params = try ShaderEffect.declared(source: try String(contentsOf: file, encoding: .utf8))
                    custom.append(.object(["effect": .string("shader"), "file": .string(path), "params": try .wrapping(params)]))
                } catch let e as DirectionError { problems.append(.object(["file": .string(path), "code": .string(e.code), "message": .string(e.message)])) }
            }
            var value = EditCatalog.json(custom: custom, problems: problems)
            if case .object(var fields) = value {
                let state = try store.directingState()
                fields["transitionsSetting"] = .string(SharedSettings.defaults.string(forKey: "transitions") ?? "hard")
                fields["transitionsMeaning"] = .string("Settings › Cutting › Transitions: “hard” means hard cuts unless a note asks for a dissolve or a dip; “editor” lets you choose them, still within latitude.")
                fields["latitude"] = .string(state.latitude.rawValue)
                fields["pictureLocked"] = .bool(state.pictureLocked)
                value = .object(fields)
            }
            return ToolResponse(value)

        default: return nil
        }
    }

    /// direction_edit: reads the batch, measures what operations need from the footage (faces, balance,
    /// stabilization, quiet, shaders, graphics), then lets the store carry it out exactly or not at all.
    func invokeEdit(_ a: JSONValue) async throws -> ToolResponse {
        let b = a["batch"] != .null ? a["batch"] : a
        let validateOnly = a["validateOnly"].bool ?? b["validateOnly"].bool ?? false
        guard let base = b["baseEditRevision"].int, base >= 0 else { throw DirectionError("bad_argument", "baseEditRevision is the editRevision you read from direction_timeline.") }
        guard let list = b["operations"].array, !list.isEmpty else { throw DirectionError("bad_argument", "operations lists the edit functions to run, in order.") }
        var ops: [EditOperation] = []
        for (i, value) in list.enumerated() {
            do { var op = try EditOperation(json: value); op.resolved = nil; ops.append(op) }
            catch let e as DirectionError { throw DirectionError(e.code, e.message, index: i) }
        }
        if case .array(let notes) = b["notes"] { guard notes.allSatisfy({ $0.int != nil }) else { throw DirectionError("bad_argument", "notes lists note numbers, like [1, 4].") } }
        var batch = EditBatch(baseEditRevision: base, sequenceID: b["sequenceID"].string, idempotencyKey: b["idempotencyKey"].string ?? UUID().uuidString, summary: b["summary"].string ?? "Edited the cut", notes: b["notes"].array?.compactMap(\.int), operations: ops)
        let p = try store.read()
        guard p.editRevision == base else { throw DirectionError("stale_revision", "This batch is based on revision \(base); the cut is now at \(p.editRevision). Read direction_timeline again and replan.") }
        let s = try p.sequence(batch.sequenceID)
        for i in batch.operations.indices {
            do { try await resolve(&batch.operations[i], p, s) }
            catch let e as DirectionError { throw DirectionError(e.code, e.message, index: i) }
        }
        return ToolResponse(try .wrapping(store.edit(batch, validateOnly: validateOnly)))
    }

    private func resolve(_ op: inout EditOperation, _ p: Project, _ s: DirectionCore.Sequence) async throws {
        func clip(_ id: String?) -> Clip? { id.flatMap { id in s.clips.first { $0.id == id } } }
        func asset(_ c: Clip) -> MediaAsset? { c.assetID.flatMap { id in p.assets.first { $0.id == id } } }
        func existing(_ id: String?) -> ClipEffect? { id.flatMap { id in s.clips.lazy.compactMap { $0.effect(id) }.first ?? s.tracks?.values.lazy.compactMap { $0.effects?.first { $0.id == id } }.first } }
        switch op.type {
        case "reframe":
            guard let follow = op.follow, ["face", "subject"].contains(follow), let c = clip(op.clipID), let a = asset(c), !a.video.isEmpty, (0.1...8).contains(op.scale ?? 0) else { return }
            op.resolved = try await TimelineAnalysis.follow(asset: a, clip: c, subject: follow, scale: op.scale!, keepIn: op.keepIn, frame: CGSize(width: s.width, height: s.height))
        case "matchBalance":
            guard let c = clip(op.clipID), let r = clip(op.toClipID), let a = asset(c), let ra = asset(r), !a.video.isEmpty, !ra.video.isEmpty else { return }
            op.resolved = .init(grade: try await TimelineAnalysis.matchBalance(asset: a, clip: c, referenceAsset: ra, reference: r))
        case "addEffect", "setEffect":
            let current = op.type == "setEffect" ? existing(op.effectID) : nil
            let name = op.type == "addEffect" ? op.effect : current?.name
            if name == "stabilize", op.type == "addEffect", let c = clip(op.target ?? op.clipID), let a = asset(c), !a.video.isEmpty, c.hold == nil {
                op.resolved = .init(keys: try await TimelineAnalysis.stabilize(asset: a, clip: c, cacheDirectory: cacheDirectory))
            }
            if name == "shader" {
                let params = (current?.params ?? [:]).merging(op.params ?? [:]) { _, b in b }
                let source: String
                if let file = op.params?["file"]?.string { source = try shaderSource(file) }
                else if let kept = current?.source { source = kept }
                else { throw DirectionError("bad_argument", "A shader effect takes params.file, like \"Effects/warm.metal\".") }
                // Every shader is compiled and timed on 3 frames at 1080p before it touches the cut.
                _ = try ShaderEffect.check(source: source, params: params.filter { $0.key != "file" })
                op.resolved = .init(source: source)
            }
        case "tightenPauses":
            guard let r = op.range else { return }
            if let quiet = try? await TimelineAnalysis.quietRanges(project: p, sequence: s, range: r, cacheDirectory: cacheDirectory) { op.resolved = .init(quiet: quiet) }
        case "placeGraphic":
            if let g = op.graphic, let id = try store.graphicAssetID(g) { op.resolved = .init(assetID: id) }
        default: break
        }
    }

    /// `Effects/<name>.metal` inside the film, and nowhere else.
    private func shaderSource(_ file: String) throws -> String {
        let folder = store.url.appendingPathComponent("Effects").standardizedFileURL
        let url = store.url.appendingPathComponent(file).standardizedFileURL
        guard url.pathExtension == "metal", url.deletingLastPathComponent().path == folder.path else { throw DirectionError("bad_argument", "A shader lives in the film's Effects folder: \"Effects/<name>.metal\".") }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw DirectionError("missing_media", "There's no \(file) in this film.") }
        return text
    }
}
