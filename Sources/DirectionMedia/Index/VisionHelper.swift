import Foundation
import DirectionCore

/// mlx-vlm on this Mac: finding its Python and Direction's helper script, what's downloaded,
/// and fetching weights with progress (settings.md › 54, footage-index.md › Engines).
public enum VisionHelper {
    // MARK: Finding things

    /// The Python from `uv tool install mlx-vlm`, else any python3 that can import mlx_vlm.
    /// GUI apps don't get the shell's PATH, so look where uv, Homebrew and python.org put it.
    public static func python() -> URL? {
        if let cached = lock.withLock({ found }) { return cached.url }
        let home = NSHomeDirectory(), fm = FileManager.default
        var result: URL?
        let uv = URL(fileURLWithPath: "\(home)/.local/share/uv/tools/mlx-vlm/bin/python")
        if fm.isExecutableFile(atPath: uv.path) { result = uv }
        else {
            var dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/Library/Frameworks/Python.framework/Versions/Current/bin"]
            dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            dirs.append("/usr/bin")
            var seen = Set<String>()
            for dir in dirs where seen.insert(dir).inserted {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent("python3")
                if fm.isExecutableFile(atPath: candidate.path), canImport(candidate) { result = candidate; break }
            }
        }
        lock.withLock { found = .init(url: result) }
        return result
    }
    private struct Found { var url: URL? }
    nonisolated(unsafe) private static var found: Found?
    private static let lock = NSLock()
    /// Settings looks again after the director installs mlx-vlm.
    public static func forget() { lock.withLock { found = nil } }

    private static func canImport(_ python: URL) -> Bool {
        let p = Process(); p.executableURL = python; p.arguments = ["-I", "-c", "import mlx_vlm"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// `describe.py`, shipped in the app's resources (Resources/Vision). The CLI finds the app's
    /// resource bundle beside it in a build folder, or in Contents/Resources inside Direction.app.
    public static func script() -> URL? {
        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["DIRECTION_VISION_HELPER"], fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath().deletingLastPathComponent()
        var bases: [URL] = [Bundle.main.resourceURL, Bundle.main.bundleURL, exe, exe.deletingLastPathComponent().appendingPathComponent("Resources")].compactMap { $0 }
        bases += bases.map { $0.appendingPathComponent("Direction_DirectionApp.bundle") } + bases.map { $0.appendingPathComponent("Direction_DirectionApp.bundle/Contents/Resources") }
        for base in bases {
            for name in ["Vision/describe.py", "describe.py"] {
                let url = base.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) { return url }
            }
        }
        // A source checkout (tests and `swift run`).
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DirectionApp/Resources/Vision/describe.py")
        return fm.fileExists(atPath: source.path) ? source : nil
    }

    // MARK: Weights

    public static var hubCache: URL {
        let env = ProcessInfo.processInfo.environment
        if let hub = env["HF_HUB_CACHE"] { return URL(fileURLWithPath: hub) }
        if let home = env["HF_HOME"] { return URL(fileURLWithPath: home).appendingPathComponent("hub") }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/huggingface/hub")
    }
    static func repoFolder(_ repo: String) -> URL { hubCache.appendingPathComponent("models--" + repo.replacingOccurrences(of: "/", with: "--")) }

    /// True when a snapshot has its config and every weight file it names. Newer huggingface_hub
    /// keeps blobs in a shared store and links to them, so links are followed.
    public static func isDownloaded(_ repo: String) -> Bool {
        let fm = FileManager.default
        let snapshots = repoFolder(repo).appendingPathComponent("snapshots")
        for snap in (try? fm.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? [] {
            guard fm.fileExists(atPath: snap.appendingPathComponent("config.json").path) else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: snap.path)) ?? []
            if let index = try? Data(contentsOf: snap.appendingPathComponent("model.safetensors.index.json")),
               let map = (try? JSONSerialization.jsonObject(with: index) as? [String: Any])?["weight_map"] as? [String: String] {
                if Set(map.values).allSatisfy({ fm.fileExists(atPath: snap.appendingPathComponent($0).path) }) { return true }
            } else if files.contains(where: { $0.hasSuffix(".safetensors") && fm.fileExists(atPath: snap.appendingPathComponent($0).path) }) { return true }
        }
        return false
    }

