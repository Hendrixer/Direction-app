import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. Cut history and changelog (33): every cut since Assembly,
// oldest at the bottom, and what each answer changed against the cut before.

extension FilmModel {
    /// Maps a moment in one cut to the same picture in another, through the source footage.
    func mapTime(_ t: Double, from a: DirectionCore.Sequence, to b: DirectionCore.Sequence) -> Double? {
        let base = { (s: DirectionCore.Sequence) in s.clips.filter { $0.kind == .video && $0.layer == 0 } }
        guard let clip = base(a).first(where: { t >= $0.start.seconds - 0.001 && t <= $0.end.seconds + 0.001 }), let asset = clip.assetID else { return nil }
        let source = clip.sourceRange.start.seconds + (t - clip.start.seconds) * clip.speed
        guard let match = base(b).first(where: { $0.assetID == asset && source >= $0.sourceRange.start.seconds - 0.001 && source <= $0.sourceRange.end.seconds + 0.001 }) else { return nil }
        return match.start.seconds + (source - match.sourceRange.start.seconds) / max(0.0001, match.speed)
    }
    /// Where a change sat in the cut before: mapped through the footage, else the note's own anchor.
    func wasRange(_ c: ReviewComment, in cut: ReviewCut) -> ClosedRange<Double>? {
        let before = cutBefore(cut)
        if let r = answerRange(c, in: cut), let now = cutSequence(cut), let old = cutSequence(before),
           let a = mapTime(r.lowerBound, from: now, to: old), let b = mapTime(r.upperBound, from: now, to: old), b >= a { return a...b }
        guard c.cutID == before?.id else { return nil }
        if let r = c.range { return r.start.seconds...r.end.seconds }
        if let t = c.time { return t.seconds...t.seconds }
        return nil
    }
    func lockedScene(for c: ReviewComment, in cut: ReviewCut) -> DailiesScene? {
        guard let r = answerRange(c, in: cut), let seq = cutSequence(cut) else { return scene(c.sceneID).flatMap { $0.locked ? $0 : nil } }
        let clips = seq.clips.filter { $0.kind == .video && $0.layer == 0 && $0.end.seconds > r.lowerBound && $0.start.seconds < max(r.upperBound, r.lowerBound + 0.01) }
        return clips.compactMap { dailies.scene(for: $0.assetID) }.first { $0.locked }
    }
    func sceneTitle(at t: Double, in cut: ReviewCut) -> String? {
        guard let seq = cutSequence(cut), let clip = seq.clips.first(where: { $0.kind == .video && $0.layer == 0 && t >= $0.start.seconds && t < $0.end.seconds }) ?? seq.clips.last else { return nil }
        return dailies.scene(for: clip.assetID)?.title
    }
}

struct CutHistoryView: View {
    @Bindable var model: FilmModel
    private var state: ChangesState { model.changes }

    var body: some View {
        HStack(spacing: 0) {
            CutList(model: model).frame(width: 300).frame(maxHeight: .infinity, alignment: .top).hairlineBorder(.trailing)
            Changelog(model: model).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(model.historyCut?.id)
                .transition(.opacity)
        }
        .background(Gate.Surface.ground)
        .animation(gateAnimation(Gate.Motion.settle), value: model.historyCut?.id)
    }
}

// MARK: Cut list

private struct CutListItem: Identifiable {
    enum Kind { case cut(ReviewCut), event(String) }
    var id: String
    var kind: Kind
    var time: Double
}

struct CutList: View {
    @Bindable var model: FilmModel

