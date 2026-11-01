import Foundation

// Styles (specs/styles.md): how a director's videos look, sound and move, kept in one folder the editor
// follows the way an app follows its design system. style.json holds the name, the rules in words, and
// what Direction carries out itself: the style's layouts, its moves (punch-ins, pushes) and its pace,
// beside the exact values (colors, fonts, levels); the folders beside it hold the parts (graphics,
// transitions, sounds, fonts, a look). The house style sits under every film; a film keeps its own copy
// of the style it uses.

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
    /// The house style: the rules every film follows, under whatever style it's cut in.
    public var isHouse: Bool { id == StyleLibrary.houseID }

    /// The style's rules, in order. A style written before rules (format 1) has them read from its guide.
    public var rules: [StyleRule] {
        if case .array(let list) = tokens["rules"] { return list.enumerated().compactMap { i, v in StyleRule(json: v, index: i) } }
        return StyleLibrary.rules(fromGuide: guide)
    }
    /// The style's own layouts, by name (layouts.md › In a style).
    public var layouts: [FrameLayout] {
        guard case .array(let list) = tokens["layouts"] else { return [] }
        return list.compactMap { try? $0.decode(FrameLayout.self) }.filter { $0.name?.isEmpty == false }
    }
    /// The style's transitions by name ("Chapter", "New section"), each with its sound (styles.md › Transitions).
    public var transitions: [StyleTransition] {
        guard case .array(let list) = tokens["transitions"] else { return [] }
        return list.compactMap { try? $0.decode(StyleTransition.self) }.filter { !$0.name.isEmpty }
    }
    /// The moves Direction carries out for this style, as written (unset ones come from the house style).
    public var moves: StyleMoves {
        var m = (try? tokens["moves"].decode(StyleMoves.self)) ?? StyleMoves()
        if m.tightenPauses == nil { m.tightenPauses = try? tokens["pace"]["tightenPauses"].decode(StyleMoves.Pauses.self) }
        return m
    }
    /// The videos it was learned from (styles.md › From a video), with what Direction measured in each.
    public var sources: [StyleSource] {
        guard case .array(let list) = tokens["sources"] else { return [] }
        return list.compactMap { try? $0.decode(StyleSource.self) }
    }
    /// Moments that show a rule, each a still in the style.
    public var examples: [StyleExample] {
        guard case .array(let list) = tokens["examples"] else { return [] }
        return list.compactMap { try? $0.decode(StyleExample.self) }.filter { StyleLibrary.isSafe($0.still) && $0.still.hasPrefix("stills/") }
    }
    /// How a video of this kind is built over time: the hook, the sections, the ending.
    public var structure: [StyleSection] {
        guard case .array(let list) = tokens["structure"] else { return [] }
        return list.compactMap { try? $0.decode(StyleSection.self) }.filter { !$0.name.isEmpty }
    }
}

/// A video a style was learned from: where it is, who made it, and the numbers Direction measured in it.
/// The video itself isn't kept; the link can fetch it again.
public struct StyleSource: Codable, Hashable, Sendable {
    public var title: String
    public var by: String?
    public var link: String?
    public var studiedAt: Double?
    /// What Direction measured, without the list of shots.
    public var measured: VideoStudy?
    public init(title: String, by: String? = nil, link: String? = nil, studiedAt: Double? = nil, measured: VideoStudy? = nil) {
        self.title = title; self.by = by; self.link = link; self.studiedAt = studiedAt; self.measured = measured
    }
    /// From a study: its numbers, its shots left out.
    public init(_ study: VideoStudy) {
        var numbers = study; numbers.shots = []
        self.init(title: study.title, by: study.by, link: study.link, studiedAt: study.studiedAt, measured: numbers)
    }
}

/// One moment that shows how the style does something: "Punch in on the punchline, like this", with a still
/// of it in the style's stills folder and where it came from.
public struct StyleExample: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// stills/<name>.jpg in the style.
    public var still: String
    public var area: String
    public var text: String
    /// The source (by its index in sources) and the second it's from.
    public var source: Int?
    public var at: Double?
    public init(id: String = newID("example"), still: String, area: String = "general", text: String, source: Int? = nil, at: Double? = nil) {
        self.id = id; self.still = still; self.area = area; self.text = text; self.source = source; self.at = at
    }
    /// The editor writes examples without ids; each is known by its still.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        still = try c.decode(String.self, forKey: .still); text = try c.decode(String.self, forKey: .text)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? still
        area = try c.decodeIfPresent(String.self, forKey: .area) ?? "general"
        source = try c.decodeIfPresent(Int.self, forKey: .source); at = try c.decodeIfPresent(Double.self, forKey: .at)
    }
}

