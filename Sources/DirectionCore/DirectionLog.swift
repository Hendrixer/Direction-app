import Foundation
import os

/// Direction's own log: what went wrong, and when, kept on this Mac so a problem can be looked at after
/// the fact (Help › Show Direction Log). The app and the `direction` helper the editor talks to both
/// write to it, each line marked with which. Lines go to Console too, under `dev.direction`.
/// Nothing secret goes in: anything shaped like an API key is masked before it's written.
public enum DirectionLog {
    public enum Level: String, Sendable { case info, warning, error }

    public static func info(_ message: String, _ category: String = "app") { write(.info, category, message) }
    public static func warning(_ message: String, _ category: String = "app") { write(.warning, category, message) }
    public static func error(_ message: String, _ category: String = "app") { write(.error, category, message) }

    /// `~/Library/Logs/Direction`. Tests write to a temporary folder instead, and `DIRECTION_LOG_DIR`
    /// moves it anywhere.
    public static var directory: URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["DIRECTION_LOG_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir) }
        if DirectionPaths.isTesting { return FileManager.default.temporaryDirectory.appendingPathComponent("DirectionTestLogs") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Direction")
    }
    public static var file: URL { directory.appendingPathComponent("Direction.log") }
    /// The log before the last one; the file rolls over at 5 MB.
    public static var previousFile: URL { directory.appendingPathComponent("Direction.1.log") }
    static let maxBytes = 5_000_000
    /// Lines older than this are dropped (`prune`), so the log holds at most 30 days and 10 MB.
    public static let keepDays = 30

    /// Drops lines older than `keepDays` from every log in the folder, and a log with nothing that
    /// recent goes. Direction does it when it opens and once a day while it's open. Every line
    /// starts with its time in UTC, so lines compare as text.
    public static func prune(in folder: URL = directory, now: Date = Date()) {
        let cutoff = stamp(now.addingTimeInterval(-Double(keepDays) * 86_400))
        let fm = FileManager.default
        let logs = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "log" }
        lock.lock(); defer { lock.unlock() }
        for url in logs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard let first = lines.firstIndex(where: { $0.prefix(cutoff.count) >= cutoff[...] }), !lines[first].isEmpty else {
                try? fm.removeItem(at: url); continue
            }
            guard first > 0 else { continue }
            try? lines[first...].joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func stamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    /// The last lines of the log, newest last.
    public static func tail(_ count: Int = 200) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(count).map(String.init))
    }

    /// Masks API keys and bearer tokens.
    public static func redact(_ text: String) -> String {
        var out = text
        for pattern in [#"sk-or-[A-Za-z0-9_\-]+"#, #"sk-[A-Za-z0-9_\-]{20,}"#, #"(?i)bearer\s+[A-Za-z0-9._\-]+"#] {
            out = out.replacingOccurrences(of: pattern, with: "•••", options: .regularExpression)
        }
        return out
    }

    // MARK: Writing

    private static let lock = NSLock()
    private static let loggers = OSAllocatedUnfairLock(initialState: [String: Logger]())


    /// "app" for Direction.app, the program's name for anything else (the `direction` helper).
    private static let process: String = {
        let name = Bundle.main.bundleIdentifier?.hasPrefix("dev.direction") == true && Bundle.main.bundlePath.hasSuffix(".app") ? "app" : ProcessInfo.processInfo.processName
        return "\(name)[\(getpid())]"
    }()

    /// Sees every line as it's written, keys already masked: crash reports keep them as what led up to a
    /// report, and send errors (CrashReporting). Set once at launch, only when reports are on.
    nonisolated(unsafe) public static var observer: (@Sendable (Level, String, String) -> Void)?

    static func write(_ level: Level, _ category: String, _ message: String) {
        let text = redact(message)
        observer?(level, category, text)
        let logger = loggers.withLock { cache in
            if let l = cache[category] { return l }
            let l = Logger(subsystem: "dev.direction", category: category); cache[category] = l; return l
        }
        switch level {
        case .info: logger.info("\(text, privacy: .public)")
        case .warning: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
        let line = "\(stamp(Date())) \(process) \(level.rawValue.uppercased()) [\(category)] \(text.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxBytes {
            try? fm.removeItem(at: previousFile)
            try? fm.moveItem(at: file, to: previousFile)
        }
        // O_APPEND: lines from the app and the helper never land on top of each other.
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = line.utf8CString.withUnsafeBufferPointer { buffer in Darwin.write(fd, buffer.baseAddress, buffer.count - 1) }
    }
}
