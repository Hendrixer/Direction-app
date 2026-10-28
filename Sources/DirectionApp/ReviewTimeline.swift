import SwiftUI
import DirectionCore

/// A playback scrubber with review markers, never an editing timeline.
struct ReviewTimeline: View {
    @Bindable var model: EditorModel
    @State private var drawingRangeAnchor: Double?
    @State private var handleDragOrigin: RangeOrigin?

    private struct RangeOrigin {
        let start: Double
        let end: Double
    }
    private var markers: [(comment: ReviewComment, time: Double)] {
        guard let sequence = model.sequence, let revision = model.displayedProject?.editRevision else { return [] }
        return model.comments.compactMap { c in ReviewAnchoring.markerTime(c, in: sequence, revision: revision).map { (c, $0) } }
    }
    private struct MarkerGroup: Identifiable {
        var items: [(comment: ReviewComment, time: Double)]
        var id: String { items[0].comment.id }
        var time: Double { items[0].time }
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
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 16), duration = max(model.duration, 0.01)
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.inset)
                        .overlay { Capsule().strokeBorder(Palette.line, lineWidth: 1) }
                        .frame(height: 10)
                        .position(x: geometry.size.width / 2, y: 31)
                        .allowsHitTesting(false)
                    if model.commentScope == "range", model.selectionEnd > model.selectionStart {
                        let start = min(duration, max(0, model.selectionStart))
                        let end = max(start, min(duration, model.selectionEnd))
                        Capsule().fill(Palette.text.opacity(0.12))
                            .overlay { Capsule().strokeBorder(Palette.text.opacity(0.35), lineWidth: 0.5) }
                            .frame(width: max(2, width * (end - start) / duration), height: 14)
                            .position(x: 8 + width * (start + (end - start) / 2) / duration, y: 31)
                            .allowsHitTesting(false)
                    }
                    Slider(value: Binding(get: { min(model.position, duration) }, set: { model.seek($0) }), in: 0...duration,
                           onEditingChanged: { editing in
                               if editing { model.player.pause(); model.playing = false }
                               else if model.duration > 0 { model.beginMomentComment(at: model.position) }
                           })
                        .controlSize(.small).tint(Palette.text)
                        .accessibilityLabel("Seek video").disabled(model.duration == 0)
                        .frame(height: 24)
                        .position(x: geometry.size.width / 2, y: 31)
                    ForEach(0...8, id: \.self) { tick in
                        Rectangle().fill(Palette.faint.opacity(0.65))
                            .frame(width: 1, height: tick.isMultiple(of: 2) ? 5 : 3)
                            .position(x: 8 + width * CGFloat(tick) / 8, y: 46)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                    ForEach(groups(width: width, duration: duration)) { group in
                        Group {
                            if group.items.count == 1, let item = group.items.first {
                                Button { model.seekComment(item.comment) } label: {
                                    Image(systemName: "bubble.left.fill").font(.system(size: 10))
                                        .foregroundStyle(model.selectedCommentID == item.comment.id ? Palette.text : item.comment.status == "accepted" ? Palette.faint : Palette.muted)
                                        .frame(width: 24, height: 21)
                                        .background(model.selectedCommentID == item.comment.id ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 5))
                                        .overlay {
                                            if model.selectedCommentID == item.comment.id {
                                                RoundedRectangle(cornerRadius: 5)
                                                    .strokeBorder(Palette.text.opacity(0.28), lineWidth: 0.5)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).help(item.comment.text)
                                    .accessibilityLabel("Comment at \(timecode(item.time)): \(item.comment.text)")
                            } else {
                                Menu {
                                    ForEach(group.items, id: \.comment.id) { item in
                                        Button(timecode(item.time) + " · " + item.comment.text) { model.seekComment(item.comment) }
                                    }
                                } label: {
                                    Text("\(group.items.count)").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Palette.muted).frame(width: 24, height: 20)
                                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
                                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line, lineWidth: 0.5) }
                                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                    .accessibilityLabel("\(group.items.count) comments near " + timecode(group.time))
                            }
                        }.position(x: 8 + width * min(1, max(0, group.time / duration)), y: 9)
                    }
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
            }.frame(height: 62)
            HStack(spacing: 12) {
                Button { model.togglePlayback() } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .offset(x: model.playing ? 0 : 1)
                        .frame(width: 38, height: 38)
                }.buttonStyle(TransportPlayStyle())
                    .accessibilityLabel(model.playing ? "Pause" : "Play")
                    .disabled(model.duration == 0 || model.isPreparing)
                HStack(spacing: 7) {
                    Text(timecode(model.position)).foregroundStyle(Palette.text)
                    Text("/").foregroundStyle(Palette.faint)
                    Text(timecode(model.duration)).foregroundStyle(Palette.muted)
                }.font(.system(size: 11, weight: .medium, design: .monospaced)).fixedSize()
                Spacer(minLength: 4)
                if model.commentScope == "range" {
                    Text(timecode(model.selectionStart) + " – " + timecode(model.selectionEnd))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.muted).lineLimit(1)
                    IconButton(symbol: "xmark", label: "Clear comment range") { model.beginMomentComment(at: model.position) }
                } else if model.commentScope == "cut" {
                    Text("Whole video").font(.system(size: 11)).foregroundStyle(Palette.muted)
                } else {
                    Button(action: selectRangeAtPlayhead) {
                        Label("Range", systemImage: "arrow.left.and.right").font(.system(size: 11))
                    }.buttonStyle(QuietButton()).disabled(model.duration == 0)
                        .help("Select a comment range, then drag either end on the seek bar")
                        .accessibilityLabel("Select comment range")
                }
                IconButton(symbol: "text.bubble", label: "Add comment", selected: model.panel == .feedback, action: focusComment)
                    .disabled(model.duration == 0)
            }
        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 12)
            .directionSurface(cornerRadius: 10, elevated: true)
    }

    private func rangeStarter(width: CGFloat, duration: Double) -> some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Palette.muted)
            .frame(width: 24, height: 16)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Palette.text.opacity(0.22), lineWidth: 0.5)
            }
            .frame(width: 28, height: 24).contentShape(Rectangle())
            .gesture(
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
            .help("Drag left or right to select a comment range")
            .accessibilityLabel("Drag to select a comment range")
            .accessibilityAction(named: Text("Select a comment range")) { selectRangeAtPlayhead() }
            .position(x: 8 + width * min(1, max(0, (drawingRangeAnchor ?? model.position) / duration)), y: 50)
    }

    private func rangeHandle(isStart: Bool, width: CGFloat, duration: Double) -> some View {
        let time = isStart ? model.selectionStart : model.selectionEnd
        let compact = width * max(0, model.selectionEnd - model.selectionStart) / duration < 28
        // Short ranges still need two independent targets on long cuts.
        let gripY: CGFloat = compact ? (isStart ? 16 : 48) : 31
        return HStack(spacing: 2) {
            Capsule().fill(Color.black.opacity(0.65)).frame(width: 1, height: 10)
            Capsule().fill(Color.black.opacity(0.65)).frame(width: 1, height: 10)
        }
        .frame(width: 10, height: compact ? 20 : 26)
        .background(
            LinearGradient(colors: [Color(white: 0.95), Color(white: 0.58), Color(white: 0.83)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 3)
        )
        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .background {
            if compact {
                Rectangle().fill(Palette.muted.opacity(0.55))
                    .frame(width: 1, height: abs(31 - gripY))
                    .offset(y: (31 - gripY) / 2).allowsHitTesting(false)
            }
        }
        .frame(width: 28, height: compact ? 24 : 38).contentShape(Rectangle())
        .gesture(
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
        .accessibilityLabel(isStart ? "Comment range start" : "Comment range end")
        .accessibilityValue(timecode(time))
        .accessibilityAdjustableAction { direction in
            let frame = 1 / max(1, model.sequence?.frameRate.value ?? 30)
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
        let minimum = min(model.duration, 1 / max(1, model.sequence?.frameRate.value ?? 30))
        let start = isStart ? min(max(0, origin.start + delta), max(0, origin.end - minimum)) : origin.start
        let end = isStart ? origin.end : min(model.duration, max(origin.start + minimum, origin.end + delta))
        model.selectCommentRange(from: start, to: end, focus: focus)
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
            model.player.pause()
            model.playing = false
            model.requestCommentFocus()
        } else {
            model.beginMomentComment(at: model.position)
        }
    }
}

private struct TransportPlayStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(white: 0.09))
            .background {
                Circle().fill(LinearGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(white: 0.79), location: 0.45),
                    .init(color: Color(white: 0.95), location: 0.52),
                    .init(color: Color(white: 0.61), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(enabled ? 1 : 0.3)
    }
}
