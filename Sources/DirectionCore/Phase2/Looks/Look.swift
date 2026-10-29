import Foundation
import GRDB

// Looks (specs/looks.md). The director chooses the look; the renderer applies it over every cut.
// The editor balances shots and may propose looks, but nothing it calls can set one (`look_is_yours`).

/// One filter inside a look. The cases are in the fixed order they render (looks.md › Filters).
public enum LookFilter: String, CaseIterable, Codable, Sendable {
    case blackAndWhite, splitTone, fade, halation, bloom, soften, chromaticAberration, vignette, grain, gateWeave, letterbox

    public var label: String {
        switch self {
        case .blackAndWhite: "Black and white"
        case .splitTone: "Split tone"
        case .fade: "Fade"
        case .halation: "Halation"
        case .bloom: "Bloom"
        case .soften: "Soften"
        case .chromaticAberration: "Chromatic aberration"
        case .vignette: "Vignette"
        case .grain: "Grain"
        case .gateWeave: "Gate weave"
        case .letterbox: "Letterbox"
        }
    }
    /// The second control, if any. The first option is the default.
    public var options: [String] {
        switch self {
        case .splitTone: ["warmTeal", "coolAmber"]
        case .grain: ["fine", "medium", "coarse"]
        case .letterbox: ["2.39", "2.00", "1.85"]
        default: []
        }
    }
    /// Letterbox is a ratio only; every other filter has an amount.
    public var hasAmount: Bool { self != .letterbox }
    public static func optionLabel(_ option: String) -> String {
        switch option {
        case "warmTeal": "Warm·Teal"
        case "coolAmber": "Cool·Amber"
        default: option.prefix(1).uppercased() + option.dropFirst()
        }
    }
}

/// One look: a LUT at a strength plus filters.
public struct LookSettings: Codable, Hashable, Sendable {
    public var name: String
    /// A .cube file, absolute path.
    public var lut: String?
    public var strength: Double
    /// Filter kind → amount 0…1 (looks.md › Filters).
    public var filters: [String: Double]
    /// Filter kind → option, e.g. "grain": "fine", "letterbox": "2.39".
    public var options: [String: String]
    /// "you", "editor" or "folder".
    public var by: String
    /// The editor's words about a look it proposed.
    public var note: String?
    public init(name: String, lut: String? = nil, strength: Double = 1, filters: [String: Double] = [:], options: [String: String] = [:], by: String = "you", note: String? = nil) {
        self.name = name; self.lut = lut; self.strength = strength; self.filters = filters; self.options = options; self.by = by; self.note = note
    }

    public static let noLook = LookSettings(name: "None")
    /// No LUT and no filters: the picture as shot (after balance).
    public var isNone: Bool { lut == nil && active.isEmpty }
    /// Filters that are on, in render order, with their amount (1 for Letterbox) and option.
    public var active: [(filter: LookFilter, amount: Double, option: String?)] {
        LookFilter.allCases.compactMap { f in
            guard let amount = filters[f.rawValue], amount > 0 else { return nil }
            return (f, min(1, amount), options[f.rawValue] ?? f.options.first)
        }
    }
}

/// The film's look, and any scene's own look, keyed by scene id.
public struct FilmLook: Codable, Hashable, Sendable {
    public var film: LookSettings?
    public var scenes: [String: LookSettings]
    public init(film: LookSettings? = nil, scenes: [String: LookSettings] = [:]) { self.film = film; self.scenes = scenes }
    /// A scene's own look wins over the film's.
    public func look(forScene sceneID: String?) -> LookSettings? { sceneID.flatMap { scenes[$0] } ?? film }
    public var isEmpty: Bool { (film?.isNone ?? true) && scenes.isEmpty }
}

/// What the renderer needs to apply looks: the look and which scene each take belongs to.
public struct LookContext: Sendable, Hashable {
    public var look: FilmLook
    public var sceneForAsset: [String: String]
    /// Take → camera LUT (.cube, absolute path), applied to that take before balance (looks.md › Where color happens, 1).
    public var cameraLUTs: [String: String]
    public init(look: FilmLook, sceneForAsset: [String: String], cameraLUTs: [String: String] = [:]) { self.look = look; self.sceneForAsset = sceneForAsset; self.cameraLUTs = cameraLUTs }
}

/// Per-take camera LUTs: what Direction found in each file and what the editor set (`cameraLUT`).
public struct CameraLUTs: Codable, Hashable, Sendable {
    /// Take → log name from the file's metadata ("Apple Log", "S-Log3", "LogC", "V-Log"), or "" for normal video.
    public var detected: [String: String] = [:]
    /// Take → "auto", "none" or a .cube path. Missing means auto.
    public var chosen: [String: String] = [:]
    public init() {}
}

