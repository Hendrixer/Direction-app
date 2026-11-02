import SwiftUI
import AppKit

extension View {
    /// `.popover`, faded by Direction instead of by macOS. The system's own popover animation steps at
    /// half the display's rate, 30 fps on a 60 Hz screen; a fade of the popover's window runs at the full
    /// rate. Everything else is the system popover: placement, arrow, closing on a click outside or Esc.
    func gatePopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(GatePopoverModifier(isPresented: isPresented, arrowEdge: arrowEdge, popover: content))
    }
}

/// The anchor is there only while its popover is open or fading out, so a list of rows that each have
/// a popover doesn't carry a view per row.
private struct GatePopoverModifier<Popover: View>: ViewModifier {
    @Binding var isPresented: Bool
    var arrowEdge: Edge
    var popover: () -> Popover
    @State private var shown = false

    func body(content: Content) -> some View {
        content.background {
            if isPresented || shown { GatePopoverAnchor(isPresented: $isPresented, shown: $shown, arrowEdge: arrowEdge, content: popover) }
        }
    }
}

private struct GatePopoverAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var shown: Bool
    var arrowEdge: Edge
    var content: () -> Content
    @Environment(\.self) private var environment

    func makeCoordinator() -> GatePopoverPresenter { GatePopoverPresenter() }
    func makeNSView(context: Context) -> GatePopoverPresenter.Anchor { GatePopoverPresenter.Anchor() }

    func updateNSView(_ anchor: GatePopoverPresenter.Anchor, context: Context) {
        let presenter = context.coordinator, presented = $isPresented, shown = $shown
        presenter.dismiss = { if presented.wrappedValue { presented.wrappedValue = false } }
        presenter.settled = { if shown.wrappedValue != $0 { shown.wrappedValue = $0 } }
        presenter.root = AnyView(content().environment(\.self, environment))
        presenter.edge = arrowEdge
        presenter.anchor = anchor
        anchor.onWindow = { [weak presenter] in presenter?.update() }
        presenter.wanted = isPresented
        presenter.update()
    }

    static func dismantleNSView(_ anchor: GatePopoverPresenter.Anchor, coordinator: GatePopoverPresenter) {
        coordinator.wanted = false
        coordinator.close(animated: false)
    }
}

/// Shows one NSPopover for a `gatePopover` and runs its fade in and out.
@MainActor final class GatePopoverPresenter: NSObject, NSPopoverDelegate {
    /// Sized like the view it's attached to; never takes a click.
    final class Anchor: NSView {
        var onWindow: (() -> Void)?
        override var isFlipped: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { DispatchQueue.main.async { [weak self] in self?.onWindow?() } }
        }
    }

    weak var anchor: Anchor?
    var root = AnyView(EmptyView())
    var edge = Edge.top
    var wanted = false
    var dismiss: () -> Void = {}
    /// Whether the popover is on screen, so the modifier keeps the anchor until it has faded out.
    var settled: (Bool) -> Void = { _ in }
    private var popover: NSPopover?
    private var host: NSHostingController<AnyView>?
    /// Counts fades, so a fade that's been overtaken doesn't close the popover.
    private var fades = 0
    private var closing = false

    func update() {
        host?.rootView = root
        if wanted { open() } else { close(animated: true) }
    }

    private func open() {
        if let popover, popover.isShown {
            if closing { closing = false; fade(to: 1) }
            return
        }
        guard let anchor, anchor.window != nil else { return }
        let host = host ?? NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        let popover = popover ?? NSPopover()
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        self.host = host; self.popover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: Self.rectEdge(edge))
        popover.contentViewController?.view.window?.alphaValue = 0
        fade(to: 1)
        let settled = settled
        DispatchQueue.main.async { settled(true) }
    }

    func close(animated: Bool) {
        guard let popover, popover.isShown else { return }
        if !animated { fades += 1; closing = false; popover.close(); return }
        guard !closing else { return }
        closing = true
        fade(to: 0)
    }

    /// Starts on the next turn of the run loop: asked inside a SwiftUI update, the animator often jumps to the end.
    private func fade(to alpha: CGFloat) {
        fades += 1
        let n = fades, reduced = SettingsKey.reducesMotion
        DispatchQueue.main.async { [weak self] in
            guard let self, n == self.fades, let window = self.popover?.contentViewController?.view.window else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = alpha > 0 ? Gate.Motion.settleDuration : Gate.Motion.snapDuration
                context.timingFunction = reduced ? CAMediaTimingFunction(name: .linear) : CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                window.animator().alphaValue = alpha
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, n == self.fades, alpha == 0, self.closing else { return }
                    self.closing = false
                    self.popover?.close()
                }
            }
        }
    }

    /// A click outside or Esc: fade first, then close.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        close(animated: true)
        dismiss()
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController?.view.window?.alphaValue = 1
        if wanted { wanted = false; dismiss() }
        let settled = settled
        DispatchQueue.main.async { settled(false) }
    }

    /// SwiftUI's arrow edge on the anchor, in the anchor's unflipped coordinates.
    static func rectEdge(_ edge: Edge) -> NSRectEdge {
        switch edge {
        case .top: .maxY
        case .bottom: .minY
        case .leading: .minX
        case .trailing: .maxX
        }
    }
}
