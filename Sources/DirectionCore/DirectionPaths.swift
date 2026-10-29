import Foundation

/// Where Direction keeps what it can always make again: decoded audio, contact sheets, frames,
/// thumbnails and sync curves, one folder per film id. Tests use a temporary folder, and
/// `DIRECTION_CACHE_DIR` moves it anywhere.
public enum DirectionPaths {
    public static var caches: URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["DIRECTION_CACHE_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir) }
        if isTesting { return FileManager.default.temporaryDirectory.appendingPathComponent("DirectionTestCaches") }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("dev.direction.editor")
    }
    public static func cache(forFilm projectID: String) -> URL { caches.appendingPathComponent(projectID) }

    /// A test process: XCTest or Swift Testing.
    public static var isTesting: Bool {
        let p = ProcessInfo.processInfo
        return p.environment["XCTestConfigurationFilePath"] != nil || p.processName == "xctest" || p.processName.hasSuffix("PackageTests") || p.processName.contains("swiftpm-testing-helper")
    }
}

/// Keeps the cache to the films that are here (system.md › Deleting a film).
public enum CacheCleanup {
    /// A film went to the Trash: its cache goes, and the library forgets it.
    public static func forget(film url: URL, projectID: String?, library: ProjectLibrary? = try? ProjectLibrary()) {
        if let projectID { try? FileManager.default.removeItem(at: DirectionPaths.cache(forFilm: projectID)) }
        try? library?.forget(path: url.resolvingSymlinksInPath().path)
        try? library?.forget(path: url.path)
    }

    /// At launch. Library entries for films that were trashed and are gone are forgotten. A film's
    /// cache goes when the film isn't in the library, or has been missing, and its cache hasn't been
    /// touched for `after` (a week): a film deleted in Finder, an old test. A missing film stays in
    /// the library so it can be found again; only its cache goes.
    @discardableResult
    public static func prune(trashed: Set<String>, library: ProjectLibrary? = try? ProjectLibrary(), after: TimeInterval = 7 * 86_400, now: Date = Date()) -> (folders: Int, bytes: Int64) {
        let entries = (try? library?.list()) ?? []
        for e in entries where !e.available && trashed.contains(e.path) { try? library?.forget(path: e.path) }
        let here = Set(entries.filter(\.available).compactMap(\.projectID))
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: DirectionPaths.caches, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return (0, 0) }
        var removed = 0, bytes: Int64 = 0
        for folder in folders where folder.lastPathComponent.hasPrefix("project-") && !here.contains(folder.lastPathComponent) {
            guard now.timeIntervalSince(lastTouched(folder)) > after else { continue }
            bytes += size(folder)
            if (try? fm.removeItem(at: folder)) != nil { removed += 1 }
        }
        return (removed, bytes)
    }

    /// Decoded audio (48 kHz, about 70 MB for three minutes of stereo) is only needed while takes are
    /// transcribed, listened to and synced; anything that needs it again decodes it again in seconds.
    @discardableResult
    public static func dropDecodedAudio(projectID: String) -> Int64 {
        let fm = FileManager.default, root = DirectionPaths.cache(forFilm: projectID)
        var bytes: Int64 = 0
        for dir in [root, root.appendingPathComponent("Audio")] {
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? [] where file.pathExtension == "caf" {
                let n = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                if (try? fm.removeItem(at: file)) != nil { bytes += n }
            }
        }
        return bytes
    }

    /// The newest change to the folder or anything one level in.
    static func lastTouched(_ folder: URL) -> Date {
        let fm = FileManager.default, key: URLResourceKey = .contentModificationDateKey
        var newest = (try? folder.resourceValues(forKeys: [key]))?.contentModificationDate ?? .distantPast
        for child in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])) ?? [] {
            if let d = (try? child.resourceValues(forKeys: [key]))?.contentModificationDate, d > newest { newest = d }
        }
        return newest
    }

    static func size(_ folder: URL) -> Int64 {
        let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let f = e?.nextObject() as? URL { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        return total
    }
}
