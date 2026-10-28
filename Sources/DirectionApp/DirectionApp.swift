import SwiftUI
import AppKit

@MainActor final class DirectionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
}

@main struct DirectionApplication: App {
    @NSApplicationDelegateAdaptor(DirectionAppDelegate.self) var delegate
    @State private var model = EditorModel()
    var body: some Scene {
        Window("Direction", id: "main") {
            EditorView(model: model)
                .preferredColorScheme(.dark)
                .task { await model.start() }
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…", action: model.createProject).keyboardShortcut("n")
                Button("Open Project…", action: model.chooseProject).keyboardShortcut("o")
                Divider()
                Button("Import Footage…", action: model.chooseMedia).keyboardShortcut("i").disabled(model.project == nil)
            }
            CommandMenu("Review") {
                Button("Working Cut", action: model.followWorkingCut).disabled(model.project == nil)
                Button("Mark Range In", action: model.markIn).keyboardShortcut("i", modifiers: [])
                Button("Mark Range Out", action: model.markOut).keyboardShortcut("o", modifiers: [])
            }
        }
    }
}
