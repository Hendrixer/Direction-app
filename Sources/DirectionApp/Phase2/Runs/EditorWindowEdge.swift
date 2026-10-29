import SwiftUI
import AppKit

/// While a run works (not paused): a 1 pt prism line around the inside of the window's content,
/// under the titlebar's hairline. It shimmers on the 2.4 s loop; static with Reduce Motion or while
/// a cut plays. Not drawn in Screening or full screen (specs/editor.md › The window edge).
struct EditorWindowEdge: View {
    @Environment(\.motionHeld) private var held
    var body: some View {
        Group {
            if held || SettingsKey.reducesMotion {
                Rectangle().strokeBorder(Gate.Voice.prism, lineWidth: 1)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Gate.Motion.shimmerPeriod) / Gate.Motion.shimmerPeriod
                    Rectangle().strokeBorder(AngularGradient(colors: Gate.Voice.prismStops + [Gate.Voice.prismStops[0]], center: .center, angle: .degrees(t * 360)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where the editor last looked or changed something, for the scene strips.
struct EditorPlayheadValue: Equatable {
    var time: Double
    /// When the activity happened; the mark fades 2 s after.
    var at: Double
    /// Snapshots keep it showing.
    var hold = false
}
struct EditorPlayheadKey: EnvironmentKey { static let defaultValue: EditorPlayheadValue? = nil }
extension EnvironmentValues {
    var editorPlayhead: EditorPlayheadValue? { get { self[EditorPlayheadKey.self] } set { self[EditorPlayheadKey.self] = newValue } }
}

/// The editor's playhead: a 9 pt prism diamond on the scenes' top edge with a 1 pt prism line down
/// through the strip. Glides (Settle) between times, fades 2 s after the last timed activity, and
/// never touches the director's playhead.
struct EditorPlayheadMark: View {
    var value: EditorPlayheadValue
    var height: CGFloat
    var x: (Double) -> CGFloat
    @Environment(\.motionHeld) private var held
    @State private var shown: Double?
    @State private var visible = false

    var body: some View {
        let t = shown ?? value.time
        ZStack(alignment: .top) {
            LinearGradient(colors: Gate.Voice.prismStops, startPoint: .top, endPoint: .bottom).frame(width: 1, height: height)
            RoundedRectangle(cornerRadius: 1.5).fill(Gate.Voice.prism).frame(width: 9, height: 9)
                .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.black.opacity(0.6), lineWidth: 1).padding(-1))
                .rotationEffect(.degrees(45)).offset(y: -4.5)
        }
        .frame(width: 11, height: height, alignment: .top)
        .position(x: x(t), y: 8 + height / 2)
        .opacity(visible || value.hold ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Nothing moves during playback: the mark waits for the cut to stop.
        .onChange(of: value.time) { _, new in if !held { withAnimation(gateAnimation(Gate.Motion.settle)) { shown = new } } }
        .onChange(of: held) { _, h in if !h, shown != value.time { withAnimation(gateAnimation(Gate.Motion.settle)) { shown = value.time } } }
        .task(id: value.at) {
            if shown == nil { shown = value.time }
            let left = value.at + 2 - Date().timeIntervalSince1970
            guard left > 0 else { visible = false; return }
            visible = true
            try? await Task.sleep(for: .seconds(left))
            withAnimation(gateAnimation(Gate.Motion.settle)) { visible = false }
        }
    }
}

/// Whether the window is full screen, for things that hide there.
struct FullScreenReader: NSViewRepresentable {
    @Binding var isFullScreen: Bool
    func makeNSView(context: Context) -> NSView { Watcher(binding: $isFullScreen) }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Watcher: NSView {
        var binding: Binding<Bool>
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
        init(binding: Binding<Bool>) { self.binding = binding; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            guard let window else { return }
            binding.wrappedValue = window.styleMask.contains(.fullScreen)
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { guard let self, let w = self.window else { return }; self.binding.wrappedValue = w.styleMask.contains(.fullScreen) }
                })
            }
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