    /// Bytes a repo's finished files hold, following links into the shared blob store.
    public static func downloadedBytes(_ repo: String) -> Int64 {
        let blobs = repoFolder(repo).appendingPathComponent("blobs")
        let items = (try? FileManager.default.contentsOfDirectory(at: blobs, includingPropertiesForKeys: nil)) ?? []
        return items.reduce(0) { $0 + size($1.resolvingSymlinksInPath()) }
    }
    private static func size(_ url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    /// Every real file in the cache's blob folders, partial ones included: growth while a download
    /// runs is its progress, whichever layout huggingface_hub uses.
    static func cacheBytes() -> Int64 {
        let fm = FileManager.default
        let repos = ((try? fm.contentsOfDirectory(at: hubCache, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("models--") }
        var total: Int64 = 0
        for root in [hubCache.appendingPathComponent("blobs")] + repos.map({ $0.appendingPathComponent("blobs") }) {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { continue }
            for case let url as URL in e where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true { total += size(url) }
        }
        return total
    }

    /// Free space where the Hugging Face cache lives.
    public static func freeBytes() -> Int64 {
        var url = hubCache
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" { url.deleteLastPathComponent() }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeNameKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
    public static func volumeName() -> String {
        var url = hubCache
        while !FileManager.default.fileExists(atPath: url.path) && url.path != "/" { url.deleteLastPathComponent() }
        return (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "this Mac"
    }
    /// A download doesn't start unless there's room for it plus 2 GB.
    public static func hasRoom(for detail: SharedSettings.LookDetail) -> Bool {
        freeBytes() >= detail.bytes - downloadedBytes(detail.repo) + 2_000_000_000
    }

    public enum Status: Equatable, Sendable {
        case noPython
        case notDownloaded
        case downloaded
        case needsMemory
    }
    public static func status(_ detail: SharedSettings.LookDetail) -> Status {
        guard python() != nil else { return .noPython }
        if ProcessInfo.processInfo.physicalMemory < detail.minimumMemory { return .needsMemory }
        return isDownloaded(detail.repo) ? .downloaded : .notDownloaded
    }

    /// Downloads a version's weights with the same Python, reporting 0…1. Cancelling stops it;
    /// what's fetched stays in the cache and the next download resumes.
    public static func download(_ detail: SharedSettings.LookDetail, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let python = python() else { throw DirectionError("mlx_vlm_missing", "mlx-vlm isn't installed. Install it in Terminal with uv tool install mlx-vlm.") }
        guard hasRoom(for: detail) else {
            throw DirectionError("disk_full", "Only \(ByteCountFormatter.string(fromByteCount: freeBytes(), countStyle: .file)) free on \(volumeName()). \(detail.label.split(separator: "\u{00B7}").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "This version") needs \(ByteCountFormatter.string(fromByteCount: detail.bytes, countStyle: .file)).")
        }
        let process = Process()
        process.executableURL = python
        process.arguments = ["-I", "-c", "import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1])", detail.repo]
        var env = ProcessInfo.processInfo.environment; env["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        process.environment = env
        let errors = Pipe(); process.standardError = errors; process.standardOutput = FileHandle.nullDevice
        let had = downloadedBytes(detail.repo), before = cacheBytes()
        let watcher = Task {
            while !Task.isCancelled {
                progress(min(0.99, Double(had + max(0, cacheBytes() - before)) / Double(max(1, detail.bytes))))
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { watcher.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in done.resume() }
                do { try process.run() } catch { process.terminationHandler = nil; done.resume(throwing: error) }
            }
        } onCancel: { process.terminate() }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.split(separator: "\n").last.map(String.init) ?? ""
            throw DirectionError("download_failed", "The download stopped. \(message)".trimmingCharacters(in: .whitespaces))
        }
        progress(1)
    }
}
