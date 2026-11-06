import SwiftUI
import AppKit
import DirectionCore

@MainActor final class DirectionAppDelegate: NSObject, NSApplicationDelegate {
    var app: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        BrandAssets.registerFonts()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        NSWindow.allowsAutomaticWindowTabbing = false
        ReaperLaunch.start()
        // A signed copy checks for updates (docs/releasing.md); one built from source doesn't.
        _ = AppUpdates.shared
        // Opened straight from the disk image: offer to move to Applications, where it can update itself.
        DispatchQueue.main.async { MoveToApplications.offerIfNeeded() }
        // The log keeps 30 days: trimmed now and once a day while Direction stays open.
        DispatchQueue.global(qos: .utility).async { DirectionLog.prune() }
        logPruning = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in DispatchQueue.global(qos: .utility).async { DirectionLog.prune() } }
    }
    private var logPruning: Timer?
    /// Quitting stops what Direction started (the editor has already been paused by QuitGuard).
    func applicationWillTerminate(_ notification: Notification) { ChildProcesses.stopAll() }
    /// Opening a .direction package from Finder or the Dock.
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first(where: { $0.pathExtension == "direction" }) { app?.open(url) } }
    /// Clicking the Dock icon with no window brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.frameAutosaveName == "DirectionMainWindow" }?.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    /// Asks before quitting in the middle of a delivery.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { QuitGuard.shouldTerminate(app) }
}

@main struct DirectionApplication: App {
    @NSApplicationDelegateAdaptor(DirectionAppDelegate.self) var delegate
    @State private var app = AppModel()

    init() { Snapshots.runIfRequested() }

    var body: some Scene {
        Window("Direction", id: "main") {
            MainWindow(app: app)
                .task { delegate.app = app; app.start() }
                .onOpenURL { app.open($0) }
        }
        .defaultSize(width: Gate.Size.windowDesign.width, height: Gate.Size.windowDesign.height)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands { DirectionCommands(app: app) }

        Settings { SettingsView(app: app).preferredColorScheme(.dark) }

        // The library: every transition, move and effect, with previews (techniques.md › The library).
        Window("Library", id: "library") { LibraryWindow(app: app) }
            .defaultSize(width: 1080, height: 700)
    }
}
