import AppKit
import DirectionCore
import DirectionReports

/// Crash and error reports at launch (system.md › Crash reports). Off until the person says yes: in Settings ›
/// General, or here, once, the first time Direction opens after it closed unexpectedly. Only copies people download
/// do any of this; a build from source never asks or sends.
@MainActor enum CrashReportsLaunch {
    static func start() {
        guard Reports.allowedHere else { return }
        Reports.startIfAllowed(process: "app")
        // After the window is up, and after Move to Applications had its turn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { lookAtLastRun() }
    }

    /// Crashes macOS kept since the last look (a week back the first time): with reports on, the ones Sentry can't
    /// see itself (programs Direction started) go now; with them off and Direction itself crashed, it asks once.
    static func lookAtLastRun() {
        let since = CrashReporting.handledThrough ?? Date().addingTimeInterval(-7 * 86_400)
        let crashes = CrashReporting.crashFiles(since: since)
        guard let newest = crashes.last else { return }
        CrashReporting.handledThrough = newest.date
        if CrashReporting.sends {
            Reports.send(crashes.filter { !$0.isDirection })
            return
        }
        guard crashes.contains(where: \.isDirection) else { return }
        let alert = NSAlert()
        alert.messageText = "Direction closed unexpectedly."
        alert.informativeText = "Send a report of what happened to Direction\u{2019}s developer, and turn on reports for next time? A report has what Direction was doing and its error messages, with your name taken out of file paths. It never has your footage. You can turn reports off in Settings \u{203A} General."
        alert.addButton(withTitle: "Send Report")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setSends(true)
        Reports.send(crashes)
    }

    #if DEBUG
    /// `DirectionApp --report-test` with DIRECTION_REPORTS=1: one test report to Sentry, then quit. Checks the wiring
    /// from a build from source; nothing else in it sends.
    static func runTestIfRequested() {
        guard CommandLine.arguments.contains("--report-test"), Reports.allowedHere else { return }
        Reports.start(process: "app")
        DirectionLog.error("Test report from a build from source, sent by --report-test (home \(NSHomeDirectory()))", "reports")
        Reports.flush()
        exit(0)
    }
    #endif

    /// The Settings switch.
    static func setSends(_ on: Bool) {
        CrashReporting.setSends(on)
        if on { Reports.start(process: "app") } else { Reports.stop() }
        DirectionLog.info(on ? "Crash reports turned on" : "Crash reports turned off", "app")
    }
}
