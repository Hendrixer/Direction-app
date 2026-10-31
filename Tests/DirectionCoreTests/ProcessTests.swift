import Testing
import Foundation
import Darwin
@testable import DirectionCore

/// Nothing Direction starts is left running (ChildProcesses, Reaper), and the log keeps 30 days.
struct ProcessTests {
    static let quick: [ChildProcesses.Step] = [(SIGINT, 0.3), (SIGTERM, 0.3), (SIGKILL, 0)]

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("processes-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func shell(_ script: String) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
        return p
    }
    /// A shell that leaves `sleep 300` behind in its group, outliving it, and says which process that is.
    private func leaving(_ dir: URL, then rest: String = "") throws -> (Process, URL) {
        let file = dir.appendingPathComponent("straggler")
        return (try shell("(sleep 300 </dev/null >/dev/null 2>&1 & echo $! > '\(file.path)'); \(rest)"), file)
    }
    private func pid(_ file: URL) throws -> pid_t {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: file, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return pid }
            usleep(20_000)
        }
        throw DirectionError("timeout", "The shell never said which process it left.")
    }
    private func gone(_ pid: pid_t) -> Bool {
        for _ in 0..<100 { if kill(pid, 0) != 0 { return true }; usleep(50_000) }
        kill(pid, SIGKILL)
        return false
    }

    @Test func stoppingAGroupStopsWhatOutlivedItsParent() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let (p, file) = try leaving(dir, then: "trap '' INT TERM; while true; do sleep 0.1; done")
        let straggler = try pid(file)
        ChildProcesses.stop(group: p.processIdentifier, Self.quick)
        p.waitUntilExit()
        #expect(p.terminationReason == .uncaughtSignal)
        #expect(gone(straggler))
    }

    @Test func whatAProgramLeftStopsWhenItEnds() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let (p, file) = try leaving(dir, then: "sleep 0.3")
        ChildProcesses.started(p)
        #expect(ChildProcesses.running.contains(p.processIdentifier))
        let straggler = try pid(file)
        p.waitUntilExit()
        ChildProcesses.ended(p)
        #expect(!ChildProcesses.running.contains(p.processIdentifier))
        #expect(gone(straggler))
    }

    @Test func theReaperStopsWhatsListedWhenItsPipeCloses() throws {
        let listed = try shell("trap '' INT; sleep 300"), unlisted = try shell("sleep 300")
        defer { unlisted.terminate() }
        let pipe = Pipe(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { Reaper.serve(pipe.fileHandleForReading, steps: Self.quick); done.signal() }
        try pipe.fileHandleForWriting.write(contentsOf: Data("+\(listed.processIdentifier)\n+\(unlisted.processIdentifier)\n-\(unlisted.processIdentifier)\n".utf8))
        usleep(100_000)
        #expect(listed.isRunning)
        // Direction goes away: its end of the pipe closes.
        try pipe.fileHandleForWriting.close()
        #expect(done.wait(timeout: .now() + 5) == .success)
        listed.waitUntilExit()
        #expect(listed.terminationReason == .uncaughtSignal)
        #expect(unlisted.isRunning)
    }

    /// The real helper, as Direction starts it: when Direction's pipe closes (a crash), it stops the editor.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: ProcessTests.helper)))
    func theHelpersReaperStopsAProgramWhenDirectionGoesAway() throws {
        let program = try shell("sleep 300")
        let reaper = Process(), pipe = Pipe()
        reaper.executableURL = URL(fileURLWithPath: Self.helper); reaper.arguments = ["reap"]
        reaper.standardInput = pipe; reaper.standardOutput = FileHandle.nullDevice; reaper.standardError = FileHandle.nullDevice
        try reaper.run()
        try pipe.fileHandleForWriting.write(contentsOf: Data("+\(program.processIdentifier)\n".utf8))
        try pipe.fileHandleForWriting.close()
        reaper.waitUntilExit()
        program.waitUntilExit()
        #expect(reaper.terminationStatus == 0 && program.terminationReason == .uncaughtSignal)
    }
    static let helper = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/direction").path

    @Test func theLogKeepsThirtyDays() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1_793_400_000)
        func lines(_ entries: [(Double, String)]) -> String { entries.map { DirectionLog.stamp(now.addingTimeInterval(-$0.0 * 86_400)) + " app[1] INFO [app] " + $0.1 + "\n" }.joined() }
        let log = dir.appendingPathComponent("Direction.log"), previous = dir.appendingPathComponent("Direction.1.log"), other = dir.appendingPathComponent("notes.txt")
        try lines([(45, "six weeks ago"), (30.5, "a month ago"), (29, "kept"), (0.5, "today")]).write(to: log, atomically: true, encoding: .utf8)
        try lines([(60, "two months ago"), (40, "also old")]).write(to: previous, atomically: true, encoding: .utf8)
        try "not a log".write(to: other, atomically: true, encoding: .utf8)
        DirectionLog.prune(in: dir, now: now)
        let kept = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(kept.count == 2 && kept[0].hasSuffix("kept") && kept[1].hasSuffix("today"))
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        // Nothing older is left, so a second pass changes nothing.
        let before = try String(contentsOf: log, encoding: .utf8)
        DirectionLog.prune(in: dir, now: now)
        #expect(try String(contentsOf: log, encoding: .utf8) == before)
    }
}
