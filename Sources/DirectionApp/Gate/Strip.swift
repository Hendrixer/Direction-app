import SwiftUI
import AppKit

/// One scene on the strip, sized by its real duration in the cut.
struct StripScene: Identifiable, Equatable {
    var id: String
    var number: Int
    var title: String
    var start: Double
    var end: Double
    var art: FootageArt
    var thumbnail: String?
    var locked = false
    /// The editor changed this scene in the cut being watched: 2 pt prism top edge.
    var changed = false
    /// A stretch with no story under it (a title alone over black): a place on the strip, not a scene.
    var passage = false
    var label: String { passage ? "" : title.isEmpty ? "\(number)" : "\(number) \(title)" }
    var duration: Double { max(0, end - start) }
}

enum StripMarkKind: Equatable { case director, outside, editor }

struct StripMark: Identifiable, Equatable {
    var id: String
    var time: Double
    var kind: StripMarkKind = .director
    var fresh = false
}

/// The scene strip replaces the scrubber everywhere. Click seeks and drag scrubs; ⌥- or ⇧-drag
/// selects a range for a note. Right-click a scene for its menu. Marks sit in a row underneath.
struct SceneStrip<Menu: View>: View {
    var scenes: [StripScene]
    var duration: Double
    var playhead: Double?
    var marks: [StripMark] = []
    var range: ClosedRange<Double>? = nil
    var tall = false
    var showsNames = true
    var onSeek: (Double) -> Void = { _ in }
    var onRange: ((Double, Double) -> Void)? = nil
    @ViewBuilder var menu: (StripScene) -> Menu

    @State private var dragStart: Double?
    @State private var dragging: Drag = .seek
    @State private var moved = false

    /// What a drag on the strip does, from where it starts: on the range's edge it resizes the range, inside it
    /// it moves the range, elsewhere it moves the playhead (with ⌥ or ⇧, it draws a new range).
    private enum Drag { case seek, draw, move(grab: Double, length: Double), lower, upper }
    @Environment(\.editorPlayhead) private var editorPlayhead
    private var sceneHeight: CGFloat { tall ? Gate.Component.Strip.tallScene : Gate.Component.Strip.scene }
    private var height: CGFloat { tall ? Gate.Component.Strip.tallHeight : Gate.Component.Strip.height }
    private var current: StripScene? { playhead.flatMap { t in scenes.first { t >= $0.start && t < $0.end } ?? scenes.last } }

