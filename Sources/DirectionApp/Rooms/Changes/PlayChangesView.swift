import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Play changes (31): only the passages that moved, with handles,
// full picture like Screening. Nothing moves during playback except the playhead and time.

struct PlayChangesView: View {
    @Bindable var model: FilmModel
    @State private var dockVisible = true
    @State private var lastMove = Date()

    private var reel: [ClosedRange<Double>] { model.changeReel(in: model.watchedCut) }
    /// The reel ran out: the picture holds on the last frame and the dock offers the way back.
    private var ended: Bool { !model.playingChanges }
    private var current: ReviewComment? { model.playingAnswer }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Gate.Surface.canvas
                picture(in: g.size).position(x: g.size.width / 2, y: g.size.height / 2)
                if !ended { tag.padding(.leading, 24).padding(.top, 76) }
                VStack {
                    Spacer()
                    dock.frame(width: min(1000, g.size.width - 48))
                        .opacity(dockVisible || ended ? 1 : 0)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                overTitlebar
            }
        }
        .onContinuousHover { _ in lastMove = Date(); if !dockVisible { withAnimation(gateAnimation(Gate.Motion.settle)) { dockVisible = true } } }
        .task {
            // The dock hides after 2 s without the pointer moving, like Screening.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if model.playing && !model.isPreview && Date().timeIntervalSince(lastMove) > 2 && dockVisible { withAnimation(gateAnimation(Gate.Motion.settle)) { dockVisible = false } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityStatus)
    }

    // MARK: Picture

    private func picture(in size: CGSize) -> some View {
        let fitted = size.width / max(1, size.height) > model.aspect ? CGSize(width: size.height * model.aspect, height: size.height) : CGSize(width: size.width, height: size.width / model.aspect)
        return PictureView(player: model.isPreview ? nil : model.player, still: model.isPreview ? model.stripScene(at: model.position)?.art ?? .dusk : nil, aspect: model.aspect)
            .frame(width: fitted.width, height: fitted.height)
            .clipShape(Rectangle())
    }

    /// CHANGED · NOTE 3, or HANDLE · CUT 3 PICTURE. Swaps instantly, never animates.
    private var tag: some View {
        HStack(spacing: 7) {
            if !model.inHandle { Gate.Voice.prism.frame(width: 14, height: 2) }
            Text(tagText)
        }
        .font(Gate.Font.timecodeSmall).foregroundStyle(Gate.Text.primary)
        .padding(.horizontal, 8).padding(.vertical, 6).gateGlass(6)
        .transaction { $0.animation = nil }
        .accessibilityLabel(tagText.lowercased())
    }
    private var tagText: String {
        if model.inHandle { return "HANDLE \u{00B7} \(model.cutBefore(model.watchedCut)?.name.uppercased() ?? "OLD") PICTURE" }
        guard let c = current else { return "CHANGED" }
        if c.isUnasked { return "CHANGED \u{00B7} UNASKED" }
        return "CHANGED \u{00B7} NOTE \(c.number.map(String.init) ?? "")"
    }

    // MARK: Titlebar over picture

    private var overTitlebar: some View {
        ZStack {
            TitlebarDragArea()
            HStack(spacing: 10) {
                Color.clear.frame(width: 62, height: 1)
                HStack(spacing: 2) {
                    crumb(model.filmName, color: Gate.Text.primary, weight: .semibold)
                    slash
                    crumb(model.watchedCut?.name ?? "", color: Gate.Text.secondary, weight: .medium)
                    slash
                    crumb("Changes", color: Gate.Text.tertiary, weight: .medium)
                }
                Spacer(minLength: 12)
                EditorPill(state: model.pill, program: model.editorProgram)
                Button { model.closeReel() } label: {
                    HStack(spacing: 6) { Image(systemName: "rectangle.portrait.and.arrow.right"); Text("Stop"); KeyHint("esc") }
                }
                .buttonStyle(.gate(.ghost)).help("Stop playing changes (esc)")
            }
            .padding(.leading, 20).padding(.trailing, 12)
        }
        .frame(height: Gate.Size.titlebar)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }
    private func crumb(_ text: String, color: Color, weight: Font.Weight) -> some View {
        Text(text).font(.system(size: 13, weight: weight)).foregroundStyle(color).padding(.horizontal, 7).lineLimit(1)
    }
    private var slash: some View { Text("/").font(.system(size: 13)).foregroundStyle(Gate.Text.disabled).padding(.horizontal, 2) }

    // MARK: Dock

    private var dock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ended { endCard } else { top; controls }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.top, 10).padding(.bottom, 8)
        .gateGlass(16)
    }

    private var top: some View {
        HStack(spacing: 10) {
            if let c = current {
                if c.isUnasked { GemMark(size: 7, solid: true) } else { Chip(c.number.map(String.init) ?? "", style: .director) }
                Text(sentence(c)).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            reelDots
            Text("\(reelPosition) of \(model.reelAnswers.count)").font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary).monospacedDigit()
        }
        .padding(.leading, 4)
    }
    private func sentence(_ c: ReviewComment) -> AttributedString {
        var head = AttributedString((model.answerSceneTitle(c) ?? "").isEmpty ? "" : (model.answerSceneTitle(c) ?? "") + ". ")
        head.foregroundColor = Gate.Text.primary; head.font = .system(size: 13, weight: .medium)
        var body = AttributedString(model.answer(c, in: model.reviewCut)?.summary ?? "")
        body.foregroundColor = Gate.Text.secondary
        return head + body
    }
    private var reelPosition: Int { (model.reelAnswers.firstIndex { $0.id == current?.id } ?? 0) + 1 }
    private var reelDots: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.reelAnswers.enumerated()), id: \.element.id) { i, _ in
                Capsule().fill(i + 1 == reelPosition ? Gate.Text.primary : i + 1 < reelPosition ? Gate.Steel.ramp[7] : Gate.Surface.hover).frame(width: 18, height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { model.previousChange() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(.gate(.ghost, icon: true)).help("Previous change (←)").accessibilityLabel("Previous change")
            Button { model.togglePlayback() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .medium)) }
                .buttonStyle(.gate(.ghost, icon: true)).help(model.playing ? "Pause (Space)" : "Play (Space)").accessibilityLabel(model.playing ? "Pause" : "Play")
            Button { model.nextChange() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(.gate(.ghost, icon: true)).help("Next change (→)").accessibilityLabel("Next change")
            TimecodeLabel(time: model.position, total: model.changesDuration(in: model.watchedCut), fps: model.fps)
            ChangeStrip(model: model)
            Text("\(Int(model.handleSeconds.rounded())) s handles").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1).fixedSize()
            if let c = current, !model.isPictureLocked {
                Button { model.replyToAnswer(c.id) } label: { SmallIconLabel("Reply", icon: "arrowshape.turn.up.left") }
                    .buttonStyle(.gate(.ghost, .small)).help("Reply (⌘R)")
                accept(c)
            }
        }
    }

    @ViewBuilder private func accept(_ c: ReviewComment) -> some View {
        let options = model.answer(c, in: model.reviewCut)?.options ?? []
        switch model.status(c) {
        case .accepted:
            Label(model.doneLabel(c), systemImage: "checkmark").labelStyle(StatusOKLabelStyle()).padding(.horizontal, 8)
        case .reopened:
            Chip("Reopened", style: .director, mono: false)
        case .unreviewed:
            if options.count > 1 {
                ForEach(options.prefix(2), id: \.label) { o in
                    Button("Use \(o.label)") { model.useOption(c.id, o.label) }.buttonStyle(.gate(.normal)).help("Use option \(o.label) (\(o.label))")
                }
            } else {
                Button { model.acceptAnswerFromChanges(c.id, advance: false) } label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command).help("Accept (Y)")
                    .accessibilityLabel("Accept note \(c.number.map(String.init) ?? "")")
            }
        }
    }

    private var endCard: some View {
        HStack(spacing: 10) {
            let left = model.toReview.count
            Text(left == 0 ? "That\u{2019}s every change. Nothing left to review." : "That\u{2019}s every change. \(left) to review.")
                .font(.system(size: 13)).foregroundStyle(Gate.Text.primary)
            Spacer(minLength: 8)
            Button("Play again") { model.playChanges() }.buttonStyle(.gate(.normal))
            Button("Back to answers") { model.closeReel() }.buttonStyle(.steel).keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.vertical, 4).padding(.leading, 4)
    }

    private var accessibilityStatus: String {
        guard !ended else { return "Played every change" }
        return "Playing changes, change \(reelPosition) of \(model.reelAnswers.count)" + (current?.number.map { ", note \($0)" } ?? "")
    }
}