/// A part of how a video of this kind runs: "Hook: a question to camera, then the result, in the first 8 s".
public struct StyleSection: Codable, Hashable, Sendable {
    public var name: String
    /// Where it usually starts and how long it runs, in seconds; nil when it varies.
    public var at: Double?
    public var length: Double?
    public var what: String
    public init(name: String, at: Double? = nil, length: Double? = nil, what: String) { self.name = name; self.at = at; self.length = length; self.what = what }
}

/// One rule of a style, in the director's words: "Text never covers my face." Kept from a note, written
/// by hand, or made with the editor. `area` groups it (pace, picture, layouts, graphics, …).
public struct StyleRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var area: String
    public var text: String
    /// Where a rule kept from a note came from.
    public var kept: Kept?
    public struct Kept: Codable, Hashable, Sendable {
        public var film: String
        public var note: String?
        public var at: Double
        public init(film: String, note: String?, at: Double = Date().timeIntervalSince1970) { self.film = film; self.note = note; self.at = at }
    }
    public init(id: String = newID("rule"), area: String = "general", text: String, kept: Kept? = nil) { self.id = id; self.area = StyleRule.area(area); self.text = text; self.kept = kept }

    /// The areas a style's rules are grouped in, in order, with their names.
    public static let areas: [(id: String, label: String)] = [
        ("general", "General"), ("pace", "Pace"), ("picture", "Picture"), ("layouts", "Layouts"), ("graphics", "Graphics"), ("captions", "Captions"),
        ("transitions", "Transitions"), ("sound", "Sound"), ("music", "Music"), ("color", "Color"), ("avoid", "Avoid"),
    ]
    public static func area(_ raw: String?) -> String {
        let a = (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return areas.contains { $0.id == a } ? a : "general"
    }
    public static func label(_ area: String) -> String { areas.first { $0.id == area }?.label ?? "General" }

    init?(json v: JSONValue, index: Int) {
        if let text = v.string { guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }; self.init(id: "rule-\(index + 1)", text: text); return }
        guard let text = v["text"].string, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        self.init(id: v["id"].string ?? "rule-\(index + 1)", area: v["area"].string ?? "general", text: text, kept: try? v["kept"].decode(Kept.self))
    }
}

/// A transition a style names for a kind of moment: which one, how long, its settings, and the sound under it.
/// `file` and `sound` are paths inside the style (transitions/glint.metal, sounds/whoosh.wav).
public struct StyleTransition: Codable, Hashable, Sendable {
    public var name: String
    /// dissolve, dipToBlack, dipToWhite, push, slide, whip, zoom, wipe, iris, or shader (with `file`).
    public var type: String
    public var frames: Int
    public var params: [String: JSONValue]?
    public var file: String?
    public var sound: String?
    /// The sound's level, in dB.
    public var soundDB: Double?
    /// A technique from the Techniques folder that makes it (techniques.md); its own settings above win.
    public var technique: String?
    /// One of the technique's named variants.
    public var variant: String?
    public init(name: String, type: String, frames: Int, params: [String: JSONValue]? = nil, file: String? = nil, sound: String? = nil, soundDB: Double? = nil, technique: String? = nil, variant: String? = nil) {
        self.name = name; self.type = type; self.frames = frames; self.params = params; self.file = file; self.sound = sound; self.soundDB = soundDB; self.technique = technique; self.variant = variant
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        technique = try c.decodeIfPresent(String.self, forKey: .technique)
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        // A style's transition made by a technique needs only the technique's name.
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? (technique == nil ? { throw DecodingError.keyNotFound(CodingKeys.type, .init(codingPath: c.codingPath, debugDescription: "type")) }() : "technique")
        frames = try c.decodeIfPresent(Int.self, forKey: .frames) ?? 0
        guard technique != nil || frames > 0 else { throw DecodingError.dataCorruptedError(forKey: .frames, in: c, debugDescription: "frames") }
        params = try c.decodeIfPresent([String: JSONValue].self, forKey: .params)
        file = try c.decodeIfPresent(String.self, forKey: .file); sound = try c.decodeIfPresent(String.self, forKey: .sound); soundDB = try c.decodeIfPresent(Double.self, forKey: .soundDB)
    }
}

