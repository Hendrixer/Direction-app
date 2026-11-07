import SwiftUI
import AppKit
import UserNotifications
import DirectionCore

// Mac integration from specs/mac.md that lives outside any one room: user notifications,
// the quit guard while a delivery runs, the editor connection, and film actions shared by
// the menu bar, the command menu and the context menus.

// MARK: Notifications

/// User notifications for a cut ready, a question, a can't-do and a delivery, honoring
/// Settings › Notifications. Held while you watch through when asked, and shown as a toast
/// instead when Direction is frontmost in the room the notification is about.
@MainActor
enum SystemNotifications {
    private static var held: [(String, String, String)] = []
    private static var delegate: NotificationRouter?

    /// The room a notification opens.
    static func room(for key: String) -> Room {
        switch key {
        case NotificationKey.delivery: .finish
        default: .cut
        }
    }

    /// Posts one notification. Call from AppModel.notify(_:_:key:).
    static func post(_ title: String, _ body: String, key: String, film: FilmModel?) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) as? Bool ?? true else { return }
        if let film, defaults.object(forKey: SettingsKey.holdDuringScreening) as? Bool ?? true, film.watchingCut {
            held.append((title, body, key)); return
        }
        let room = room(for: key)
        if let film, NSApp.isActive, NSApp.keyWindow?.frameAutosaveName == "DirectionMainWindow", film.room == room {
            if film.toast == nil || key != NotificationKey.cutReady { film.toast = Toast(title: title, detail: body, editor: key != NotificationKey.delivery) }
            return
        }
        guard SystemSupport.isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body
        content.userInfo = ["key": key, "room": room.rawValue, "film": film?.url?.path ?? ""]
        content.threadIdentifier = film?.url?.path ?? "direction"
        if defaults.string(forKey: SettingsKey.notificationSound) != "none" { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Delivers what was held while you watched through. Call when watching ends.
    static func releaseHeld(film: FilmModel?) {
        let queue = held; held = []
        for (title, body, key) in queue { post(title, body, key: key, film: film) }
    }

    /// Asks once, after the first turnover rather than at launch (Settings › Notifications).
    static func requestPermissionIfNeeded() { requestPermission {} }
    /// Settings › Notifications › Turn On asks now; `done` runs on the main actor once macOS answers.
    static func requestPermission(_ done: @escaping @MainActor @Sendable () -> Void) {
        guard SystemSupport.isBundledApp else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in Task { @MainActor in done() } }
    }

    /// Clicking a notification opens its film in the right room. Call once at launch.
    static func install(app: AppModel) {
        guard SystemSupport.isBundledApp, delegate == nil else { return }
        let router = NotificationRouter(app: app)
        delegate = router
        UNUserNotificationCenter.current().delegate = router
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "dev.direction.editor"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") { NSWorkspace.shared.open(url) }
    }
}

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    weak var app: AppModel?
    init(app: AppModel) { self.app = app }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        // Notifications posted before Screening, Notes and Changes became the Cut room still open it.
        let path = info["film"] as? String ?? "", room = (info["room"] as? String).flatMap { Room(rawValue: $0) ?? (["screening", "notes", "changes"].contains($0) ? .cut : nil) }
        await MainActor.run {
            guard let app else { return }
            NSApp.activate()
            NSApp.windows.first { $0.frameAutosaveName == "DirectionMainWindow" }?.makeKeyAndOrderFront(nil)
            if !path.isEmpty, app.film?.url?.path != path, FileManager.default.fileExists(atPath: path) { app.open(URL(fileURLWithPath: path)) }
            guard let film = app.film, let room else { return }
            if room == .cut, !film.openQuestions.isEmpty { film.notesTab = .questions }
            film.go(room)
        }
    }
}

/// "Launch film is delivered" / "4 files, 2.1 GB.": one notification when every export of a
/// delivery has finished. Screening copies from the Share sheet don't count.
@MainActor
enum DeliveryWatch {
    private static var running: Set<String> = []
    private static var finished: [String] = []
    private static weak var watching: FilmModel?

