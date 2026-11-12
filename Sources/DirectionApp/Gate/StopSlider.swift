import SwiftUI
import DirectionCore

/// `.slider` with stops: the 4 pt track, steel-8 fill up to the knob, the 16 pt steel-9 knob, and a dot at
/// each stop, with the stops' names under it. Click or drag anywhere and it lands on the nearest stop;
/// a name picks its stop; VoiceOver and the arrow keys move a stop at a time.
struct StopSlider<Value: Hashable>: View {
    let stops: [(Value, String)]
    @Binding var selection: Value
    var label: String
    @Environment(\.isEnabled) private var enabled

    private var index: Int { stops.firstIndex { $0.0 == selection } ?? 0 }

    var body: some View {
        let last = max(1, stops.count - 1)
        VStack(spacing: 7) {
            GeometryReader { g in
                // The knob's middle sits on the first and last stops, so the track runs 8 pt in from each end.
                let span = max(1, g.size.width - 16)
                let at = { (k: Int) in 8 + span * CGFloat(k) / CGFloat(last) }
                ZStack(alignment: .leading) {
                    Capsule().fill(Gate.Surface.hover).frame(width: span, height: 4).offset(x: 8)
                    Capsule().fill(Gate.Steel.ramp[8]).frame(width: at(index) - 8, height: 4).offset(x: 8)
                    ForEach(stops.indices, id: \.self) { k in
                        Circle().fill(k <= index ? Gate.Steel.ramp[8] : Gate.Line.strong).frame(width: 6, height: 6).offset(x: at(k) - 3)
                    }
                    Circle().fill(Gate.Steel.ramp[9]).frame(width: 16, height: 16).shadow(color: .black.opacity(0.7), radius: 1.5, y: 1).offset(x: at(index) - 8)
                        .animation(.easeOut(duration: 0.16), value: index)
                }
                // The whole width takes clicks, the last stop's dot and knob included.
                .frame(width: g.size.width, height: 18, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let k = Int(((v.location.x - 8) / span * CGFloat(last)).rounded())
                    choose(min(stops.count - 1, max(0, k)))
                })
            }
            .frame(height: 18)
            // Each name under its own dot: the first starts at the track's start, the last ends at its end, the
            // rest are centred on theirs. One line each.
            GeometryReader { g in
                let span = max(1, g.size.width - 16)
                ZStack(alignment: .topLeading) {
                    ForEach(stops.indices, id: \.self) { k in
                        let name = Button { choose(k) } label: {
                            Text(stops[k].1).font(.system(size: 11.5, weight: k == index ? .medium : .regular))
                                .foregroundStyle(k == index ? Gate.Text.primary : Gate.Text.tertiary).lineLimit(1).fixedSize()
                        }.buttonStyle(.plain)
                        if k == 0 { name.frame(width: g.size.width, alignment: .leading) }
                        else if k == stops.count - 1 { name.frame(width: g.size.width, alignment: .trailing) }
                        else { name.frame(width: 0).offset(x: 8 + span * CGFloat(k) / CGFloat(last)) }
                    }
                }
            }
            .frame(height: 15)
        }
        .opacity(enabled ? 1 : Gate.Component.Button.disabledOpacity)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(stops[index].1)
        .accessibilityAdjustableAction { d in choose(min(stops.count - 1, max(0, index + (d == .increment ? 1 : -1)))) }
        .focusable(enabled)
        .onMoveCommand { d in
            if d == .left { choose(max(0, index - 1)) } else if d == .right { choose(min(stops.count - 1, index + 1)) }
        }
    }

    private func choose(_ k: Int) {
        guard enabled, stops.indices.contains(k), stops[k].0 != selection else { return }
        selection = stops[k].0
    }
}

/// A film's speed and quality (specs/editor.md › Speed and quality): Fastest · Faster · Balanced · Best, and what the
/// stop means in a line.
struct SpeedQualityControl: View {
    @Binding var quality: FilmQuality
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StopSlider(stops: FilmQuality.allCases.map { ($0, $0.label) }, selection: $quality, label: "Speed and quality")
            Text(quality.detail).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).cssLineHeight(1.45, size: 11.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
