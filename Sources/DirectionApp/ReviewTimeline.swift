import SwiftUI
import AppKit
import DirectionCore

/// A source-backed overview of the cut. It is navigation and note anchoring, not an editing timeline.
struct ReviewTimeline: View {
    @Bindable var model: EditorModel
    var steelPlayback = false
    @State private var drawingRangeAnchor: Double?
    @State private var handleDragOrigin: RangeOrigin?
    @FocusState private var seekFocused: Bool

    private struct RangeOrigin {
        let start: Double
        let end: Double
    }

    private struct MarkerGroup: Identifiable {
        var items: [(comment: ReviewComment, time: Double)]
        var id: String { items[0].comment.id }
        var time: Double { items[0].time }
    }

    private var frameRate: Double { model.sequence?.frameRate.value ?? 30 }

    private var markers: [(comment: ReviewComment, time: Double)] {
        guard let sequence = model.sequence, let revision = model.displayedProject?.editRevision else { return [] }
        return model.comments.compactMap { comment in
            ReviewAnchoring.markerTime(comment, in: sequence, revision: revision).map { (comment, $0) }
        }
    }

    private func groups(width: CGFloat, duration: Double) -> [MarkerGroup] {
        var result: [MarkerGroup] = []
        for item in markers.sorted(by: { $0.time < $1.time }) {
            if let last = result.last, (item.time - last.time) / duration * width < 26 {
                result[result.count - 1].items.append(item)
            } else { result.append(MarkerGroup(items: [item])) }
        }
        return result
    }

