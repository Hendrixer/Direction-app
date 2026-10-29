import SwiftUI
import AppKit
import DirectionCore

/// The editor's questions and can't-dos, answered without leaving the room.
struct QuestionsTab: View {
    @Bindable var model: FilmModel
    private var answered: [EditorQuestion] {
        let turnover = model.notesTurnover?.id ?? model.lastTurnover?.id
        return model.questions.filter { $0.answer != nil && $0.turnoverID == turnover }
    }
    var body: some View {
        if model.openQuestions.isEmpty && answered.isEmpty {
            EmptyStateView(title: "No questions.", message: "When the editor needs you to decide something, it asks here.") { EmptyView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.openQuestions) { q in
                        if q.kind == "cant" { CantNotice(model: model, question: q, inset: false) }
                        else { QuestionCard(model: model, question: q, primary: q.id == model.openQuestions.first { $0.kind != "cant" }?.id) }
                    }
                    .transition(.noticeArrival)
                    Text("Answered questions stay here, under the note they belong to.")
                        .font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    ForEach(answered) { q in AnsweredLine(model: model, question: q) }
                }
                .padding(.vertical, 14).padding(.horizontal, 12)
                .animation(gateAnimation(Gate.Motion.glide), value: model.openQuestions.map(\.id))
            }
        }
    }
}

/// "You chose T5." under an answered question.
struct AnsweredLine: View {
    var model: FilmModel
    var question: EditorQuestion
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            GemMark(size: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(question.text).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary).lineLimit(2)
                Text(model.answerSummary(question)).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// `.question`: ion border, the diamond, 2–4 choices, optional words, the steel Answer.
struct QuestionCard: View {
    @Bindable var model: FilmModel
    var question: EditorQuestion
    /// The first open question's Answer is the window's default button.
    var primary = true
    /// Steel only where the titlebar has no steel button (the Questions tab).
    var steel = true
    @FocusState private var fieldFocused: Bool