public enum LookRules {
    /// Every editor path that would change the director's look throws this.
    public static func refuse() -> DirectionError {
        DirectionError("look_is_yours", "The look is the director's. Propose looks with direction_make_look and offer them as Options or in a question; picking one sets it.")
    }
}

// MARK: Settings › Footage › Color

extension SharedSettings {
    public enum LookKey {
        public static let looksFolder = "looksFolder"
        public static let convertLog = "convertLogFootage"
    }
    public static let logNames = ["Apple Log", "S-Log3", "LogC", "V-Log"]
    public static var defaultLooksFolder: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Direction/Looks").path }
    /// Tests point this at a temporary folder so nothing reads or creates the director's own.
    nonisolated(unsafe) public static var looksFolderOverride: URL?
    /// The Looks folder (frame 54). Subfolders are groups; `Camera/` holds camera LUTs.
    public static var looksFolder: URL {
        if let looksFolderOverride { return looksFolderOverride }
        let path = defaults.string(forKey: LookKey.looksFolder).flatMap { $0.isEmpty ? nil : $0 } ?? defaultLooksFolder
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
    public static var convertLogFootage: Bool { defaults.object(forKey: LookKey.convertLog) as? Bool ?? true }
    /// Creates the Looks folder and its Camera folder if they're missing. Only the app calls this.
    @discardableResult
    public static func ensureLooksFolder() throws -> URL {
        let url = looksFolder
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Camera"), withIntermediateDirectories: true)
        return url
    }
}

// MARK: Store

private enum LookKeyName { static let film = "film", camera = "camera", proposals = "proposals" }

extension ProjectStore {
    static func ensureLookTables(_ db: Database) throws {
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS looks (key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
    }
    private static func lookValue<T: Decodable>(_ db: Database, _ key: String, as type: T.Type) throws -> T? {
        try Data.fetchOne(db, sql: "SELECT payload FROM looks WHERE key = ?", arguments: [key]).map { try JSONDecoder().decode(type, from: $0) }
    }
    private static func setLookValue<T: Encodable>(_ db: Database, _ key: String, _ value: T) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO looks (key, payload) VALUES (?, ?)", arguments: [key, try JSONEncoder.direction.encode(value)])
    }

    /// Where the editor writes the looks it proposes.
    public var editorLooksFolder: URL { url.appendingPathComponent("Editor/Looks") }
    /// Where chosen looks from the Looks folder are copied, so the film keeps working if the folder changes.
    public var filmLooksFolder: URL { url.appendingPathComponent("Looks") }

    /// The film's look, with LUT paths made absolute.
    public func filmLook() throws -> FilmLook {
        let stored = try database.read { try Self.lookValue($0, LookKeyName.film, as: FilmLook.self) } ?? FilmLook()
        return FilmLook(film: stored.film.map(resolved), scenes: stored.scenes.mapValues(resolved))
    }
    private func resolved(_ look: LookSettings) -> LookSettings {
        var l = look
        if let lut = l.lut, !lut.hasPrefix("/") { l.lut = url.appendingPathComponent(lut).path }
        return l
    }

    /// The director chooses the look for the film (sceneID nil) or one scene. For a scene, nil goes back to
    /// the film's look; `LookSettings.noLook` gives the scene no look at all. Only the director's acts pass
    /// `asDirector`; every other caller gets `look_is_yours`.
    @discardableResult
    public func setLook(_ look: LookSettings?, sceneID: String? = nil, asDirector: Bool) throws -> FilmLook {
        guard asDirector else { throw LookRules.refuse() }
        let dailies = try dailies()
        let scene = try sceneID.map { id in
            guard let s = dailies.scenes.first(where: { $0.id == id }) else { throw DirectionError("scene_not_found", "Scene not found.") }
            return s
        }
        var chosen = try look.map(keptInFilm)
        if chosen?.isNone == true && sceneID == nil { chosen = nil }
        let summary = scene.map { "Changed the look of scene \($0.number)" } ?? "Changed the look of the film"
        try database.write { db in
            var current = try Self.lookValue(db, LookKeyName.film, as: FilmLook.self) ?? FilmLook()
            if let sceneID { current.scenes[sceneID] = chosen } else { current.film = chosen }
            try Self.setLookValue(db, LookKeyName.film, current)
            try Self.event(db, kind: "look.updated", revision: try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0, summary: summary)
        }
        return try filmLook()
    }

