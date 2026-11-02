import SwiftUI
import AppKit
import os

/// The sample film on the second screen, opening and closing the editor popover, so Instruments'
/// Animation Hitches can time the popover's frames:
///   xctrace record --template 'Animation Hitches' --launch -- DirectionApp --popover-probe
@MainActor
enum PopoverProbe {
    static func run() -> Never {
        BrandAssets.registerFonts()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let model = SampleFilm.make()
        // The slowest screen: a 60 Hz one is where a slow frame shows.
        let screen = NSScreen.screens.min { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond } ?? NSScreen.main!
        let size = NSSize(width: 1280, height: 800)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false, screen: screen)
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Gate.Surface.ground)
        window.contentView = NSHostingView(rootView: FilmWindow(app: nil, model: model).environment(\.colorScheme, .dark))
        let f = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        print("screen:", screen.localizedName, screen.maximumFramesPerSecond)
        let log = OSLog(subsystem: "dev.direction.probe", category: .pointsOfInterest)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for _ in 0..<5 {
                os_signpost(.event, log: log, name: "open")
                model.showEditorPopover = true
                try? await Task.sleep(for: .seconds(0.06))
                report("opening")
                try? await Task.sleep(for: .seconds(0.44))
                report("open")
                try? await Task.sleep(for: .seconds(0.5))
                os_signpost(.event, log: log, name: "close")
                model.showEditorPopover = false
                try? await Task.sleep(for: .seconds(0.06))
                report("closing")
                try? await Task.sleep(for: .seconds(0.44))
                report("closed")
                try? await Task.sleep(for: .seconds(0.3))
            }
            exit(0)
        }
        app.run()
        exit(0)
    }

    /// The popover's window as the director would see it: its alpha and the scale it's drawn at.
    private static func report(_ moment: String) {
        let popovers = NSApp.windows.filter { String(describing: type(of: $0)).contains("Popover") && $0.isVisible }
        print(moment + ":", popovers.isEmpty ? "no popover" : popovers.map { window in
            let layer = window.contentView?.superview?.layer
            return String(format: "popover at alpha %.2f, scale %.4f", window.alphaValue, (layer?.presentation() ?? layer)?.transform.m11 ?? 1)
        }.joined(separator: ", "))
    }
}
