import Foundation
import CryptoKit
import DirectionCore

/// Direction's own yt-dlp, for video links (styles.md › From a video, techniques.md › Learning one). Sites like
/// YouTube stop working with an older yt-dlp every few weeks, so Direction keeps its own: fetched from yt-dlp's
/// releases the first time a link is used, checked against the checksums published with that release, and
/// brought up to date at most once a day, before a download. Nobody installs anything. A yt-dlp already on the
/// Mac is the fallback when Direction can't get its own.
public actor VideoDownloader {
    public static let shared = VideoDownloader()

    /// yt-dlp's newest release; `latest/download/<name>` follows it.
    static let release = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/")!
    /// The standalone build for macOS: one file, Apple silicon and Intel.
    static let asset = "yt-dlp_macos"
    static let checkEvery: TimeInterval = 86_400

    private var updating: Task<Void, Error>?

    static var folder: URL { DirectionPaths.tools }
    /// Direction's copy.
    public static var tool: URL { folder.appendingPathComponent("yt-dlp") }
    /// Touched each time the copy is found current.
    static var checked: URL { folder.appendingPathComponent("yt-dlp.checked") }

    /// The yt-dlp to run, and whether it's Direction's own (current, so it takes the newest options).
    public func ready() async throws -> (tool: URL, own: Bool) {
        let fm = FileManager.default, have = fm.isExecutableFile(atPath: Self.tool.path)
        if have, let at = Self.lastChecked, Date().timeIntervalSince(at) < Self.checkEvery { return (Self.tool, true) }
        do {
            if updating == nil { updating = Task { try await Self.bringUpToDate() } }
            defer { updating = nil }
            try await updating!.value
            return (Self.tool, true)
        } catch {
            DirectionLog.warning("Couldn\u{2019}t bring yt-dlp up to date: \(error.localizedDescription)", "media")
            if have { return (Self.tool, true) }
            if let theirs = TutorialStudy.downloader() { return (theirs, false) }
            throw DirectionError("downloader_unavailable", "Direction couldn\u{2019}t get yt-dlp, the downloader it uses for video links: \(error.localizedDescription) Check the internet connection and try again, or drop the video file in instead.")
        }
    }

    static var lastChecked: Date? {
        (try? FileManager.default.attributesOfItem(atPath: checked.path))?[.modificationDate] as? Date
    }

    /// Compares Direction's copy with the newest release's checksum; downloads and checks the release when
    /// they differ. A release published between the two fetches makes them differ once, so it tries twice.
    static func bringUpToDate() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for _ in 0..<2 {
            guard let expected = checksum(for: asset, in: String(decoding: try await fetch(release.appendingPathComponent("SHA2-256SUMS")), as: UTF8.self)) else {
                throw DirectionError("downloader_unverified", "yt-dlp\u{2019}s release has no checksum for \(asset).")
            }
            if let current = try? Data(contentsOf: tool, options: .mappedIfSafe), sha256(current) == expected { touch(); return }
            let data = try await fetch(release.appendingPathComponent(asset))
            guard sha256(data) == expected else { continue }
            let incoming = folder.appendingPathComponent("yt-dlp.incoming")
            try data.write(to: incoming, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: incoming.path)
            if fm.fileExists(atPath: tool.path) { _ = try fm.replaceItemAt(tool, withItemAt: incoming) } else { try fm.moveItem(at: incoming, to: tool) }
            DirectionLog.info("Got yt-dlp from its newest release (\(data.count / 1_000_000) MB, checksum matched)", "media")
            touch(); return
        }
        throw DirectionError("downloader_unverified", "The download didn\u{2019}t match the checksum yt-dlp published.")
    }

    /// The hash for `name` in a SHA2-256SUMS file: lines of "<hash>  <name>".
    static func checksum(for name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name, parts[0].count == 64 else { continue }
            return parts[0].lowercased()
        }
        return nil
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func touch() {
        let fm = FileManager.default
        if fm.fileExists(atPath: checked.path) { try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: checked.path) }
        else { fm.createFile(atPath: checked.path, contents: Data()) }
    }

    static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Direction", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DirectionError("downloader_unavailable", "GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0) for \(url.lastPathComponent).")
        }
        return data
    }
}