/// The current passage only: hatched handles either side, changed spans with a prism top edge.
struct ChangeStrip: View {
    var model: FilmModel
    private struct Span: Identifiable { var id: Int; var range: ClosedRange<Double>; var changed: Bool }

    private var passage: ClosedRange<Double>? {
        let reel = model.changeReel(in: model.watchedCut)
        if reel.indices.contains(model.changeIndex) { return reel[model.changeIndex] }
        return reel.first { $0.contains(model.position) } ?? reel.last
    }
    private func spans(_ p: ClosedRange<Double>) -> [Span] {
        let changed = model.reelAnswers.compactMap { model.answerRange($0) }.filter { $0.overlaps(p) }
            .map { max($0.lowerBound, p.lowerBound)...min($0.upperBound, p.upperBound) }.sorted { $0.lowerBound < $1.lowerBound }
        var out: [Span] = [], cursor = p.lowerBound
        for r in changed {
            if r.lowerBound > cursor + 0.01 { out.append(.init(id: out.count, range: cursor...r.lowerBound, changed: false)) }
            if let last = out.last, last.changed, last.range.upperBound >= r.lowerBound { out[out.count - 1].range = last.range.lowerBound...max(last.range.upperBound, r.upperBound) }
            else { out.append(.init(id: out.count, range: max(cursor, r.lowerBound)...max(cursor, r.upperBound), changed: true)) }
            cursor = max(cursor, r.upperBound)
        }
        if p.upperBound > cursor + 0.01 { out.append(.init(id: out.count, range: cursor...p.upperBound, changed: false)) }
        return out
    }

