import Foundation
import DirectionCore
import DirectionMedia

// The director's sounds and images (library.md): what's on the shelves, and bringing one into this film as its
// own copy in <film>/Library, never footage.
extension ToolCatalog {
    static var libraryDefinitions: [ToolDefinition] { [
        definition("direction_library", "List the director's sounds and images, kept outside any film (the Sounds and Images folders, beside Styles): music beds, stings and sound effects, logos and stills. Each has its name, kind (music, effect or image), summary of what Direction measured (length, tempo, key, instruments, voice; size, transparency, words), the director's note on when to use it and where it's from. Music has its grid: tempo, beats in a bar, where every bar starts (bar 1 first) and the bars where the song moves on (beats: true adds every beat), the same grid for every part of a song; steady false is music with no steady beat to cut on. Times in edits can be the song's bars once it's placed ({bar: 9}, {bar: 9, beat: 3}, {beat: 33}), and placeMusic's fit makes a song a given length by joining its bars. A song kept in parts (stems such as Drums, Bass, Instruments, Melody, and maybe its Full mix) is one item with its parts; a note names the song (\"@Neon Drive\") or one part (\"@Neon Drive Drums\"). kind or query (words in any of that) narrows the list. A note or the brief names one with \"@Name\". To use one, bring it in with direction_import's library and the name (the film keeps its own copy, and it isn't footage; a song brings every part), then place it: placeMusic for music (parts picks a song's parts, which play in time together), overwrite onto A3 for an effect, cutaway and reframe for an image.", ["kind": string, "query": string, "beats": bool]),
    ] }
}