    private var items: [CutListItem] {
        var out = model.cuts.map { CutListItem(id: $0.id, kind: .cut($0), time: $0.createdAt) }
        // Picture locks and unlocks are their own rows; scene locks too.
        for e in model.events {
            switch e.summary {
            case "Locked picture": out.append(.init(id: "event-\(e.id)", kind: .event("Picture locked"), time: e.createdAt))
            case "Unlocked picture": out.append(.init(id: "event-\(e.id)", kind: .event("Picture unlocked"), time: e.createdAt))
            case "Locked a scene": out.append(.init(id: "event-\(e.id)", kind: .event("Scene locked"), time: e.createdAt))
            case "Unlocked a scene": out.append(.init(id: "event-\(e.id)", kind: .event("Scene unlocked"), time: e.createdAt))
            // The director's look applies to every cut, so it's an event, not a cut (looks.md › 63).
            case let s where e.kind == "look.updated": out.append(.init(id: "event-\(e.id)", kind: .event(s), time: e.createdAt))
            // A graphic's words, fixed by the director without a new cut (graphics.md › 64).
            case let s where e.kind == "graphic.words": out.append(.init(id: "event-\(e.id)", kind: .event(s), time: e.createdAt))
            default: break
            }
        }
        if let at = model.directing.pictureLockedAt, !out.contains(where: { if case .event("Picture locked") = $0.kind { abs($0.time - at) < 2 } else { false } }) {
            out.append(.init(id: "event-picture-lock", kind: .event("Picture locked"), time: at))
        }
        return out.sorted { $0.time > $1.time }
    }