    var body: some View {
        HStack(spacing: Gate.Space.s3) {
            Button { model.togglePlayback() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .offset(x: model.playing ? 0 : 0.5)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(TransportPlayStyle(steel: steelPlayback))
            .accessibilityLabel(model.playing ? "Pause" : "Play")
            .disabled(model.duration == 0 || model.isPreparing)

            VStack(alignment: .leading, spacing: Gate.Space.s1) {
                Text(timecode(model.position, frameRate: frameRate, frames: !model.playing))
                    .foregroundStyle(Gate.Text.primary)
                Text("/ " + timecode(model.duration, frameRate: frameRate, frames: false))
                    .foregroundStyle(Gate.Text.tertiary)
            }
            .font(Gate.Font.timecode).monospacedDigit()
            .frame(minWidth: 68, alignment: .leading)

            sceneStrip.frame(minWidth: 140, maxWidth: .infinity)

            noteControls
        }
        .padding(.horizontal, Gate.Space.s4)
        .padding(.top, Gate.Space.s1)
        .padding(.bottom, Gate.Space.s2)
    }

    private var sceneStrip: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 16)
            let duration = max(model.duration, 0.01)
            ZStack(alignment: .leading) {
                SceneTileStrip(
                    clips: model.sequence?.clips ?? [],
                    assets: model.displayedProject?.assets ?? [],
                    duration: model.duration
                )
                .equatable()
                .frame(width: width, height: 24)
                .position(x: geometry.size.width / 2, y: 28)
                .allowsHitTesting(false).accessibilityHidden(true)

                seekTarget(width: width, duration: duration)
                    .frame(width: geometry.size.width, height: 32)
                    .position(x: geometry.size.width / 2, y: 28)

                if model.commentScope == "range", model.selectionEnd > model.selectionStart {
                    rangeSelection(width: width, duration: duration)
                }

                playhead(width: width, duration: duration)

                markerButtons(width: width, duration: duration)

                if model.commentScope == "range", drawingRangeAnchor == nil {
                    rangeHandle(isStart: true, width: width, duration: duration)
                    rangeHandle(isStart: false, width: width, duration: duration)
                }
                if model.duration > 0, model.commentScope != "cut",
                   model.commentScope != "range" || drawingRangeAnchor != nil {
                    rangeStarter(width: width, duration: duration)
                }
            }
            .coordinateSpace(name: "commentSeekRail")
        }
        .frame(height: 60)
    }

    private func seekTarget(width: CGFloat, duration: Double) -> some View {
        Color.clear.contentShape(Rectangle())
            // Recognize pointer edits alongside macOS's editable keyboard focus.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("commentSeekRail"))
                    .onChanged { value in
                        guard model.duration > 0 else { return }
                        model.player.pause(); model.playing = false
                        model.seek(ReviewStripLayout.time(at: value.location.x - 8, width: width, duration: duration))
                    }
                    .onEnded { value in
                        guard model.duration > 0 else { return }
                        model.beginMomentComment(at: ReviewStripLayout.time(at: value.location.x - 8, width: width, duration: duration))
                    }
            )
            .focusable(model.duration > 0, interactions: .edit)
            .focused($seekFocused)
            .focusEffectDisabled()
            .overlay {
                if seekFocused {
                    RoundedRectangle(cornerRadius: Gate.Radius.frame)
                        .strokeBorder(Gate.Text.primary, lineWidth: 2).allowsHitTesting(false)
                }
            }
            .onKeyPress(.leftArrow) { keyboardSeek(-1); return .handled }
            .onKeyPress(.rightArrow) { keyboardSeek(1); return .handled }
            .onKeyPress(.return) { focusComment(); return .handled }
            .onKeyPress(.space) { model.togglePlayback(); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Seek video")
            .accessibilityValue(
                timecode(model.position, frameRate: frameRate) + " of " +
                timecode(model.duration, frameRate: frameRate, frames: false)
            )
            .accessibilityHint("Use the arrow keys to seek. Press Return to write a note at this moment.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: keyboardSeek(1)
                case .decrement: keyboardSeek(-1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("Note at this moment")) { focusComment() }
            .accessibilityAction(named: Text("Select note range")) { selectRangeAtPlayhead() }
            .help("Click the strip to mark a moment. Drag the playhead grip to select a range.")
    }

    private func playhead(width: CGFloat, duration: Double) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 1).fill(Gate.Text.primary).frame(width: 2, height: 34)
                .overlay { RoundedRectangle(cornerRadius: 1).stroke(.black.opacity(0.6), lineWidth: 0.5) }
            RoundedRectangle(cornerRadius: Gate.Radius.frame).fill(Gate.Text.primary).frame(width: 10, height: 4)
        }
        .frame(width: 10, height: 34)
        .position(x: 8 + width * min(1, max(0, model.position / duration)), y: 27)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func rangeSelection(width: CGFloat, duration: Double) -> some View {
        let start = min(duration, max(0, model.selectionStart))
        let end = max(start, min(duration, model.selectionEnd))
        return RoundedRectangle(cornerRadius: Gate.Radius.frame)
            .fill(Gate.Voice.directorWash)
            .overlay {
                RoundedRectangle(cornerRadius: Gate.Radius.frame)
                    .strokeBorder(Gate.Voice.director.opacity(0.85), lineWidth: 1)
            }
            .frame(width: max(2, width * (end - start) / duration), height: 28)
            .position(x: 8 + width * (start + (end - start) / 2) / duration, y: 28)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func markerButtons(width: CGFloat, duration: Double) -> some View {
        ForEach(groups(width: width, duration: duration)) { group in
            Group {
                if group.items.count == 1, let item = group.items.first {
                    Button { model.seekComment(item.comment) } label: {
                        DirectorPin().fill(Gate.Voice.director)
                            .frame(width: 9, height: 12)
                            .opacity(item.comment.status == "accepted" ? 0.45 : 1)
                            .frame(width: 24, height: 20).contentShape(Rectangle())
                            .background {
                                if model.selectedCommentID == item.comment.id {
                                    RoundedRectangle(cornerRadius: Gate.Radius.frame).fill(Gate.Voice.directorWash)
                                }
                            }
                    }
                    .buttonStyle(.plain).help(item.comment.text)
                    .accessibilityLabel("Note at \(timecode(item.time, frameRate: frameRate)): \(item.comment.text)")
                } else {
                    Menu {
                        ForEach(group.items, id: \.comment.id) { item in
                            Button(timecode(item.time, frameRate: frameRate) + " · " + item.comment.text) {
                                model.seekComment(item.comment)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            DirectorPin().fill(Gate.Voice.director).frame(width: 8, height: 11)
                            Text("\(group.items.count)").font(Gate.Font.caption).foregroundStyle(Gate.Voice.director)
                        }
                        .frame(minWidth: 24, minHeight: 20).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("\(group.items.count) comments near " + timecode(group.time, frameRate: frameRate))
                }
            }
            .position(x: 8 + width * min(1, max(0, group.time / duration)), y: 50)
        }
    }

    private var noteControls: some View {
        HStack(spacing: Gate.Space.s1) {
            if model.commentScope == "range" {
                IconButton(symbol: "xmark", label: "Clear note range") {
                    model.beginMomentComment(at: model.position)
                }
            } else if model.commentScope == "cut" {
                Text("Whole cut").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
            } else {
                Button(action: selectRangeAtPlayhead) {
                    Label("Range", systemImage: "arrow.left.and.right")
                }
                .buttonStyle(QuietButton()).disabled(model.duration == 0)
                .help("Select a comment range, then drag either end on the strip")
                .accessibilityLabel("Select note range")
            }

            IconButton(symbol: "text.bubble", label: "Add note", action: focusComment)
                .disabled(model.duration == 0)
        }
    }

    private func rangeStarter(width: CGFloat, duration: Double) -> some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Gate.Text.secondary)
            .frame(width: 24, height: 12)
            .background(Gate.Surface.raised, in: RoundedRectangle(cornerRadius: Gate.Radius.frame))
            .overlay {
                RoundedRectangle(cornerRadius: Gate.Radius.frame).strokeBorder(Gate.Line.strong, lineWidth: 0.5)
            }
            .frame(width: 28, height: 18).contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("commentSeekRail"))
                    .onChanged { value in
                        if drawingRangeAnchor == nil { drawingRangeAnchor = model.position }
                        guard let anchor = drawingRangeAnchor else { return }
                        let end = anchor + value.translation.width / width * duration
                        model.selectCommentRange(from: anchor, to: end, focus: false)
                    }
                    .onEnded { value in
                        guard let anchor = drawingRangeAnchor else { return }
                        let end = anchor + value.translation.width / width * duration
                        model.selectCommentRange(from: anchor, to: end, focus: true)
                        drawingRangeAnchor = nil
                    }
            )
            .help("Drag left or right to select a note range")
            .accessibilityLabel("Drag to select a note range")
            .accessibilityAction(named: Text("Select a comment range")) { selectRangeAtPlayhead() }
            .position(x: 8 + width * min(1, max(0, (drawingRangeAnchor ?? model.position) / duration)), y: 8)
    }

    private func rangeHandle(isStart: Bool, width: CGFloat, duration: Double) -> some View {
        let time = isStart ? model.selectionStart : model.selectionEnd
        let compact = width * max(0, model.selectionEnd - model.selectionStart) / duration < 28
        // Short ranges still need two independent targets on long cuts.
        let gripY: CGFloat = compact ? (isStart ? 8 : 48) : 28
        return RoundedRectangle(cornerRadius: Gate.Radius.frame)
            .fill(Gate.Voice.director)
            .frame(width: 7, height: compact ? 16 : 26)
            .overlay {
                Capsule().fill(Gate.Voice.directorInk.opacity(0.7)).frame(width: 1, height: 8)
            }
            .background {
                if compact {
                    Rectangle().fill(Gate.Voice.director.opacity(0.65))
                        .frame(width: 1, height: abs(28 - gripY))
                        .offset(y: (28 - gripY) / 2).allowsHitTesting(false)
                }
            }
            .frame(width: 28, height: compact ? 22 : 38).contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("commentSeekRail"))
                    .onChanged { value in
                        if handleDragOrigin == nil {
                            handleDragOrigin = RangeOrigin(start: model.selectionStart, end: model.selectionEnd)
                        }
                        guard let origin = handleDragOrigin else { return }
                        moveRangeHandle(isStart: isStart, origin: origin, delta: value.translation.width / width * duration, focus: false)
                    }
                    .onEnded { _ in
                        model.selectCommentRange(from: model.selectionStart, to: model.selectionEnd, focus: true)
                        handleDragOrigin = nil
                    }
            )
            .help(isStart ? "Drag to adjust the comment range start" : "Drag to adjust the comment range end")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isStart ? "Note range start" : "Note range end")
            .accessibilityValue(timecode(time, frameRate: frameRate))
            .accessibilityAdjustableAction { direction in
                let frame = 1 / max(1, frameRate)
                let delta: Double
                switch direction {
                case .increment: delta = frame
                case .decrement: delta = -frame
                @unknown default: return
                }
                moveRangeHandle(
                    isStart: isStart,
                    origin: RangeOrigin(start: model.selectionStart, end: model.selectionEnd),
                    delta: delta,
                    focus: true
                )
            }
            .position(x: 8 + width * min(1, max(0, time / duration)), y: gripY)
    }

    private func moveRangeHandle(isStart: Bool, origin: RangeOrigin, delta: Double, focus: Bool) {
        let minimum = min(model.duration, 1 / max(1, frameRate))
        let start = isStart ? min(max(0, origin.start + delta), max(0, origin.end - minimum)) : origin.start
        let end = isStart ? origin.end : min(model.duration, max(origin.start + minimum, origin.end + delta))
        model.selectCommentRange(from: start, to: end, focus: focus)
    }

    private func keyboardSeek(_ direction: Double) {
        guard model.duration > 0 else { return }
        model.player.pause(); model.playing = false
        model.seek(model.position + direction / max(1, frameRate))
    }

    private func selectRangeAtPlayhead() {
        guard model.duration > 0 else { return }
        let span = min(1, model.duration)
        let start = min(max(0, model.position), max(0, model.duration - span))
        model.selectCommentRange(from: start, to: start + span, focus: true)
    }

    private func focusComment() {
        if model.commentScope == "range" {
            model.selectCommentRange(from: model.selectionStart, to: model.selectionEnd, focus: true)
        } else if model.commentScope == "cut" {
            model.panel = .feedback
            model.player.pause(); model.playing = false
            model.requestCommentFocus()
        } else {
            model.beginMomentComment(at: model.position)
        }
    }
}

