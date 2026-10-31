import Foundation
import DirectionCore
import DirectionMedia

// Techniques (specs/techniques.md): the director's library of named ways to do one thing, often learned
// from a tutorial video. The editor lists and reads them, uses them with the `technique` edit, and writes
// one only in a technique job or when the director asks.
extension ToolCatalog {
    static var techniqueDefinitions: [ToolDefinition] { [
        definition("direction_techniques", "List the director's techniques (the Techniques folder): name, one sentence, kind (transition, effect or recipe), when to use it, what the footage needs, its variants, and where it was learned. Reach for one when a style, the brief or a note names it, or when its \"when\" fits and the style leaves you the choice."),
        definition("direction_technique", "Read one technique by name: how it's made (its transition or effect and their settings, or a recipe's steps), its variants, its files with paths, and the tutorial it came from. Use a transition or effect with the technique edit (op technique, name, editPoint or clipID, variant?); follow a recipe's steps yourself.", ["name": string], required: ["name"]),
        definition("direction_save_technique", "Write a technique into the director's Techniques folder, only in a technique job or when the director asks: a new one with name, or changes to one with id. kind is transition ({type, frames, params?, file: <its Metal, a transitions shader>, sound?, soundDB?}), effect ({name: a built-in effect or shader, params?, file?}) or recipe (steps: edit operations in words with their arguments). summary is one sentence; when says where it belongs; needs what the footage must have. variants are named settings [{name, params?, frames?}]. source is where it was learned {title, url, author, at}. files copies from your working folder into the technique: [{from, to}] (to like transition.metal or sounds/clicks.wav). A transition's Metal is compiled and timed before it's saved. Returns the technique as direction_technique reads it.", [
            "id": string, "name": string, "summary": string, "kind": string, "when": string, "needs": string,
            "transition": object, "effect": object, "steps": list(string), "variants": list(object), "source": object,
            "files": .object(["type": .string("array"), "items": record(["from": string, "to": string], required: ["from", "to"])]),
        ], readOnly: false),
        definition("direction_study_frames", "Full frames of a video you're learning a technique from, at the times you give (seconds), saved as JPEGs beside it; read them to see a result or a settings panel up close. video is the path from your job.", ["video": string, "times": list(number)], required: ["video", "times"]),
    ] }
}

