import Foundation
import SwiftUI
import AppKit
import UserNotifications
import DirectionCore

/// The app: the Films list, the open film, and app-wide behavior (recent documents, Dock badge, notifications).
@MainActor @Observable
final class AppModel {
    var films: [ProjectEntry] = []
    var film: FilmModel?
    /// An alert's text. Every one also goes in Direction's log.
    var error: String? { didSet { if let error, error != oldValue { DirectionLog.error("Alert: \(error)") } } }
    /// Previews show sample films without touching the library.
    var previewFilms: [FilmSummary]?

    @ObservationIgnored @AppStorage("whenOpening") var whenOpening = "lastFilm"
    @ObservationIgnored @AppStorage("lastFilm") var lastFilm = ""

    func start() {
        LibraryModel.shared.load()
        let info = Bundle.main.infoDictionary
        DirectionLog.info("Direction \(info?["CFBundleShortVersionString"] as? String ?? "dev") (\(info?["CFBundleVersion"] as? String ?? "?")) started on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        // Caches of films that are gone: trashed in Finder, or old tests (system.md › Deleting a film).
        let trashed = FilmLibraryIndex.trashed
        Task.detached(priority: .background) {
            let (folders, bytes) = CacheCleanup.prune(trashed: trashed)
            if folders > 0 { DirectionLog.info("Cleared the cache of \(folders) film\(folders == 1 ? "" : "s") that aren\u{2019}t here anymore (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))", "cache") }
            await MainActor.run { self.reloadFilms() }
        }
        reloadFilms()
        if let index = CommandLine.arguments.firstIndex(of: "--project"), CommandLine.arguments.count > index + 1 { open(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
        else if whenOpening == "lastFilm", !lastFilm.isEmpty, FileManager.default.fileExists(atPath: lastFilm) { open(URL(fileURLWithPath: lastFilm)) }
        else if whenOpening == "newFilm" { newFilm() }
    }

    func reloadFilms() { films = (try? ProjectLibrary().list()) ?? [] }

    func open(_ url: URL) {
        // Already open (the editor asked to show it, a notification, Open Recent): bring it forward.
        // Opening it again would close it first, and closing cancels its running jobs.
        if let film, let open = film.url, open.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath() {
            NSApp?.activate()
            NSApp?.windows.first { $0.frameAutosaveName == "DirectionMainWindow" }?.makeKeyAndOrderFront(nil)
            return
        }
        guard mayCloseFilm(opening: "\u{201C}\(filmName(url))\u{201D}") else { return }
        show(url)
    }

    private func show(_ url: URL) {
        do {
            film?.close()
            let model = try FilmModel(url: url)
            model.onNotify = { [weak self] title, body, key in self?.notify(title, body, key: key); self?.updateDockBadge() }
            model.startPolling()
            film = model
            lastFilm = url.path
            FilmLibraryIndex.noteRestored(url.path)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            reloadFilms()
        } catch { self.error = error.localizedDescription }
    }

    /// Back to Films. False when the director kept a running delivery going instead.
    @discardableResult
    func closeFilm() -> Bool {
        guard mayCloseFilm(opening: nil) else { return false }
        film?.close(); film = nil; reloadFilms(); NSApp.dockTile.badgeLabel = nil
        return true
    }

    /// Closing a film stops its running deliveries, so opening another film or going back to Films asks
    /// first, the way Quit does. `opening` names what would open instead; nil is Films.
    func mayCloseFilm(opening: String?) -> Bool {
        guard let film, !QuitGuard.runningDeliveries(film).isEmpty else { return true }
        return askToStopDelivering(film, opening)
    }
    /// Keep Delivering (false) or Stop and Open (true). Tests answer for the director.
    @ObservationIgnored var askToStopDelivering: @MainActor (FilmModel, String?) -> Bool = AppModel.askToStopDelivering(_:opening:)

    static func askToStopDelivering(_ film: FilmModel, opening: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = opening.map { "Open \($0) and stop delivering?" } ?? "Close \(film.filmName) and stop delivering?"
        alert.informativeText = "\(film.filmName) is still being delivered. If you \(opening == nil ? "close it" : "open another film") now, the files won\u{2019}t be finished. You can deliver again later."
        alert.addButton(withTitle: opening == nil ? "Stop and Close" : "Stop and Open")
        alert.addButton(withTitle: "Keep Delivering")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Back to Films. A new film you haven't put anything into (no title, brief, footage or notes)
    /// goes to the Trash instead of cluttering the list.
    func leaveFilm() {
        guard let film, let url = film.url else { closeFilm(); return }
        let pristine = film.isUntitled && !film.hasFootage && film.brief.logline.isEmpty && film.brief.feeling.isEmpty && film.notes.isEmpty && film.cuts.isEmpty
        let projectID = film.project?.id
        guard closeFilm(), pristine else { return }
        NSWorkspace.shared.recycle([url]) { _, error in
            MainActor.assumeIsolated { if error == nil { FilmLibraryIndex.noteTrashed(url.path); CacheCleanup.forget(film: url, projectID: projectID); self.reloadFilms() } }
        }
    }

    func chooseFilm() {
        let panel = NSOpenPanel(); panel.title = "Open a film"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// New film: a .direction package in the library folder, named later in the brief. It opens on Who's editing?
    func newFilm(named name: String = "Untitled film") {
        guard mayCloseFilm(opening: "a new film") else { return }
        let folder = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "libraryFolder") ?? (NSHomeDirectory() + "/Movies/Direction"))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(name + ".direction"), n = 2
        while FileManager.default.fileExists(atPath: target.path) { target = folder.appendingPathComponent("\(name) \(n).direction"); n += 1 }
        do { _ = try ProjectStore.create(at: target, name: target.deletingPathExtension().lastPathComponent); show(target); film?.askWhoEdits() } catch { self.error = error.localizedDescription }
    }

    /// Dock badge: what's waiting for the director.
    func updateDockBadge() {
        guard let film else { NSApp.dockTile.badgeLabel = nil; return }
        let waiting = film.openQuestions.count + film.unreviewedAnswers.count
        NSApp.dockTile.badgeLabel = waiting > 0 ? String(waiting) : nil
    }

    /// Settings decide whether it shows, waits for the end of a screening, or becomes a toast while the app is in front.
    func notify(_ title: String, _ body: String, key: String) { SystemNotifications.post(title, body, key: key, film: film) }
}

/// A row in the Films grid.
struct FilmSummary: Identifiable {
    var id: String
    var name: String
    var path: String
    var duration: String?
    var status: String
    var editorBusy = false
    var waiting: String?
    var locked = false
    /// A painted stand-in, for sample films. A real film shows its own picture, or the mark until it has one.
    var art: FootageArt?
    var thumbnail: String?
}
