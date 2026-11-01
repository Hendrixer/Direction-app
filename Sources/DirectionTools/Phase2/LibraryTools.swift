import Foundation
import DirectionCore
import DirectionMedia

// The director's sounds and images (library.md): what's on the shelves, and bringing one into this film as its
// own copy in <film>/Library, never footage.
extension ToolCatalog {
    static var libraryDefinitions: [ToolDefinition] { [
        definition("direction_library", "List the director's sounds and images, kept outside any film (the Sounds and Images folders, beside Styles): music beds, stings and sound effects, logos and stills. Each has its name, kind (music, effect or image), summary of what Direction measured (length, tempo, key, instruments, voice; size, transparency, words), the director's note on when to use it and where it's from. kind or query (words in any of that) narrows the list. A note or the brief names one with \"@Name\". To use one, bring it in with direction_import's library and the name (the film keeps its own copy, and it isn't footage), then place it: placeMusic for music, overwrite onto A3 for an effect, cutaway and reframe for an image.", ["kind": string, "query": string]),
    ] }
}

extension ToolRuntime {
    func invokeLibrary(_ name: String, _ a: JSONValue) async throws -> ToolResponse? {
        switch name {
        case "direction_library":
            let kind = a["kind"].string.flatMap(ShelfItem.Kind.init(rawValue:))
            let words = (a["query"].string ?? "").lowercased().split(separator: " ")
            var items: [JSONValue] = []
            for library in MediaLibrary.shelves {
                for i in library.items() where kind == nil || i.kind == kind {
                    let text = [i.name, i.summary, i.note ?? "", i.source ?? ""].joined(separator: " ").lowercased()
                    guard words.allSatisfy({ text.contains($0) }) else { continue }
                    items.append(.object(["name": .string(i.name), "kind": .string(i.kind.rawValue), "summary": .string(i.summary),
                                          "note": i.note.map(JSONValue.string) ?? .null, "source": i.source.map(JSONValue.string) ?? .null,
                                          "measured": try i.measured.map { try JSONValue.wrapping($0) } ?? .null, "path": .string(library.url(i).path)]))
                }
            }
            return ToolResponse(.object(["items": .array(items), "sounds": .string(MediaLibrary.sounds.folder.path), "images": .string(MediaLibrary.images.folder.path)]))
        default: return nil
        }
    }

    /// A library sound or image comes into the film as the film's own copy, so the film plays and delivers
    /// whatever happens to the library. Asked for again, it's the copy already in.
    func importFromLibrary(_ name: String, _ a: JSONValue) async throws -> ToolResponse {
        guard let (library, item) = MediaLibrary.find(name) else { throw DirectionError("library_item_not_found", "There\u{2019}s no \(name) in the library. direction_library lists what\u{2019}s there.") }
        let fm = FileManager.default, p = try store.read()
        if let had = p.assets.first(where: { $0.fromLibrary == item.file && fm.fileExists(atPath: $0.path) }) {
            return ToolResponse(.object(["asset": try .wrapping(had), "editRevision": .number(Double(p.editRevision)), "alreadyIn": .bool(true)]))
        }
        let source = library.url(item), folder = store.url.appendingPathComponent("Library/\(library.shelf == .sounds ? "Sounds" : "Images")", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (item.file as NSString).deletingPathExtension, ext = (item.file as NSString).pathExtension
        var n = 1, copy = folder.appendingPathComponent(item.file)
        while fm.fileExists(atPath: copy.path), !(fm.contentsEqual(atPath: copy.path, andPath: source.path) && !p.assets.contains { $0.path == copy.path }) {
            n += 1; copy = folder.appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
        }
        if !fm.fileExists(atPath: copy.path) { try fm.copyItem(at: source, to: copy) }
        do {
            var asset = try await MediaInspector.inspect(url: copy, thumbnailDirectory: cacheDirectory.appendingPathComponent("Thumbnails"))
            asset.name = item.file; asset.fromLibrary = item.file
            let output = try store.addAsset(asset, append: false, expectedRevision: a["baseEditRevision"].int ?? p.editRevision, key: a["idempotencyKey"].string ?? UUID().uuidString)
            let saved = output.assets.first { $0.path == asset.path } ?? asset
            return ToolResponse(.object(["asset": try .wrapping(saved), "editRevision": .number(Double(output.editRevision))]))
        } catch {
            try? fm.removeItem(at: copy)
            throw error
        }
    }
}