    var body: some View {
        GeometryReader { g in
            let width = g.size.width, gaps = CGFloat(max(0, scenes.count - 1)) * Gate.Component.Strip.gap
            let total = max(duration, scenes.map(\.end).max() ?? 0, 0.001)
            let usable = max(1, width - gaps)
            let x = { (t: Double) -> CGFloat in xPosition(t, scenes: scenes, total: total, usable: usable) }
            ZStack(alignment: .topLeading) {
                HStack(spacing: Gate.Component.Strip.gap) {
                    // A scene the cut comes back to has a tile each time: tiles are places, identified by position.
                    ForEach(Array(scenes.enumerated()), id: \.offset) { _, scene in
                        let w = max(2, usable * scene.duration / total)
                        // Kept to its own width: a short scene shows its picture, never spills into the next.
                        sceneTile(scene, isCurrent: scene.id == current?.id, width: w)
                            .frame(width: w, height: sceneHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .contextMenu { menu(scene) }
                    }
                }
                .padding(.top, 8)
                if let range {
                    let w = max(3, x(range.upperBound) - x(range.lowerBound))
                    RoundedRectangle(cornerRadius: 3).fill(Gate.Voice.directorWash).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Gate.Voice.director, lineWidth: 1.5))
                        .overlay {
                            // Grips on both edges: the range can be pulled longer or shorter.
                            if onRange != nil && w > 14 {
                                HStack {
                                    Capsule().fill(Gate.Voice.director).frame(width: 3, height: max(8, sceneHeight * 0.45))
                                    Spacer(minLength: 0)
                                    Capsule().fill(Gate.Voice.director).frame(width: 3, height: max(8, sceneHeight * 0.45))
                                }
                                .padding(.horizontal, 2.5)
                            }
                        }
                        .frame(width: w, height: sceneHeight + 4).offset(x: x(range.lowerBound), y: 6).allowsHitTesting(false)
                }
                ForEach(marks) { mark in
                    ZStack {
                        if mark.fresh { FreshHalo() }
                        switch mark.kind {
                        case .director: PinMark()
                        case .outside: PinMark(color: Gate.Text.secondary)
                        case .editor: GemMark(size: 7)
                        }
                    }
                    .position(x: x(mark.time), y: 8 + sceneHeight + 7)
                    .allowsHitTesting(false)
                }
                // The editor's playhead rides every strip under the director's (specs/editor.md).
                if let editor = editorPlayhead {
                    EditorPlayheadMark(value: editor, height: sceneHeight, x: x)
                }
                if let playhead {
                    Playhead(height: sceneHeight + 12).position(x: x(playhead), y: 2 + (sceneHeight + 12) / 2).allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard case .active(let p) = phase, onRange != nil, let range else { if case .ended = phase { NSCursor.arrow.set() }; return }
                switch grab(p.x, range: range, x: x) {
                case .lower, .upper: NSCursor.resizeLeftRight.set()
                case .move: NSCursor.openHand.set()
                default: NSCursor.arrow.set()
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let t = time(at: value.location.x, scenes: scenes, total: total, usable: usable)
                if dragStart == nil {
                    let start = time(at: value.startLocation.x, scenes: scenes, total: total, usable: usable)
                    dragStart = start; moved = false
                    if let range, onRange != nil { dragging = grab(value.startLocation.x, range: range, x: x) } else { dragging = .seek }
                    if case .move(_, let length) = dragging, let range { dragging = .move(grab: start - range.lowerBound, length: length) }
                    if case .seek = dragging, onRange != nil, !NSEvent.modifierFlags.intersection([.option, .shift]).isEmpty { dragging = .draw }
                    if case .move = dragging { NSCursor.closedHand.set() }
                }
                if abs(value.translation.width) > 3 { moved = true }
                guard let start = dragStart, let onRange else { onSeek(t); return }
                let shortest = min(0.1, total)
                switch dragging {
                case .seek: onSeek(t)
                case .draw: if moved { onRange(min(start, t), max(start, t)) }
                case .move(let grabbed, let length):
                    guard moved else { return }
                    let lower = max(0, min(total - length, t - grabbed))
                    onRange(lower, lower + length)
                case .lower: if moved, let range { onRange(max(0, min(t, range.upperBound - shortest)), range.upperBound) }
                case .upper: if moved, let range { onRange(range.lowerBound, min(total, max(t, range.lowerBound + shortest))) }
                }
            }.onEnded { value in
                // A click on the range that didn't drag it moves the playhead there, like anywhere else.
                if !moved, let start = dragStart { switch dragging { case .move, .lower, .upper: onSeek(start); default: break } }
                if case .move = dragging { NSCursor.openHand.set() }
                dragStart = nil; dragging = .seek; moved = false
            })
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scene strip")
        .accessibilityValue(current.map { "In scene \($0.label)" } ?? "")
        .accessibilityAdjustableAction { direction in
            guard let playhead else { return }
            let idx = scenes.firstIndex { $0.id == current?.id } ?? 0
            let next = direction == .increment ? min(scenes.count - 1, idx + 1) : max(0, idx - 1)
            if scenes.indices.contains(next) { onSeek(direction == .increment || playhead - scenes[idx].start < 1 ? scenes[next].start : scenes[idx].start) }
        }
    }

    private func sceneTile(_ scene: StripScene, isCurrent: Bool, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Gate.Surface.panel
            Thumbnail(path: scene.thumbnail, art: scene.art)
                .opacity(scene.locked ? 0.3 : isCurrent ? 0.8 : 0.55).grayscale(scene.locked ? 1 : 0)
            if scene.locked { Hatching(opacity: 0.07) }
            // The name where it fits, then only the lock, then only the picture.
            if showsNames && width >= 18 && (width >= 34 || scene.locked) {
                HStack(spacing: 4) {
                    if scene.locked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    if width >= 34 { Text(scene.label).lineLimit(1).truncationMode(.tail) }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.primary).shadow(color: .black, radius: 1.5, y: 1)
                .padding(.horizontal, 6)
            }
        }
        .overlay(alignment: .top) { if scene.changed { Gate.Voice.prism.frame(height: 2) } }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isCurrent || scene.locked ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1))
    }

    /// What a drag starting at `px` takes hold of: an edge of the range (within 6 pt), the range, or nothing.
    private func grab(_ px: CGFloat, range: ClosedRange<Double>, x: (Double) -> CGFloat) -> Drag {
        let lo = x(range.lowerBound), hi = x(range.upperBound)
        if abs(px - lo) <= 6 && px <= (lo + hi) / 2 { return .lower }
        if abs(px - hi) <= 6 { return .upper }
        if px > lo && px < hi { return .move(grab: 0, length: range.upperBound - range.lowerBound) }
        return .seek
    }

    private func xPosition(_ t: Double, scenes: [StripScene], total: Double, usable: CGFloat) -> CGFloat {
        guard !scenes.isEmpty else { return usable * t / total }
        var x: CGFloat = 0
        for (i, s) in scenes.enumerated() {
            let w = usable * s.duration / total
            if t < s.end || i == scenes.count - 1 { return x + w * CGFloat(max(0, min(1, (t - s.start) / max(s.duration, 0.0001)))) }
            x += w + Gate.Component.Strip.gap
        }
        return x
    }
    private func time(at px: CGFloat, scenes: [StripScene], total: Double, usable: CGFloat) -> Double {
        guard !scenes.isEmpty else { return max(0, min(total, Double(px / usable) * total)) }
        var x: CGFloat = 0
        for (i, s) in scenes.enumerated() {
            let w = usable * s.duration / total
            if px <= x + w || i == scenes.count - 1 { return max(0, min(total, s.start + s.duration * Double(max(0, min(1, (px - x) / max(w, 1)))))) }
            x += w + Gate.Component.Strip.gap
        }
        return total
    }
}

extension SceneStrip where Menu == EmptyView {
    init(scenes: [StripScene], duration: Double, playhead: Double?, marks: [StripMark] = [], range: ClosedRange<Double>? = nil, tall: Bool = false, showsNames: Bool = true, onSeek: @escaping (Double) -> Void = { _ in }, onRange: ((Double, Double) -> Void)? = nil) {
        self.init(scenes: scenes, duration: duration, playhead: playhead, marks: marks, range: range, tall: tall, showsNames: showsNames, onSeek: onSeek, onRange: onRange, menu: { _ in EmptyView() })
    }
}

/// 2 pt playhead with a 10×5 cap.
struct Playhead: View {
    var height: CGFloat = 36
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 1).fill(Gate.Text.primary).frame(width: 2, height: height).shadow(color: .black.opacity(0.6), radius: 0.5)
            RoundedRectangle(cornerRadius: 2).fill(Gate.Text.primary).frame(width: 10, height: 5)
        }.frame(width: 10, height: height)
    }
}
