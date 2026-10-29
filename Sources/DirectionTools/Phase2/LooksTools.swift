import Foundation
import CoreImage
import DirectionCore
import DirectionMedia

// Looks (specs/looks.md). The editor reads the look and proposes looks; only the director sets one.
extension ToolCatalog {
    static var looksDefinitions: [ToolDefinition] {
        let filter = record(["kind": strings(LookFilter.allCases.map(\.rawValue)), "amount": number, "option": string], required: ["kind"])
        return [
            definition("direction_looks", "Read the looks. current: the director's look for the film and for each scene that has its own (LUT, strength 0–1, filters). available: the Looks folder by group, and the looks you made (Editor/Looks). filters: the eleven filters in render order with their options. camera: each take's log curve from its metadata and the camera LUT it gets. The look is the director's: you may balance shots and propose looks, never set one."),
            definition("direction_make_look", "Make a look to propose. name (shown under its tile). The LUT comes from at most one of: cube (the text of a .cube file you wrote: LUT_3D_SIZE 17–65, values 0–1), fromStill (a reference still's path: Direction matches the film's color to it), or fromLUT (a LUT's name or path in the Looks folder). strength 0–1 (default 1). filters: [{kind, amount 0–1, option?}] (option: splitTone warmTeal|coolAmber, grain fine|medium|coarse, letterbox 2.39|2.00|1.85). note: why, in a sentence. noteID: the note it answers. Direction validates the LUT, saves the look in Editor/Looks and returns before and after stills on three frames from different scenes. Then offer two or three looks as Options or a question with up to four; the director's pick sets the look. Setting it yourself (apply) is refused with look_is_yours.", ["name": string, "cube": string, "fromStill": string, "fromLUT": string, "strength": number, "filters": list(filter), "note": string, "noteID": string, "apply": bool], required: ["name"], readOnly: false),
        ]
    }
}