extension ToolRuntime {
    func invokeLibrary(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_library":
            let kind = a["kind"].string.flatMap(ShelfItem.Kind.init(rawValue:))
            let words = (a["query"].string ?? "").lowercased().split(separator: " "), everyBeat = a["beats"].bool ?? false
            // What was measured, with the grid as the editor reads it and without the listening's own version.
            func measured(_ m: ShelfItem.Measured?) throws -> JSONValue {
                guard let m, case .object(var o) = try JSONValue.wrapping(m) else { return .null }
                o["version"] = nil
                if let g = m.grid { o["grid"] = g.compact(beats: everyBeat) }
                return .object(o)
            }
            var items: [JSONValue] = []
            func matches(_ text: [String?]) -> Bool { let t = text.compactMap { $0 }.joined(separator: " ").lowercased(); return words.allSatisfy { t.contains($0) } }
            for song in MediaLibrary.sounds.songs() where (kind == nil || kind == .music) && matches([song.name, song.summary, song.note, song.source] + song.parts.map(\.part)) {
                let parts: [JSONValue] = song.parts.map { p in .object(["part": .string(p.part ?? ""), "name": .string(Song.name(song.name, part: p.part ?? "")), "file": .string(p.file), "summary": .string(p.summary)]) }
                items.append(.object(["name": .string(song.name), "kind": .string("music"), "summary": .string(song.summary), "parts": .array(parts),
                                      "note": song.note.map(JSONValue.string) ?? .null, "source": song.source.map(JSONValue.string) ?? .null,
                                      "measured": try measured(song.lead.measured), "path": .string(MediaLibrary.sounds.url(song.lead).path)]))
            }
            for library in MediaLibrary.shelves {
                for i in library.items() where !i.isPart && (kind == nil || i.kind == kind) {
                    let text = [i.name, i.summary, i.note ?? "", i.source ?? ""].joined(separator: " ").lowercased()
                    guard words.allSatisfy({ text.contains($0) }) else { continue }
                    items.append(.object(["name": .string(i.name), "kind": .string(i.kind.rawValue), "summary": .string(i.summary),
                                          "note": i.note.map(JSONValue.string) ?? .null, "source": i.source.map(JSONValue.string) ?? .null,
                                          "measured": try measured(i.measured), "path": .string(library.url(i).path)]))
                }
            }
            return ToolResponse(.object(["items": .array(items), "sounds": .string(MediaLibrary.sounds.folder.path), "images": .string(MediaLibrary.images.folder.path)]))
        default: return nil
        }
    }

    /// A library sound or image comes into the film as the film's own copy, so the film plays and delivers
    /// whatever happens to the library. Asked for again, it's the copy already in.
    func importFromLibrary(_ name: String, _ a: JSONValue) async throws -> ToolResponse {
        if let (song, part) = MediaLibrary.findSong(name) { return try await importSong(song, asking: part, a) }
        guard let (library, item) = MediaLibrary.find(name) else { throw DirectionError("library_item_not_found", "There\u{2019}s no \(name) in the library. direction_library lists what\u{2019}s there.") }
        let fm = FileManager.default, p = try store.read()
        if let had = p.assets.first(where: { $0.fromLibrary == item.file && fm.fileExists(atPath: $0.path) }) {
            return ToolResponse(.object(["asset": try .wrapping(had), "editRevision": .number(Double(p.editRevision)), "alreadyIn": .bool(true)]))
        }
        let (asset, copied) = try await copy(item, from: library, into: p)
        do {
            let output = try store.addAsset(asset, append: false, expectedRevision: a["baseEditRevision"].int ?? p.editRevision, key: a["idempotencyKey"].string ?? UUID().uuidString)
            let saved = output.assets.first { $0.path == asset.path } ?? asset
            return ToolResponse(.object(["asset": try .wrapping(saved), "editRevision": .number(Double(output.editRevision))]))
        } catch {
            if copied { try? fm.removeItem(at: URL(fileURLWithPath: asset.path)) }
            throw error
        }
    }

    /// A song kept in parts comes in whole, in one revision: every part the film's own copy, each knowing its
    /// song and part, so they can play in time together. Parts already in are marked as the song's.
    func importSong(_ song: Song, asking: ShelfItem?, _ a: JSONValue) async throws -> ToolResponse {
        let fm = FileManager.default, p = try store.read(), library = MediaLibrary.sounds
        var new: [MediaAsset] = [], copies: [URL] = [], had: [String: String] = [:]
        for part in song.parts {
            if let old = p.assets.first(where: { $0.fromLibrary == part.file && fm.fileExists(atPath: $0.path) }) { had[old.id] = part.part; continue }
            var (asset, copied) = try await copy(part, from: library, into: p, avoiding: new.map(\.path))
            asset.song = song.name; asset.part = part.part; asset.name = Song.name(song.name, part: part.part ?? "")
            new.append(asset); if copied { copies.append(URL(fileURLWithPath: asset.path)) }
        }
        let current = p.assets.contains { had[$0.id] != nil && ($0.song != song.name || $0.part != had[$0.id]) }
        do {
            let output = new.isEmpty && !current ? p : try store.update(expectedRevision: a["baseEditRevision"].int ?? p.editRevision, key: a["idempotencyKey"].string ?? UUID().uuidString,
                request: try JSONValue.object(["operation": .string("import"), "library": .string(song.name)]).data(), summary: "Imported \(song.name)") { [new, had, name = song.name] p in
                for i in p.assets.indices where had[p.assets[i].id] != nil { p.assets[i].song = name; p.assets[i].part = had[p.assets[i].id] }
                for asset in new where !p.assets.contains(where: { $0.path == asset.path }) { p.assets.append(asset) }
            }
            let parts = output.assets.filter { $0.song == song.name && $0.fromLibrary.map { f in song.parts.contains { $0.file == f } } == true }
            let asked = parts.first { $0.fromLibrary == (asking ?? song.lead).file } ?? parts.first
            var out: [String: JSONValue] = ["song": .string(song.name), "editRevision": .number(Double(output.editRevision)),
                                            "parts": .array(parts.map { .object(["part": .string($0.part ?? ""), "assetID": .string($0.id)]) })]
            if let asked { out["asset"] = try .wrapping(asked) }
            if new.isEmpty { out["alreadyIn"] = .bool(true) }
            return ToolResponse(.object(out))
        } catch {
            for c in copies { try? fm.removeItem(at: c) }
            throw error
        }
    }

    /// A shelf's file copied into the film's Library folder, measured as an asset: an identical copy already
    /// there that nothing uses is taken as it is. Says whether it copied, so a failure can take it away again.
    func copy(_ item: ShelfItem, from library: MediaLibrary, into p: Project, avoiding: [String] = []) async throws -> (MediaAsset, copied: Bool) {
        let fm = FileManager.default
        let source = library.url(item), folder = store.url.appendingPathComponent("Library/\(library.shelf == .sounds ? "Sounds" : "Images")", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (item.file as NSString).deletingPathExtension, ext = (item.file as NSString).pathExtension
        var n = 1, copy = folder.appendingPathComponent(item.file)
        while fm.fileExists(atPath: copy.path), !(fm.contentsEqual(atPath: copy.path, andPath: source.path) && !p.assets.contains { $0.path == copy.path } && !avoiding.contains(copy.path)) {
            n += 1; copy = folder.appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
        }
        let copied = !fm.fileExists(atPath: copy.path)
        if copied { try fm.copyItem(at: source, to: copy) }
        do {
            var asset = try await MediaInspector.inspect(url: copy, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
            asset.name = item.file; asset.fromLibrary = item.file
            return (asset, copied)
        } catch {
            if copied { try? fm.removeItem(at: copy) }
            throw error
        }
    }
}