/// What Direction carries out for a style without the editor working it out: punch-ins on jump cuts, the
/// emphasis punch, the slow push, and how tight the pauses go (agent-timeline.md › Moves).
public struct StyleMoves: Codable, Hashable, Sendable {
    public struct PunchIn: Codable, Hashable, Sendable {
        /// Framings in turn on each jump cut: wide, then medium, then wide again.
        public var scales: [Double]
        /// Where the face sits: thirds (eyes on the upper third) or center.
        public var keepIn: String?
        public init(scales: [Double], keepIn: String? = nil) { self.scales = scales; self.keepIn = keepIn }
    }
    public struct Emphasis: Codable, Hashable, Sendable {
        public var scale: Double
        /// At most one this often.
        public var everySeconds: Double?
        public init(scale: Double, everySeconds: Double? = nil) { self.scale = scale; self.everySeconds = everySeconds }
    }
    public struct Push: Codable, Hashable, Sendable {
        public var from: Double, to: Double
        /// Only shots at least this long.
        public var longerThan: Double
        public init(from: Double, to: Double, longerThan: Double) { self.from = from; self.to = to; self.longerThan = longerThan }
    }
    public struct Pauses: Codable, Hashable, Sendable {
        public var longerThan: Double, to: Double
        public init(longerThan: Double, to: Double) { self.longerThan = longerThan; self.to = to }
    }
    /// Zooms on a screen recording: how far (min to max), how long in and out, and the shortest hold.
    public struct Zoom: Codable, Hashable, Sendable {
        public var min: Double, max: Double
        public var `in`: Double, out: Double
        public var hold: Double
        public init(min: Double, max: Double, in: Double, out: Double, hold: Double) { self.min = min; self.max = max; self.in = `in`; self.out = out; self.hold = hold }
    }
    public var punchIn: PunchIn?
    public var emphasisPunch: Emphasis?
    public var slowPush: Push?
    public var tightenPauses: Pauses?
    public var screenZoom: Zoom?
    public init(punchIn: PunchIn? = nil, emphasisPunch: Emphasis? = nil, slowPush: Push? = nil, tightenPauses: Pauses? = nil, screenZoom: Zoom? = nil) {
        self.punchIn = punchIn; self.emphasisPunch = emphasisPunch; self.slowPush = slowPush; self.tightenPauses = tightenPauses; self.screenZoom = screenZoom
    }
    /// Direction's own, under the house style.
    public static let standard = StyleMoves(punchIn: .init(scales: [1, 1.15], keepIn: "thirds"), emphasisPunch: .init(scale: 1.3, everySeconds: 45), slowPush: .init(from: 1, to: 1.05, longerThan: 8), tightenPauses: .init(longerThan: 0.35, to: 0.15),
                                            screenZoom: .init(min: 1.4, max: 2, in: 0.6, out: 0.5, hold: 1.5))
    /// These moves, with any left unset taken from `base`.
    public func over(_ base: StyleMoves) -> StyleMoves {
        StyleMoves(punchIn: punchIn ?? base.punchIn, emphasisPunch: emphasisPunch ?? base.emphasisPunch, slowPush: slowPush ?? base.slowPush, tightenPauses: tightenPauses ?? base.tightenPauses, screenZoom: screenZoom ?? base.screenZoom)
    }
}

