import Testing
import Foundation
@testable import DirectionCore

/// Crash and error reports (system.md › Crash reports): what leaves the Mac is scrubbed, a loop of one error is one
/// report, and only Direction's crashes (and the programs it started) are ever picked up.
struct CrashReportingTests {
    @Test func theirNameNeverLeavesTheMac() {
        let text = "Couldn't read /Users/kaelyn/Movies/Direction/Haul.direction/cut.mov for Kaelyn Smith (kaelyn); also /Users/other/x and sk-or-v1-abcdefghijklmnop"
        let out = CrashReporting.scrub(text, home: "/Users/kaelyn", names: ["kaelyn", "Kaelyn Smith"])
        #expect(out == "Couldn't read ~/Movies/Direction/Haul.direction/cut.mov for [you] ([you]); also /Users/[you]/x and •••")
        // Short names aren't replaced inside other words.
        #expect(CrashReporting.scrub("ok at 0:12", home: "/Users/ab", names: ["ab"]) == "ok at 0:12")
    }

    @Test func oneKindOfErrorIsOneReport() {
        let gate = CrashReporting.ErrorGate(limit: 3)
        #expect(gate.admits("editor", "Run 7F3A2B1C-0000 failed after 12 s"))
        #expect(!gate.admits("editor", "Run 99AA77BB-1111 failed after 40 s"))
        #expect(gate.admits("media", "The video didn't download"))
        #expect(gate.admits("editor", "Claude Code isn't signed in"))
        #expect(!gate.admits("tools", "Something new"), "no more than the limit in one run")
    }

    @Test func onlyDirectionsCrashesArePickedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("direction-ips-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func ips(_ file: String, app: String, proc: String, parent: String, ago: Double) throws {
            let head = #"{"app_name":"\#(app)","timestamp":"2026-11-05","bug_type":"309","name":"\#(app)"}"#
            let body = #"{"procName":"\#(proc)","parentProc":"\#(parent)","pid":42}"#
            let url = dir.appendingPathComponent(file)
            try Data((head + "\n" + body).utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ago)], ofItemAtPath: url.path)
        }
        try ips("Direction-2026-11-05-200000.ips", app: "Direction", proc: "Direction", parent: "launchd", ago: 60)
        try ips("Python-2026-11-05-190000.ips", app: "Python", proc: "Python", parent: "direction", ago: 120)
        try ips("Python-2026-11-05-180000.ips", app: "Python", proc: "Python", parent: "zsh", ago: 180)
        try ips("Safari-2026-11-05-170000.ips", app: "Safari", proc: "Safari", parent: "launchd", ago: 240)
        try ips("Direction-2026-10-01-100000.ips", app: "Direction", proc: "Direction", parent: "launchd", ago: 30 * 86_400)
        try Data("not a report".utf8).write(to: dir.appendingPathComponent("Direction-broken.ips"))
        let found = CrashReporting.crashFiles(since: Date().addingTimeInterval(-7 * 86_400), in: dir)
        #expect(found.map(\.url.lastPathComponent) == ["Python-2026-11-05-190000.ips", "Direction-2026-11-05-200000.ips"])
        #expect(found.map(\.isDirection) == [false, true] && found.first?.parent == "direction")
    }

    @Test func reportsAreOffUntilSomeoneSaysYes() {
        let suite = "direction-reports-test-" + UUID().uuidString
        let before = SharedSettings.defaults
        SharedSettings.defaults = UserDefaults(suiteName: suite)!
        defer { SharedSettings.defaults.removePersistentDomain(forName: suite); SharedSettings.defaults = before }
        #expect(!CrashReporting.sends)
        CrashReporting.setSends(true)
        #expect(CrashReporting.sends)
    }
}
