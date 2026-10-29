import Testing
import Foundation
@testable import DirectionCore

/// The cache keeps to the films that are here (system.md › Deleting a film).
struct CacheTests {
    @Test func testsNeverUseTheRealCache() {
        #expect(!DirectionPaths.caches.path.contains("/Library/Caches/"))
    }

    @Test func goneFilmsLoseTheirCacheAndTrashedOnesLeaveTheLibrary() throws {
        let fm = FileManager.default, dir = fm.temporaryDirectory.appendingPathComponent("direction-cache-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let library = try ProjectLibrary(url: dir.appendingPathComponent("library.sqlite"))
        // A film that's here, one deleted in Finder, and one trashed from Direction.
        let here = try ProjectStore.create(at: dir.appendingPathComponent("Here.direction"), name: "Here")
        let finder = try ProjectStore.create(at: dir.appendingPathComponent("Finder.direction"), name: "Finder")
        let trashed = try ProjectStore.create(at: dir.appendingPathComponent("Trashed.direction"), name: "Trashed")
        for s in [here, finder, trashed] { try library.register(s) }
        let ids = try [here, finder, trashed].map { try $0.read().id }
        try fm.removeItem(at: finder.url); try fm.removeItem(at: trashed.url)
        let orphan = "project-test-\(UUID().uuidString)", fresh = "project-test-\(UUID().uuidString)"
        let weekOld = Date().addingTimeInterval(-10 * 86_400)
        for id in ids + [orphan, fresh] {
            let folder = DirectionPaths.cache(forFilm: id)
            try fm.createDirectory(at: folder.appendingPathComponent("Thumbnails"), withIntermediateDirectories: true)
            guard id != fresh else { continue }
            for url in [folder.appendingPathComponent("Thumbnails"), folder] { try fm.setAttributes([.modificationDate: weekOld], ofItemAtPath: url.path) }
        }
        defer { for id in ids + [orphan, fresh] { try? fm.removeItem(at: DirectionPaths.cache(forFilm: id)) } }

        CacheCleanup.prune(trashed: [trashed.url.path], library: library)
        func cached(_ id: String) -> Bool { fm.fileExists(atPath: DirectionPaths.cache(forFilm: id).path) }
        #expect(cached(ids[0]) && cached(fresh))
        #expect(!cached(ids[1]) && !cached(ids[2]) && !cached(orphan))
        // The Finder-deleted film stays listed, so it can be found again; the trashed one is forgotten.
        let names = try library.list().map(\.name).sorted()
        #expect(names == ["Finder", "Here"])

        // Trashing from Direction: the cache and the entry go at once.
        CacheCleanup.forget(film: here.url, projectID: ids[0], library: library)
        let left = try library.list()
        #expect(!cached(ids[0]) && !left.contains { $0.name == "Here" })
        #expect(ProjectLibrary.projectID(at: dir.appendingPathComponent("Here.direction")) == ids[0])
    }

    @Test func decodedAudioGoesAndEverythingElseStays() throws {
        let fm = FileManager.default, id = "project-test-\(UUID().uuidString)", root = DirectionPaths.cache(forFilm: id)
        try fm.createDirectory(at: root.appendingPathComponent("Audio"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Sheets"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for path in ["a.caf", "Audio/b.caf", "Sheets/take.jpg"] { try Data(count: 1_000).write(to: root.appendingPathComponent(path)) }
        #expect(CacheCleanup.dropDecodedAudio(projectID: id) == 2_000)
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("a.caf").path) && !fm.fileExists(atPath: root.appendingPathComponent("Audio/b.caf").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("Sheets/take.jpg").path))
    }
}
