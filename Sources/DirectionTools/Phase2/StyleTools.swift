import Foundation
import DirectionCore

// Styles (specs/styles.md): the director's styles in the Styles folder, the house style under every film,
// the one this film is cut in (its own copy in Style/), and the editor writing one when the director asks.
extension ToolCatalog {
    static var styleDefinitions: [ToolDefinition] { [
        definition("direction_styles", "List the director's styles (the Styles folder): id, name, summary, how many rules and what each holds, plus the one this film's brief uses and the house style (id house: the rules every film follows). A style is how the director's videos look, sound and move: rules in words, named layouts, moves Direction carries out (punch-ins, pushes, how tight pauses go), exact values, and its parts (graphics, transitions, effects, sounds, music, fonts, a look, stills)."),
        definition("direction_style", "Read what this film follows (or one style with id; house is the house style): the rules, the house style's first and then the film's style's, each with its area and where it's from; the named layouts (use them by name: layout op with layout: \"Showing\"); the moves (punchIn, emphasisPunch, slowPush and tightenPauses run with these numbers when you leave theirs out); the exact values; and each part with its path and how to use it. Your note and the brief come first; where the style and the house style disagree, the style wins. Copy a graphic's folder to Editor/Graphics/<name>/ and check it with direction_graphic; copy a transition to Editor/Transitions/ and an effect to Editor/Effects/; bring a sound or music in with direction_import; propose its look with direction_make_look fromLUT: <its path>. Never apply the look yourself.", ["id": string]),
        definition("direction_save_style", "Write a style into the director's Styles folder, only when the director asks for one (a style job or a note): a new one with name and summary, or changes to one with id (house writes the house style). rules adds rules, each one sentence in the director's words with an area (general, pace, picture, layouts, graphics, captions, transitions, sound, music, color, avoid); removeRules takes rules out by id. tokens are merged key by key into style.json (null removes one): layouts (named: [{name, kind: screenAndYou|you|screen|sideBySide, corner?, size?: small|medium|large, shape?: circle|rounded|wide, screen?: full|framed, edge?: #RRGGBB}]), moves ({punchIn?: {scales, keepIn?}, emphasisPunch?: {scale, everySeconds?}, slowPush?: {from, to, longerThan}}), pace ({tightenPauses: {longerThan, to}, averageShotSeconds, longestShotSeconds, hookBySeconds}), colors, fonts, motion, captions, transitions, sound, graphics (which part plays which role), look. Numbers Direction carries out go in layouts, moves and pace; what only you can judge goes in rules. files copies parts in: [{from (a path in your working folder, like Graphics/lower-third or Effects/flash.metal), to (where in the style: graphics/<name>, transitions/<name>.metal, effects/<name>.metal, sounds/<name>.wav, music/<name>.m4a, fonts/<name>.otf, look.cube, stills/<name>.jpg)}]. Returns the style as direction_style reads it.", [
            "id": string, "name": string, "summary": string, "tokens": object,
            "rules": .object(["type": .string("array"), "items": record(["area": string, "text": string], required: ["text"])]),
            "removeRules": list(string),
            "files": .object(["type": .string("array"), "items": record(["from": string, "to": string], required: ["from", "to"])]),
        ], readOnly: false),
    ] }
}