/// What a film follows: the house style, then its own style on top (the narrower one wins where they
/// disagree; a note or the brief wins over both).
public struct AppliedStyle: Sendable {
    public struct Rule: Hashable, Sendable {
        public var rule: StyleRule
        /// The style it belongs to: the house style's id, or the film's style's.
        public var styleID: String
        public var styleName: String
        public init(rule: StyleRule, styleID: String, styleName: String) { self.rule = rule; self.styleID = styleID; self.styleName = styleName }
    }
    public var house: Style
    public var style: Style?
    public init(house: Style, style: Style?) { self.house = house; self.style = style }
    /// The house style's rules first, then the style's.
    public var rules: [Rule] {
        house.rules.map { Rule(rule: $0, styleID: house.id, styleName: house.name) } + (style?.rules ?? []).map { Rule(rule: $0, styleID: style!.id, styleName: style!.name) }
    }
    /// The style's layouts, or the house style's when it has none.
    public var layouts: [FrameLayout] { (style?.layouts).flatMap { $0.isEmpty ? nil : $0 } ?? house.layouts }
    public func layout(named name: String) -> FrameLayout? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return layouts.first { $0.name?.lowercased() == n }
    }
    /// The style's transitions, or the house style's when it has none.
    public var transitions: [StyleTransition] { (style?.transitions).flatMap { $0.isEmpty ? nil : $0 } ?? house.transitions }
    /// A transition by name, and the style it comes from (its file and sound are paths inside it).
    public func transition(named name: String) -> (transition: StyleTransition, style: Style)? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let s = style, let t = s.transitions.first(where: { $0.name.lowercased() == n }) { return (t, s) }
        return house.transitions.first { $0.name.lowercased() == n }.map { ($0, house) }
    }
    /// Each move from the style, else the house style, else Direction's own.
    public var moves: StyleMoves { (style?.moves ?? StyleMoves()).over(house.moves).over(.standard) }
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
    /// The house style's folder in the Styles folder. It isn't listed with the styles a brief picks.
    public static let houseID = "house"
    public static let houseName = "House style"
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

    /// A guide in words (format 1) as rules: each bullet or paragraph under a heading is one rule in that
    /// heading's area. The template's own placeholder lines aren't rules.
    public static func rules(fromGuide guide: String) -> [StyleRule] {
        let placeholders = Set(template(name: "", summary: "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        var out: [StyleRule] = [], area = "general", paragraph: [String] = []
        func flush() {
            let text = paragraph.joined(separator: " ").replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            paragraph = []
            guard !text.isEmpty, !placeholders.contains(text), text != "What this style is, and the videos it\u{2019}s for.", text != "What this style is, and the videos it's for." else { return }
            out.append(StyleRule(id: "rule-\(out.count + 1)", area: area, text: text))
        }
        for raw in guide.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { flush(); area = StyleRule.area(String(line.dropFirst(3)).split(separator: " ").first.map(String.init)); continue }
            if line.hasPrefix("# ") { flush(); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { flush(); paragraph = [String(line.dropFirst(2))]; continue }
            paragraph.append(line)
        }
        flush()
        return out
    }

    /// Every style in a folder, by name, without the house style. Folders without a readable style.json are skipped.
    public static func list(in folder: URL) -> [Style] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0 != houseID }.compactMap { try? read(folder.appendingPathComponent($0, isDirectory: true)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The house style in a Styles folder, or an empty one until something is kept in it.
    public static func house(in folder: URL) -> Style {
        let url = folder.appendingPathComponent(houseID, isDirectory: true)
        if var s = try? read(url) { s.name = houseName; return s }
        return Style(id: houseID, url: url, name: houseName, summary: "", updatedAt: 0, tokens: .object(["format": .number(2), "name": .string(houseName), "rules": .array([])]), contents: StyleContents())
    }

    /// What a film follows: the house style in `folder` with the film's own style over it.
    public static func applied(_ style: Style?, folder: URL) -> AppliedStyle { AppliedStyle(house: house(in: folder), style: style) }

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
        while id == houseID || FileManager.default.fileExists(atPath: folder.appendingPathComponent(id).path) { id = "\(stem)-\(n)"; n += 1 }
        return id
    }

    /// A new style: its name and sentence, and rules when there are some.
    @discardableResult
    public static func create(name: String, summary: String, rules: [StyleRule] = [], in folder: URL) throws -> Style {
        try save(id: nil, name: name, summary: summary, tokens: nil, guide: nil, rules: rules, in: folder)
    }

    /// Writes a style: a new one without `id`, or changes to the one named (the house style's id writes the
    /// house style, made the first time). Tokens replace style.json's values key by key (null removes one).
    /// `rules` replaces the style's rules; a `guide` in words (the older way) is read into rules. `files`
    /// copies parts in, each to a path inside the style like "graphics/lower-third" or "sounds/whoosh.wav";
    /// nothing else in the folder changes.
    @discardableResult
    public static func save(id: String?, name: String?, summary: String?, tokens: JSONValue?, guide: String?, rules: [StyleRule]? = nil, files: [(from: URL, to: String)] = [], in folder: URL) throws -> Style {
        let fm = FileManager.default
        let styleID: String
        var values: [String: JSONValue] = ["format": .number(2), "rules": .array([])]
        if id == houseID {
            styleID = houseID
            if case .object(let old) = house(in: folder).tokens { values = old }
            values["name"] = .string(houseName)
        } else if let id {
            guard isSafe(id), fm.fileExists(atPath: folder.appendingPathComponent(id).appendingPathComponent(tokensFile).path) else { throw DirectionError("style_not_found", "There's no style \(id). direction_styles lists them.") }
            styleID = id
            if case .object(let old) = try read(folder.appendingPathComponent(id)).tokens { values = old }
        } else {
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { throw DirectionError("invalid_arguments", "A new style needs a name.") }
            styleID = newID(name, in: folder)
        }
        // A style written before rules keeps the ones its guide says, in style.json from now on.
        if values["rules"] == nil, let id, id != houseID, rules == nil, guide == nil {
            values["rules"] = try .wrapping(StyleLibrary.rules(fromGuide: (try? String(contentsOf: folder.appendingPathComponent(id).appendingPathComponent(guideFile), encoding: .utf8)) ?? ""))
        }
        if case .object(let changes) = tokens {
            for (k, v) in changes where !["format", "rules"].contains(k) { values[k] = v == .null ? nil : v }
            if let layouts = changes["layouts"], layouts != .null {
                guard case .array(let list) = layouts, list.allSatisfy({ (try? $0.decode(FrameLayout.self))?.name?.isEmpty == false }) else {
                    throw DirectionError("invalid_arguments", "layouts is a list of named layouts: [{name, kind: screenAndYou|you|screen|sideBySide, corner?, size?, shape?, screen?, edge?}].")
                }
            }
            if let moves = changes["moves"], moves != .null, (try? moves.decode(StyleMoves.self)) == nil {
                throw DirectionError("invalid_arguments", "moves is {punchIn?: {scales, keepIn?}, emphasisPunch?: {scale, everySeconds?}, slowPush?: {from, to, longerThan}, screenZoom?: {min, max, in, out, hold}}.")
            }
            if case .array(let list) = changes["transitions"], !list.allSatisfy({ (try? $0.decode(StyleTransition.self)).map { !$0.name.isEmpty } == true }) {
                throw DirectionError("invalid_arguments", "transitions is a list of named transitions: [{name, type, frames, params?, file? (transitions/<name>.metal), sound? (sounds/<name>.wav), soundDB?}].")
            }
        }
        else if tokens != nil && tokens != .null { throw DirectionError("invalid_arguments", "tokens is an object of the style's values, like {\"colors\": {\"accent\": \"#FFC800\"}}.") }
        if let guide { values["rules"] = try .wrapping(StyleLibrary.rules(fromGuide: guide)) }
        if let rules { values["rules"] = try .wrapping(rules.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }
        values["format"] = .number(2)
        if styleID != houseID, let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { values["name"] = .string(name) }
        if let summary { values["summary"] = .string(summary.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values["name"]?.string?.isEmpty == false else { throw DirectionError("invalid_arguments", "A style needs a name.") }
        values["updatedAt"] = .number(Date().timeIntervalSince1970.rounded())
        // Every part's destination is checked before anything is written.
        for f in files { guard isSafe(f.to), fm.fileExists(atPath: f.from.path) else { throw DirectionError("invalid_arguments", "Can't copy \(f.from.lastPathComponent) to \(f.to): give a file or folder that exists and a path inside the style, like sounds/whoosh.wav.") } }
        let url = folder.appendingPathComponent(styleID, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONValue.object(values).data(pretty: true).write(to: url.appendingPathComponent(tokensFile), options: .atomic)
        for f in files {
            let target = url.appendingPathComponent(f.to)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try replace(target, with: f.from)
        }
        var saved = try read(url)
        if styleID == houseID { saved.name = houseName }
        return saved
    }

    /// Adds one rule to a style, or to the house style.
    @discardableResult
    public static func keep(_ rule: StyleRule, in id: String, folder: URL) throws -> Style {
        let current = id == houseID ? house(in: folder) : try read(folder.appendingPathComponent(id, isDirectory: true))
        guard !rule.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DirectionError("invalid_arguments", "A rule needs words.") }
        return try save(id: id, name: nil, summary: nil, tokens: nil, guide: nil, rules: current.rules + [rule], in: folder)
    }

    /// Takes rules out of a style by id.
    @discardableResult
    public static func remove(rules ids: Set<String>, from id: String, folder: URL) throws -> Style {
        let current = id == houseID ? house(in: folder) : try read(folder.appendingPathComponent(id, isDirectory: true))
        return try save(id: id, name: nil, summary: nil, tokens: nil, guide: nil, rules: current.rules.filter { !ids.contains($0.id) }, in: folder)
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
    /// Tests point this at a temporary folder so nothing reads or writes the director's own. Every tool reads
    /// the folder (the house style is under every film), so it's guarded while a test changes it.
    public static var stylesFolderOverride: URL? {
        get { overrideLock.lock(); defer { overrideLock.unlock() }; return overrideURL }
        set { overrideLock.lock(); overrideURL = newValue; overrideLock.unlock() }
    }
    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var overrideURL: URL?
    /// The Styles folder: one folder per style. DIRECTION_STYLES_PATH overrides it for a process; a test
    /// process without either gets a folder of its own.
    public static var stylesFolder: URL {
        if let stylesFolderOverride { return stylesFolderOverride }
        if let env = ProcessInfo.processInfo.environment["DIRECTION_STYLES_PATH"], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        if DirectionPaths.isTesting { return FileManager.default.temporaryDirectory.appendingPathComponent("DirectionTestStyles", isDirectory: true) }
        let path = defaults.string(forKey: stylesFolderKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultStylesFolder
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }
}
