import Foundation
import CryptoKit
import DirectionCore

/// The graphics runtime, bundled libraries, Archivo and the examples (Graphics/Web in this target).
/// Found by hand rather than through `Bundle.module`, whose lookup misses the copy beside the
/// command-line helper in `Direction.app/Contents/Helpers` and would crash it.
public enum GraphicResources {
    public static let libraries = ["anime", "d3", "three", "lottie"]

    /// `Graphics/Web` inside the target's resource bundle.
    public static let web: URL? = {
        let name = "Direction_DirectionMedia.bundle"
        let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")).resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle.main.resourceURL,                                      // Direction.app/Contents/Resources
            executable.deletingLastPathComponent().appendingPathComponent("Resources"), // Contents/Helpers/direction
            executable,                                                    // swift build: beside the products
            Bundle(for: Marker.self).bundleURL.deletingLastPathComponent(), // test bundles
            Bundle.main.bundleURL,
        ]
        for base in candidates.compactMap({ $0 }) {
            let web = base.appendingPathComponent(name).appendingPathComponent("Web")
            if FileManager.default.fileExists(atPath: web.appendingPathComponent("runtime.js").path) { return web }
            let nested = base.appendingPathComponent(name).appendingPathComponent("Contents/Resources/Web")
            if FileManager.default.fileExists(atPath: nested.appendingPathComponent("runtime.js").path) { return nested }
        }
        return nil
    }()
    private final class Marker {}

    static func required() throws -> URL {
        guard let web else { throw DirectionError("graphics_unavailable", "Direction's graphics runtime is missing from this build. Reinstall Direction.") }
        return web
    }

    public static func runtimeSource() throws -> String { try String(contentsOf: required().appendingPathComponent("runtime.js"), encoding: .utf8) }

    /// Changes whenever the runtime or a library changes, so cached renders are made again.
    static let version: String = {
        guard let web else { return "missing" }
        var hash = SHA256()
        for path in ["runtime.js"] + libraries.map({ "lib/\($0).js" }) + ["lib/three.module.js"] {
            if let data = try? Data(contentsOf: web.appendingPathComponent(path)) { hash.update(data: data) }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }()

    // MARK: Examples (graphics.md › Examples shipped with the app)

    public struct Example: Codable, Sendable {
        public var name: String
        public var title: String
        public var summary: String
        public var libraries: [String]?
    }

    public static func examples() throws -> [Example] {
        try JSONDecoder().decode([Example].self, from: Data(contentsOf: required().appendingPathComponent("examples/examples.json")))
    }

    /// One example by name or title ("title-card", "Title card").
    public static func example(_ query: String) throws -> (Example, URL) {
        let all = try examples(), key = query.lowercased().replacingOccurrences(of: " ", with: "-")
        guard let e = all.first(where: { $0.name == key || $0.title.lowercased() == query.lowercased() }) else {
            throw DirectionError("example_not_found", "There's no example called \(query). Examples: \(all.map(\.name).joined(separator: ", ")).")
        }
        return (e, try required().appendingPathComponent("examples/\(e.name)", isDirectory: true))
    }

    /// Every file in a folder, relative paths sorted, skipping hidden files.
    static func files(in folder: URL) throws -> [String] {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { continue }
            out.append(String(path.dropFirst(base.count + 1)))
        }
        return out.sorted()
    }
}
