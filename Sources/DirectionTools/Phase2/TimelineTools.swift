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
            var custom: [JSONValue] = [], problems: [JSONValue] = [], transitions: [JSONValue] = []
            for file in editorFiles("Effects", "metal") {
                let path = "Effects/" + file.lastPathComponent
                do {
                    let params = try ShaderEffect.declared(source: try String(contentsOf: file, encoding: .utf8))
                    custom.append(.object(["effect": .string("shader"), "file": .string(path), "params": try .wrapping(params)]))
                } catch let e as DirectionError { problems.append(.object(["file": .string(path), "code": .string(e.code), "message": .string(e.message)])) }
            }
            for file in editorFiles("Transitions", "metal") {
                let path = "Transitions/" + file.lastPathComponent
                do {
                    let params = try TransitionShader.declared(source: try String(contentsOf: file, encoding: .utf8))
                    transitions.append(.object(["type": .string("shader"), "file": .string(path), "params": try .wrapping(params)]))
                } catch let e as DirectionError { problems.append(.object(["file": .string(path), "code": .string(e.code), "message": .string(e.message)])) }
            }
            var value = EditCatalog.json(custom: custom, problems: problems)
            if case .object(var fields) = value {
                fields["customTransitions"] = .array(transitions)
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
                if let file = op.params?["file"]?.string { source = try editorSource(file, folder: "Effects") }
                else if let kept = current?.source { source = kept }
                else { throw DirectionError("bad_argument", "A shader effect takes params.file, like \"Effects/warm.metal\".") }
                // Every shader is compiled and timed on 3 frames at 1080p before it touches the cut.
                _ = try ShaderEffect.check(source: source, params: params.filter { $0.key != "file" })
                op.resolved = .init(source: source)
            }
        case "transition":
            // Direction's own and the editor's are compiled and timed before they touch the cut.
            guard let type = op.transitionType, type != "dissolve", type != "dipToBlack", type != "dipToWhite" else { return }
            let source: String
            if type == "shader" {
                guard let file = op.params?["file"]?.string else { throw DirectionError("bad_argument", "A shader transition takes params.file, like \"Transitions/flash.metal\".") }
                source = try editorSource(file, folder: "Transitions")
            } else if let own = TransitionShader.builtIn(type) { source = own } else { return }
            _ = try TransitionShader.check(source: source, params: (op.params ?? [:]).filter { $0.key != "file" })
            op.resolved = .init(source: source)
        case "pin":
            guard op.corners == nil || op.follow == "screen", let c = clip(op.clipID), c.layer > 0 else { return }
            guard let story = s.clips.filter({ $0.layer == 0 && $0.kind == .video && $0.start <= c.start && c.start < $0.end }).first, let a = asset(story), !a.video.isEmpty else {
                throw DirectionError("bad_argument", "There's no shot on V1 under \(c.name) to pin it into.")
            }
            op.resolved = try await TimelineAnalysis.pin(clip: c, story: story, asset: a, corners: op.corners, frame: CGSize(width: s.width, height: s.height), fps: s.frameRate.value)
        case "zoomThrough":
            guard let point = op.editPoint, let left = clip(point.split(separator: "|").first.map(String.init)), left.layer == 0, let a = asset(left), !a.video.isEmpty, left.hold == nil else { return }
            op.resolved = try await TimelineAnalysis.zoomThrough(left: left, asset: a, seconds: op.seconds ?? 1, corners: op.corners, frame: CGSize(width: s.width, height: s.height), fps: s.frameRate.value)
        case "tightenPauses":
            // How tight is the style's, unless the editor says.
            if op.longerThan == nil || op.to == nil, let pauses = (try? store.appliedStyle())?.moves.tightenPauses {
                if op.longerThan == nil { op.longerThan = pauses.longerThan }
                if op.to == nil { op.to = .number(pauses.to) }
            }
            guard let r = op.range else { return }
            if let quiet = try? await TimelineAnalysis.quietRanges(project: p, sequence: s, range: r, cacheDirectory: cacheDirectory) { op.resolved = .init(quiet: quiet) }
        case "placeGraphic":
            if let g = op.graphic, let id = try store.graphicAssetID(g) { op.resolved = .init(assetID: id) }
        case "layout":
            // A layout by name is one of the film's style's (or the house style's).
            if op.layout == nil, let name = op.layoutName {
                let applied = try store.appliedStyle()
                guard let found = applied.layout(named: name) else {
                    let names = applied.layouts.compactMap(\.name)
                    throw DirectionError("bad_argument", names.isEmpty ? "This film\u{2019}s style has no layouts by name. Give one: {kind, corner?, size?, shape?, screen?}." : "The style has no layout called \(name). It has \(names.joined(separator: ", ")).")
                }
                op.layout = found
            }
            guard op.layout != nil else { return }
            op.resolved = .init(layout: try await LayoutAnalysis.measure(project: p, sequence: s, dailies: try store.dailies(), range: op.range, cacheDirectory: cacheDirectory))
        case "punchIn", "emphasisPunch", "slowPush":
            // Moves take the style's numbers unless the editor gives its own, and frame on the faces layouts track.
            let moves = (try? store.appliedStyle())?.moves ?? .standard
            switch op.type {
            case "punchIn":
                if op.scales == nil { op.scales = moves.punchIn?.scales }
                if op.keepIn == nil { op.keepIn = moves.punchIn?.keepIn }
            case "emphasisPunch":
                if op.scale == nil { op.scale = moves.emphasisPunch?.scale }
            default:
                if op.scales == nil, let p = moves.slowPush { op.scales = [p.from, p.to] }
                if op.longerThan == nil { op.longerThan = moves.slowPush?.longerThan }
            }
            guard let r = op.range else { return }
            var faces: [String: FaceTrack] = [:]
            // The story's takes where they show, and the camera a layout shows full frame over them; a take a
            // layout covers isn't tracked (a long screen recording would cost a minute for nothing).
            let laid = s.clips.filter { $0.layer > 0 && $0.layout != nil }
            func covered(_ c: Clip) -> Bool { laid.contains { $0.start <= c.start && $0.end >= c.end } }
            let framed = s.clips.filter { c in
                c.kind == .video && c.start < r.end && c.end > r.start && ((c.layer == 0 && !covered(c)) || (c.layout?.role == .camera && c.layout?.layout.kind == .you))
            }
            for c in framed {
                guard let a = asset(c), !a.video.isEmpty, !a.isImage, faces[a.id] == nil else { continue }
                if let track = try? await LayoutAnalysis.faceTrack(a, cacheDirectory: cacheDirectory) { faces[a.id] = track }
            }
            op.resolved = .init(faces: faces)
        default: break
        }
    }

    // MARK: Layouts the director sets (layouts.md)

    /// Lays out `range` of the latest cut (all of it when nil) the director's way, at once: measured here,
    /// carried out as the director's own revision, and played by the cut. Returns the revision it made.
    public func setLayout(_ layout: FrameLayout, range: MediaRange?) async throws -> EditResult {
        let p = try store.read()
        guard let cut = try store.cuts().first else { throw DirectionError("no_cut", "There\u{2019}s no cut yet. Layouts change a cut once the editor has made one.") }
        let s = try p.sequence(cut.sequenceID)
        let r = range ?? MediaRange(start: .zero, duration: s.duration)
        var op = EditOperation(op: "layout"); op.layout = layout; op.range = r
        op.resolved = .init(layout: try await LayoutAnalysis.measure(project: p, sequence: s, dailies: try store.dailies(), range: r, cacheDirectory: cacheDirectory))
        return try store.directorEdit([op], summary: "Layout: \(layout.label)", expectedRevision: p.editRevision)
    }

    /// Finds the faces and sorts the takes ahead of time, so the first layout doesn't wait on Vision.
    public func prepareLayouts() async {
        guard let p = try? store.read(), let cut = try? store.cuts().first, let s = try? p.sequence(cut.sequenceID), let d = try? store.dailies() else { return }
        _ = try? await LayoutAnalysis.measure(project: p, sequence: s, dailies: d, range: nil, cacheDirectory: cacheDirectory)
    }

    /// `Effects/<name>.metal` or `Transitions/<name>.metal` in the editor's folder (`<film>/Editor/`,
    /// where it works), or in the film itself for films from before, and nowhere else.
    private func editorSource(_ file: String, folder: String) throws -> String {
        let parts = file.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts[0] == folder, parts[1].hasSuffix(".metal"), !parts[1].hasPrefix(".") else { throw DirectionError("bad_argument", "It lives in the \(folder) folder of your working folder: \"\(folder)/<name>.metal\".") }
        guard let url = editorFiles(folder, "metal").first(where: { $0.lastPathComponent == parts[1] }), let text = try? String(contentsOf: url, encoding: .utf8) else { throw DirectionError("missing_media", "There's no \(file) in this film.") }
        return text
    }

    /// The files of one kind in a folder of the editor's working folder, then the film's own for films
    /// from before it had one; a name in both is the editor's.
    func editorFiles(_ folder: String, _ ext: String) -> [URL] {
        var seen = Set<String>(), out: [URL] = []
        for base in [store.url.appendingPathComponent("Editor/" + folder), store.url.appendingPathComponent(folder)] {
            for file in ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []).filter({ $0.pathExtension == ext }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where seen.insert(file.lastPathComponent).inserted { out.append(file) }
        }
        return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