private struct TransportPlayStyle: ButtonStyle {
    var steel = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(steel ? Gate.Component.Button.steelInk : Gate.Text.primary)
            .background {
                if steel { GateSteelSurface(cornerRadius: Gate.Radius.control, pressed: configuration.isPressed) }
                else {
                    RoundedRectangle(cornerRadius: Gate.Radius.control)
                        .fill(configuration.isPressed ? Gate.Surface.panel : Gate.Surface.raised)
                        .overlay { RoundedRectangle(cornerRadius: Gate.Radius.control).strokeBorder(Gate.Line.subtle, lineWidth: 1) }
                }
            }
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Pin, not a speech bubble: the director's shape from the Gate guide.
private struct DirectorPin: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.38),
                      control1: CGPoint(x: rect.width * 0.4, y: rect.height * 0.77),
                      control2: CGPoint(x: rect.minX, y: rect.height * 0.68))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.height * 0.14),
                      control2: CGPoint(x: rect.width * 0.22, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.38),
                      control1: CGPoint(x: rect.width * 0.78, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.height * 0.14))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.height * 0.68),
                      control2: CGPoint(x: rect.width * 0.6, y: rect.height * 0.77))
        path.closeSubpath()
        return path
    }
}

private struct SceneTileStrip: View, Equatable {
    let clips: [Clip]
    let assets: [MediaAsset]
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            let segments = ReviewStripLayout.segments(clips: clips, duration: duration)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Gate.Radius.frame).fill(Gate.Surface.sunken)
                    .overlay { RoundedRectangle(cornerRadius: Gate.Radius.frame).strokeBorder(Gate.Line.subtle, lineWidth: 1) }
                ForEach(segments) { segment in
                    let span = geometry.size.width * (segment.end - segment.start) / max(duration, 0.01)
                    sceneTile(segment, width: max(0, span - 2))
                        .frame(width: max(0, span - 2), height: geometry.size.height)
                        .position(x: geometry.size.width * (segment.start + (segment.end - segment.start) / 2) / max(duration, 0.01),
                                  y: geometry.size.height / 2)
                }
            }
        }
    }

    @ViewBuilder
    private func sceneTile(_ segment: ReviewStripSegment, width: CGFloat) -> some View {
        if let clip = segment.clip {
            let asset = assets.first { $0.id == clip.assetID }
            ZStack(alignment: .leading) {
                Gate.Surface.panel
                if let path = asset?.thumbnailPath, let image = SceneThumbnailCache.image(at: path) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: width, height: 24).clipped().opacity(0.55)
                }
                Color.black.opacity(0.28)
                if width > 20 {
                    let name = clip.name.isEmpty ? (asset?.name ?? "") : clip.name
                    Text(width > 84 ? "\(segment.number ?? 1) \(name)" : "\(segment.number ?? 1)")
                        .font(Gate.Font.caption).foregroundStyle(Gate.Text.primary)
                        .lineLimit(1).padding(.horizontal, Gate.Space.s1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Gate.Radius.frame))
            .overlay { RoundedRectangle(cornerRadius: Gate.Radius.frame).strokeBorder(Gate.Line.subtle, lineWidth: 1) }
        } else {
            Gate.Surface.sunken
                .overlay {
                    if width > 84 {
                        Text("Gap").font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: Gate.Radius.frame).strokeBorder(Gate.Line.subtle, lineWidth: 1) }
        }
    }
}

