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
    var label: String { title.isEmpty ? "\(number)" : "\(number) \(title)" }
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
    @State private var selectingRange = false
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
                    ForEach(scenes) { scene in
                        sceneTile(scene, isCurrent: scene.id == current?.id)
                            .frame(width: max(2, usable * scene.duration / total), height: sceneHeight)
                            .contextMenu { menu(scene) }
                    }
                }
                .padding(.top, 8)
                if let range {
                    RoundedRectangle(cornerRadius: 3).fill(Gate.Voice.directorWash).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Gate.Voice.director, lineWidth: 1.5))
                        .frame(width: max(3, x(range.upperBound) - x(range.lowerBound)), height: sceneHeight + 4).offset(x: x(range.lowerBound), y: 6).allowsHitTesting(false)
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
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let t = time(at: value.location.x, scenes: scenes, total: total, usable: usable)
                if dragStart == nil {
                    dragStart = time(at: value.startLocation.x, scenes: scenes, total: total, usable: usable)
                    selectingRange = onRange != nil && !NSEvent.modifierFlags.intersection([.option, .shift]).isEmpty
                }
                if selectingRange {
                    if let start = dragStart, let onRange, abs(value.translation.width) > 4 { onRange(min(start, t), max(start, t)) }
                } else { onSeek(t) }
            }.onEnded { _ in dragStart = nil; selectingRange = false })
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

    private func sceneTile(_ scene: StripScene, isCurrent: Bool) -> some View {
        ZStack(alignment: .leading) {
            Gate.Surface.panel
            Thumbnail(path: scene.thumbnail, art: scene.art)
                .opacity(scene.locked ? 0.3 : isCurrent ? 0.8 : 0.55).grayscale(scene.locked ? 1 : 0)
            if scene.locked { Hatching(opacity: 0.07) }
            if showsNames {
                HStack(spacing: 4) {
                    if scene.locked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    Text(scene.label).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Gate.Text.primary).shadow(color: .black, radius: 1.5, y: 1)
                .padding(.horizontal, 6)
            }
        }
        .overlay(alignment: .top) { if scene.changed { Gate.Voice.prism.frame(height: 2) } }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isCurrent || scene.locked ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1))
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
