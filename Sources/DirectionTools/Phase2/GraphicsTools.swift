import Foundation
import DirectionCore
import DirectionMedia

// Graphics (specs/graphics.md): titles, lower thirds and end cards the editor writes as small web
// pages in Editor/Graphics/<name>/, checked and rendered by Direction, then placed with placeGraphic.
extension ToolCatalog {
    static var graphicsDefinitions: [ToolDefinition] {
        [
            definition("direction_graphic_examples", "List the graphics examples that ship with Direction (Title card, Lower third, Chapter card, End card, Quote, Kinetic words, Counter, Map line, Simple chart, Logo sting, Credits roll, Captions style), or pass name for one example's full source. Start every graphic from the closest example: copy its files into Editor/Graphics/<name>/ in the film and change them.",
                       ["name": .object(["type": .string("string"), "description": .string("An example's name or title, such as title-card or Lower third.")])]),
            definition("direction_graphic", "Check and render the graphic in Editor/Graphics/<name>/ (index.html calling direction.graphic({duration, words, render})). Returns stills at 0, 25, 50, 75 and 100%, console errors, render time per frame, and problems: words that overflow their box, anything outside title safe (90%), text under 24 px at 1080p, contrast under 4.5:1 against the picture behind it, words over their max, and visible words not in words. Fix every problem and look at the stills before placing it with direction_edit placeGraphic. Renders are ProRes 4444 with alpha, cached by files and words, and registered as an asset (assetID). Fails if the page throws, a frame takes over 2 s, or it requests the internet. Words the director changed stay theirs (words_are_yours) unless note is a later note that names the graphic. check: true checks and makes stills without rendering the movie.", [
                "name": .object(["type": .string("string"), "description": .string("The graphic's folder name: lowercase letters, digits and dashes, such as title or lower-third.")]),
                "note": .object(["type": .array([.string("string"), .string("integer")]), "description": .string("The note this graphic answers: its id or number, or \"unasked\" with latitude free.")]),
                "check": bool,
            ], required: ["name", "note"], readOnly: false),
        ]
    }
}

extension ToolRuntime {
    func invokeGraphics(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_graphic_examples":
            guard let query = a["name"].string, !query.isEmpty else {
                let list = try GraphicResources.examples().map { e -> JSONValue in
                    .object(["name": .string(e.name), "title": .string(e.title), "summary": .string(e.summary), "libraries": .array((e.libraries ?? []).map(JSONValue.string))])
                }
                return ToolResponse(.object([
                    "examples": .array(list),
                    "folder": .string(store.graphicsFolder.path),
                    "contract": .string("index.html calls direction.graphic({ duration (s), words: { key: { label, text, max } }, render(t, words) }). render draws the whole frame for time t and may be async. Every visible word comes from words. Helpers: direction.ease.{linear,in,out,inOut,spring}, direction.clamp, direction.lerp, direction.random(seed). Time is Direction's: Date.now, performance.now and requestAnimationFrame advance only per frame, Math.random is seeded, and CSS and Web Animations are seeked to t. Nothing loads from the internet."),
                    "libraries": .array(GraphicResources.libraries.map { .string("direction:lib/\($0).js") } + [.string("direction:lib/three.module.js (ES module)")]),
                    "fonts": .string("Archivo (bundled, font-family 'Archivo', weights 100–900, widths 62–125%), system fonts, and font files in the graphic's folder."),
                ]))
            }
            let (example, folder) = try GraphicResources.example(query)
            let files = try GraphicResources.files(in: folder).map { path -> JSONValue in
                .object(["path": .string(path), "source": .string((try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)) ?? "")])
            }
            return ToolResponse(.object(["name": .string(example.name), "title": .string(example.title), "summary": .string(example.summary), "files": .array(files),
                                         "copyTo": .string(store.graphicsFolder.appendingPathComponent("<name>").path)]))

        case "direction_graphic":
            let graphic = try a.requiredString("name"), noteID = try graphicNote(a["note"])
            let result = try await GraphicMaker.make(store: store, name: graphic, noteID: noteID, checkOnly: a["check"].bool ?? false, cacheDirectory: cacheDirectory)
            return ToolResponse(try graphicJSON(result), imagePaths: result.stills.map(\.path))

        default: return nil
        }
    }

    /// A note by id or number; "unasked" for a graphic no note asked for.
    private func graphicNote(_ value: JSONValue) throws -> String? {
        if value.string?.lowercased() == "unasked" { return nil }
        let notes = try store.notes()
        let found: ReviewComment?
        if let n = value.int ?? value.string.flatMap({ Int($0) }) { found = notes.first { $0.number == n } }
        else if let id = value.string { found = notes.first { $0.id == id } }
        else { throw DirectionError("invalid_arguments", "note is a note id or number, or \"unasked\".") }
        guard let note = found, note.visibleToEditor else { throw DirectionError("note_not_found", "There's no note \(value.string ?? value.int.map(String.init) ?? "") you can answer.") }
        return note.id
    }

    private func graphicJSON(_ r: GraphicResult) throws -> JSONValue {
        let g = r.graphic
        let words: [JSONValue] = g.words.map { w in
            // setByDirector: the director typed these; keep them unless a later note names the graphic.
            .object(["key": .string(w.key), "label": .string(w.label), "text": .string(g.text(w.key) ?? w.text), "max": w.maxLength.map { .number(Double($0)) } ?? .null, "setByDirector": .bool(g.directorWords[w.key] != nil)])
        }
        let ms = r.frameMilliseconds
        var value: [String: JSONValue] = [
            "name": .string(g.name), "folder": .string(g.folder), "duration": .number(g.duration), "words": .array(words),
            "note": g.noteID.map(JSONValue.string) ?? .string("unasked"),
            "problems": try .wrapping(r.problems), "consoleErrors": .array(r.consoleErrors.map(JSONValue.string)),
            "stills": try .wrapping(r.stills), "picture": .string(r.picture),
            "frameTimes": .object(["milliseconds": .array(ms.map(JSONValue.number)), "slowest": .number(ms.max() ?? 0), "average": .number(ms.isEmpty ? 0 : (ms.reduce(0, +) / Double(ms.count) * 10).rounded() / 10)]),
        ]
        if let movie = r.movie {
            value["movie"] = .object(["path": .string(movie.path), "cached": .bool(r.cached), "frames": .number(Double(movie.frames)), "width": .number(Double(movie.width)), "height": .number(Double(movie.height)),
                                      "frameRate": .number(movie.frameRate.value), "codec": .string("ProRes 4444 with alpha")])
            value["assetID"] = g.assetID.map(JSONValue.string) ?? .null
            value["editRevision"] = r.editRevision.map { .number(Double($0)) } ?? .null
        } else { value["movie"] = .null }
        value["next"] = .string(r.problems.isEmpty
            ? (r.movie == nil ? "No problems. Run direction_graphic without check to render it, then place it with direction_edit placeGraphic." : "No problems. Look at the stills, then place it with direction_edit placeGraphic (graphic: \"\(g.name)\").")
            : "Fix every problem, run direction_graphic again and look at the stills before placing it.")
        return .object(value)
    }
}