extension ToolRuntime {
    func invokeLooks(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_looks": return try await looks()
        case "direction_make_look": return try await makeLook(a)
        default: return nil
        }
    }

    private func looks() async throws -> ToolResponse {
        await CameraLog.detectMissing(in: store)
        let p = try store.read(), d = try store.dailies(), look = try store.filmLook(), folder = SharedSettings.looksFolder
        let scenes: [JSONValue] = try look.scenes.sorted { $0.key < $1.key }.map { id, l in
            .object(["sceneID": .string(id), "scene": d.scenes.first { $0.id == id }.map { .string($0.label) } ?? .null, "look": try .wrapping(l)])
        }
        let groups = LooksLibrary.groups(folder: folder, film: store.url)
        let available: [JSONValue] = try groups.map { g in
            .object(["group": .string(g.name), "byEditor": .bool(g.byEditor), "looks": .array(try g.looks.map { e in
                .object(["name": .string(e.name), "path": .string(e.path), "look": try .wrapping(e.settings), "problem": e.problem.map(JSONValue.string) ?? .null])
            })])
        }
        let filters: [JSONValue] = LookFilter.allCases.map { f in
            .object(["kind": .string(f.rawValue), "label": .string(f.label), "hasAmount": .bool(f.hasAmount), "options": .array(f.options.map(JSONValue.string))])
        }
        let camera = try store.cameraLUTs(), context = try store.lookContext()
        let cameraFolder = folder.appendingPathComponent(LooksLibrary.cameraFolder)
        let takes: [JSONValue] = p.assets.filter { !$0.video.isEmpty && !$0.isImage }.map { asset in
            let log = camera.detected[asset.id].flatMap { $0.isEmpty ? nil : $0 }
            return .object(["assetID": .string(asset.id), "name": .string(asset.name), "log": log.map(JSONValue.string) ?? .null,
                            "chosen": .string(camera.chosen[asset.id] ?? "auto"), "cameraLUT": context?.cameraLUTs[asset.id].map(JSONValue.string) ?? .null])
        }
        let installed = SharedSettings.logNames.filter { FileManager.default.fileExists(atPath: cameraFolder.appendingPathComponent($0 + ".cube").path) }
        return ToolResponse(.object([
            "current": .object(["film": try .wrapping(look.film ?? LookSettings.noLook), "scenes": .array(scenes)]),
            "looksFolder": .string(folder.path),
            "available": .array(available),
            "filters": .array(filters),
            "camera": .object(["convertLogAutomatically": .bool(SharedSettings.convertLogFootage), "folder": .string(cameraFolder.path), "installed": .array(installed.map(JSONValue.string)), "takes": .array(takes)]),
            "rule": .string("The look is the director's. Propose looks with direction_make_look and offer them as Options or in a question."),
        ]))
    }

    private func makeLook(_ a: JSONValue) async throws -> ToolResponse {
        if a["apply"].bool == true { throw LookRules.refuse() }
        let name = try a.requiredString("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count) else { throw DirectionError("bad_argument", "name is 1–60 characters.") }
        let sources = ["cube", "fromStill", "fromLUT"].filter { a[$0].string != nil }
        guard sources.count <= 1 else { throw DirectionError("bad_argument", "Give the LUT as one of cube, fromStill or fromLUT, not \(sources.joined(separator: " and ")).") }
        let strength = a["strength"].double ?? 1
        guard (0...1).contains(strength) else { throw DirectionError("bad_argument", "strength is 0–1.") }
        if let noteID = a["noteID"].string { _ = try store.comment(noteID) }

        var filters: [String: Double] = [:], options: [String: String] = [:]
        for value in a["filters"].array ?? [] {
            guard let f = value["kind"].string.flatMap(LookFilter.init(rawValue:)) else { throw DirectionError("bad_argument", "Unknown filter.") }
            let amount = value["amount"].double ?? (f.hasAmount ? 0.5 : 1)
            guard (0...1).contains(amount) else { throw DirectionError("bad_argument", "\(f.label) amount is 0–1.") }
            if let option = value["option"].string {
                guard f.options.contains(option) else { throw DirectionError("bad_argument", f.options.isEmpty ? "\(f.label) has no option." : "\(f.label) option is one of \(f.options.joined(separator: ", ")).") }
                options[f.rawValue] = option
            }
            filters[f.rawValue] = f.hasAmount ? amount : 1
        }

        // Plain frames first: they're the stills, and what a reference still is matched against.
        let frames = try await plainStills(count: 3)
        var cube: CubeLUT?
        if let text = a["cube"].string { cube = try CubeLUT.parse(text) }
        else if let reference = a["fromLUT"].string { cube = try CubeLUT.load(try folderLUT(reference)) }
        else if let path = a["fromStill"].string {
            guard let still = LookMaker.image(at: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)) else { throw DirectionError("still_not_found", "Can't open a still at \(path).") }
            guard let source = LookMaker.stats(frames.map(\.image)) else { throw DirectionError("no_frames", "There's no cut to match yet. Assemble first, then match the look to the still.") }
            guard let target = LookMaker.stats([still]) else { throw DirectionError("still_not_found", "The still at \(path) has no pixels.") }
            cube = LookMaker.transfer(from: source, to: target, title: name)
        }
        if cube?.title == nil { cube?.title = name }

        let proposal = LookSettings(name: name, strength: strength, filters: filters, options: options, by: "editor", note: a["note"].string)
        let entry = try LooksLibrary.saveEditorLook(proposal, cube: cube, in: store.editorLooksFolder)
        if let noteID = a["noteID"].string { try store.recordLookProposal(noteID: noteID, path: entry.path) }

        // Before is the picture as the director sees it now; after is the same frame with this look.
        let current = try store.lookContext()
        let folder = cacheDirectory.appendingPathComponent("Looks").appendingPathComponent(newID("look"))
        var stills: [JSONValue] = [], paths: [String] = []
        let d = try store.dailies()
        for (i, f) in frames.enumerated() {
            let before = folder.appendingPathComponent("\(i + 1)-before.png"), after = folder.appendingPathComponent("\(i + 1)-after.png")
            try LookMaker.writePNG(LookPipeline.apply(f.image, context: current, storyAssetID: f.pick.assetID, frameIndex: f.frameIndex), to: before, colorSpace: f.image.colorSpace)
            try LookMaker.writePNG(LookPipeline.apply(entry.settings, to: f.image, frameIndex: f.frameIndex), to: after, colorSpace: f.image.colorSpace)
            let scene = d.scenes.first { $0.id == f.pick.sceneID }
            stills.append(.object(["scene": scene.map { .string($0.label) } ?? .null, "time": .number(f.pick.time), "before": .string(before.path), "after": .string(after.path)]))
            paths += [before.path, after.path]
        }
        let lut: JSONValue = cube.map { .object(["kind": .string($0.kind.rawValue), "size": .number(Double($0.size))]) } ?? .null
        return ToolResponse(.object([
            "look": try .wrapping(entry.settings), "path": .string(entry.path), "lut": lut, "stills": .array(stills),
            "next": .string("Offer this with one or two others as Options (A/B) in your answer, or ask with up to four looks. The director's pick sets the look; you can't."),
        ]), imagePaths: paths)
    }

    /// A LUT in the Looks folder by name ("Print film") or path.
    private func folderLUT(_ reference: String) throws -> URL {
        let expanded = NSString(string: reference).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        let all = LooksLibrary.folderGroups(SharedSettings.looksFolder).flatMap(\.looks)
        guard let hit = all.first(where: { $0.name.caseInsensitiveCompare(reference) == .orderedSame || $0.path.hasSuffix("/" + reference) }) else {
            throw DirectionError("lut_not_found", "There's no LUT called \(reference) in the Looks folder. direction_looks lists them.")
        }
        return URL(fileURLWithPath: hit.path)
    }

    /// Plain frames (no look) from different scenes of the current cut, rendered with the existing renderer.
    private func plainStills(count: Int) async throws -> [(pick: LookMaker.StillPick, image: CIImage, frameIndex: Int)] {
        let p = try store.read()
        guard let sequence = try? p.sequence(nil), sequence.duration > .zero else { return [] }
        let d = try store.dailies()
        let picks = LookMaker.picks(sequence, sceneForAsset: d.takes.compactMapValues(\.sceneID), count: count)
        guard !picks.isEmpty else { return [] }
        let compiled = try await SequenceRenderer.compile(project: p, sequenceID: sequence.id, cacheDirectory: cacheDirectory, previewMaxDimension: 640)
        var out: [(LookMaker.StillPick, CIImage, Int)] = []
        for pick in picks {
            let url = cacheDirectory.appendingPathComponent("Looks").appendingPathComponent(newID("plain") + ".png")
            _ = try await SequenceRenderer.frame(compiled, at: .init(seconds: pick.time), to: url, maxDimension: 640)
            guard let image = LookMaker.image(at: url) else { continue }
            out.append((pick, image, Int((pick.time * sequence.frameRate.value).rounded(.down))))
        }
        return out
    }
}
