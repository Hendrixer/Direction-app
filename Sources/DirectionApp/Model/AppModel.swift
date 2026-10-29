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
    var error: String?
    /// Previews show sample films without touching the library.
    var previewFilms: [FilmSummary]?

    @ObservationIgnored @AppStorage("whenOpening") var whenOpening = "lastFilm"
    @ObservationIgnored @AppStorage("lastFilm") var lastFilm = ""

    func start() {
        reloadFilms()
        if let index = CommandLine.arguments.firstIndex(of: "--project"), CommandLine.arguments.count > index + 1 { open(URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
        else if whenOpening == "lastFilm", !lastFilm.isEmpty, FileManager.default.fileExists(atPath: lastFilm) { open(URL(fileURLWithPath: lastFilm)) }
        else if whenOpening == "newFilm" { newFilm() }
    }

    func reloadFilms() { films = (try? ProjectLibrary().list()) ?? [] }

    func open(_ url: URL) {
        do {
            film?.close()
            let model = try FilmModel(url: url)
            model.onNotify = { [weak self] title, body, key in self?.notify(title, body, key: key); self?.updateDockBadge() }
            model.startPolling()
            film = model
            lastFilm = url.path
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            reloadFilms()
        } catch { self.error = error.localizedDescription }
    }

    func closeFilm() { film?.close(); film = nil; reloadFilms(); NSApp.dockTile.badgeLabel = nil }

    func chooseFilm() {
        let panel = NSOpenPanel(); panel.title = "Open a film"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// New film: a .direction package in the library folder, named later in the brief.
    func newFilm(named name: String = "Untitled film") {
        let folder = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "libraryFolder") ?? (NSHomeDirectory() + "/Movies/Direction"))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appendingPathComponent(name + ".direction"), n = 2
        while FileManager.default.fileExists(atPath: target.path) { target = folder.appendingPathComponent("\(name) \(n).direction"); n += 1 }
        do { _ = try ProjectStore.create(at: target, name: target.deletingPathExtension().lastPathComponent); open(target) } catch { self.error = error.localizedDescription }
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
    var art: FootageArt = .dusk
    var thumbnail: String?
}