    /// Call whenever the film's jobs change (SystemBanners does).
    static func check(_ film: FilmModel) {
        // Another film: what the last one was delivering stopped with it and must not hold back this one's.
        if watching !== film { watching = film; running = []; finished = [] }
        let exports = film.jobs.filter { $0.kind == "export" && !ScreeningCopy.jobIDs.contains($0.id) }
        for job in exports where !job.isTerminal { running.insert(job.id) }
        for job in exports where job.isTerminal && running.contains(job.id) {
            running.remove(job.id)
            if job.status == "completed", let path = job.result?["path"].string { finished.append(path) }
        }
        guard running.isEmpty, !finished.isEmpty else { return }
        let files = finished; finished = []
        let bytes = files.compactMap { DeliveryFormat.fileSize(URL(fileURLWithPath: $0)) }.reduce(0, +)
        let body = "\(files.count) \(files.count == 1 ? "file" : "files"), \(SystemSupport.bytes(bytes))."
        film.onNotify?("\(film.filmName) is delivered", body, NotificationKey.delivery)
    }
}

// MARK: Quit

/// `direction reap`, started at launch: if Direction goes away without stopping the programs it
/// started (a crash, Force Quit), the reaper does (`ChildProcesses`, `Reaper`).
enum ReaperLaunch {
    nonisolated(unsafe) private static var reaper: Process?

    static func start() {
        // A program that's gone must not take Direction with it when it's written to.
        signal(SIGPIPE, SIG_IGN)
        guard reaper == nil, let helper = EditorJobs.helperPath else { return }
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: helper); p.arguments = ["reap"]
        p.standardInput = pipe; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        p.terminationHandler = { p in DirectionLog.warning("The reaper stopped (status \(p.terminationStatus)); programs won\u{2019}t be stopped if Direction crashes.", "processes") }
        do { try p.run() } catch { DirectionLog.warning("Couldn\u{2019}t start the reaper: \(error.localizedDescription)", "processes"); return }
        reaper = p
        ChildProcesses.connectReaper(pipe.fileHandleForWriting)
    }
}

@MainActor
enum QuitGuard {
    /// Running exports this process owns (a delivery or a screening copy).
    static func runningDeliveries(_ film: FilmModel?) -> [JobRecord] {
        (film?.jobs ?? []).filter { $0.kind == "export" && !$0.isTerminal && $0.ownerPID == getpid() }
    }

