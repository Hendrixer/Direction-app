import Foundation
import Darwin
import os

/// Every program Direction starts gets a process group of its own (Foundation's `Process` makes one),
/// and what that program starts joins it unless it asks otherwise. Stopping the group stops all of
/// it, even what outlived its parent: a shell's `ffmpeg … &`, the editor's tool server.
///
/// The groups running are listed here. When a program ends, whatever it left in its group is
/// stopped. On quit Direction stops the rest; if Direction goes away without doing so (a crash,
/// Force Quit), its reaper (`direction reap`, `Reaper`) sees its pipe close and stops them instead.
public enum ChildProcesses {
    /// A signal, then how long to wait for the group to go before the next.
    public typealias Step = (signal: Int32, wait: TimeInterval)
    /// SIGINT first, so the editor keeps its session; then SIGTERM; then SIGKILL.
    public static let gently: [Step] = [(SIGINT, 4), (SIGTERM, 2), (SIGKILL, 0)]
    public static let firmly: [Step] = [(SIGTERM, 2), (SIGKILL, 0)]

    private struct State { var groups: Set<pid_t> = []; var reaper: FileHandle? }
    private static let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// After `run()`: the program's group is listed (and told to the reaper).
    public static func started(_ p: Process) {
        let g = p.processIdentifier
        guard g > 0 else { return }
        // A program can be over before this is called (its `ended` came first): then it isn't listed.
        state.withLockUnchecked { s in guard p.isRunning else { return }; s.groups.insert(g); tell(s.reaper, "+\(g)") }
    }

    /// Once the program has exited: it's taken off the list, and anything it left running in its
    /// group is stopped (off the calling thread).
    public static func ended(_ p: Process) {
        let g = p.processIdentifier
        guard g > 0 else { return }
        state.withLockUnchecked { s in s.groups.remove(g); tell(s.reaper, "-\(g)") }
        if isAlive(group: g) { DispatchQueue.global(qos: .utility).async { stop(group: g, firmly) } }
    }

    /// The groups still running.
    public static var running: Set<pid_t> { state.withLockUnchecked { $0.groups } }

    /// Every group still running, all at once. Blocks until they're gone or the steps run out.
    public static func stopAll(_ steps: [Step] = firmly) {
        let groups = Array(running)
        guard !groups.isEmpty else { return }
        DispatchQueue.concurrentPerform(iterations: groups.count) { stop(group: groups[$0], steps) }
        state.withLockUnchecked { s in for g in groups { s.groups.remove(g); tell(s.reaper, "-\(g)") } }
    }

    /// Each signal in turn while anyone in the group is left. Blocks.
    public static func stop(group g: pid_t, _ steps: [Step]) {
        for step in steps {
            guard isAlive(group: g) else { return }
            killpg(g, step.signal)
            let deadline = Date().addingTimeInterval(step.wait)
            while isAlive(group: g) && Date() < deadline { usleep(25_000) }
        }
    }

    /// Anyone left in the group (a process that's exited but not been waited for counts until it is).
    public static func isAlive(group g: pid_t) -> Bool { g > 0 && (killpg(g, 0) == 0 || errno == EPERM) }

    /// Hands the list to the reaper, now and from here on.
    public static func connectReaper(_ handle: FileHandle) {
        // A reaper that's gone must not take Direction with it: writes fail instead of raising SIGPIPE.
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        state.withLockUnchecked { s in s.reaper = handle; for g in s.groups { tell(handle, "+\(g)") } }
    }

    private static func tell(_ reaper: FileHandle?, _ line: String) { try? reaper?.write(contentsOf: Data((line + "\n").utf8)) }

    /// The folder a process is working in, or nil if it's gone or not ours to read. The editor runs
    /// in its film's Editor folder, which is how a run left by an earlier Direction is recognized.
    public static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: info.pvi_cdir.vip_path) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) } }
    }
}

/// `direction reap`: started by Direction with a pipe for its input. It reads "+<group>" when a
/// program starts and "-<group>" when it ends; when the pipe closes (Direction quit, crashed or
/// was forced to quit) it stops every group still listed, gently, then exits.
public enum Reaper {
    public static func serve(_ input: FileHandle, steps: [ChildProcesses.Step] = ChildProcesses.gently) {
        var groups = Set<pid_t>(), pending = Data()
        while true {
            let data = input.availableData
            if data.isEmpty { break }
            pending.append(data)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...nl)
                guard let sign = line.first, let g = pid_t(line.dropFirst()), g > 0 else { continue }
                if sign == "+" { groups.insert(g) } else if sign == "-" { groups.remove(g) }
            }
        }
        let left = Array(groups.filter(ChildProcesses.isAlive(group:)))
        guard !left.isEmpty else { return }
        DirectionLog.warning("Direction went away with \(left.count) program\(left.count == 1 ? "" : "s") still running; stopping them.", "processes")
        DispatchQueue.concurrentPerform(iterations: left.count) { ChildProcesses.stop(group: left[$0], steps) }
    }
}