    /// Copies a LUT from outside the film into `Looks/`, and stores paths inside the film relative to it.
    private func keptInFilm(_ look: LookSettings) throws -> LookSettings {
        var l = look
        guard let lut = l.lut else { return l }
        var source = URL(fileURLWithPath: NSString(string: lut).expandingTildeInPath).standardizedFileURL
        let root = url.standardizedFileURL.path + "/"
        if !source.path.hasPrefix(root) {
            guard FileManager.default.fileExists(atPath: source.path) else { throw DirectionError("lut_not_found", "There's no LUT at \(source.path).") }
            try FileManager.default.createDirectory(at: filmLooksFolder, withIntermediateDirectories: true)
            let data = try Data(contentsOf: source)
            let base = source.deletingPathExtension().lastPathComponent
            var target = filmLooksFolder.appendingPathComponent(base + ".cube"), n = 2
            // Same name, different file: keep both.
            while FileManager.default.fileExists(atPath: target.path), (try? Data(contentsOf: target)) != data {
                target = filmLooksFolder.appendingPathComponent("\(base) \(n).cube"); n += 1
            }
            if !FileManager.default.fileExists(atPath: target.path) { try data.write(to: target, options: .atomic) }
            source = target
        }
        l.lut = String(source.path.dropFirst(root.count))
        return l
    }

    // MARK: Proposals

    /// Looks the editor made for a note, so its answer can open them in the Look sheet. Note → LUT or look paths.
    public func lookProposals() throws -> [String: [String]] { try database.read { try Self.lookValue($0, LookKeyName.proposals, as: [String: [String]].self) } ?? [:] }
    public func recordLookProposal(noteID: String, path: String) throws {
        _ = try comment(noteID)
        try database.write { db in
            var all = try Self.lookValue(db, LookKeyName.proposals, as: [String: [String]].self) ?? [:]
            if !(all[noteID] ?? []).contains(path) { all[noteID, default: []].append(path) }
            try Self.setLookValue(db, LookKeyName.proposals, all)
            try Self.event(db, kind: "look.proposed", revision: try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0, summary: "The editor proposed a look")
        }
    }

    // MARK: Camera LUTs

    public func cameraLUTs() throws -> CameraLUTs { try database.read { try Self.lookValue($0, LookKeyName.camera, as: CameraLUTs.self) } ?? CameraLUTs() }
    /// Remembers what Direction found in a take's metadata, so the renderer doesn't reopen files.
    public func recordLogDetection(_ found: [String: String]) throws {
        guard !found.isEmpty else { return }
        try database.write { db in
            var c = try Self.lookValue(db, LookKeyName.camera, as: CameraLUTs.self) ?? CameraLUTs()
            for (k, v) in found { c.detected[k] = v }
            try Self.setLookValue(db, LookKeyName.camera, c)
        }
    }
    /// The editor sets or clears a take's camera LUT: "auto", "none" or a .cube path (agent-timeline.md › cameraLUT).
    public func setCameraLUT(assetID: String, lut: String) throws {
        _ = try read().asset(assetID)
        guard ["auto", "none"].contains(lut) || lut.hasSuffix(".cube") else { throw DirectionError("bad_argument", "lut is auto, none or a .cube file.") }
        try database.write { db in
            var c = try Self.lookValue(db, LookKeyName.camera, as: CameraLUTs.self) ?? CameraLUTs()
            c.chosen[assetID] = lut == "auto" ? nil : lut
            try Self.setLookValue(db, LookKeyName.camera, c)
            try Self.event(db, kind: "look.camera", revision: try Int.fetchOne(db, sql: "SELECT revision FROM state WHERE id = 1") ?? 0, summary: "Set a camera LUT")
        }
    }

    // MARK: For the renderer

    /// The film's look for rendering. Owned by the looks area; nil until a look is chosen.
    public func lookContext() throws -> LookContext? { try lookContext(looksFolder: SharedSettings.looksFolder, convertLog: SharedSettings.convertLogFootage) }

    public func lookContext(looksFolder: URL, convertLog: Bool) throws -> LookContext? {
        let look = try filmLook(), d = try dailies()
        let scenes = Set(d.scenes.map(\.id))
        let sceneForAsset = d.takes.compactMapValues { t in t.sceneID.flatMap { scenes.contains($0) ? $0 : nil } }
        var camera: [String: String] = [:]
        let c = try cameraLUTs()
        for id in Set(c.detected.keys).union(c.chosen.keys) {
            switch c.chosen[id] {
            case "none": continue
            case let path? where path.hasSuffix(".cube"):
                camera[id] = path.hasPrefix("/") ? path : url.appendingPathComponent(path).path
            default:
                guard convertLog, let log = c.detected[id], !log.isEmpty else { continue }
                let file = looksFolder.appendingPathComponent("Camera").appendingPathComponent(log + ".cube")
                if FileManager.default.fileExists(atPath: file.path) { camera[id] = file.path }
            }
        }
        guard !look.isEmpty || !camera.isEmpty else { return nil }
        return LookContext(look: look, sceneForAsset: sceneForAsset, cameraLUTs: camera)
    }
}
