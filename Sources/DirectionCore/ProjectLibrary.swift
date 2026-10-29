import Foundation
import GRDB

public struct ProjectEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var path: String
    public var lastOpened: Double
    public var available: Bool
    /// The film's id, which names its cache folder.
    public var projectID: String?
}

/// A local index of explicitly opened projects, shared safely across app and agent processes.
/// It never scans the user's filesystem or selects an implicit editing target.
public final class ProjectLibrary: Sendable {
    private let database: DatabaseQueue
    public init(url: URL? = nil) throws {
        let location = url ?? Self.defaultURL
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration(); config.busyMode = .timeout(10)
        database = try DatabaseQueue(path: location.path, configuration: config)
        try database.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS projects (path TEXT PRIMARY KEY, project_id TEXT NOT NULL, name TEXT NOT NULL, last_opened DOUBLE NOT NULL)")
        }
    }
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["DIRECTION_LIBRARY_PATH"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Direction/projects.sqlite")
    }
    public func register(_ store: ProjectStore) throws {
        let project = try store.read(), path = store.url.resolvingSymlinksInPath().path
        try database.write { db in
            try db.execute(sql: "INSERT INTO projects (path, project_id, name, last_opened) VALUES (?, ?, ?, ?) ON CONFLICT(path) DO UPDATE SET project_id=excluded.project_id, name=excluded.name, last_opened=excluded.last_opened", arguments: [path, project.id, project.name, Date().timeIntervalSince1970])
        }
    }
    public func list() throws -> [ProjectEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM projects ORDER BY last_opened DESC LIMIT 100").map { row in
                let path: String = row["path"]
                return ProjectEntry(id: path, name: row["name"], path: path, lastOpened: row["last_opened"], available: FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("manifest.json").path), projectID: row["project_id"])
            }
        }
    }
    /// The film went to the Trash: it leaves the list. Opening it again puts it back.
    public func forget(path: String) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM projects WHERE path = ?", arguments: [path]) }
    }
    /// A film package's id, from its manifest, without opening its database.
    public static func projectID(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")) else { return nil }
        return (try? JSONDecoder().decode(JSONValue.self, from: data))?["projectID"].string
    }
}