    private var ui: NotesUI { model.notesUI }
    private var choice: String? { ui.choices[question.id] }
    private var words: Binding<String> {
        Binding(get: { ui.answerText[question.id] ?? "" }, set: { text in
            ui.answerText[question.id] = text
            if !text.isEmpty { ui.choices[question.id] = nil }
        })
    }
    private var canAnswer: Bool { choice != nil || !(ui.answerText[question.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    private var heldScene: Int { question.noteIDs.compactMap(model.note).first.flatMap(model.anchorScene)?.number ?? 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GemMark(size: 8)
                Text("Editor asks").fontWeight(.medium).foregroundStyle(Gate.Voice.agent)
                Spacer(minLength: 0)
                Text(model.ago(question.createdAt)).foregroundStyle(Gate.Text.disabled)
            }
            .font(Gate.Font.small).lineHeight(12, 1.45)
            Text(question.text).font(.system(size: 13.5)).foregroundStyle(Gate.Text.primary).lineHeight(13.5, 1.5)
                .fixedSize(horizontal: false, vertical: true)
            if !question.noteIDs.isEmpty {
                HStack(spacing: 5) {
                    Chip("Holds", mono: false)
                    ForEach(question.noteIDs, id: \.self) { id in Chip(model.noteNumber(id), style: .director) }
                    Text("Everything else keeps cutting.").font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineLimit(1)
                }
            }
            VStack(spacing: 8) {
                ForEach(question.choices) { c in
                    QuestionChoiceRow(model: model, choice: c, on: choice == c.id, fallbackScene: heldScene) {
                        ui.choices[question.id] = c.id
                        ui.answerText[question.id] = nil
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Choices")
            if question.allowsText {
                TextField("", text: words)
                    .gateField(focused: fieldFocused)
                    .overlay(alignment: .leading) {
                        if words.wrappedValue.isEmpty {
                            Text("Or tell me in your words\u{2026}").font(Gate.Font.body).foregroundStyle(Gate.Text.disabled).padding(.leading, 10).allowsHitTesting(false)
                        }
                    }
                    .focused($fieldFocused)
                    .onSubmit(send)
                    .accessibilityLabel("Answer in your words")
            }
            HStack {
                Spacer()
                answerButton
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).fill(Gate.Surface.panel)
            .overlay(RoundedRectangle(cornerRadius: Gate.Radius.card, style: .continuous).strokeBorder(Gate.Voice.agent.opacity(0.35), lineWidth: 1)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Question from the editor")
    }

    @ViewBuilder private var answerButton: some View {
        let button = Button(action: send) { HStack(spacing: 6) { Text("Answer"); KeyHint("↩") } }
            .buttonStyle(.gate(steel ? .steel : .normal)).disabled(!canAnswer)
        if primary { button.keyboardShortcut(.defaultAction) } else { button }
    }

    private func send() {
        guard canAnswer else { return }
        model.answerQuestion(question)
    }
}

struct QuestionChoiceRow: View {
    var model: FilmModel
    var choice: QuestionChoice
    var on: Bool
    var fallbackScene: Int
    var pick: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            RadioDot(on: on)
            thumb
            VStack(alignment: .leading, spacing: 0) {
                Text(choice.label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Gate.Text.primary).lineHeight(12.5, 1.45)
                if let detail = choice.detail {
                    Text(detail).font(Gate.Font.caption).foregroundStyle(Gate.Text.tertiary).lineHeight(11, 1.45).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if choice.assetID != nil {
                Button(action: play) { Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Gate.Text.tertiary) }
                    .buttonStyle(.plain).help("Play this take").accessibilityLabel("Play \(choice.label)")
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(Gate.Surface.raised))
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(on ? Gate.Text.primary : Gate.Line.subtle, lineWidth: on ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { pick() }
    }

    @ViewBuilder private var thumb: some View {
        if choice.assetID != nil {
            TakeThumb(model: model, assetID: choice.assetID, fallbackScene: fallbackScene)
                .onTapGesture(perform: play)
                .accessibilityLabel(model.takeCode(choice.assetID) ?? choice.label)
        } else if choice.label.localizedCaseInsensitiveContains("both") {
            RoundedRectangle(cornerRadius: 4).fill(Gate.Surface.sunken).frame(width: 64, height: 36)
                .overlay(Image(systemName: "rectangle.split.2x1").font(.system(size: 13, weight: .medium)).foregroundStyle(Gate.Text.tertiary))
        }
    }

    /// Plays the take in the stage when it's in the cut being watched.
    private func play() {
        pick()
        guard let id = choice.assetID, let clip = model.sequence?.clips.first(where: { $0.assetID == id }) else { return }
        model.seek(clip.start.seconds)
        if !model.playing { model.togglePlayback() }
    }
}

/// `.notice.cant`: the editor can't do a note as written. The rest of the cut keeps moving.
struct CantNotice: View {
    @Bindable var model: FilmModel
    var question: EditorQuestion
    var inset = true

    private var ui: NotesUI { model.notesUI }
    private var confirmUnlock: DailiesScene? { ui.confirmingUnlock == question.id ? ui.choices[question.id].flatMap { id in question.choices.first { $0.id == id } }.flatMap(model.unlockScene) : nil }
    private var choice: String? { ui.choices[question.id] }
    private var held: [ReviewComment] { question.noteIDs.compactMap(model.note) }
    private var numbers: String {
        let n = held.compactMap(\.number).map(String.init)
        return n.count <= 1 ? "note \(n.first ?? "")" : "notes \(n.dropLast().joined(separator: ", ")) and \(n.last!)"
    }
    private var source: String? {
        guard let c = held.first else { return nil }
        return (["Note \(c.number.map(String.init) ?? "")"] + [c.person?.name].compactMap { $0 } + ["\u{201C}\(c.text)\u{201D}"]).joined(separator: " · ")
    }
    private var preview: QuestionChoice? { question.choices.first { $0.assetID != nil && !$0.recommended } ?? question.choices.first { $0.assetID != nil } }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: question.text.localizedCaseInsensitiveContains("lock") ? "lock.fill" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.State.alert)
                Text("I can\u{2019}t do \(numbers) yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Gate.Text.primary)
                Spacer(minLength: 0)
                ForEach(held) { c in Chip(c.number.map(String.init) ?? "–", style: .director) }
            }
            NoticeText(text: question.text, small: [question.detail, source].compactMap { $0 }.joined(separator: "\n"))
            VStack(spacing: 8) {
                ForEach(question.choices) { c in
                    CantChoiceRow(model: model, choice: c, on: choice == c.id, unlocks: model.unlockScene(for: c) != nil) { ui.choices[question.id] = c.id }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("How should the editor handle \(numbers)?")
            HStack(spacing: 8) {
                Button { model.answerOrConfirm(question) } label: { HStack(spacing: 6) { Text("Answer"); KeyHint("↩") } }
                    .buttonStyle(.gate).disabled(choice == nil)
                if let preview, let code = model.takeCode(preview.assetID) {
                    Button("Show me \(code)") { show(preview) }.buttonStyle(.gate(.ghost))
                }
            }
        }
        Notice(tone: .cant, inset: inset) { content }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The editor can\u{2019}t do \(numbers)")
        .alert(confirmUnlock.map { "Unlock \($0.number) \($0.title)?" } ?? "", isPresented: Binding(get: { confirmUnlock != nil }, set: { if !$0 { ui.confirmingUnlock = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Unlock") {
                if let scene = confirmUnlock { model.lockScene(scene.id, false); model.answerQuestion(question) }
                ui.confirmingUnlock = nil
            }
        } message: {
            Text("The editor may change it for \(numbers) only.")
        }
    }

    private func show(_ c: QuestionChoice) {
        if let clip = model.sequence?.clips.first(where: { $0.assetID == c.assetID }) { model.pause(); model.seek(clip.start.seconds) }
        else { model.openTakeID = c.assetID; model.go(.dailies) }
    }
}

struct CantChoiceRow: View {
    var model: FilmModel
    var choice: QuestionChoice
    var on: Bool
    var unlocks: Bool
    var pick: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            if choice.assetID != nil { TakeThumb(model: model, assetID: choice.assetID) }
            VStack(alignment: .leading, spacing: 0) {
                Text(choice.label).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary).lineHeight(12.5, 1.45)
                if let detail = choice.detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Gate.Text.tertiary).lineHeight(11.5, 1.45).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, choice.assetID == nil ? 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            if choice.recommended { Chip("I\u{2019}d pick this", style: .agent, mono: false) }
            if unlocks { Image(systemName: "lock.open").font(.system(size: 11, weight: .medium)).foregroundStyle(Gate.Text.tertiary) }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).fill(Gate.Surface.raised))
        .overlay(RoundedRectangle(cornerRadius: Gate.Radius.control, style: .continuous).strokeBorder(on ? Gate.Text.primary : Gate.Line.subtle, lineWidth: on ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint(choice.recommended ? "The editor would pick this" : "")
        .accessibilityAction { pick() }
    }
}

/// The sheet foot while cutting: "Cutting Cut 4 · 3 of 7 notes", time left and a prism meter.
struct CuttingStatusFoot: View {
    var model: FilmModel
    var turnover: Turnover
    var body: some View {
        let total = max(1, turnover.noteIDs.count), done = turnover.progress.values.filter { $0 == .done }.count
        let waitingOnYou = model.openQuestions.contains { $0.noteIDs.isEmpty }
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                GemMark(size: 7)
                Text(waitingOnYou ? "Waiting for you" : "Cutting \(model.nextCutName) · \(done) of \(total) notes").foregroundStyle(Gate.Text.tertiary)
                Spacer(minLength: 0)
                if !waitingOnYou, let left = model.remainingSeconds(turnover) { Text(model.minutesLeft(left, suffix: false)).foregroundStyle(Gate.Text.disabled) }
            }
            .font(Gate.Font.small).lineHeight(12, 1.45)
            if !waitingOnYou { GateProgress(value: turnover.percent ?? Double(done) / Double(total), agent: true) }
        }
        .padding(.top, 13).padding(.horizontal, 16).padding(.bottom, 14)
        .hairlineBorder(.top)
    }
}

extension FilmModel {
    /// A choice that unlocks a locked scene needs your confirmation first; the editor never unlocks anything itself.
    func unlockScene(for c: QuestionChoice) -> DailiesScene? {
        guard c.label.lowercased().hasPrefix("unlock") else { return nil }
        return scenes.first { $0.locked && c.label.localizedCaseInsensitiveContains($0.title) }
    }
    /// Answer, or ask to confirm first when the choice unlocks a scene.
    func answerOrConfirm(_ q: EditorQuestion) {
        guard let id = notesUI.choices[q.id], let c = q.choices.first(where: { $0.id == id }) else {
            if q.kind != "cant" { answerQuestion(q) }
            return
        }
        if unlockScene(for: c) != nil { notesUI.confirmingUnlock = q.id } else { answerQuestion(q) }
    }
    /// ↑ / ↓ through a question's choices.
    func moveChoice(_ q: EditorQuestion, _ step: Int) {
        guard !q.choices.isEmpty else { return }
        let index = q.choices.firstIndex { $0.id == notesUI.choices[q.id] }.map { $0 + step } ?? (step > 0 ? 0 : q.choices.count - 1)
        notesUI.choices[q.id] = q.choices[max(0, min(q.choices.count - 1, index))].id
        notesUI.answerText[q.id] = nil
    }
    /// Sends the picked choice or the typed words, and records the answer on the notes it held.
    func answerQuestion(_ q: EditorQuestion) {
        let ui = notesUI
        let choiceID = ui.choices[q.id]
        let words = ui.answerText[q.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard choiceID != nil || !(words ?? "").isEmpty else { return }
        answer(q, choiceID: choiceID, text: words?.isEmpty == false ? words : nil)
        let said = q.choices.first { $0.id == choiceID }?.label ?? words ?? ""
        for id in q.noteIDs { perform { _ = try $0.reply(commentID: id, text: "Answered the editor: \(said)", author: "Director") } }
        ui.choices[q.id] = nil; ui.answerText[q.id] = nil
        if openQuestions.isEmpty, notesTab == .questions { notesTab = .sheet }
    }
    /// "You chose T5."
    func answerSummary(_ q: EditorQuestion) -> String {
        guard let a = q.answer else { return "" }
        if let label = q.choices.first(where: { $0.id == a.choiceID })?.label {
            let short = label.hasPrefix("Use ") ? String(label.dropFirst(4)) : "\u{201C}\(label)\u{201D}"
            return "You chose \(short)."
        }
        return a.text.map { "You said: \u{201C}\($0)\u{201D}" } ?? ""
    }
    /// "5A T3" for a take.
    func takeCode(_ assetID: String?) -> String? {
        guard let assetID else { return nil }
        let t = dailies.take(assetID)
        guard let code = t.code else { return nil }
        return [t.setupCode, code].compactMap { $0 }.joined(separator: " ")
    }
}
