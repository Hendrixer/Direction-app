import Foundation

// Styles (specs/styles.md): how a director's videos look, sound and move, kept in one folder the editor
// follows the way an app follows its design system. style.json holds the name and the exact values
// (colors, fonts, timings, levels); guide.md says the rest in words; the folders beside them hold the
// parts (graphics, transitions, sounds, fonts, a look). A film keeps its own copy of the style it uses.

public struct Style: Hashable, Sendable, Identifiable {
    /// The style's folder name in the Styles folder.
    public var id: String
    public var url: URL
    public var name: String
    public var summary: String
    public var updatedAt: Double
    /// style.json as written, name and summary included.
    public var tokens: JSONValue
    public var contents: StyleContents
    public init(id: String, url: URL, name: String, summary: String, updatedAt: Double, tokens: JSONValue, contents: StyleContents) {
        self.id = id; self.url = url; self.name = name; self.summary = summary; self.updatedAt = updatedAt; self.tokens = tokens; self.contents = contents
    }
    public var guide: String { (try? String(contentsOf: url.appendingPathComponent(StyleLibrary.guideFile), encoding: .utf8)) ?? "" }
}

/// What's in a style's folders, by file name (graphics by folder name).
public struct StyleContents: Codable, Hashable, Sendable {
    public var graphics: [String] = []
    public var transitions: [String] = []
    public var effects: [String] = []
    public var sounds: [String] = []
    public var music: [String] = []
    public var fonts: [String] = []
    public var stills: [String] = []
    public var look: Bool = false
    public init() {}

