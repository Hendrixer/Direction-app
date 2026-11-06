import AppKit
import DirectionCore

/// A downloaded copy opened straight from its disk image runs from a read-only place macOS picks: it can't
/// update itself, and it's gone once the disk image is ejected. Direction says so at launch and offers to move
/// itself to Applications (system.md › Opened from the disk image). A copy built from source never asks.
@MainActor
enum MoveToApplications {
    static let applications = URL(fileURLWithPath: "/Applications/Direction.app")

    /// macOS runs a downloaded app from a temporary copy (App Translocation), or it runs from the mounted image.
    static func isFromDownload(_ path: String) -> Bool { path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") }

    static func offerIfNeeded() {
        guard AppUpdates.shared.updates, !DirectionPaths.isTesting, isFromDownload(Bundle.main.bundlePath) else { return }
        DirectionLog.info("Direction is running from its disk image (\(Bundle.main.bundlePath))", "app")
        let alert = NSAlert()
        alert.messageText = "Move Direction to Applications?"
        alert.informativeText = "Direction is running from the disk image, so it can\u{2019}t update itself, and it closes when the disk image is ejected. It can move itself to Applications and open from there."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        move()
    }

    /// Copies this app into Applications (an older copy there goes to the Trash first), opens it, and quits.
    /// A copy there that's as new or newer is opened as it is.
    static func move() {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: applications.path) {
                if build(of: applications) >= build(of: Bundle.main.bundleURL) { return open() }
                try fm.trashItem(at: applications, resultingItemURL: nil)
            }
            try fm.copyItem(at: Bundle.main.bundleURL, to: applications)
            DirectionLog.info("Moved Direction to Applications", "app")
            open()
        } catch {
            DirectionLog.error("Couldn\u{2019}t move Direction to Applications: \(error.localizedDescription)", "app")
            let alert = NSAlert()
            alert.messageText = "Direction couldn\u{2019}t move itself."
            alert.informativeText = "\(error.localizedDescription) Drag Direction from the disk image to Applications, then open it from there."
            alert.runModal()
        }
    }

    private static func open() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: applications, configuration: config) { _, error in
            Task { @MainActor in
                if let error { DirectionLog.error("Couldn\u{2019}t open Direction in Applications: \(error.localizedDescription)", "app"); return }
                NSApp.terminate(nil)
            }
        }
    }

    private static func build(of app: URL) -> Int {
        (Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0
    }
}
