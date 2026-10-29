import SwiftUI
import AppKit

/// Configures the main window like a native Mac document window with a custom 52 pt titlebar:
/// full-size content, traffic lights centered in the bar at x 20, frame autosave, minimum size,
/// full-screen support. The titlebar view handles dragging and double-click (see TitlebarDragArea).
struct WindowConfigurator: NSViewRepresentable {
    var autosaveName = "DirectionMainWindow"
    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView(); view.autosaveName = autosaveName; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class WindowObserverView: NSView {
    var autosaveName = ""
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.minSize = Gate.Size.windowMin
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        if window.frameAutosaveName.isEmpty { window.setFrameAutosaveName(autosaveName) }
        window.backgroundColor = NSColor(Gate.Surface.ground)
        layoutTrafficLights()
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didEnterFullScreenNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.layoutTrafficLights() } })
        }
    }
    /// Centers the system traffic lights vertically in the 52 pt bar, starting at x 20.
    func layoutTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        // close → titlebar view → titlebar container (in the theme frame, origin bottom-left).
        guard let close = window.standardWindowButton(.closeButton), let titlebar = close.superview, let container = titlebar.superview else { return }
        let height = Gate.Size.titlebar, spacing: CGFloat = 20
        container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
        titlebar.frame = container.bounds
        for (i, type) in buttons.enumerated() {
            guard let b = window.standardWindowButton(type) else { continue }
            b.setFrameOrigin(NSPoint(x: Gate.Size.trafficLightsX + CGFloat(i) * spacing, y: (height - b.frame.height) / 2))
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// The empty part of the titlebar: drags the window and honors the system's
/// "Double-click a window's title bar to" setting (zoom, minimize, or nothing).
struct TitlebarDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window?.performMiniaturize(nil)
                case "None": break
                default: window?.performZoom(nil)
                }
                return
            }
            window?.performDrag(with: event)
        }
    }
}