    /// "3 graphics · 2 transitions · 6 sounds · a look"; empty when it's words only.
    public var line: String {
        func n(_ c: Int, _ one: String, _ many: String) -> String? { c == 0 ? nil : "\(c) \(c == 1 ? one : many)" }
        return [n(graphics.count, "graphic", "graphics"), n(transitions.count, "transition", "transitions"), n(effects.count, "effect", "effects"), n(sounds.count, "sound", "sounds"),
                n(music.count, "music track", "music tracks"), n(fonts.count, "font", "fonts"), look ? "a look" : nil, n(stills.count, "still", "stills")].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

public enum StyleLibrary {
    public static let tokensFile = "style.json", guideFile = "guide.md", lookFile = "look.cube"
    /// A film's copy of its style: `<film>.direction/Style/`.
    public static let filmFolder = "Style"
    static let audio: Set<String> = ["wav", "aif", "aiff", "m4a", "mp3", "caf"]
    /// Each part's folder and the files it holds. Graphics are folders with an index.html.
    public static let parts: [(folder: String, extensions: Set<String>)] = [
        ("transitions", ["metal"]), ("effects", ["metal"]), ("sounds", audio), ("music", audio), ("fonts", ["ttf", "otf"]), ("stills", ["jpg", "jpeg", "png", "heic"]),
    ]

    /// The guide a new style starts from: one heading for each thing an editor decides.
    public static func template(name: String, summary: String) -> String {
        """
        # \(name)

        \(summary.isEmpty ? "What this style is, and the videos it's for." : summary)

        ## Pace
        How long shots hold, how tight the pauses are, how soon it gets to the point.

        ## Picture
        Framing, punch-ins, B-roll and screen recordings: how often the picture changes, and with what.

        ## Graphics
        Titles, lower thirds, callouts: when they come in, how they move, how long they stay.

        ## Captions
        On or off, how many words at a time, where, and how they look.

        ## Transitions
        Hard cuts, or which transitions, how long, and where they belong.

        ## Sound
        Sound effects (whooshes, pops, clicks): when they play and how loud.

        ## Music
        What kind, how loud under talking, where it drops out.

        ## Color
        The look, and how strong.

        ## Avoid
        What never happens in this style.

        """
    }

    /// Every style in a folder, by name. Folders without a readable style.json are skipped.
    public static func list(in folder: URL) -> [Style] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { try? read(folder.appendingPathComponent($0, isDirectory: true)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func read(_ url: URL) throws -> Style {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(tokensFile)) else { throw DirectionError("style_not_found", "There's no style in \(url.lastPathComponent).") }
        guard let tokens = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = tokens, let name = tokens["name"].string, !name.isEmpty else {
            throw DirectionError("style_invalid", "\(url.lastPathComponent)/\(tokensFile) needs at least a name: {\"name\": \"…\", \"summary\": \"…\"}.")
        }
        return Style(id: url.lastPathComponent, url: url, name: name, summary: tokens["summary"].string ?? "", updatedAt: tokens["updatedAt"].double ?? 0, tokens: tokens, contents: contents(url))
    }

    public static func contents(_ url: URL) -> StyleContents {
        let fm = FileManager.default
        func files(_ folder: String, _ exts: Set<String>) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: url.appendingPathComponent(folder).path)) ?? []).filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
        }
        var c = StyleContents()
        c.graphics = ((try? fm.contentsOfDirectory(atPath: url.appendingPathComponent("graphics").path)) ?? []).filter { fm.fileExists(atPath: url.appendingPathComponent("graphics/\($0)/index.html").path) }.sorted()
        c.transitions = files("transitions", ["metal"]); c.effects = files("effects", ["metal"]); c.sounds = files("sounds", audio); c.music = files("music", audio)
        c.fonts = files("fonts", ["ttf", "otf"]); c.stills = files("stills", ["jpg", "jpeg", "png", "heic"])
        c.look = fm.fileExists(atPath: url.appendingPathComponent(lookFile).path)
        return c
    }

    /// A folder name from a style's name: "Desk Talk" → desk-talk, then desk-talk-2 if that's taken.
    public static func newID(_ name: String, in folder: URL) -> String {
        let base = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined().split(separator: "-").joined(separator: "-")
        let stem = base.isEmpty ? "style" : String(base.prefix(48))
        var id = stem, n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(id).path) { id = "\(stem)-\(n)"; n += 1 }
        return id
    }

    /// A new style: its style.json and a guide to fill in.
    @discardableResult
    public static func create(name: String, summary: String, guide: String? = nil, in folder: URL) throws -> Style {
        try save(id: nil, name: name, summary: summary, tokens: nil, guide: guide ?? template(name: name, summary: summary), in: folder)
    }

    /// Writes a style: a new one without `id`, or changes to the one named. Tokens replace style.json's
    /// values key by key (null removes one); guide, when given, replaces guide.md. `files` copies parts in,
    /// each to a path inside the style like "graphics/lower-third" or "sounds/whoosh.wav"; nothing else in
    /// the folder changes.
    @discardableResult
    public static func save(id: String?, name: String?, summary: String?, tokens: JSONValue?, guide: String?, files: [(from: URL, to: String)] = [], in folder: URL) throws -> Style {
        let fm = FileManager.default
        let styleID: String
        var values: [String: JSONValue] = ["format": .number(1)]
        if let id {
            guard isSafe(id), fm.fileExists(atPath: folder.appendingPathComponent(id).appendingPathComponent(tokensFile).path) else { throw DirectionError("style_not_found", "There's no style \(id). direction_styles lists them.") }
            styleID = id
            if case .object(let old) = try read(folder.appendingPathComponent(id)).tokens { values = old }
        } else {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw DirectionError("invalid_arguments", "A new style needs a name.") }
            styleID = newID(name, in: folder)
        }
        if case .object(let changes) = tokens { for (k, v) in changes { values[k] = v == .null ? nil : v } }
        else if tokens != nil && tokens != .null { throw DirectionError("invalid_arguments", "tokens is an object of the style's values, like {\"colors\": {\"accent\": \"#FFC800\"}}.") }
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { values["name"] = .string(name) }
        if let summary { values["summary"] = .string(summary.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values["name"]?.string?.isEmpty == false else { throw DirectionError("invalid_arguments", "A style needs a name.") }
        values["updatedAt"] = .number(Date().timeIntervalSince1970.rounded())
        // Every part's destination is checked before anything is written.
        for f in files { guard isSafe(f.to), fm.fileExists(atPath: f.from.path) else { throw DirectionError("invalid_arguments", "Can't copy \(f.from.lastPathComponent) to \(f.to): give a file or folder that exists and a path inside the style, like sounds/whoosh.wav.") } }
        let url = folder.appendingPathComponent(styleID, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONValue.object(values).data(pretty: true).write(to: url.appendingPathComponent(tokensFile), options: .atomic)
        if let guide { try Data(guide.utf8).write(to: url.appendingPathComponent(guideFile), options: .atomic) }
        else if !fm.fileExists(atPath: url.appendingPathComponent(guideFile).path) { try Data(template(name: values["name"]?.string ?? styleID, summary: values["summary"]?.string ?? "").utf8).write(to: url.appendingPathComponent(guideFile), options: .atomic) }
        for f in files {
            let target = url.appendingPathComponent(f.to)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try replace(target, with: f.from)
        }
        return try read(url)
    }

    /// Gives a film its own copy of a style (or none), replacing the copy it had.
    public static func use(_ style: Style?, film: URL) throws {
        let fm = FileManager.default, target = film.appendingPathComponent(filmFolder, isDirectory: true)
        guard let style else { if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }; return }
        try replace(target, with: style.url)
    }

    /// The film's style, from its own copy, under the id its brief names.
    public static func film(_ film: URL, id: String?) -> Style? {
        guard let id, var s = try? read(film.appendingPathComponent(filmFolder, isDirectory: true)) else { return nil }
        s.id = id
        return s
    }

    /// Copies a file or folder over whatever is at `target`, so a reader never sees half of either.
    static func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent)-\(UUID().uuidString)")
        try fm.copyItem(at: source, to: temporary)
        if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: temporary) } else { try fm.moveItem(at: temporary, to: target) }
    }

    /// A relative path that stays inside the folder it's in.
    public static func isSafe(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
    }
}

// MARK: Settings › Styles

extension SharedSettings {
    public static let stylesFolderKey = "stylesFolder"
    public static var defaultStylesFolder: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Direction/Styles").path }
    /// Tests point this at a temporary folder so nothing reads or writes the director's own.
    nonisolated(unsafe) public static var stylesFolderOverride: URL?
    /// The Styles folder: one folder per style. DIRECTION_STYLES_PATH overrides it for a process.
    public static var stylesFolder: URL {
        if let stylesFolderOverride { return stylesFolderOverride }
        if let env = ProcessInfo.processInfo.environment["DIRECTION_STYLES_PATH"], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        let path = defaults.string(forKey: stylesFolderKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultStylesFolder
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }
}
