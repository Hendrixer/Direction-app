import Foundation
import Sentry
import DirectionCore

/// Sends crash and error reports to Sentry when the person turned them on (system.md › Crash reports). Both Direction
/// and its `direction` helper start it; a copy built from source and the tests never do. Every report is scrubbed
/// (CrashReporting.scrub) before it leaves the Mac, and none carries the person's IP address or the Mac's name.
public enum Reports {
    /// Starts reporting for this process when the person said yes. `process` is "app" or "helper".
    public static func startIfAllowed(process: String) {
        guard CrashReporting.sends, allowedHere else { return }
        start(process: process)
    }

    /// A signed copy someone downloaded, or a build from source run with DIRECTION_REPORTS=1 to check reports work.
    /// Never the tests.
    public static var allowedHere: Bool {
        guard !DirectionPaths.isTesting else { return false }
        return release != nil || ProcessInfo.processInfo.environment["DIRECTION_REPORTS"] == "1"
    }

    public static func start(process: String) {
        guard !SentrySDK.isEnabled else { return }
        let gate = CrashReporting.ErrorGate()
        SentrySDK.start { o in
            o.dsn = CrashReporting.dsn
            o.releaseName = release.map { "direction@\($0)" } ?? "direction@source"
            o.environment = release == nil ? "source" : "release"
            o.sendDefaultPii = false
            o.debug = ProcessInfo.processInfo.environment["DIRECTION_REPORTS_DEBUG"] == "1"
            o.attachStacktrace = true
            // A main thread stuck for 5 s is a freeze worth a report; shorter ones are a render or a seek.
            o.enableAppHangTracking = true
            o.appHangTimeoutInterval = 5
            o.enableAutoPerformanceTracing = false
            o.enableNetworkTracking = false
            o.enableNetworkBreadcrumbs = false
            o.enableCaptureFailedRequests = false
            o.enableFileIOTracing = false
            o.maxBreadcrumbs = 100
            o.beforeSend = { event in scrub(event) }
            o.beforeBreadcrumb = { crumb in crumb.message = crumb.message.map { CrashReporting.scrub($0) }; return crumb }
        }
        SentrySDK.configureScope { scope in scope.setTag(value: process, key: "process") }
        // Direction's log: every line leads up to a report; each new kind of error is a report of its own.
        DirectionLog.observer = { level, category, raw in
            // Scrubbed before anything is made from it: the fingerprint and tags leave the Mac too.
            let text = CrashReporting.scrub(raw)
            let crumb = Breadcrumb(level: level == .error ? .error : level == .warning ? .warning : .info, category: category)
            crumb.message = String(text.prefix(400))
            SentrySDK.addBreadcrumb(crumb)
            guard level == .error, gate.admits(category, text) else { return }
            SentrySDK.capture(message: String(text.prefix(1_000))) { scope in
                scope.setLevel(.error)
                scope.setTag(value: category, key: "category")
                scope.setFingerprint(["log", CrashReporting.kind(category, text)])
            }
        }
    }

    /// Waits up to `timeout` for reports still being sent.
    public static func flush(timeout: TimeInterval = 10) { if SentrySDK.isEnabled { SentrySDK.flush(timeout: timeout) } }

    /// Turning the box off stops reporting at once.
    public static func stop() {
        DirectionLog.observer = nil
        if SentrySDK.isEnabled { SentrySDK.flush(timeout: 2); SentrySDK.close() }
    }

    /// Crashes macOS kept from before reports were on, or from a program Direction started: each sent once, as a
    /// report with the crash file attached, scrubbed.
    public static func send(_ crashes: [CrashReporting.CrashFile]) {
        guard SentrySDK.isEnabled else { return }
        for crash in crashes {
            guard let text = try? String(contentsOf: crash.url, encoding: .utf8) else { continue }
            let what = crash.isDirection ? "\(crash.process) crashed" : "\(crash.process), started by \(crash.parent ?? "Direction"), crashed"
            SentrySDK.capture(message: what) { scope in
                scope.setLevel(.fatal)
                scope.setTag(value: crash.process, key: "crashed")
                scope.setTag(value: "macos-report", key: "source")
                scope.setFingerprint(["macos-crash", crash.process])
                scope.addAttachment(Attachment(data: Data(CrashReporting.scrub(text).utf8), filename: "\(crash.process).ips", contentType: "application/json"))
            }
        }
        SentrySDK.flush(timeout: 10)
    }

    /// A tool call or a step that has gone on far longer than any should: one report with every thread's stack, so
    /// it shows where it's stuck.
    public static func stuck(_ what: String, minutes: Int, tags: [String: String] = [:]) {
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(message: "\(what) has been going for \(minutes) min", attachAllThreads: true) { scope in
            scope.setLevel(.warning)
            scope.setTag(value: "stuck", key: "kind")
            for (k, v) in tags { scope.setTag(value: CrashReporting.scrub(v), key: k) }
            scope.setFingerprint(["stuck", what])
        }
    }

    // MARK: Scrubbing an event

    static func scrub(_ event: Event) -> Event {
        event.serverName = nil
        event.user = nil
        if let m = event.message { event.message = SentryMessage(formatted: CrashReporting.scrub(m.formatted)) }
        event.exceptions?.forEach { e in e.value = e.value.map { CrashReporting.scrub($0) } }
        event.breadcrumbs?.forEach { c in c.message = c.message.map { CrashReporting.scrub($0) } }
        event.debugMeta?.forEach { d in d.codeFile = d.codeFile.map { CrashReporting.scrub($0) } }
        // Every stack's frames name the program they're in by its path, which can be under the home folder.
        let frames: (SentryStacktrace?) -> Void = { st in st?.frames.forEach { f in f.package = f.package.map { CrashReporting.scrub($0) }; f.fileName = f.fileName.map { CrashReporting.scrub($0) } } }
        event.threads?.forEach { frames($0.stacktrace) }
        event.exceptions?.forEach { frames($0.stacktrace) }
        frames(event.stacktrace)
        event.fingerprint = event.fingerprint?.map { CrashReporting.scrub($0) }
        if let tags = event.tags { event.tags = tags.mapValues { CrashReporting.scrub($0) } }
        if var context = event.context, var device = context["device"] {
            device["name"] = nil
            context["device"] = device
            event.context = context
        }
        return event
    }

    // MARK: Which copy this is

    /// "0.3.2+184" for a signed copy with an update feed (the copies people download), nil for one built from source.
    /// The helper finds the app it's inside.
    static var release: String? {
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath().path
        let bundle: Bundle? = Bundle.main.bundlePath.hasSuffix(".app") ? .main
            : exe.range(of: ".app/Contents/").map { Bundle(path: String(exe[..<$0.lowerBound]) + ".app") } ?? nil
        guard let info = bundle?.infoDictionary, info["SUFeedURL"] != nil, let version = info["CFBundleShortVersionString"] as? String else { return nil }
        return info["CFBundleVersion"].map { "\(version)+\($0)" } ?? version
    }
}