    /// "Quit and stop delivering?" and "The editor is cutting Cut 4. Quit and pause it?"
    /// Call from applicationShouldTerminate(_:).
    static func shouldTerminate(_ app: AppModel?) -> NSApplication.TerminateReply {
        if !runningDeliveries(app?.film).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Quit and stop delivering?"
            alert.informativeText = "\(app?.film?.filmName ?? "The film") is still being delivered. If you quit now, the files won\u{2019}t be finished. You can deliver again later."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Keep Delivering")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        let runner = EditorRunner.shared
        guard runner.liveCount > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "\(editorDoing(app?.film)) Quit and pause it?"
        alert.informativeText = "It keeps its place. When you open Direction again, you can resume it."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        // Quit pauses each run and keeps its session; the next launch offers Resume.
        runner.pauseAllForQuit { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    /// "The editor is cutting Cut 4."
    private static func editorDoing(_ film: FilmModel?) -> String {
        guard let film, let run = film.runs.active else { return "The editor is working." }
        switch run.job {
        case .turnover: return "The editor is cutting \(film.nextCutName)."
        case .assemble: return "The editor is building the assembly."
        case .logFootage: return "The editor is logging your footage."
        case .finish: return "The editor is finishing \(film.filmName)."
        case .style: return "The editor is making a style."
        case .technique: return "The editor is learning a technique."
        case .script: return "The editor is writing the picture for \(film.filmName)."
        case .breakdown: return "The editor is breaking down \(film.filmName)."
        }
    }
}

// MARK: The editor connection

/// How an outside agent connects to Direction: the bundled CLI as an MCP server.
enum EditorConnection {
    static var cliPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/direction").path }
    static var isBundled: Bool { FileManager.default.isExecutableFile(atPath: cliPath) }

    static var mcpConfig: String {
        let escaped = cliPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "mcpServers": {
            "direction": {
              "command": "\(escaped)",
              "args": ["mcp"]
            }
          }
        }
        """
    }

    static var claudeCommand: String { "claude mcp add direction -- \"\(cliPath)\" mcp" }
    static var codexCommand: String { "codex mcp add direction -- \"\(cliPath)\" mcp" }

    /// Help › Connect an Editor… when no film window is showing the popover.
    @MainActor static func presentAlert() {
        let alert = NSAlert()
        alert.messageText = "Connect an editor"
        alert.informativeText = "Your editor is an agent like Claude Code or Codex. Add Direction to it as an MCP server, then ask it to open your film.\(isBundled ? "" : "\n\nThis copy of Direction runs outside its app bundle, so the path below may not exist. Build the app with scripts/build-app.sh.")"
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        text.string = mcpConfig; text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 6); text.drawsBackground = true; text.backgroundColor = .textBackgroundColor
        let scroll = NSScrollView(frame: text.frame); scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Copy Configuration")
        alert.addButton(withTitle: "Copy Claude Code Command")
        alert.addButton(withTitle: "Done")
        switch alert.runModal() {
        case .alertFirstButtonReturn: SystemSupport.copy(mcpConfig)
        case .alertSecondButtonReturn: SystemSupport.copy(claudeCommand)
        default: break
        }
    }
}

// MARK: Film actions shared by menus, the command menu and context menus

/// Actions the menu bar, the command menu and the context menus share. A separate type
/// (not a FilmModel extension) so these names can't collide with room code.
@MainActor
struct FilmActions {
    let m: FilmModel
    init(_ model: FilmModel) { m = model }

    /// The scene under the playhead, as a Dailies scene (lockable).
    var currentScene: DailiesScene? { m.stripScene(at: m.position).flatMap { s in m.dailies.scenes.first { $0.id == s.id } } }

    var lockSceneUnavailableReason: String? {
        if currentScene == nil { return m.dailies.scenes.isEmpty ? "No scenes logged yet" : "No scene under the playhead" }
        if m.isPictureLocked { return "Picture is locked" }
        return nil
    }
    func toggleCurrentSceneLock() {
        guard let s = currentScene else { return }
        m.lockScene(s.id, !s.locked)
    }

    var lockPictureUnavailableReason: String? {
        if m.isPictureLocked { return "Picture is already locked" }
        if m.cuts.isEmpty { return "No cut yet" }
        return m.picturelockBlockers.first
    }

    var timecode: String { Timecode.format(m.position, fps: m.fps) }
    func copyTimecode() { SystemSupport.copy(timecode); m.toast = Toast(title: "Copied \(timecode)") }

    /// ↑ / ↓: the previous scene's start (or this scene's, if well into it), or the next scene's.
    func jumpScene(_ delta: Int) {
        let scenes = m.stripScenes
        guard !scenes.isEmpty else { return }
        let i = scenes.firstIndex { m.position >= $0.start && m.position < $0.end } ?? (delta > 0 ? -1 : scenes.count)
        var target = max(0, min(scenes.count - 1, i + delta))
        if delta < 0, scenes.indices.contains(i), m.position - scenes[i].start > 1 { target = i }
        m.pause(); m.seek(scenes[target].start)
    }

    func setRangeIn() { if m.room != .cut { m.go(.cut) }; m.setStretchEdge(start: true) }
    func setRangeOut() { if m.room != .cut { m.go(.cut) }; m.setStretchEdge(start: false) }

    /// New Note (⌥⌘N, or words typed in the command menu): a note on this moment in the Cut room, open to write in.
    func startNote(text: String = "") {
        guard m.isEnabled(.cut) else { return }
        m.go(.cut); m.pause()
        m.mark()
        if !text.isEmpty, m.notesUI.editingNoteID != nil { m.draftText = text }
    }

    /// Go to a Time… (⌃G): asks for a time the way the app shows it (1:12, or 1:02:03 in a cut over an hour) and seeks.
    func askForTimecode() {
        let hours = m.duration >= 3600
        let alert = NSAlert(); alert.messageText = "Go to a time"
        alert.informativeText = hours ? "Hours, minutes and seconds (1:02:03), minutes and seconds (12:04), or seconds (72)." : "Minutes and seconds (1:12), or seconds (72)."
        let field = NSTextField(string: Timecode.format(m.position, fps: m.fps)); field.frame = NSRect(x: 0, y: 0, width: 200, height: 24); field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        alert.accessoryView = field; alert.addButton(withTitle: "Go"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let t = Self.parseTimecode(field.stringValue, fps: m.fps, hours: hours) else { return }
        m.pause(); m.seek(t)
    }

    /// "72" is seconds and "1:12" minutes and seconds. Three parts are hours, minutes and seconds (`hours`, a cut
    /// over an hour, where times read that way: Timecode.format), otherwise minutes, seconds and frames as times
    /// used to read. Four are hours, minutes, seconds and frames.
    static func parseTimecode(_ text: String, fps: Double, hours: Bool = false) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
        if parts.count == 1 { return Double(parts[0]).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
        let n = parts.compactMap(Int.init)
        guard n.count == parts.count, (2...4).contains(n.count), n.allSatisfy({ $0 >= 0 }) else { return nil }
        switch n.count {
        case 2: return Double(n[0] * 60 + n[1])
        case 3: return hours ? Double(n[0] * 3600 + n[1] * 60 + n[2]) : Double(n[0] * 60 + n[1]) + Double(n[2]) / fps
        default: return Double(n[0] * 3600 + n[1] * 60 + n[2]) + Double(n[3]) / fps
        }
    }

    /// Film › Export for an Editing App…: the watched cut as a folder Final Cut Pro and DaVinci Resolve open
    /// (issue #4), at any stage, not only once it's delivered.
    func exportTimeline() {
        guard let cut = m.watchedCut, let runtime = m.runtime else { return }
        let panel = NSSavePanel()
        panel.title = "Export for an Editing App"; panel.prompt = "Export"
        panel.message = "A folder with \(cut.name) for Final Cut Pro or DaVinci Resolve, each sound track on its own, and the look."
        panel.nameFieldStringValue = "\(m.filmName) \u{2013} \(cut.name) Timeline"; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let film = m
        film.toast = Toast(title: "Exporting \(cut.name) for an editing app\u{2026}")
        Task { @MainActor in
            do {
                let response = try await runtime.invoke("direction_export", arguments: .object(["path": .string(url.path), "preset": .string("timeline"), "revision": .number(Double(film.revision(of: cut))), "sequenceID": .string(cut.sequenceID)]))
                let job = try response.value.decode(JobRecord.self)
                ScreeningCopy.jobIDs.insert(job.id)
                _ = try await runtime.waitForJob(job.id)
                film.toast = Toast(title: "\(cut.name) is ready for an editing app", detail: url.lastPathComponent, actionTitle: "Show in Finder", run: { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            } catch {
                film.toast = Toast(title: "\(cut.name) wasn\u{2019}t exported", detail: error.localizedDescription)
            }
        }
    }

    func revealInFinder() {
        if let url = m.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: UserDefaults.standard.string(forKey: SettingsKey.libraryFolder) ?? SettingsKey.defaultLibrary)) }
    }

    func confirmUnlockPicture() {
        let alert = NSAlert(); alert.messageText = "Unlock picture?"
        alert.informativeText = "The editor can change the edit again, and the scenes that locked with the picture open again. Finishing work may need redoing. It\u{2019}s recorded in History."
        alert.addButton(withTitle: "Unlock Picture"); alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn { m.unlockPicture() }
    }

    /// Plays from a moment.
    func play(from time: Double) { m.pause(); m.seek(time); m.togglePlayback() }
}