    var body: some View {
        let list = items
        let lastCutID = list.last { if case .cut = $0.kind { true } else { false } }?.id
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button { model.showAnswers() } label: { SmallIconLabel("Answers", icon: "chevron.left", size: 9) }
                    .buttonStyle(.gate(.ghost, .small)).help("Back to the answers (esc)")
                Spacer()
                SectionLabel(model.cuts.count == 1 ? "1 cut" : "\(model.cuts.count) cuts")
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list) { item in
                        switch item.kind {
                        case .cut(let cut): cutRow(cut, isLast: cut.id == lastCutID)
                        case .event(let text): eventRow(text, time: item.time)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cuts, newest first")
    }

    private func cutRow(_ cut: ReviewCut, isLast: Bool) -> some View {
        let on = model.historyCut?.id == cut.id, latest = cut.id == model.latestCut?.id
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(latest ? AnyShapeStyle(Gate.Voice.prism) : AnyShapeStyle(Gate.Text.disabled))
                .frame(width: 9, height: 9).rotationEffect(.degrees(45)).padding(.top, 5).padding(.leading, 5).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cut.name).font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary)
                    Spacer(minLength: 6)
                    Text(ChangesFormat.when(cut.createdAt)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                }
                .frame(minHeight: 21)
                Text(summary(cut)).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1).frame(minHeight: 17)
            }
        }
        .padding(10)
        .background { if on { RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.subtle, lineWidth: 1)) } }
        .overlay(alignment: .topLeading) { if !isLast { Gate.Line.strong.frame(width: 1).padding(.top, 26).padding(.bottom, -14).padding(.leading, 19) } }
        .contentShape(Rectangle())
        .onTapGesture { model.changes.historyCutID = cut.id; model.changes.historyNoteID = nil }
        .contextMenu {
            Button("Screen \(cut.name)") { model.watch(cut); model.go(.screening) }
            Button("Watch \(cut.name)") { model.watch(cut) }
            if let before = model.cutBefore(cut) { Button("Compare with \(before.name)") { model.compareWholeCuts(cut) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func eventRow(_ text: String, time: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: text.hasPrefix("Changed the look") ? "camera.filters" : text.contains("the words of") ? "character.cursor.ibeam" : text.contains("unlocked") ? "lock.open" : "lock.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(Gate.Text.tertiary).frame(width: 22)
            Text(text).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary)
            Spacer(minLength: 6)
            Text(ChangesFormat.when(time)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func summary(_ cut: ReviewCut) -> String {
        var parts: [String] = []
        let answers = model.answers(in: cut).count
        let before = model.cutBefore(cut)
        if before == nil || cut.name == "Assembly" {
            let circles = model.circledCount
            parts.append(circles == 1 ? "From 1 circle" : "From \(circles) circles")
        } else {
            parts.append(answers == 1 ? "1 answer" : "\(answers) answers")
        }
        if let d = model.cutDuration(cut) {
            parts.append(Timecode.duration(d))
            if let p = model.cutDuration(before) { parts.append(ChangesFormat.signedSeconds(d - p)) }
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: Changelog

struct Changelog: View {
    @Bindable var model: FilmModel
    private var cut: ReviewCut? { model.historyCut }
    private var before: ReviewCut? { model.cutBefore(cut) }
    private var rows: [ReviewComment] { model.answers(in: cut) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            if before == nil || cut?.name == "Assembly" { circles } else { table }
        }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(before.map { "\($0.name) \u{2192} \(cut?.name ?? "")" } ?? (cut?.name ?? "History")).font(Gate.Font.brandL).foregroundStyle(Gate.Text.primary).lineLimit(1)
                Spacer(minLength: 8)
                if before != nil {
                    Button { if let cut { model.compareWholeCuts(cut) } } label: { Label("Compare whole cuts", systemImage: "rectangle.split.2x1") }
                        .buttonStyle(.gate(.normal)).help("Both cuts side by side, on one playhead")
                }
                if !rows.isEmpty {
                    Button {
                        if let cut, cut.id != model.watchedCut?.id { model.watch(cut) }
                        model.openChangesReel()
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill"); Text("Play changes"); CountTag(Timecode.duration(model.changesDuration(in: cut))) }
                    }
                    .buttonStyle(.gate(.normal)).help("Play only what moved (⇧⌘P)")
                }
            }
            Text(subline).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(2).frame(minHeight: 17)
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
        .hairlineBorder(.bottom)
    }

    private var subline: String {
        guard let cut else { return "" }
        guard let before, cut.name != "Assembly" else { return "Built from your circles \u{00B7} \(ChangesFormat.dayAndTime(cut.createdAt))" + (model.cutDuration(cut).map { " \u{00B7} \(Timecode.duration($0))" } ?? "") }
        var s = "\(rows.count == 1 ? "1 change" : "\(rows.count) changes") from your notes on \(before.name) \u{00B7} built \(ChangesFormat.dayAndTime(cut.createdAt))"
        if let a = model.cutDuration(before), let b = model.cutDuration(cut) { s += " \u{00B7} \(Timecode.duration(a)) \u{2192} \(Timecode.duration(b))" }
        return s + ". Reverting a change reopens its note for your next turnover."
    }

    // MARK: Table

    private var table: some View {
        ScrollView {
            VStack(spacing: 0) {
                LogRowLayout {
                    Text("Note"); Color.clear; Text("Change"); Text("In \(cut?.name ?? "")"); Text("Delta"); Color.clear
                }
                .font(Gate.Font.label).tracking(0.74).textCase(.uppercase).foregroundStyle(Gate.Text.disabled)
                .padding(.horizontal, 22).padding(.vertical, 8).frame(height: 30)
                .hairlineBorder(.bottom)
                ForEach(rows) { c in ChangeRow(model: model, note: c, cut: cut!) }
                if rows.isEmpty {
                    Text("No changes in \(cut?.name ?? "this cut").").font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(22)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Changes in \(cut?.name ?? "")")
    }

    // MARK: Assembly

    private var circles: some View {
        let takes = model.dailies.takes.values.filter(\.circled).sorted { ($0.setupCode ?? "", $0.code ?? "") < ($1.setupCode ?? "", $1.code ?? "") }
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(takes) { t in
                    LogRowLayout {
                        RingMark(size: 10)
                        Thumbnail(path: model.asset(t.assetID)?.thumbnailPath, art: FootageArt.forScene(model.scene(t.sceneID)?.number ?? 1))
                            .frame(width: 120, height: 40).clipShape(RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            Text([t.setupCode, t.code].compactMap { $0 }.joined(separator: " ")).foregroundStyle(Gate.Text.primary)
                            Text(t.caption ?? "").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                        }
                        Text(model.scene(t.sceneID)?.label ?? "").font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                        Color.clear
                        Color.clear
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 22).padding(.vertical, 11).hairlineBorder(.bottom)
                }
            }
        }
    }
}

/// 30 · 120 · flexible · 160 · 64 · 160, gap 14: the changelog grid.
struct LogRowLayout: Layout {
    static let fixed: [CGFloat?] = [30, 120, nil, 160, 64, 160]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let widths = columnWidths(width)
        let height = zip(subviews, widths).map { $0.sizeThatFits(.init(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (i, (view, w)) in zip(subviews, columnWidths(bounds.width)).enumerated() {
            let size = view.sizeThatFits(.init(width: w, height: nil))
            let last = i == subviews.count - 1
            view.place(at: CGPoint(x: last ? x + w - min(w, size.width) : x, y: bounds.midY), anchor: .leading, proposal: .init(width: w, height: nil))
            x += w + 14
        }
    }
    private func columnWidths(_ total: CGFloat) -> [CGFloat] {
        let fixed = Self.fixed.compactMap { $0 }.reduce(0, +) + 14 * 5
        return Self.fixed.map { $0 ?? max(80, total - fixed) }
    }
}

struct ChangeRow: View {
    @Bindable var model: FilmModel
    let note: ReviewComment
    let cut: ReviewCut

    private var answer: NoteAnswer? { model.answer(note, in: cut) }
    private var revert: FeedbackReply? { model.answer(note, in: cut)?.cutID == note.latestAnswer?.cutID ? model.revertReply(note) : nil }
    private var selected: Bool { model.changes.historyNoteID == note.id }

    var body: some View {
        LogRowLayout {
            number
            AnswerThumb(model: model, note: note, prism: false).frame(width: 120, height: 40).opacity(revert != nil ? 0.45 : 1)
            what.opacity(revert != nil ? 0.45 : 1)
            ranges
            HStack(spacing: 6) {
                Text(model.deltaText(note, in: cut, picked: true)).font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                // A made clip's provenance stays with the cut that introduced it (made-media.md).
                if let made = model.made.introduced(note, in: cut, film: model) { MadeChip(film: model, record: made, place: "history-" + cut.id) }
            }
            action
        }
        .font(.system(size: 13))
        .padding(.horizontal, 22).padding(.vertical, 11)
        .background(selected ? Gate.Surface.panel : .clear)
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            model.changes.historyNoteID = note.id
            // Double-click plays that change with handles.
            if NSApp.currentEvent?.clickCount == 2 {
                if cut.id != model.watchedCut?.id { model.watch(cut) }
                model.openChangesReel(from: note.id)
            }
        }
        .contextMenu {
            Button("Play This Change") { if cut.id != model.watchedCut?.id { model.watch(cut) }; model.openChangesReel(from: note.id) }
            if revert == nil { Button("Revert This Change\u{2026}") { model.changes.revertNoteID = note.id }.disabled(revertBlocker != nil) }
            else { Button("Put Back") { model.putBack(note.id) }.disabled(note.noteState == .turnedOver) }
            Button("Show Note in Answers") { model.watch(cut); model.showAnswers(); model.selectedAnswerNoteID = note.id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var number: some View {
        if note.isUnasked { GemMark(size: 8, solid: true).accessibilityLabel("Unasked") }
        else { Text(note.number.map(String.init) ?? "").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Voice.director) }
    }

    private var headline: String {
        guard let a = answer else { return note.text }
        if let pick = a.pick, let o = a.options?.first(where: { $0.label == pick }) { return "Option \(pick): \(o.summary.prefix(1).lowercased() + o.summary.dropFirst())." }
        return ChangesFormat.headline(a.summary)
    }

    private var what: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headline).foregroundStyle(Gate.Text.primary).lineLimit(1).help(answer?.summary ?? "")
            Text(sub).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
        }
    }
    private var sub: String {
        if let r = revert { return "Revert asked by you \u{00B7} \(ChangesFormat.time(r.createdAt)) \u{00B7} next turnover" }
        return model.answerRange(note, in: cut).flatMap { model.sceneTitle(at: $0.lowerBound, in: cut) } ?? model.scene(note.sceneID)?.title ?? ""
    }

    private var ranges: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let r = model.answerRange(note, in: cut) { Text(Timecode.range(r.lowerBound, r.upperBound, fps: model.fps)).foregroundStyle(Gate.Text.tertiary) }
            else { Text("Whole cut").foregroundStyle(Gate.Text.tertiary) }
            if let w = model.wasRange(note, in: cut) { Text("was \(Timecode.range(w.lowerBound, w.upperBound, fps: model.fps))").foregroundStyle(Gate.Text.disabled) }
            else { Text("new").foregroundStyle(Gate.Text.disabled) }
        }
        .font(.system(size: 11, design: .monospaced)).lineSpacing(3).lineLimit(1).fixedSize()
    }

    /// Why this change can't be reverted right now, if it can't.
    private var revertBlocker: String? {
        if model.isPictureLocked { return "Unlock picture to revert" }
        if let s = model.lockedScene(for: note, in: cut) { return "Unlock \(s.label) to revert" }
        if cut.id != note.latestAnswer?.cutID { return "A later cut changed this again" }
        if model.status(note, in: cut) == .reopened { return "This note is already reopened" }
        return nil
    }

    @ViewBuilder private var action: some View {
        if revert != nil {
            if note.noteState == .turnedOver {
                Text("In your turnover").font(Gate.Font.small).foregroundStyle(Gate.Text.disabled)
            } else {
                Button { model.putBack(note.id) } label: { SmallIconLabel("Put back", icon: "arrow.uturn.backward") }
                    .buttonStyle(.gate(.normal, .small)).help("Keep the change as the editor made it")
            }
        } else {
            Button { model.changes.revertNoteID = note.id } label: { SmallIconLabel("Revert this change", icon: "arrow.uturn.backward") }
                .buttonStyle(.gate(.ghost, .small))
                .disabled(revertBlocker != nil)
                .help(revertBlocker ?? "Ask the editor to put this back (⌘⌫)")
                .popover(isPresented: Binding(get: { model.changes.revertNoteID == note.id }, set: { if !$0 { model.changes.revertNoteID = nil } }), arrowEdge: .bottom) {
                    RevertPopover(model: model, note: note, cut: cut)
                }
        }
    }

    private var accessibilityText: String {
        var parts = [note.isUnasked ? "Unasked" : "Note \(note.number.map(String.init) ?? "")", answer?.summary ?? note.text]
        if let s = model.answerRange(note, in: cut).flatMap({ model.sceneTitle(at: $0.lowerBound, in: cut) }) { parts.append(s) }
        if let r = model.answerRange(note, in: cut) { parts.append("in \(cut.name) from \(Timecode.format(r.lowerBound, fps: model.fps)) to \(Timecode.format(r.upperBound, fps: model.fps))") }
        if let w = model.wasRange(note, in: cut) { parts.append("was \(Timecode.format(w.lowerBound, fps: model.fps)) to \(Timecode.format(w.upperBound, fps: model.fps))") }
        parts.append(model.deltaText(note, in: cut, picked: true))
        if revert != nil { parts.append("Revert asked") }
        return parts.joined(separator: ", ")
    }
}

/// "Revert note 5's change in Cut 4?" The note goes back to the sheet and into the next turnover.
struct RevertPopover: View {
    var model: FilmModel
    let note: ReviewComment
    let cut: ReviewCut
    var body: some View {
        let n = note.number.map(String.init) ?? ""
        let before = model.cutBefore(cut)?.name ?? "the cut before"
        VStack(alignment: .leading, spacing: 10) {
            Text("Revert note \(n)\u{2019}s change in \(cut.name)?").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
            Text("This reopens note \(n) and asks the editor to put it back the way it was in \(before). It goes into your next turnover; nothing changes until then.")
                .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { model.changes.revertNoteID = nil }.buttonStyle(.gate(.ghost)).keyboardShortcut(.cancelAction)
                Button("Revert") { model.revertChange(note.id) }.buttonStyle(.gate(.normal)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
