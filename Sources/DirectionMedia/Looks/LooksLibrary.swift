import Foundation
import CoreServices
import DirectionCore

/// One look the Look sheet can show as a tile.
public struct LookEntry: Sendable, Hashable, Identifiable, Codable {
    public var id: String { path }
    public var name: String
    /// The .cube file, or the editor's .json for a look with filters only.
    public var path: String
    public var group: String
    public var settings: LookSettings
    /// Why the LUT can't be used; the sheet shows "Can't read this LUT" and never applies it.
    public var problem: String?
    public init(name: String, path: String, group: String, settings: LookSettings, problem: String? = nil) {
        self.name = name; self.path = path; self.group = group; self.settings = settings; self.problem = problem
    }
}

public struct LookGroup: Sendable, Hashable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var looks: [LookEntry]
    public var byEditor: Bool { name == LooksLibrary.editorGroup }
    public init(name: String, looks: [LookEntry]) { self.name = name; self.looks = looks }
}

/// The looks Direction can offer: the editor's (the film's `Editor/Looks/`) and the director's Looks folder,
/// where each subfolder is a group and `Camera/` holds camera LUTs instead of looks.
public enum LooksLibrary {
    public static let editorGroup = "Made by the editor", folderGroup = "Your looks folder", cameraFolder = "Camera"

    public static func groups(folder: URL, film: URL?) -> [LookGroup] {
        let editor = film.map { editorLooks(in: $0.appendingPathComponent("Editor/Looks")) } ?? []
        return (editor.isEmpty ? [] : [LookGroup(name: editorGroup, looks: editor)]) + folderGroups(folder)
    }

    /// Loose .cube files first, as "Your looks folder", then one group per subfolder, in name order.
    public static func folderGroups(_ folder: URL) -> [LookGroup] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        var groups: [LookGroup] = []
        let loose = cubes(items, group: folderGroup)
        if !loose.isEmpty { groups.append(LookGroup(name: folderGroup, looks: loose)) }
        let folders = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.lastPathComponent != cameraFolder }
        for sub in folders.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let inside = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
            let looks = cubes(inside, group: sub.lastPathComponent)
            if !looks.isEmpty { groups.append(LookGroup(name: sub.lastPathComponent, looks: looks)) }
        }
        return groups
    }

    /// Oldest first, so a LUT dropped in lands at the end of its group.
    private static func cubes(_ urls: [URL], group: String) -> [LookEntry] {
        let created = { (u: URL) in (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        return urls.filter { $0.pathExtension.lowercased() == "cube" }
            .sorted { (created($0), $0.lastPathComponent) < (created($1), $1.lastPathComponent) }
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return LookEntry(name: name, path: url.path, group: group, settings: LookSettings(name: name, lut: url.path, by: "folder"), problem: LookPipeline.problem(url.path))
            }
    }

    /// The looks the editor made: each is `<slug>.json` (a LookSettings) with an optional `<slug>.cube`.
    public static func editorLooks(in folder: URL) -> [LookEntry] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        let created = { (u: URL) in (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        return items.filter { $0.pathExtension == "json" }.sorted { (created($0), $0.lastPathComponent) < (created($1), $1.lastPathComponent) }.compactMap { url in
            guard let data = try? Data(contentsOf: url), var look = try? JSONDecoder().decode(LookSettings.self, from: data) else { return nil }
            if let lut = look.lut, !lut.hasPrefix("/") { look.lut = folder.appendingPathComponent(lut).path }
            look.by = "editor"
            return LookEntry(name: look.name, path: look.lut ?? url.path, group: editorGroup, settings: look, problem: look.lut.flatMap(LookPipeline.problem))
        }
    }

    /// Saves a look the editor made into `Editor/Looks`, next to its LUT. The name picks the file name.
    public static func saveEditorLook(_ look: LookSettings, cube: CubeLUT?, in folder: URL) throws -> LookEntry {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = slug(look.name)
        var stem = base, n = 2
        // A new name never overwrites another look; the same name replaces the editor's earlier version.
        while let existing = try? Data(contentsOf: folder.appendingPathComponent(stem + ".json")),
              let other = try? JSONDecoder().decode(LookSettings.self, from: existing), other.name != look.name {
            stem = "\(base)-\(n)"; n += 1
        }
        var saved = look
        saved.by = "editor"
        let cubeURL = folder.appendingPathComponent(stem + ".cube")
        if let cube {
            try cube.text.write(to: cubeURL, atomically: true, encoding: .utf8)
            saved.lut = cubeURL.lastPathComponent
        } else {
            try? FileManager.default.removeItem(at: cubeURL)
            saved.lut = nil
        }
        try JSONEncoder.direction.encode(saved).write(to: folder.appendingPathComponent(stem + ".json"), options: .atomic)
        saved.lut = cube == nil ? nil : cubeURL.path
        return LookEntry(name: saved.name, path: saved.lut ?? folder.appendingPathComponent(stem + ".json").path, group: editorGroup, settings: saved, problem: saved.lut.flatMap(LookPipeline.problem))
    }

    static func slug(_ name: String) -> String {
        let s = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { out, c in if !(c == "-" && out.hasSuffix("-")) { out.append(c) } }
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "look" : String(trimmed.prefix(60))
    }
}

/// Watches folders (and everything under them) and calls back once a burst of changes settles.
/// FSEvents with a 0.4 s latency, so a LUT dropped into the Looks folder shows within 2 s.
public final class LooksWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable () -> Void

    public init(paths: [URL], onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<LooksWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.4, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "dev.direction.looks-watcher", qos: .utility))
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        self.stream = nil
    }
    deinit { stop() }
}