    var body: some View {
        GeometryReader { g in
            if let p = passage {
                let parts = spans(p), total = max(0.001, p.upperBound - p.lowerBound)
                let usable = max(1, g.size.width - CGFloat(max(0, parts.count - 1)) * 2)
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(parts) { s in
                            span(s).frame(width: max(2, usable * (s.range.upperBound - s.range.lowerBound) / total))
                        }
                    }
                    .padding(.vertical, 3)
                    RoundedRectangle(cornerRadius: 1).fill(Gate.Text.primary).frame(width: 2).shadow(color: .black.opacity(0.6), radius: 0.5)
                        .offset(x: g.size.width * max(0, min(1, (model.position - p.lowerBound) / total)) - 1)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in model.pause(); model.seek(p.lowerBound + total * Double(max(0, min(1, v.location.x / g.size.width)))) })
            }
        }
        .frame(height: 30)
        .frame(minWidth: 120)
        .accessibilityLabel("This change and its handles")
    }

    private func span(_ s: Span) -> some View {
        let art = model.stripScene(at: s.range.lowerBound)?.art ?? .dusk
        return ZStack {
            Gate.Surface.panel
            Thumbnail(path: model.stripScene(at: s.range.lowerBound)?.thumbnail, art: art).opacity(s.changed ? 0.85 : 0.5)
            if !s.changed { HandleHatch() }
        }
        .overlay(alignment: .top) { if s.changed { Gate.Voice.prism.frame(height: 2) } }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(s.changed ? Gate.Line.strong : Gate.Line.subtle, lineWidth: 1))
    }
}

/// Dark 135° hatching over handles: 2 pt lines every 5 pt at 45% black.
struct HandleHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width { path.move(to: .init(x: x, y: size.height)); path.addLine(to: .init(x: x + size.height, y: 0)); x += 5 }
            context.stroke(path, with: .color(.black.opacity(0.45)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}