extension ToolRuntime {
    func invokeTechniques(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        let folder = SharedSettings.techniquesFolder
        switch name {
        case "direction_techniques":
            let list: [JSONValue] = TechniqueLibrary.list(in: folder).map { t in
                .object(["id": .string(t.id), "name": .string(t.name), "summary": .string(t.summary), "kind": .string(t.kind), "when": .string(t.when), "needs": .string(t.needs),
                         "variants": .array(t.variants.map { .string($0.name) }), "learnedFrom": t.source["title"].string.map(JSONValue.string) ?? .null])
            }
            return ToolResponse(.object(["techniques": .array(list), "folder": .string(folder.path)]))
        case "direction_technique":
            let wanted = try a.requiredString("name")
            guard let t = TechniqueLibrary.find(wanted, in: folder) else { throw notFound(wanted, folder) }
            return ToolResponse(json(t))
        case "direction_save_technique":
            var files: [(from: URL, to: String)] = []
            for f in a["files"].array ?? [] {
                guard let from = f["from"].string, let to = f["to"].string else { throw DirectionError("invalid_arguments", "Each file is {from, to}.") }
                files.append((try workingFile(from), to))
            }
            var fields: [String: JSONValue] = [:]
            for k in ["name", "summary", "kind", "when", "needs", "transition", "effect", "steps", "variants", "source"] where a[k] != .null { fields[k] = a[k] }
            // A transition's or effect's Metal is compiled and timed before anything is written.
            let existing = a["id"].string.flatMap { try? TechniqueLibrary.read(folder.appendingPathComponent($0)) }
            for key in ["transition", "effect"] {
                guard let file = (fields[key] ?? existing?.tokens[key])?["file"].string else { continue }
                let from = files.first { $0.to == file }?.from ?? existing?.url.appendingPathComponent(file)
                guard let from, let source = try? String(contentsOf: from, encoding: .utf8) else { throw DirectionError("invalid_arguments", "\(file) isn't among the files, or in the technique.") }
                if key == "transition" { _ = try TransitionShader.check(source: source) } else { _ = try ShaderEffect.check(source: source) }
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let t = try TechniqueLibrary.save(id: a["id"].string, fields: fields, files: files, in: folder)
            return ToolResponse(json(t))
        case "direction_study_frames":
            let video = URL(fileURLWithPath: try a.requiredString("video")).standardizedFileURL
            guard video.path.hasPrefix(store.url.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: video.path) else { throw DirectionError("invalid_arguments", "video is the one in your job, inside this film.") }
            let times = (a["times"].array ?? []).compactMap(\.double).filter { $0 >= 0 }.prefix(24)
            guard !times.isEmpty else { throw DirectionError("invalid_arguments", "times lists the seconds to look at, like [1.5, 2, 2.5].") }
            let made = try await TutorialStudy.frames(video, at: Array(times), to: video.deletingLastPathComponent().appendingPathComponent("frames"))
            return ToolResponse(.object(["frames": .array(made.map { .string($0.path) })]))
        default: return nil
        }
    }

    private func notFound(_ name: String, _ folder: URL) -> DirectionError {
        let names = TechniqueLibrary.list(in: folder).map(\.name)
        return DirectionError("technique_not_found", names.isEmpty ? "There are no techniques yet." : "There's no technique called \(name). There's \(names.joined(separator: ", ")).")
    }

    private func json(_ t: Technique) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(t.id), "name": .string(t.name), "summary": .string(t.summary), "kind": .string(t.kind), "when": .string(t.when), "needs": .string(t.needs),
                                      "variants": t.tokens["variants"], "steps": t.tokens["steps"], "source": t.source, "folder": .string(t.url.path)]
        if t.kind == "transition" { o["transition"] = t.tokens["transition"] }
        if t.kind == "effect" { o["effect"] = t.tokens["effect"] }
        let files = (FileManager.default.enumerator(at: t.url, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { !$0.hasDirectoryPath && $0.lastPathComponent != TechniqueLibrary.file }
        o["files"] = .array(files.map { .string($0.path) })
        o["use"] = .string(t.kind == "recipe" ? "Follow the steps with direction_edit." : "direction_edit with {op: \"technique\", name: \"\(t.name)\", \(t.kind == "transition" ? "editPoint" : "clipID"), variant?}.")
        return .object(o)
    }

    /// A transition technique made ready for the cut: its kind, length and settings (the variant's, then
    /// what's given), its checked Metal from the technique's folder, and its sound.
    func techniqueTransition(_ t: Technique, variant: String?, frames: Int?, params: [String: JSONValue]?, project p: Project) async throws -> (type: String, frames: Int, params: [String: JSONValue], source: String?, sound: MediaAsset?, soundDB: Double?) {
        guard let tr = t.transition else { throw DirectionError("bad_argument", "\(t.name) is \(t.kind == "effect" ? "an effect: give clipID" : "a recipe: follow its steps (direction_technique)").") }
        if let variant, t.variant(variant) == nil { throw DirectionError("bad_argument", "\(t.name) has no variant \(variant). It has \(t.variants.map(\.name).joined(separator: ", ")).") }
        let v = t.variant(variant)
        var merged = tr.params ?? [:]
        for (k, x) in v?.params ?? [:] { merged[k] = x }
        for (k, x) in params ?? [:] { merged[k] = x }
        var source: String?
        if tr.type == "shader" {
            guard let file = tr.file, StyleLibrary.isSafe(file), let text = try? String(contentsOf: t.url.appendingPathComponent(file), encoding: .utf8) else { throw DirectionError("missing_media", "\(t.name) has no Metal file.") }
            source = text; merged["file"] = .string(file)
        }
        var sound: MediaAsset?
        if let file = tr.sound, StyleLibrary.isSafe(file) {
            let url = t.url.appendingPathComponent(file)
            if let had = p.assets.first(where: { $0.path == url.path }) { sound = had } else if FileManager.default.fileExists(atPath: url.path) { sound = try await MediaInspector.inspect(url: url, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails")) }
        }
        return (tr.type, frames ?? v?.frames ?? tr.frames, merged, source, sound, tr.soundDB ?? -18)
    }

    /// `technique`: becomes the transition or effect it makes, set up from the Techniques folder. Returns true
    /// when it's ready; false when what it became still needs measuring (pixelGrid).
    func resolveTechnique(_ op: inout EditOperation, _ p: Project) async throws -> Bool {
        let folder = SharedSettings.techniquesFolder
        guard let name = op.transitionName else { throw DirectionError("bad_argument", "name is the technique's name; direction_techniques lists them.") }
        guard let t = TechniqueLibrary.find(name, in: folder) else { throw notFound(name, folder) }
        switch t.kind {
        case "transition":
            guard op.editPoint != nil else { throw DirectionError("bad_argument", "\(t.name) is a transition: give editPoint (\"<left clip>|<right clip>\").") }
            let made = try await techniqueTransition(t, variant: op.variant, frames: op.frames, params: op.params, project: p)
            op.type = "transition"; op.transitionType = made.type; op.frames = made.frames
            op.params = made.params.isEmpty ? nil : made.params
            op.resolved = .init()
            if let source = made.source ?? TransitionShader.builtIn(made.type) {
                _ = try TransitionShader.check(source: source, params: made.params.filter { $0.key != "file" })
                op.resolved?.source = source
            }
            op.resolved?.sound = made.sound; op.resolved?.soundDB = made.soundDB
            return true
        case "effect":
            guard let fx = t.effect else { throw DirectionError("bad_argument", "\(t.name) has no effect.") }
            guard let clipID = op.clipID ?? op.target else { throw DirectionError("bad_argument", "\(t.name) is an effect: give clipID, the clip it goes on.") }
            if let variant = op.variant, t.variant(variant) == nil { throw DirectionError("bad_argument", "\(t.name) has no variant \(variant). It has \(t.variants.map(\.name).joined(separator: ", ")).") }
            var params = fx.params ?? [:]
            for (k, x) in t.variant(op.variant)?.params ?? [:] { params[k] = x }
            for (k, x) in op.params ?? [:] { params[k] = x }
            op.type = "addEffect"; op.effect = fx.name; op.target = clipID; op.clipID = nil
            if fx.name == "shader" {
                guard let file = fx.file, StyleLibrary.isSafe(file), let source = try? String(contentsOf: t.url.appendingPathComponent(file), encoding: .utf8) else { throw DirectionError("missing_media", "\(t.name) has no Metal file.") }
                _ = try ShaderEffect.check(source: source, params: params.filter { $0.key != "file" })
                params["file"] = .string(file); op.params = params; op.resolved = .init(source: source)
                return true
            }
            op.params = params.isEmpty ? nil : params
            return false
        default:
            throw DirectionError("bad_argument", "\(t.name) is a recipe: follow its steps (direction_technique).")
        }
    }
}
