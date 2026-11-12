import SwiftUI
import AppKit
import DirectionCore

// The Cut room's sheet in two parts (specs/cut.md › Answers on the sheet): the notes the editor answered in the
// cut on screen, each with its answer under it, then the notes for the next turnover. Once every answer is
// accepted or replied to, the answered notes fold to one line.

extension FilmModel {
    /// Looking back at an older cut, opened from the crumb, rather than working on the latest.
    var looksBack: Bool { watchedCutID != nil && watchedCut?.id != latestCut?.id }
    /// The answered notes on the sheet: those still to look at, those acted on this visit, or every one when
    /// the answered line is open, or the cut is an older one you're looking back at.
    var sheetAnswers: [ReviewComment] {
        let all = changes.showAllAnswers || looksBack
        return reviewAnswers.filter { all || status($0) == .unreviewed || changes.sticky.contains($0.id) }
    }
    /// The notes under the answers: what goes into the next turnover, and what's with the editor now.
    var sheetNotesBelow: [ReviewComment] {
        let shown = Set(sheetAnswers.map(\.id))
        return sheetNotes.filter { !shown.contains($0.id) }
    }
    /// Answers and notes in the order the sheet shows them: ↑ and ↓ walk this.
    var sheetRows: [ReviewComment] { sheetAnswers + sheetNotesBelow }
    /// "1 accepted · 2 to look at".
    var answersLine: String {
        let left = toReview.count, done = reviewAnswers.count - left
        var parts: [String] = []
        if left > 0 { parts.append("\(left) to look at") }
        if done > 0 { parts.append(left == 0 ? (done == 1 ? "1 answered" : "all \(done) answered") : "\(done) done") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// "Answered in Cut 5 · 2 to look at" above the answered notes; one line once nothing is left to look at.
struct AnsweredHeader: View {
    @Bindable var model: FilmModel
    var body: some View {
        let cut = model.reviewCut?.name ?? "this cut"
        let folded = model.sheetAnswers.isEmpty
        // It folds and opens only once nothing is left to look at, and never on a cut you're looking back at.
        let folds = !model.looksBack && model.toReview.isEmpty
        let line = HStack(spacing: 8) {
            GemMark(size: 6)
            Text("Answered in \(cut)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Gate.Text.secondary)
            Text(model.answersLine).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
            Spacer(minLength: 0)
            if folds {
                Image(systemName: folded ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Gate.Text.disabled)
            }
        }
        .padding(.horizontal, 16).frame(height: 34)
        .contentShape(Rectangle())
        HStack(spacing: 0) {
            Group {
                if folds {
                    Button { withAnimation(gateAnimation(Gate.Motion.settle)) { model.changes.showAllAnswers.toggle() } } label: { line }
                        .buttonStyle(.plain)
                        .help(folded ? "Show every answer in \(cut)" : "Fold the answered notes")
                } else {
                    line.accessibilityAddTraits(.isHeader)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Answered in \(cut), \(model.answersLine)")
            // Everything accepted: the scene tiles, to lock what's right, when the director wants them.
            if model.canLockScenes && !model.changes.lockingScenes {
                Button { withAnimation(gateAnimation(Gate.Motion.glide)) { model.changes.lockingScenes = true } } label: { Label("Lock scenes", systemImage: "lock") }
                    .buttonStyle(.gate(.ghost, .small)).padding(.trailing, 10)
                    .help("Lock the scenes that are right, so the editor won\u{2019}t recut them")
            }
        }
        .hairlineBorder(.bottom)
    }
}

/// "Notes on Cut 5": the notes for the next turnover, under the answered ones.
struct NotesBelowHeader: View {
    var title: String
    var body: some View {
        HStack(spacing: 8) {
            PinMark(size: 8)
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Gate.Text.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).frame(height: 34)
        .hairlineBorder(.bottom)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A note the editor answered in the cut on screen: your words, then the answer under them, with what you can do
/// about it. Done answers stay quiet; a reply opens its thread in place (32).
struct AnsweredNoteRow: View {
    @Bindable var model: FilmModel
    let note: ReviewComment
    @State private var hovered = false

    private var cut: ReviewCut? { model.reviewCut }
    private var status: AnswerStatus { model.status(note) }
    private var answer: NoteAnswer? { model.answer(note, in: cut) }
    private var selected: Bool { model.selectedAnswerNoteID == note.id }
    private var replying: Bool { model.changes.replyingNoteID == note.id }
    private var done: Bool { status != .unreviewed }
    private var partly: Bool { answer?.delta?.lowercased() == "partly" }
    private var revert: FeedbackReply? { answer?.cutID == note.latestAnswer?.cutID ? model.revertReply(note) : nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                number.lineHeight(14, 1.25, mono: true).frame(width: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        words.frame(maxWidth: .infinity, alignment: .leading)
                        if done { doneMark }
                    }
                    reply
                    if !done { actions }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12).padding(.bottom, 13).padding(.leading, 14).padding(.trailing, 16)
            if replying { AnswerThread(model: model, note: note, inset: 50).transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .background(selected || replying || hovered ? Gate.Surface.panel : Color.clear)
        .overlay(alignment: .leading) { if selected { Gate.Voice.agent.frame(width: 2) } }
        .hairlineBorder(.bottom)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // One click selects and cues the change; a double-click plays just this change.
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2, model.answerRange(note) != nil { model.openChangesReel(from: note.id) } else { model.selectAnswer(note, cue: !model.isPreview) }
        }
        .contextMenu { AnswerContextMenu(model: model, note: note) }
        .gatePopover(isPresented: Binding(get: { model.changes.keepingNoteID == note.id }, set: { if !$0 { model.changes.keepingNoteID = nil } }), arrowEdge: .bottom) {
            KeepRulePopover(model: model, note: note, suggestion: answer?.rule) { model.changes.keepingNoteID = nil }
        }
        .gatePopover(isPresented: Binding(get: { model.changes.revertNoteID == note.id && cut != nil }, set: { if !$0 { model.changes.revertNoteID = nil } }), arrowEdge: .bottom) {
            if let cut { RevertPopover(model: model, note: note, cut: cut) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var number: some View {
        if note.isUnasked { GemMark(size: 8, solid: true).padding(.top, 3).accessibilityLabel("Unasked") }
        else { NoteNumber(note: note) }
    }

    /// Your note as you wrote it; an unasked change says so instead.
    @ViewBuilder private var words: some View {
        if note.isUnasked {
            Text("Unasked").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Voice.agent)
        } else {
            Mentions.text(note.text, footage: model.footageNames).font(.system(size: 13)).foregroundStyle(done ? Gate.Text.tertiary : Gate.Text.primary)
                .lineHeight(13, 1.45).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The editor's answer: a picture of what changed, then what it did, with the delta after it.
    private var reply: some View {
        HStack(alignment: .top, spacing: 10) {
            if !done { AnswerThumb(model: model, note: note).frame(width: 72, height: 41) }
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence).font(.system(size: 12.5)).lineHeight(12.5, 1.45).lineLimit(done ? 2 : 4).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(model.changePlace(note, in: cut) ?? plainSentence)
                if let made = model.made.records(for: note, in: cut, film: model).first {
                    // Made picture or sound (made-media.md › Where made things show).
                    MadeChip(film: model, record: made, place: "answer")
                }
            }
        }
        .opacity(done ? 0.7 : 1)
    }

    private var sentence: AttributedString {
        var out = AttributedString()
        if let scene = model.answerSceneTitle(note) {
            var s = AttributedString(scene.hasSuffix(".") ? scene : scene + ".")
            s.foregroundColor = Gate.Text.primary; s.font = .system(size: 12.5, weight: .medium)
            out += s; out += AttributedString(" ")
        }
        var body = AttributedString(answer?.summary ?? note.text)
        body.foregroundColor = Gate.Text.secondary
        out += body
        let delta = model.deltaText(note)
        if !delta.isEmpty {
            var d = AttributedString("  " + delta)
            d.foregroundColor = partly ? Gate.State.alert : Gate.Text.tertiary; d.font = .system(size: 11, design: .monospaced)
            out += d
        }
        return out
    }
    private var plainSentence: String { [model.answerSceneTitle(note).map { $0 + "." }, answer?.summary].compactMap { $0 }.joined(separator: " ") }

    /// Accept · Reply · Play it; Pick A or B for two options; Reply first when the editor only got part of it.
    @ViewBuilder private var actions: some View {
        if replying {
            Chip("Replying", mono: false)
        } else if !model.isPictureLocked && !model.looksBack {
            HStack(spacing: 6) {
                if model.hasOptions(note) && answer?.pick == nil {
                    Button("Pick A or B") { model.selectAnswer(note); model.comparingNoteID = note.id }
                        .buttonStyle(.gate(.normal, .small)).help("Compare the two versions (\u{21A9})")
                } else if !partly {
                    Button { model.acceptAnswerFromChanges(note.id) } label: { SmallIconLabel("Accept", icon: "checkmark", size: 9) }
                        .buttonStyle(.gate(.normal, .small)).help("Keep it in the cut (A)")
                        .accessibilityLabel("Accept note \(note.number.map(String.init) ?? "")")
                }
                Button("Reply") { model.replyToAnswer(note.id) }
                    .buttonStyle(.gate(partly ? .normal : .ghost, .small)).help("Tell the editor what\u{2019}s not right yet (R)")
                if model.answerRange(note) != nil {
                    Button { model.openChangesReel(from: note.id) } label: { SmallIconLabel("Play it", icon: "play.fill", size: 8) }
                        .buttonStyle(.gate(.ghost, .small)).help("Play this change with its handles")
                }
            }
        }
    }

    /// ✓ Accepted, Used B, Reopened or Reverting, and what an accepted answer still offers.
    @ViewBuilder private var doneMark: some View {
        switch status {
        case .accepted:
            HStack(spacing: 8) {
                // A note that said something for every time can be kept (styles.md › Keep as a rule).
                if let kept = answer?.keptRule {
                    Chip("Kept as a rule", icon: "checkmark", mono: false).help("In \(kept.styleName)")
                } else if answer?.rule != nil && hovered && !model.looksBack {
                    Button("Keep as a Rule\u{2026}") { model.changes.keepingNoteID = note.id }
                        .buttonStyle(.gate(.ghost, .small)).help(answer?.rule?.text ?? "")
                }
                Label(model.doneLabel(note), systemImage: "checkmark").labelStyle(StatusOKLabelStyle())
            }
        case .reopened:
            HStack(spacing: 6) {
                if revert != nil && note.noteState != .turnedOver && hovered {
                    Button("Put back") { model.putBack(note.id) }.buttonStyle(.gate(.ghost, .small)).help("Keep the change as the editor made it")
                }
                Chip(revert == nil ? "Reopened" : "Reverting", style: .director, mono: false).help("Goes into your next turnover")
            }
        case .unreviewed:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        var parts = [note.isUnasked ? "Unasked" : "Note \(note.number.map(String.init) ?? "")", note.isUnasked ? "" : note.text]
        if let s = model.answerSceneTitle(note) { parts.append(s) }
        parts.append(answer?.summary ?? "")
        let d = model.deltaText(note)
        if !d.isEmpty { parts.append(d.replacingOccurrences(of: "\u{2212}", with: "minus ").replacingOccurrences(of: " s", with: " seconds")) }
        if status == .accepted { parts.append(model.doneLabel(note)) }
        if status == .reopened { parts.append("Reopened") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
