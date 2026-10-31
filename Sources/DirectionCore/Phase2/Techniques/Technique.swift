import Foundation

// Techniques (specs/techniques.md): a named way of doing one thing the same way every time, often learned
// from a tutorial video: a transition, an effect, or a recipe of edit operations. Each is a folder in the
// Techniques folder with technique.json and its files (Metal, sounds, overlays). The editor reaches for one
// when a style, the brief or a note names it; Direction does the how, like layouts and moves.

public struct Technique: Hashable, Sendable, Identifiable {
    /// The technique's folder name.
    public var id: String
    public var url: URL
    /// technique.json as written.
    public var tokens: JSONValue
    public init(id: String, url: URL, tokens: JSONValue) { self.id = id; self.url = url; self.tokens = tokens }

    public var name: String { tokens["name"].string ?? id }
    public var summary: String { tokens["summary"].string ?? "" }
    /// transition, effect or recipe.
    public var kind: String { tokens["kind"].string ?? "recipe" }
    /// When to reach for it, and what the footage needs for it to work.
    public var when: String { tokens["when"].string ?? "" }
    public var needs: String { tokens["needs"].string ?? "" }
    public var updatedAt: Double { tokens["updatedAt"].double ?? 0 }
    /// A transition technique: its kind, length, settings, Metal file and sound, paths inside the technique.
    public var transition: StyleTransition? {
        guard kind == "transition", var t = try? tokens["transition"].decode(StyleTransition.self) else { return nil }
        if t.name.isEmpty { t.name = name }
        return t
    }
    /// An effect technique: a built-in effect (or `shader` with its file) and its settings.
    public var effect: Effect? { kind == "effect" ? try? tokens["effect"].decode(Effect.self) : nil }
    public struct Effect: Codable, Hashable, Sendable {
        public var name: String
        public var params: [String: JSONValue]?
        /// For a shader effect: its Metal file inside the technique.
        public var file: String?
        public init(name: String, params: [String: JSONValue]? = nil, file: String? = nil) { self.name = name; self.params = params; self.file = file }
    }
    /// Named settings: "Big squares", "Fine grid".
    public var variants: [Variant] { (try? tokens["variants"].decode([Variant].self)) ?? [] }
    public struct Variant: Codable, Hashable, Sendable {
        public var name: String
        public var params: [String: JSONValue]?
        public var frames: Int?
        public init(name: String, params: [String: JSONValue]? = nil, frames: Int? = nil) { self.name = name; self.params = params; self.frames = frames }
    }
    /// The steps in Direction's edit operations, for the editor to follow (a recipe, or how to set one up).
    public var steps: [String] { tokens["steps"].array?.compactMap(\.string) ?? [] }
    /// Where it was learned: the tutorial's title, link, maker and the moment.
    public var source: JSONValue { tokens["source"] }

    /// A variant by name (any case), or nil.
    public func variant(_ name: String?) -> Variant? {
        guard let n = name?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty else { return nil }
        return variants.first { $0.name.lowercased() == n }
    }
}

public enum TechniqueLibrary {
    public static let file = "technique.json"
    public static let kinds = ["transition", "effect", "recipe"]

    /// Every technique in a folder, by name. Folders without a readable technique.json are skipped.
    public static func list(in folder: URL) -> [Technique] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { try? read(folder.appendingPathComponent($0, isDirectory: true)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func read(_ url: URL) throws -> Technique {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(file)), let tokens = try? JSONDecoder().decode(JSONValue.self, from: data), tokens["name"].string?.isEmpty == false else {
            throw DirectionError("technique_not_found", "There's no technique in \(url.lastPathComponent).")
        }
        return Technique(id: url.lastPathComponent, url: url, tokens: tokens)
    }

    /// A technique by name or id, in any case.
    public static func find(_ name: String, in folder: URL) -> Technique? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return list(in: folder).first { $0.name.lowercased() == n || $0.id == n }
    }

    /// Writes a technique: a new one without `id`, or changes to one. `fields` replace technique.json's values
    /// key by key (null removes one); `files` copies parts in, each to a path inside the technique.
    @discardableResult
    public static func save(id: String?, fields: [String: JSONValue], files: [(from: URL, to: String)] = [], in folder: URL) throws -> Technique {
        let fm = FileManager.default
        var values: [String: JSONValue] = ["format": .number(1)]
        let techniqueID: String
        if let id {
            guard StyleLibrary.isSafe(id), let old = try? read(folder.appendingPathComponent(id)) else { throw DirectionError("technique_not_found", "There's no technique \(id). direction_techniques lists them.") }
            techniqueID = id
            if case .object(let o) = old.tokens { values = o }
        } else {
            guard let name = fields["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw DirectionError("invalid_arguments", "A new technique needs a name.") }
            techniqueID = StyleLibrary.newID(name, in: folder)
        }
        for (k, v) in fields where k != "format" { values[k] = v == .null ? nil : v }
        let kind = values["kind"]?.string ?? ""
        guard kinds.contains(kind) else { throw DirectionError("invalid_arguments", "kind is transition, effect or recipe.") }
        guard values["name"]?.string?.isEmpty == false, values["summary"]?.string?.isEmpty == false, values["when"]?.string?.isEmpty == false else { throw DirectionError("invalid_arguments", "A technique needs a name, a summary in one sentence and when to use it.") }
        if kind == "transition" { guard (try? values["transition"]?.decode(StyleTransition.self)) != nil else { throw DirectionError("invalid_arguments", "A transition technique has transition: {type, frames, params?, file? (its Metal), sound?, soundDB?}.") } }
        if kind == "effect" { guard (try? values["effect"]?.decode(Technique.Effect.self)) != nil else { throw DirectionError("invalid_arguments", "An effect technique has effect: {name, params?, file?}.") } }
        if kind == "recipe" { guard values["steps"]?.array?.isEmpty == false else { throw DirectionError("invalid_arguments", "A recipe has steps: the edit operations to run, in words with their arguments.") } }
        values["updatedAt"] = .number(Date().timeIntervalSince1970.rounded())
        for f in files { guard StyleLibrary.isSafe(f.to), fm.fileExists(atPath: f.from.path) else { throw DirectionError("invalid_arguments", "Can't copy \(f.from.lastPathComponent) to \(f.to): give a file that exists and a path inside the technique, like sounds/clicks.wav.") } }
        let url = folder.appendingPathComponent(techniqueID, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONValue.object(values).data(pretty: true).write(to: url.appendingPathComponent(file), options: .atomic)
        for f in files {
            let target = url.appendingPathComponent(f.to)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try StyleLibrary.replace(target, with: f.from)
        }
        return try read(url)
    }
}

extension SharedSettings {
    public static let techniquesFolderKey = "techniquesFolder"
    public static var defaultTechniquesFolder: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Direction/Techniques").path }
    /// The Techniques folder: one folder per technique. DIRECTION_TECHNIQUES_PATH overrides it for a process; a
    /// test process without it gets a folder of its own.
    public static var techniquesFolder: URL {
        if let env = ProcessInfo.processInfo.environment["DIRECTION_TECHNIQUES_PATH"], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        if DirectionPaths.isTesting { return FileManager.default.temporaryDirectory.appendingPathComponent("DirectionTestTechniques", isDirectory: true) }
        let path = defaults.string(forKey: techniquesFolderKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultTechniquesFolder
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }
}
