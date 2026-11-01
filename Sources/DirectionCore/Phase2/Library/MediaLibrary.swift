import Foundation
import UniformTypeIdentifiers

// Sounds and images the director keeps (library.md): music beds, stings and sound effects; logos, stills and
// overlays. Each is a folder beside Styles and Techniques, so they're there without a film and for every
// film. The files stay as the director brought them; what Direction measured and what the director wrote
// about each is kept in the folder's .library.json. The Library window shows them, "@" names them in a note
// or the brief, and a film that uses one keeps its own copy in <film>/Library. None of it is footage.

public struct ShelfItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case music, effect, image
        public var label: String { switch self { case .music: "Music"; case .effect: "Sound effect"; case .image: "Image" } }
    }
    /// Its file in the folder, which is also its id; its name is the file's, without the extension.
    public var file: String
    public var kind: Kind
    /// What the director wrote about it: when to use it.
    public var note: String?
    /// Where it's from: a music library and its license, a link, the film it was made in.
    public var source: String?
    public var measured: Measured?
    /// The file as it was when it was measured: a file changed in the Finder is measured again.
    public var fileSize: Int64
    public var modifiedAt: Double
    public var addedAt: Double

    public init(file: String, kind: Kind, note: String? = nil, source: String? = nil, addedAt: Double = Date().timeIntervalSince1970) {
        self.file = file; self.kind = kind; self.note = note; self.source = source; fileSize = 0; modifiedAt = 0; self.addedAt = addedAt
    }
    public var id: String { file }
    public var name: String { (file as NSString).deletingPathExtension }
    public var isSound: Bool { kind != .image }

    public struct Measured: Codable, Hashable, Sendable {
        public var seconds: Double?
        /// Music: beats a minute, its key, integrated loudness (LUFS), the instruments heard most, and whether a voice sings.
        public var tempo: Double?
        public var key: String?
        public var loudness: Double?
        public var instruments: [String]?
        public var vocals: Bool?
        /// A sound effect: what it sounds like ("whoosh").
        public var sounds: [String]?
        /// Its level over its length, 0–1, for the waveform the Library draws.
        public var levels: [Float]?
        /// An image: its size in pixels, whether any of it is see-through, and the words in it.
        public var width: Int?
        public var height: Int?
        public var transparent: Bool?
        public var words: String?
        public init() {}
    }

    /// One line, as the Library shows it and the editor reads it: "Music · 2:14 · 92 BPM · D minor · piano, strings · no vocals".
    public var summary: String {
        guard let m = measured else { return kind == .image ? kind.label : "\(kind.label), not listened to yet" }
        var parts = [kind.label]
        if kind == .image {
            if let w = m.width, let h = m.height { parts.append("\(w) \u{00D7} \(h)" + (m.transparent == true ? " with transparency" : "")) }
            if let words = m.words, !words.isEmpty { parts.append("reads \u{201C}\(words)\u{201D}") }
        } else {
            if let s = m.seconds { parts.append(s < 10 ? String(format: "%.1f s", s) : String(format: "%d:%02d", Int(s.rounded()) / 60, Int(s.rounded()) % 60)) }
            if kind == .music {
                if let t = m.tempo { parts.append("\(Int(t.rounded())) BPM") }
                if let k = m.key { parts.append(k) }
                if let i = m.instruments, !i.isEmpty { parts.append(i.joined(separator: ", ")) }
                if let v = m.vocals { parts.append(v ? "vocals" : "no vocals") }
            } else if let s = m.sounds, !s.isEmpty { parts.append(s.joined(separator: ", ")) }
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// One shelf of the library: Sounds or Images, a folder of the director's files.
public struct MediaLibrary: Sendable, Equatable {
    public enum Shelf: String, Sendable, CaseIterable { case sounds, images }
    public var shelf: Shelf
    public var folder: URL
    public init(_ shelf: Shelf, folder: URL) { self.shelf = shelf; self.folder = folder }

    public static var sounds: MediaLibrary { .init(.sounds, folder: SharedSettings.soundsFolder) }
    public static var images: MediaLibrary { .init(.images, folder: SharedSettings.imagesFolder) }
    public static var shelves: [MediaLibrary] { [sounds, images] }

    static let indexFile = ".library.json"
    /// The folders are written from the app, and read by the editor's own process.
    private static let lock = NSLock()

    /// Which shelf takes a file: sound for Sounds, pictures for Images; nil for anything else.
    public static func shelf(for url: URL) -> Shelf? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .audio) { return .sounds }
        if type.conforms(to: .image), !type.conforms(to: .pdf) { return .images }
        return nil
    }

    /// The shelf a file is on, when it's inside one of the library's folders.
    public static func holding(_ url: URL) -> MediaLibrary? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return shelves.first { path.hasPrefix($0.folder.standardizedFileURL.resolvingSymlinksInPath().path + "/") }
    }

    public func url(_ item: ShelfItem) -> URL { folder.appendingPathComponent(item.file) }

    /// Every file on the shelf, by name, with what's known about it. A file put in the folder in the Finder is
    /// on it too: a sound is music until it's been listened to.
    public func items() -> [ShelfItem] {
        let index = Self.lock.withLock { readIndex() }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && Self.shelf(for: folder.appendingPathComponent($0)) == shelf }
            .map { index[$0] ?? ShelfItem(file: $0, kind: shelf == .images ? .image : .music, addedAt: 0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// An item by its name or file, in any case.
    public func find(_ name: String) -> ShelfItem? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        return items().first { $0.name.lowercased() == n || $0.file.lowercased() == n }
    }

    /// An item on either shelf, by name.
    public static func find(_ name: String) -> (MediaLibrary, ShelfItem)? {
        for library in shelves { if let item = library.find(name) { return (library, item) } }
        return nil
    }

    /// True when the file has changed since it was measured, or never was.
    public func needsMeasuring(_ item: ShelfItem) -> Bool {
        guard item.measured != nil, let values = try? url(item).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return true }
        return Int64(values.fileSize ?? -1) != item.fileSize || abs((values.contentModificationDate?.timeIntervalSince1970 ?? 0) - item.modifiedAt) > 0.01
    }

    /// Copies a file onto the shelf under its own name, or "Name 2" when that's taken; the original stays where
    /// it was. The same file again is the one already there.
    @discardableResult
    public func add(_ url: URL, kind: ShelfItem.Kind? = nil, source: String? = nil, note: String? = nil) throws -> ShelfItem {
        guard Self.shelf(for: url) == shelf else {
            throw DirectionError("not_for_library", shelf == .sounds ? "\(url.lastPathComponent) isn\u{2019}t a sound." : "\(url.lastPathComponent) isn\u{2019}t an image.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 1, target = folder.appendingPathComponent(url.lastPathComponent)
        while fm.fileExists(atPath: target.path) {
            if fm.contentsEqual(atPath: target.path, andPath: url.path), let had = items().first(where: { $0.file == target.lastPathComponent }) { return had }
            n += 1; target = folder.appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
        }
        let temp = folder.appendingPathComponent(".\(UUID().uuidString).adding")
        do { try fm.copyItem(at: url, to: temp); try fm.moveItem(at: temp, to: target) } catch { try? fm.removeItem(at: temp); throw error }
        let item = ShelfItem(file: target.lastPathComponent, kind: kind ?? (shelf == .images ? .image : .music), note: note, source: source)
        try save(item)
        return item
    }

    /// Writes what's known about an item: its kind, the director's words, what was measured.
    public func save(_ item: ShelfItem) throws {
        try Self.lock.withLock {
            var index = readIndex(); index[item.file] = item
            try writeIndex(index)
        }
    }

    /// Changes one item as it is now on the shelf.
    @discardableResult
    public func update(_ file: String, _ change: (inout ShelfItem) -> Void) throws -> ShelfItem {
        guard var item = items().first(where: { $0.file == file }) else { throw DirectionError("library_item_not_found", "\(file) isn\u{2019}t in the library.") }
        change(&item)
        try save(item)
        return item
    }

    /// Gives an item a new name: its file is renamed, keeping its extension.
    @discardableResult
    public func rename(_ item: ShelfItem, to name: String) throws -> ShelfItem {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/"), !clean.contains(":"), !clean.hasPrefix(".") else { throw DirectionError("bad_name", "Give it a name without a slash or a colon.") }
        let ext = (item.file as NSString).pathExtension, file = ext.isEmpty ? clean : "\(clean).\(ext)"
        guard file != item.file else { return item }
        guard !items().contains(where: { $0.file != item.file && $0.name.lowercased() == clean.lowercased() }) else { throw DirectionError("name_taken", "Something in the library is already called \(clean).") }
        try FileManager.default.moveItem(at: url(item), to: folder.appendingPathComponent(file))
        var renamed = item; renamed.file = file
        try Self.lock.withLock {
            var index = readIndex(); index[item.file] = nil; index[file] = renamed
            try writeIndex(index)
        }
        return renamed
    }

    /// Takes an item off the shelf: its file goes to the Trash. Films that used it keep their copies.
    public func remove(_ item: ShelfItem, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        try trash(url(item))
        try Self.lock.withLock {
            var index = readIndex(); index[item.file] = nil
            try writeIndex(index)
        }
    }

    private func readIndex() -> [String: ShelfItem] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.indexFile)) else { return [:] }
        return (try? JSONDecoder().decode([String: ShelfItem].self, from: data)) ?? [:]
    }
    private func writeIndex(_ index: [String: ShelfItem]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: folder.appendingPathComponent(Self.indexFile), options: .atomic)
    }
}

extension SharedSettings {
    public static let soundsFolderKey = "soundsFolder", imagesFolderKey = "imagesFolder"
    /// The Sounds folder. DIRECTION_SOUNDS_PATH overrides it for a process; a test process without it gets a folder of its own.
    public static var soundsFolder: URL { libraryFolder("DIRECTION_SOUNDS_PATH", key: soundsFolderKey, name: "Sounds") }
    /// The Images folder. DIRECTION_IMAGES_PATH overrides it for a process; a test process without it gets a folder of its own.
    public static var imagesFolder: URL { libraryFolder("DIRECTION_IMAGES_PATH", key: imagesFolderKey, name: "Images") }

    private static func libraryFolder(_ variable: String, key: String, name: String) -> URL {
        if let env = ProcessInfo.processInfo.environment[variable], !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        if DirectionPaths.isTesting { return FileManager.default.temporaryDirectory.appendingPathComponent("DirectionTest\(name)", isDirectory: true) }
        let path = defaults.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Direction/\(name)").path
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }
}