@MainActor private enum SceneThumbnailCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    static func image(at path: String) -> NSImage? {
        if let cached = images.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        images.setObject(image, forKey: path as NSString)
        return image
    }
}

/// Real visible-source intervals. Gaps stay gaps; hidden lower-layer cuts do not invent scenes.
struct ReviewStripSegment: Identifiable, Equatable {
    var clip: Clip?
    var start: Double
    var end: Double
    var number: Int?
    var id: String { (clip?.id ?? "gap") + "@" + String(start) }
}

enum ReviewStripLayout {
    static func segments(clips: [Clip], duration: Double) -> [ReviewStripSegment] {
        guard duration.isFinite, duration > 0 else { return [] }
        let pictures = clips.filter {
            $0.kind == .video && $0.speed.isFinite && $0.speed > 0 &&
            $0.start.seconds.isFinite && $0.end.seconds.isFinite &&
            $0.end.seconds > 0 && $0.start.seconds < duration && $0.end > $0.start
        }
        guard !pictures.isEmpty else { return [] }
        let boundaries = Set([0.0, duration] + pictures.flatMap {
            [max(0, min(duration, $0.start.seconds)), max(0, min(duration, $0.end.seconds))]
        }).sorted()
        var result: [ReviewStripSegment] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let middle = start + (end - start) / 2
            let visible = pictures.filter { $0.start.seconds <= middle && $0.end.seconds > middle }
                .max { ($0.layer, $0.start.seconds, $0.id) < ($1.layer, $1.start.seconds, $1.id) }
            if let previous = result.last, previous.clip?.id == visible?.id, previous.end == start {
                result[result.count - 1].end = end
            } else {
                result.append(ReviewStripSegment(clip: visible, start: start, end: end))
            }
        }
        var number = 0
        for index in result.indices where result[index].clip != nil {
            number += 1
            result[index].number = number
        }
        return result
    }

    static func time(at offset: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard offset.isFinite, width.isFinite, width > 0, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, Double(offset / width))) * duration
    }
}
