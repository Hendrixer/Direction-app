import Foundation
import DirectionCore

// Styles (specs/styles.md): the director's styles in the Styles folder, the one this film is cut in
// (its own copy in Style/), and the editor writing one when the director asks for it.
extension ToolCatalog {
    static var styleDefinitions: [ToolDefinition] { [
        definition("direction_styles", "List the director's styles (the Styles folder): id, name, summary and what each holds, plus the one this film's brief uses. A style is how the director's videos look, sound and move: exact values in style.json, the rest in words in guide.md, and its parts (graphics, transitions, effects, sounds, music, fonts, a look, stills)."),
        definition("direction_style", "Read the film's style (or another with id): its values, its guide in words, and each part with its path and how to use it. Follow it the way an app follows its design system: the brief and the notes come first, the style decides everything they leave open. Copy a graphic's folder to Editor/Graphics/<name>/ and check it with direction_graphic; copy a transition to Editor/Transitions/ and an effect to Editor/Effects/; bring a sound or music in with direction_import; propose its look with direction_make_look fromLUT: <its path>. Never apply the look yourself.", ["id": string]),
        definition("direction_save_style", "Write a style into the director's Styles folder, only when the director asks for one (a style job or a note): a new one with name and summary, or changes to one with id. tokens are the exact values, merged key by key into style.json (null removes one): colors, fonts, pace (averageShotSeconds, pausesUpTo, hookBySeconds), picture (punchIn, brollEverySeconds), motion (in, out, ease), captions, transitions, sound (musicUnderSpeechDB, effectsDB, loudnessLUFS), and anything else the editor should hold to. guide (Markdown) replaces guide.md: Pace, Picture, Graphics, Captions, Transitions, Sound, Music, Color, Avoid, in plain words with numbers. files copies parts in: [{from (a path in your working folder, like Graphics/lower-third or Effects/flash.metal), to (where in the style: graphics/<name>, transitions/<name>.metal, effects/<name>.metal, sounds/<name>.wav, music/<name>.m4a, fonts/<name>.otf, look.cube, stills/<name>.jpg)}]. Returns the style as direction_style reads it.", [
            "id": string, "name": string, "summary": string, "tokens": object, "guide": string,
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
                .object(["id": .string(s.id), "name": .string(s.name), "summary": .string(s.summary), "holds": .string(s.contents.line.isEmpty ? "words only" : s.contents.line), "thisFilm": .bool(s.id == current)])
            }
            var value: [String: JSONValue] = ["styles": .array(list), "folder": .string(folder.path)]
            value["thisFilm"] = try store.style().map { .object(["id": .string($0.id), "name": .string($0.name)]) } ?? .null
            return ToolResponse(.object(value))

        case "direction_style":
            let style: Style
            if let id = a["id"].string, id != (try store.brief().style) {
                guard StyleLibrary.isSafe(id) else { throw DirectionError("style_not_found", "There's no style \(id). direction_styles lists them.") }
                style = try StyleLibrary.read(SharedSettings.stylesFolder.appendingPathComponent(id, isDirectory: true))
            } else {
                guard let s = try store.style() else { throw DirectionError("style_not_found", "This film's brief has no style. The brief and the notes are all there is; direction_styles lists the director's styles.") }
                style = s
            }
            return ToolResponse(styleJSON(style))

        case "direction_save_style":
            var files: [(from: URL, to: String)] = []
            for f in a["files"].array ?? [] {
                guard let from = f["from"].string, let to = f["to"].string else { throw DirectionError("invalid_arguments", "Each file is {from, to}.") }
                files.append((try workingFile(from), to))
            }
            let s = try StyleLibrary.save(id: a["id"].string, name: a["name"].string, summary: a["summary"].string, tokens: a["tokens"] == .null ? nil : a["tokens"], guide: a["guide"].string, files: files, in: SharedSettings.stylesFolder)
            // The film's copy follows when it's this film's style.
            if s.id == (try store.brief().style) { try store.refreshStyle() }
            return ToolResponse(styleJSON(s))

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

    private func styleJSON(_ s: Style) -> JSONValue {
        let c = s.contents, base = s.url
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
        return .object([
            "id": .string(s.id), "name": .string(s.name), "summary": .string(s.summary), "tokens": s.tokens, "guide": .string(s.guide), "parts": .object(parts), "folder": .string(base.path),
            "use": .string("Graphics: copy the folder to copyTo in your working folder (fonts go in the graphic's folder too), then direction_graphic. Transitions and effects: copy to copyTo and use them like your own. Sounds and music: direction_import the path, then place it. Look: propose it with direction_make_look fromLUT: <look>. Stills show what it looks like."),
        ])
    }
}
