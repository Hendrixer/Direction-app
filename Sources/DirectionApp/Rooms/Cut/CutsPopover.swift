import SwiftUI
import DirectionCore

// Older cuts open from the cut's name in the crumb (specs/cut.md › Older cuts): every cut since the
// assembly, newest first, with the picture locks and looks between them. Picking one shows it in the Cut
// room, its notes and the answers they got; Compare puts it beside the cut before.

extension FilmModel {
    /// Maps a moment in one cut to the same picture in another, through the source footage.
    func mapTime(_ t: Double, from a: DirectionCore.Sequence, to b: DirectionCore.Sequence) -> Double? {
        let base = { (s: DirectionCore.Sequence) in s.clips.filter { $0.kind == .video && $0.layer == s.storyLayer } }
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
        let clips = seq.clips.filter { $0.kind == .video && $0.layer == seq.storyLayer && $0.end.seconds > r.lowerBound && $0.start.seconds < max(r.upperBound, r.lowerBound + 0.01) }
        return clips.compactMap { dailies.scene(for: $0.assetID) }.first { $0.locked }
    }
    func sceneTitle(at t: Double, in cut: ReviewCut) -> String? {
        guard let seq = cutSequence(cut), let clip = seq.clips.first(where: { $0.kind == .video && $0.layer == seq.storyLayer && t >= $0.start.seconds && t < $0.end.seconds }) ?? seq.clips.last else { return nil }
        return dailies.scene(for: clip.assetID)?.title
    }
    /// Why a change can't be reverted right now, if it can't.
    func revertBlocker(_ c: ReviewComment, in cut: ReviewCut?) -> String? {
        guard let cut else { return "No cut" }
        if isPictureLocked { return "Unlock picture to revert" }
        if let s = lockedScene(for: c, in: cut) { return "Unlock \(s.label) to revert" }
        if cut.id != c.latestAnswer?.cutID { return "A later cut changed this again" }
        if status(c, in: cut) == .reopened { return "This note is already reopened" }
        return nil
    }
    /// "In Cut 4 01:08:00–01:16:20, was 01:12:08–01:21:04 in Cut 3": where a change sits, for its tooltip.
    func changePlace(_ c: ReviewComment, in cut: ReviewCut?) -> String? {
        guard let cut, let r = answerRange(c, in: cut) else { return nil }
        var s = "In \(cut.name) \(Timecode.range(r.lowerBound, r.upperBound, fps: fps))"
        if let w = wasRange(c, in: cut) { s += ", was \(Timecode.range(w.lowerBound, w.upperBound, fps: fps)) in \(cutBefore(cut)?.name ?? "the cut before")" }
        return s
    }
    /// The cut list's line under a cut's name.
    func cutSummary(_ cut: ReviewCut) -> String {
        var parts: [String] = []
        let answers = answers(in: cut).count
        let before = cutBefore(cut)
        if before == nil || cut.name == "Assembly" {
            parts.append(circledCount == 1 ? "From 1 circle" : "From \(circledCount) circles")
        } else {
            if answers > 0 { parts.append(answers == 1 ? "Answered 1 note" : "Answered \(answers) notes") }
        }
        if let d = cutDuration(cut) {
            parts.append(Timecode.duration(d))
            if let p = cutDuration(before) { parts.append(ChangesFormat.signedSeconds(d - p)) }
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}


// MARK: The cuts popover

private struct CutListItem: Identifiable {
    enum Kind { case cut(ReviewCut), event(String) }
    var id: String
    var kind: Kind
    var time: Double
}


struct CutsPopover: View {
    @Bindable var model: FilmModel
    var close: () -> Void
    @State private var hovered: String?

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
            // A new shape, changed by the director with black bars (cut.md › Changing the shape).
            case let s where e.kind == "edit.committed" && s.hasPrefix("Shape: "): out.append(.init(id: "event-\(e.id)", kind: .event(s), time: e.createdAt))
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Cuts")
                Spacer()
                Text("Newest first").font(Gate.Font.small).foregroundStyle(Gate.Text.disabled)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            // As tall as its cuts, scrolling past 420 pt.
            ViewThatFits(in: .vertical) {
                rows(list)
                ScrollView { rows(list) }.frame(maxHeight: 420)
            }
            Text("Every cut is kept.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .hairlineBorder(.top)
        }
        .padding(.bottom, 2)
        .frame(width: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cuts, newest first")
    }

    private func rows(_ list: [CutListItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(list) { item in
                switch item.kind {
                case .cut(let cut): cutRow(cut)
                case .event(let text): eventRow(text, time: item.time)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func cutRow(_ cut: ReviewCut) -> some View {
        let on = model.watchedCut?.id == cut.id, latest = cut.id == model.latestCut?.id
        let before = model.cutBefore(cut)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(latest ? AnyShapeStyle(Gate.Voice.prism) : AnyShapeStyle(Gate.Text.disabled))
                    .frame(width: 8, height: 8).rotationEffect(.degrees(45)).padding(.top, 6).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(cut.name).font(Gate.Font.brandS).foregroundStyle(Gate.Text.primary)
                        Text(ChangesFormat.when(cut.createdAt)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
                        Spacer(minLength: 6)
                        if let d = model.cutDuration(cut) { Text(Timecode.duration(d)).font(Gate.Font.mono).foregroundStyle(Gate.Text.tertiary) }
                    }
                    Text(model.cutSummary(cut)).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                }
            }
            if hovered == cut.id || on {
                HStack(spacing: 6) {
                    Button { close(); model.watch(cut); model.watchThrough() } label: { SmallIconLabel("Watch through", icon: "play.fill", size: 8) }
                        .buttonStyle(.gate(.ghost, .small))
                    if let before {
                        Button { close(); model.watch(cut); model.compareWholeCuts(cut) } label: { SmallIconLabel("Compare with \(before.name)", icon: "rectangle.split.2x1", size: 9) }
                            .buttonStyle(.gate(.ghost, .small)).help("Both cuts side by side, on one playhead")
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background { if on { RoundedRectangle(cornerRadius: 8).fill(Gate.Surface.raised).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Gate.Line.subtle, lineWidth: 1)) } }
        .contentShape(Rectangle())
        .onHover { if $0 { hovered = cut.id } else if hovered == cut.id { hovered = nil } }
        // Picking a cut shows it in the room: its picture, and the answers it gave your notes.
        .onTapGesture { close(); model.watch(cut); model.go(.cut) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(cut.name), \(model.cutSummary(cut))")
        .accessibilityAction { close(); model.watch(cut); model.go(.cut) }
    }

    private func eventRow(_ text: String, time: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: text.hasPrefix("Changed the look") ? "camera.filters" : text.contains("the words of") ? "character.cursor.ibeam" : text.hasPrefix("Shape: ") ? "aspectratio" : text.contains("unlocked") ? "lock.open" : "lock.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(Gate.Text.tertiary).frame(width: 18)
            Text(text).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary)
            Spacer(minLength: 6)
            Text(ChangesFormat.when(time)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Gate.Text.disabled)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .accessibilityElement(children: .combine)
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
