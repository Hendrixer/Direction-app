import SwiftUI
import AppKit

@MainActor final class DirectionAppDelegate: NSObject, NSApplicationDelegate {
    var app: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        BrandAssets.registerFonts()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        NSWindow.allowsAutomaticWindowTabbing = false
    }
    /// Opening a .direction package from Finder or the Dock.
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first(where: { $0.pathExtension == "direction" }) { app?.open(url) } }
    /// Clicking the Dock icon with no window brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.frameAutosaveName == "DirectionMainWindow" }?.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
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

        Settings { SettingsView().preferredColorScheme(.dark) }
    }
}
