import SwiftUI

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
