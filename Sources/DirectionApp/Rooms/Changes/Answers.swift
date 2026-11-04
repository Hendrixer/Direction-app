import SwiftUI
import DirectionCore

// The editor's answers on the Cut room's sheet (specs/cut.md › Answers on the sheet): the parts an answer row
// is made of, its menu, and the reply thread (32). The row itself is AnsweredNoteRow.

/// "✓ Accepted" in green.
struct StatusOKLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 10, weight: .semibold)); configuration.title }
            .font(.system(size: 12)).foregroundStyle(Gate.State.approve).lineLimit(1).fixedSize()
    }
}

/// 96 × 54 picture of the changed passage, with the editor's 2 pt prism top edge.
struct AnswerThumb: View {
    var model: FilmModel
    var note: ReviewComment
    var prism = true
    var body: some View {
        let scene = model.answerScene(note)
        ZStack {
            Gate.Surface.panel
            Thumbnail(path: scene?.thumbnail, art: scene?.art ?? .room)
        }
        .overlay(alignment: .top) { if prism { Gate.Voice.prism.frame(height: 2) } }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Gate.Line.subtle, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Right-click an answer: Accept, Reply, Play this change, Show in the cut before, Revert this change.
struct AnswerContextMenu: View {
    var model: FilmModel
    var note: ReviewComment
    var body: some View {
        let status = model.status(note)
        let before = model.cutBefore(model.reviewCut)
        Button("Accept") { model.acceptAnswerFromChanges(note.id) }.disabled(status != .unreviewed || model.isPictureLocked)
        Button("Reply\u{2026}") { model.replyToAnswer(note.id) }.disabled(model.isPictureLocked)
        Button("Play This Change") { model.openChangesReel(from: note.id) }.disabled(model.answerRange(note) == nil)
        Button("Keep as a Rule\u{2026}") { model.changes.keepingNoteID = note.id }.disabled(model.answer(note, in: model.reviewCut)?.keptRule != nil)
        if let before {
            Button("Show in \(before.name)") {
                let t = model.noteTime(note)
                model.watch(before)
                if let t { model.seek(t) }
            }
        }
        Divider()
        if model.revertReply(note) != nil {
            Button("Put Back") { model.putBack(note.id) }.disabled(note.noteState == .turnedOver)
        } else {
            Button("Revert This Change\u{2026}") { model.changes.revertNoteID = note.id }
                .disabled(model.revertBlocker(note, in: model.reviewCut) != nil)
        }
    }
}

// MARK: Thread (32)

struct ThreadMessage: Identifiable {
    var id: String
    var editor: Bool
    var outside = false
    var who: String
    var text: String
}

extension FilmModel {
    /// The note, every answer and every reply, oldest first. Shows which cut each message refers to.
    func threadMessages(_ c: ReviewComment) -> [ThreadMessage] {
        var first = ThreadMessage(id: c.id, editor: c.isUnasked, outside: c.isOutside, who: "", text: c.text)
        first.who = c.isUnasked ? "Editor \u{00B7} Unasked" : "\(c.isOutside ? c.person?.name ?? "Outside" : "You") \u{00B7} on \(cutName(c.cutID))"
        var items: [(Double, ThreadMessage)] = []
        let answers = c.answers ?? []
        for a in answers {
            let name = cuts.first { $0.id == a.cutID }?.name ?? "Cut"
            let longer = c.replies.first { $0.author != "Director" && $0.revision == a.revision && $0.text.hasPrefix(a.summary) }
            items.append((a.createdAt, .init(id: "answer-\(a.cutID)", editor: true, who: "Editor \u{00B7} \(name)", text: longer?.text ?? a.summary)))
        }
        for r in c.replies {
            if r.author == "Director" {
                guard r.text != "Accepted" else { continue }
                items.append((r.createdAt, .init(id: r.id, editor: false, who: "You \u{00B7} on \(cut(atRevision: r.revision)?.name ?? "this cut")", text: r.text)))
            } else if !answers.contains(where: { r.revision == $0.revision && r.text.hasPrefix($0.summary) }) {
                items.append((r.createdAt, .init(id: r.id, editor: true, who: "Editor \u{00B7} \(cut(atRevision: r.revision)?.name ?? "")", text: r.text)))
            }
        }
        return [first] + items.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

struct AnswerThread: View {
    @Bindable var model: FilmModel
    let note: ReviewComment
    /// Lines the thread up with the row's words.
    var inset: CGFloat = 52
    @FocusState private var focused: Bool
    @State private var sendKey: Any?

    private var number: String { note.number.map(String.init) ?? "" }
    private var draft: Binding<String> { Binding(get: { model.changes.drafts[note.id] ?? "" }, set: { model.changes.drafts[note.id] = $0 }) }
    private var canSend: Bool { !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.threadMessages(note)) { m in message(m) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Conversation on note \(number)")
            if draft.wrappedValue.isEmpty { quickReplies }
            GateTextArea(text: draft, placeholder: "What\u{2019}s not right yet?", minHeight: 64, focused: $focused)
                .accessibilityLabel("Reply to the editor about note \(number)")
            HStack(spacing: 8) {
                Text("Goes into your next turnover").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                Spacer(minLength: 8)
                Button("Cancel") { model.cancelReply() }.buttonStyle(.gate(.ghost))
                Button { model.sendReply(note.id) } label: {
                    HStack(spacing: 6) { Text("Reopen \(number)"); KeyHint("\u{2318}\u{21A9}") }
                }
                .buttonStyle(.gate(.normal)).disabled(!canSend)
                .help("Reopen note \(number) (⌘↩)")
            }
        }
        .padding(.top, 4).padding(.leading, inset).padding(.trailing, 14).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Gate.Surface.panel)
        .overlay(alignment: .bottom) { Hairline() }
        .onExitCommand { model.cancelReply() }
        .task {
            try? await Task.sleep(for: .seconds(Gate.Motion.glideDuration))
            focused = true
        }
        .onAppear { installSendKey() }
        .onDisappear { if let sendKey { NSEvent.removeMonitor(sendKey) }; sendKey = nil }
    }

    /// ⌘↩ sends while the thread is open. It's caught before the titlebar's ⌘↩, so the steel
    /// button still plays changes when clicked.
    private func installSendKey() {
        guard sendKey == nil else { return }
        let id = note.id
        sendKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard [36, 76].contains(event.keyCode), flags == .command, event.window?.isKeyWindow ?? true else { return event }
            let sent = MainActor.assumeIsolated {
                guard model.changes.replyingNoteID == id, model.sheet == nil else { return false }
                model.sendReply(id)
                return true
            }
            return sent ? nil : event
        }
    }

    private func message(_ m: ThreadMessage) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Group {
                if m.editor { GemMark(size: 7) } else { PinMark(color: m.outside ? Gate.Text.secondary : Gate.Voice.director) }
            }
            .frame(width: 14, height: 14).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.who).font(Gate.Font.caption).foregroundStyle(Gate.Text.disabled).frame(minHeight: 16)
                Mentions.text(m.text, footage: model.footageNames).font(.system(size: 12.5)).lineSpacing(2.7).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quickReplies: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(["Not quite.", "Go further.", "Too much.", "Put it back the way it was."], id: \.self) { phrase in
                Button { draft.wrappedValue = phrase + (phrase.hasPrefix("Put") ? "" : " "); focused = true } label: {
                    Chip(phrase.hasPrefix("Put") ? "Put it back" : String(phrase.dropLast()), mono: false)
                }
                .buttonStyle(.plain).help("Insert \u{201C}\(phrase)\u{201D}")
            }
        }
    }
}
