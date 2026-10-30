import SwiftUI
import DirectionCore

// Owner: Changes and Finish agent. The answers panel (29, 30, 32, 34): head, tabs, rows, reply thread, foot.

struct AnswersPanel: View {
    @Bindable var model: FilmModel
    private var state: ChangesState { model.changes }
    private var cutName: String { model.reviewCut?.name ?? "this cut" }

    var body: some View {
        VStack(spacing: 0) {
            head
            tabs
            list.frame(maxHeight: .infinity, alignment: .top)
            foot
        }
        .frame(width: 560)
        .frame(maxHeight: .infinity)
        .background(Gate.Surface.ground)
        .hairlineBorder(.leading)
        .alert("Accept \(model.acceptableRemaining.count) answers?", isPresented: Binding(get: { state.confirmAcceptAll }, set: { state.confirmAcceptAll = $0 })) {
            Button("Accept \(model.acceptableRemaining.count)") { model.acceptAllRemaining() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.toReview.count > model.acceptableRemaining.count ? "They stay in \(cutName). Answers with two options wait for your pick." : "They stay in \(cutName).")
        }
    }

    // MARK: Head

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Answers in \(cutName)").font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary).lineLimit(1)
                Spacer(minLength: 8)
                Button { model.showCutHistory() } label: { SmallIconLabel("History", icon: "clock.arrow.circlepath") }
                    .buttonStyle(.gate(.ghost, .small)).help("Cut history (⌘Y)")
            }
            Text(subline).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1).frame(minHeight: 17)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
    }

    private var subline: String {
        let total = model.reviewAnswers.count
        var parts: [String] = []
        if let d = model.cutDuration(model.reviewCut) { parts.append(Timecode.duration(d)) }
        if total > 0 && model.toReview.isEmpty { parts.append("every answer accepted"); return parts.joined(separator: " \u{00B7} ") }
        if let d = model.cutDuration(model.reviewCut), let prev = model.cutBefore(model.reviewCut), let p = model.cutDuration(prev) {
            parts.append(ChangesFormat.lengthChange(d - p, than: prev.name))
        }
        parts.append(total == 1 ? "1 answer" : "\(total) answers")
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(AnswersTab.allCases) { tab in
                let on = model.answersTab == tab
                Button {
                    state.sticky = []
                    state.chosenTab = tab
                } label: {
                    HStack(spacing: 14) {
                        Text(tab.title).font(.system(size: 12, weight: .medium))
                        Text("\(model.count(for: tab))").font(Gate.Font.mono).foregroundStyle(Gate.Text.disabled).offset(y: -2)
                    }
                    .foregroundStyle(on ? Gate.Text.primary : Gate.Text.tertiary)
                    .padding(.leading, 8).padding(.trailing, 16).frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) { if on { Gate.Text.primary.frame(height: 2) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityLabel("\(tab.title), \(model.count(for: tab))")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 49)
        .hairlineBorder(.bottom)
    }

    // MARK: List

    private var list: some View {
        let rows = model.answers(for: model.answersTab)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { c in
                        AnswerRow(model: model, note: c).id(c.id)
                        if state.replyingNoteID == c.id {
                            AnswerThread(model: model, note: c).transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    if rows.isEmpty { empty }
                }
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.selectedAnswerNoteID) { _, id in if let id { withAnimation(gateAnimation(Gate.Motion.settle)) { proxy.scrollTo(id) } } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Answers in \(cutName)")
    }

    private var empty: some View {
        let text: String
        if model.reviewAnswers.isEmpty { text = "No answers in \(cutName). When the editor delivers a cut from your notes, each change shows up here with its note number." }
        else if model.answersTab == .review { text = "Every answer is accepted. Screen it again for more notes, or lock picture when the edit is done." }
        else { text = "Nothing accepted yet." }
        return Text(text).font(Gate.Font.body).foregroundStyle(Gate.Text.tertiary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
    }

    // MARK: Foot

    private var foot: some View {
        Text(footText).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
            .frame(minHeight: 44)
            .hairlineBorder(.top)
    }
    private var footText: String {
        if model.isPictureLocked { return "Picture is locked. Unlock it from Film \u{203A} Unlock Picture to change the edit." }
        if !model.reviewAnswers.isEmpty && model.toReview.isEmpty { return "Nothing left to review. Screen it again for more notes, or lock picture to start finishing." }
        return "Accepted answers stay in \(cutName). Anything you reply to goes into your next turnover."
    }
}

// MARK: Answer row

struct AnswerRow: View {
    @Bindable var model: FilmModel
    let note: ReviewComment

    private var status: AnswerStatus { model.status(note) }
    private var selected: Bool { model.selectedAnswerNoteID == note.id }
    private var replying: Bool { model.changes.replyingNoteID == note.id }
    private var answer: NoteAnswer? { model.answer(note, in: model.reviewCut) }
    private var done: Bool { status == .accepted }
    private var partly: Bool { answer?.delta?.lowercased() == "partly" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                number.frame(width: 24, alignment: .leading)
                AnswerThumb(model: model, note: note).frame(width: 96, height: 54).opacity(done ? 0.55 : 1)
                what.opacity(done ? 0.55 : 1).frame(maxWidth: .infinity, alignment: .leading)
                right
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Hairline()
        }
        .background(selected || replying ? Gate.Surface.panel : .clear)
        .contentShape(Rectangle())
        // One click selects and cues; a double-click plays just this change. Buttons in the row win.
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2 { model.openChangesReel(from: note.id) } else { model.selectAnswer(note) }
        }
        .contextMenu { AnswerContextMenu(model: model, note: note) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var number: some View {
        if note.isUnasked { GemMark(size: 8, solid: true).accessibilityLabel("Unasked") }
        else { Text(note.number.map(String.init) ?? "–").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Gate.Voice.director) }
    }

    private var what: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.kindLabel(note)).font(Gate.Font.caption).foregroundStyle(note.isUnasked ? Gate.Voice.agent : Gate.Text.tertiary)
            Text(sentence).font(.system(size: 12.5)).lineSpacing(2.5).lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(plainSentence)
        }
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
        return out
    }
    private var plainSentence: String { [model.answerSceneTitle(note).map { $0 + "." }, answer?.summary].compactMap { $0 }.joined(separator: " ") }

    private var right: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.deltaText(note)).font(Gate.Font.mono).foregroundStyle(partly ? Gate.State.alert : Gate.Text.tertiary).lineLimit(1)
                // Made picture or sound (made-media.md › Where made things show).
                if let made = model.made.records(for: note, in: model.reviewCut, film: model).first { MadeChip(film: model, record: made, place: "answer") }
            }
            actions
        }
        .fixedSize()
    }

    @ViewBuilder private var actions: some View {
        if replying {
            Chip("Replying", mono: false)
        } else {
            switch status {
            case .accepted:
                Label(model.doneLabel(note), systemImage: "checkmark").labelStyle(StatusOKLabelStyle())
            case .reopened:
                Chip(model.revertReply(note) == nil ? "Reopened" : "Reverting", style: .director, mono: false)
                    .help("Goes into your next turnover")
            case .unreviewed:
                if model.isPictureLocked {
                    EmptyView()
                } else if model.hasOptions(note) && answer?.pick == nil {
                    Button("Pick A or B") { model.selectAnswer(note); model.comparingNoteID = note.id }
                        .buttonStyle(.gate(.normal, .small)).help("Compare the two versions")
                } else {
                    HStack(spacing: 6) {
                        if !partly {
                            Button { model.acceptAnswerFromChanges(note.id) } label: { SmallIconLabel("Accept", icon: "checkmark", size: 9) }
                                .buttonStyle(.gate(.normal, .small)).help("Accept (Y)")
                                .accessibilityLabel("Accept note \(note.number.map(String.init) ?? "")")
                        }
                        Button { model.replyToAnswer(note.id) } label: { Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10, weight: .medium)) }
                            .buttonStyle(.gate(partly ? .normal : .ghost, .small, icon: !partly))
                            .help("Reply (⌘R)").accessibilityLabel("Reply")
                    }
                }
            }
        }
    }

    private var accessibilityText: String {
        var parts = [note.isUnasked ? "Unasked" : "Note \(note.number.map(String.init) ?? "")", model.kindLabel(note)]
        if let s = model.answerSceneTitle(note) { parts.append(s) }
        parts.append(answer?.summary ?? "")
        let d = model.deltaText(note)
        if !d.isEmpty { parts.append(d.replacingOccurrences(of: "\u{2212}", with: "minus ").replacingOccurrences(of: " s", with: " seconds")) }
        if status == .accepted { parts.append(model.doneLabel(note)) }
        return parts.joined(separator: ", ")
    }
}

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
        if let before {
            Button("Show in \(before.name)") {
                let t = model.noteTime(note)
                model.watch(before)
                if let t { model.seek(t) }
            }
        }
        Divider()
        Button("Revert This Change\u{2026}") {
            model.changes.historyCutID = model.reviewCut?.id
            model.changes.historyNoteID = note.id
            model.changes.revertNoteID = note.id
            model.showCutHistory()
        }
        .disabled(status == .reopened || model.isPictureLocked)
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
                Text("Reopens note \(number) for your next turnover").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                Spacer(minLength: 8)
                Button("Cancel") { model.cancelReply() }.buttonStyle(.gate(.ghost))
                Button { model.sendReply(note.id) } label: {
                    HStack(spacing: 6) { Image(systemName: "arrowshape.turn.up.left"); Text("Reopen note \(number)"); KeyHint("\u{2318}\u{21A9}") }
                }
                .buttonStyle(.gate(.normal)).disabled(!canSend)
                .help("Reopen note \(number) (⌘↩)")
            }
        }
        .padding(.top, 4).padding(.leading, 52).padding(.trailing, 14).padding(.bottom, 14)
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
                Text(m.text).font(.system(size: 12.5)).lineSpacing(2.7).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quickReplies: some View {
        HStack(spacing: 6) {
            ForEach(["Not quite.", "Go further.", "Too much.", "Put it back the way it was."], id: \.self) { phrase in
                Button { draft.wrappedValue = phrase + (phrase.hasPrefix("Put") ? "" : " "); focused = true } label: {
                    Chip(phrase.hasPrefix("Put") ? "Put it back" : String(phrase.dropLast()), mono: false)
                }
                .buttonStyle(.plain).help("Insert \u{201C}\(phrase)\u{201D}")
            }
        }
    }
}
