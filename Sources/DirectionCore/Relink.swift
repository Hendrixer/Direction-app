import Foundation
import GRDB

// Footage is linked unless Settings › Storage asks for copies, so a take can go missing when a drive is unplugged.
// Relinking points a take at its file's new location. It goes through `update`, so it is
// one revision in history and the lock rules see it like any other change.

/// A missing take found again: where its file is now and what that file looks like.
public struct AssetRelink: Codable, Hashable, Sendable {
    public var assetID: String
    public var path: String
    public var fileSize: Int64
    public var modifiedAt: Double
    /// The candidate's measured length. It must match the take within one frame.
    public var duration: MediaTime
    public var bookmark: Data?
    public init(assetID: String, path: String, fileSize: Int64, modifiedAt: Double, duration: MediaTime, bookmark: Data? = nil) {
        self.assetID = assetID; self.path = path; self.fileSize = fileSize; self.modifiedAt = modifiedAt; self.duration = duration; self.bookmark = bookmark
    }
}

/// How a missing take is recognised in a folder: file name first, then length within one frame.
public enum FootageMatch {
    /// One frame at the take's own rate; 24 fps when the source doesn't say.
    public static func frameTolerance(_ asset: MediaAsset) -> Double {
        let rate = asset.video.first?.frameRate ?? 0
        return 1 / (rate.isFinite && rate >= 1 ? rate : 24)
    }

    public static func durationMatches(_ asset: MediaAsset, _ duration: MediaTime) -> Bool {
        guard duration.isValid else { return false }
        return asset.isImage || abs(duration.seconds - asset.duration.seconds) <= frameTolerance(asset) + 1e-6
    }

    /// Files whose name matches each missing take's original file name, ignoring case. Keyed by asset ID.
    public static func candidates(for assets: [MediaAsset], in files: [URL]) -> [String: [URL]] {
        let byName = Dictionary(grouping: files) { $0.lastPathComponent.lowercased() }
        var out: [String: [URL]] = [:]
        for asset in assets {
            let name = URL(fileURLWithPath: asset.path).lastPathComponent.lowercased()
            if let found = byName[name], !found.isEmpty { out[asset.id] = found.sorted { $0.path < $1.path } }
        }
        return out
    }

    /// The take's original file is reachable at its path or through its bookmark.
    public static func isReachable(_ asset: MediaAsset, fileManager: FileManager = .default) -> Bool {
        if fileManager.fileExists(atPath: asset.path) { return true }
        guard let bookmark = asset.bookmark else { return false }
        for options: URL.BookmarkResolutionOptions in [[.withSecurityScope, .withoutUI, .withoutMounting], [.withoutUI, .withoutMounting]] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale), fileManager.fileExists(atPath: url.path) { return true }
        }
        return false
    }
}

extension ProjectStore {
    /// Footage whose original file can't be reached right now.
    public func missingAssets(fileManager: FileManager = .default) throws -> [MediaAsset] {
        try read().assets.filter { !FootageMatch.isReachable($0, fileManager: fileManager) }
    }

    /// An older revision with each take where the latest one has it, so a take relinked once plays and
    /// delivers from its new place in every saved cut.
    static func withCurrentLocations(_ db: Database, _ project: Project) throws -> Project {
        struct Assets: Decodable { var assets: [MediaAsset] }
        guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM state WHERE id = 1") else { return project }
        let now = Dictionary(try JSONDecoder().decode(Assets.self, from: data).assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var p = project
        for i in p.assets.indices {
            guard let a = now[p.assets[i].id], a.path != p.assets[i].path || a.bookmark != p.assets[i].bookmark else { continue }
            p.assets[i].path = a.path; p.assets[i].name = a.name; p.assets[i].fileSize = a.fileSize
            p.assets[i].modifiedAt = a.modifiedAt; p.assets[i].bookmark = a.bookmark
        }
        return p
    }

    /// Points missing takes at their files' new locations. Every candidate must match its take's
    /// length within one frame. Notes, circles and cuts refer to takes by ID, so nothing else changes.
    @discardableResult
    public func relink(_ links: [AssetRelink], key: String = UUID().uuidString) throws -> Project {
        guard !links.isEmpty else { throw DirectionError("nothing_to_relink", "Choose at least one take to relink.") }
        guard Set(links.map(\.assetID)).count == links.count, Set(links.map(\.path)).count == links.count else { throw DirectionError("invalid_relink", "Each take relinks to one file, and each file to one take.") }
        let current = try read()
        let request = try JSONEncoder.direction.encode(links.sorted { $0.assetID < $1.assetID })
        let summary = links.count == 1 ? "Relinked \(current.assets.first { $0.id == links[0].assetID }?.name ?? "a take")" : "Relinked \(links.count) takes"
        return try update(expectedRevision: current.editRevision, key: key, request: request, summary: summary) { p in
            for link in links {
                guard let i = p.assets.firstIndex(where: { $0.id == link.assetID }) else { throw DirectionError("asset_not_found", "Take \(link.assetID) isn't footage in this film.") }
                let path = URL(fileURLWithPath: link.path).standardizedFileURL.path
                guard !path.isEmpty, link.fileSize >= 0, link.modifiedAt.isFinite else { throw DirectionError("invalid_relink", "The new file's details aren't valid.") }
                guard FootageMatch.durationMatches(p.assets[i], link.duration) else {
                    throw DirectionError("relink_length_mismatch", "\(URL(fileURLWithPath: path).lastPathComponent) is \(String(format: "%.2f", link.duration.seconds)) s; \(p.assets[i].name) was \(String(format: "%.2f", p.assets[i].duration.seconds)) s. Only a file of the same length can replace a take.")
                }
                guard !p.assets.contains(where: { $0.id != link.assetID && $0.path == path }) else { throw DirectionError("already_imported", "\(URL(fileURLWithPath: path).lastPathComponent) is already another take in this film.") }
                p.assets[i].path = path
                p.assets[i].name = URL(fileURLWithPath: path).lastPathComponent
                p.assets[i].fileSize = link.fileSize
                p.assets[i].modifiedAt = link.modifiedAt
                p.assets[i].bookmark = link.bookmark
            }
        }
    }
}
