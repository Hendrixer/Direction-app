import Foundation

/// Crash and error reports (system.md › Crash reports): off until the person turns them on in Settings, or says
/// yes once after Direction closed unexpectedly. The app and the `direction` helper read the same switch. What a
/// report carries is scrubbed here first: the person's name and home folder never leave the Mac.
public enum CrashReporting {
    /// Where Direction's reports go (Sentry). It's public by design: it only lets a copy of Direction send, and the
    /// project's rate limits and monthly allowance cap what anyone can send with it.
    public static let dsn = "https://d4a905856fb3035b4f8a326c265d2a86@o4512383135645696.ingest.us.sentry.io/4512383143444480"

    public enum Key {
        public static let sends = "sendsCrashReports"
        /// The newest crash report macOS kept that Direction already asked about or sent, by its date.
        public static let handledThrough = "crashReportsHandledThrough"
    }
    public static var sends: Bool { SharedSettings.defaults.bool(forKey: Key.sends) }
    public static func setSends(_ on: Bool) { SharedSettings.defaults.set(on, forKey: Key.sends) }
    public static var handledThrough: Date? {
        get { SharedSettings.defaults.object(forKey: Key.handledThrough) as? Date }
        set { SharedSettings.defaults.set(newValue, forKey: Key.handledThrough) }
    }

    // MARK: Scrubbing

    /// The person out of anything a report carries: their home folder becomes "~", anyone's /Users/<name> becomes
    /// /Users/[you], and their short and full names "[you]". Keys are masked the way the log masks them.
    public static func scrub(_ text: String, home: String = NSHomeDirectory(), names: [String] = [NSUserName(), NSFullUserName()]) -> String {
        var out = DirectionLog.redact(text)
        if home.count > 1 { out = out.replacingOccurrences(of: home, with: "~") }
        out = out.replacingOccurrences(of: #"/Users/[^/\s"':]+"#, with: "/Users/[you]", options: .regularExpression)
        // Longest first, so a full name goes whole before its first name does. Only as a word of its own: "ann"
        // stays in "planning".
        for n in Set(names).sorted(by: { $0.count > $1.count }) where n.count >= 3 {
            let word = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: n) + #"(?![\p{L}\p{N}])"#
            out = out.replacingOccurrences(of: word, with: "[you]", options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    // MARK: Errors

    /// Errors sent as their own reports in one run of a program, at most: a loop of the same failure mustn't use up
    /// the month. Each kind of error is sent once; the rest stay in the log and ride along with later reports.
    public static let errorsPerRun = 20
    /// "Run 7F3A… failed after 12 s" and "…after 40 s" are the same kind of error: digits and ids don't count.
    public static func kind(_ category: String, _ message: String) -> String {
        let head = String(message.prefix(140))
        let plain = head.replacingOccurrences(of: #"[0-9a-fA-F-]{8,}|\d+(\.\d+)?"#, with: "#", options: .regularExpression)
        return "\(category): \(plain)"
    }
    /// Decides which errors become reports: new kinds only, and no more than `errorsPerRun`.
    public final class ErrorGate: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = Set<String>()
        private var sent = 0
        public let limit: Int
        public init(limit: Int = CrashReporting.errorsPerRun) { self.limit = limit }
        public func admits(_ category: String, _ message: String) -> Bool {
            lock.withLock {
                guard sent < limit, seen.insert(CrashReporting.kind(category, message)).inserted else { return false }
                sent += 1
                return true
            }
        }
    }

    // MARK: Crash reports macOS kept

    public static var diagnosticReports: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
    }
    /// Direction's own processes, by the name macOS gives them.
    public static let directionProcesses: Set<String> = appProcesses.union(["direction"])
    /// The app, by the names macOS gives it (a build from source is DirectionApp); "direction" is its helper.
    public static let appProcesses: Set<String> = ["Direction", "DirectionApp"]

    /// One crash report macOS kept, read from its two JSON parts.
    public struct CrashFile: Equatable, Sendable {
        public var url: URL
        public var date: Date
        /// The program that crashed ("Direction", "direction", "Python").
        public var process: String
        /// Who started it: Direction's own crashes have none of Direction's names here.
        public var parent: String?
        /// Direction crashed, as opposed to a program it started.
        public var isDirection: Bool { CrashReporting.directionProcesses.contains(process) }
        /// The app itself closed, not its helper or a program either one started.
        public var isApp: Bool { CrashReporting.appProcesses.contains(process) }
    }

    /// The crashes macOS kept that are Direction's: Direction itself, its helper, and any program either one started
    /// (Python for the footage index, yt-dlp, the editor's own program). Never another app's or a program the person
    /// ran themselves. Newer than `since`, oldest first.
    public static func crashFiles(since: Date, in dir: URL = diagnosticReports) -> [CrashFile] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.compactMap { url -> CrashFile? in
            guard url.pathExtension == "ips", let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > since,
                  let info = read(url) else { return nil }
            let ours = directionProcesses.contains(info.process) || info.parent.map(directionProcesses.contains) == true
            return ours ? CrashFile(url: url, date: date, process: info.process, parent: info.parent) : nil
        }
        .sorted { $0.date < $1.date }
    }

    /// The process and its parent, from an .ips: a JSON header line, then the report's JSON.
    static func read(_ url: URL) -> (process: String, parent: String?)? {
        guard let data = try? Data(contentsOf: url), data.count < 20_000_000, let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard let head = parts.first.flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }) else { return nil }
        let body = parts.count > 1 ? (try? JSONSerialization.jsonObject(with: Data(parts[1].utf8))) as? [String: Any] : nil
        guard let process = (body?["procName"] as? String) ?? (head["app_name"] as? String) ?? (head["name"] as? String) else { return nil }
        return (process, body?["parentProc"] as? String)
    }
}