extension ToolRuntime {
    func invokeStyles(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_styles":
            let folder = SharedSettings.stylesFolder, current = try store.brief().style
            let list: [JSONValue] = StyleLibrary.list(in: folder).map { s in
                .object(["id": .string(s.id), "name": .string(s.name), "summary": .string(s.summary), "rules": .number(Double(s.rules.count)), "layouts": .array(s.layouts.compactMap { $0.name.map(JSONValue.string) }),
                         "holds": .string(s.contents.line.isEmpty ? "words only" : s.contents.line), "thisFilm": .bool(s.id == current)])
            }
            let house = StyleLibrary.house(in: folder)
            var value: [String: JSONValue] = ["styles": .array(list), "folder": .string(folder.path),
                                              "house": .object(["id": .string(house.id), "name": .string(house.name), "rules": .number(Double(house.rules.count)), "note": .string("Under every film. Where a film's style says otherwise, the style wins.")])]
            value["thisFilm"] = try store.style().map { .object(["id": .string($0.id), "name": .string($0.name)]) } ?? .null
            return ToolResponse(.object(value))

        case "direction_style":
            if let id = a["id"].string, id != (try store.brief().style) {
                if id == StyleLibrary.houseID { return ToolResponse(styleJSON(AppliedStyle(house: StyleLibrary.house(in: SharedSettings.stylesFolder), style: nil), only: true)) }
                guard StyleLibrary.isSafe(id) else { throw DirectionError("style_not_found", "There's no style \(id). direction_styles lists them.") }
                let other = try StyleLibrary.read(SharedSettings.stylesFolder.appendingPathComponent(id, isDirectory: true))
                return ToolResponse(styleJSON(AppliedStyle(house: StyleLibrary.house(in: SharedSettings.stylesFolder), style: other), only: true))
            }
            return ToolResponse(styleJSON(try store.appliedStyle()))

        case "direction_save_style":
            var files: [(from: URL, to: String)] = []
            for f in a["files"].array ?? [] {
                guard let from = f["from"].string, let to = f["to"].string else { throw DirectionError("invalid_arguments", "Each file is {from, to}.") }
                files.append((try workingFile(from), to))
            }
            let folder = SharedSettings.stylesFolder
            var s = try StyleLibrary.save(id: a["id"].string, name: a["name"].string, summary: a["summary"].string, tokens: a["tokens"] == .null ? nil : a["tokens"], guide: a["guide"].string, files: files, in: folder)
            if let gone = a["removeRules"].array?.compactMap(\.string), !gone.isEmpty { s = try StyleLibrary.remove(rules: Set(gone), from: s.id, folder: folder) }
            for r in a["rules"].array ?? [] {
                guard let text = r["text"].string else { throw DirectionError("invalid_arguments", "Each rule is {area, text}.") }
                s = try StyleLibrary.keep(StyleRule(area: r["area"].string ?? "general", text: text), in: s.id, folder: folder)
            }
            // The film's copy follows when it's this film's style.
            if s.id == (try store.brief().style) { try store.refreshStyle() }
            return ToolResponse(styleJSON(AppliedStyle(house: StyleLibrary.house(in: folder), style: s.isHouse ? nil : s), only: true))

        default: return nil
        }
    }

    /// A path the editor names: in its working folder (`<film>/Editor/`), or anywhere inside the film.
    private func workingFile(_ path: String) throws -> URL {
        let film = store.url.standardizedFileURL.path, editor = store.url.appendingPathComponent("Editor").standardizedFileURL
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path).standardizedFileURL : editor.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(film + "/"), FileManager.default.fileExists(atPath: url.path) else { throw DirectionError("invalid_arguments", "\(path) isn't in your working folder. Give a path like Graphics/lower-third.") }
        return url
    }

    /// What a film follows (the house style and its own), or one style alone (`only`; the house style when
    /// there's no other): rules with where each is from, layouts by name, moves, values and parts.
    private func styleJSON(_ applied: AppliedStyle, only: Bool = false) -> JSONValue {
        let main = applied.style ?? applied.house
        let rules = only ? main.rules.map { AppliedStyle.Rule(rule: $0, styleID: main.id, styleName: main.name) } : applied.rules
        let c = main.contents, base = main.url
        func path(_ p: String) -> String { base.appendingPathComponent(p).path }
        var parts: [String: JSONValue] = [
            "graphics": .array(c.graphics.map { .object(["name": .string($0), "path": .string(path("graphics/" + $0)), "copyTo": .string("Graphics/\($0)")]) }),
            "transitions": .array(c.transitions.map { .object(["file": .string($0), "path": .string(path("transitions/" + $0)), "copyTo": .string("Transitions/\($0)")]) }),
            "effects": .array(c.effects.map { .object(["file": .string($0), "path": .string(path("effects/" + $0)), "copyTo": .string("Effects/\($0)")]) }),
            "sounds": .array(c.sounds.map { .object(["file": .string($0), "path": .string(path("sounds/" + $0))]) }),
            "music": .array(c.music.map { .object(["file": .string($0), "path": .string(path("music/" + $0))]) }),
            "fonts": .array(c.fonts.map { .object(["file": .string($0), "path": .string(path("fonts/" + $0))]) }),
            "stills": .array(c.stills.map { .object(["file": .string($0), "path": .string(path("stills/" + $0))]) }),
        ]
        parts["look"] = c.look ? .string(path(StyleLibrary.lookFile)) : .null
        var values: [String: JSONValue] = [:]
        if case .object(let t) = main.tokens { values = t.filter { !["format", "name", "summary", "updatedAt", "rules", "layouts", "moves"].contains($0.key) } }
        let layouts = only ? main.layouts : applied.layouts
        let ruleList: [JSONValue] = rules.map { r in
            .object(["id": .string(r.rule.id), "area": .string(r.rule.area), "text": .string(r.rule.text), "from": .string(r.styleName), "styleID": .string(r.styleID)])
        }
        let follows = only ? "One style on its own." : (applied.style == nil ? "This film has no style: the house style, the brief and the notes." : "The house style, with \(main.name) over it. Your notes and the brief come first; where \(main.name) and the house style disagree, \(main.name) wins.")
        return .object([
            "id": .string(main.id), "name": .string(main.name), "summary": .string(main.summary),
            "follows": .string(follows), "rules": .array(ruleList),
            "layouts": (try? .wrapping(layouts)) ?? .array([]),
            "moves": (try? .wrapping(only ? main.moves.over(.standard) : applied.moves)) ?? .null,
            "values": .object(values), "parts": .object(parts), "folder": .string(base.path),
            "use": .string("Rules: follow them where your note and the brief leave a choice open. Layouts: the layout op by name. Moves: punchIn, emphasisPunch, slowPush and tightenPauses take these numbers when you leave theirs out. Graphics: copy the folder to copyTo in your working folder (fonts go in the graphic's folder too), then direction_graphic. Transitions and effects: copy to copyTo and use them like your own. Sounds and music: direction_import the path, then place it. Look: propose it with direction_make_look fromLUT: <look>. Stills show what it looks like."),
        ])
    }
}
