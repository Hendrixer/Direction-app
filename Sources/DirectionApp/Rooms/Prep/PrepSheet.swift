import SwiftUI
import DirectionCore

/// The Script room's right side: the director's notes on rows and the editor's questions, and the composer.
struct ScriptSheet: View {
    @Bindable var model: FilmModel
    var script: AVScript
    var selected: [String]
    @Binding var tab: PrepSheetTab
    @Binding var noteText: String
    @Binding var noteKind: NoteKind?
    @State private var rules: [String] = []

    private var notes: [PrepNote] { script.notes.filter { $0.state != .dropped }.sorted { $0.number < $1.number } }
    private var questions: [AVRow] { script.rows.filter { $0.question != nil }.sorted { ($0.question!.isOpen ? 0 : 1, $0.question!.createdAt) < ($1.question!.isOpen ? 0 : 1, $1.question!.createdAt) } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes on the script").font(Gate.Font.brandM).foregroundStyle(Gate.Text.primary)
                Text(subtitle).font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            PrepTabs(tab: $tab, notes: notes.count, questions: script.openQuestions.count)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .notes:
                        if notes.isEmpty { guidance.padding(16) }
                        ForEach(notes) { n in PrepNoteRow(note: n, anchor: anchor(n)) { model.dropScriptNote(n.id) } }
                    case .questions:
                        if questions.isEmpty { Text("The editor asks here when only you can say what a row should show.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).padding(16) }
                        ForEach(questions, id: \.id) { r in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("Row \(script.number(of: r.id) ?? 0)")
                                if let q = r.question, q.isOpen { RowQuestion(question: q) { model.answerRow(r.id, choice: $0) } }
                                else if let q = r.question { AnsweredQuestion(question: q) }
                            }.padding(16).hairlineBorder(.bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            composer
        }
        .background(Gate.Surface.ground)
        .hairlineBorder(.leading)
        .task(id: model.brief.style) { rules = ((try? model.store?.appliedStyle())?.style?.rules ?? []).prefix(5).map(\.text) }
    }

    private var subtitle: String {
        let written = script.openNotes.count, out = script.turnedOver.count, done = script.notes.filter { $0.state == .done }.count
        if written == 0 && out == 0 && done == 0 { return "None yet" }
        return [written > 0 ? "\(written) waiting for Turn over" : nil, out > 0 ? "\(out) with the editor" : nil, done > 0 ? "\(done) done" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func anchor(_ n: PrepNote) -> String {
        let numbers = (n.rowIDs ?? []).compactMap { script.number(of: $0) }
        return numbers.count == 1 ? "Row \(numbers[0])" : "Rows \(EditorJobs.rowList(numbers))"
    }

    @ViewBuilder private var guidance: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.writingPicture {
                HStack(alignment: .top, spacing: 9) {
                    GemMark().padding(.top, 5)
                    Text("I\u{2019}m writing what we see under each line, from \(model.styleName.map { "the \($0) style" } ?? "the brief").").font(.system(size: 13)).foregroundStyle(Gate.Text.primary)
                }
                if !rules.isEmpty {
                    SectionLabel("From the style").padding(.top, 4)
                    ForEach(rules, id: \.self) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Circle().fill(Gate.Text.disabled).frame(width: 4, height: 4); Text(r).font(Gate.Font.small).foregroundStyle(Gate.Text.secondary) }
                    }
                }
                Text("Leave notes while I write. I\u{2019}ll read them when you turn them over.").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).padding(.top, 4)
            } else {
                Text("Click a row\u{2019}s number to select it (\u{21E7}-click for more), then write a note below. Notes wait here until you turn them over. What you type in a cell applies now, and the editor keeps it.")
                    .font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary).lineSpacing(2)
            }
        }
    }

    private var composer: some View {
        let rows = selected.compactMap { script.number(of: $0) }
        let ready = !rows.isEmpty && !noteText.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").font(.system(size: 11)).foregroundStyle(Gate.Text.tertiary)
                if rows.isEmpty { Text("Select rows to leave a note").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary) }
                else { Text("Note \(script.nextNoteNumber) on").font(Gate.Font.small).foregroundStyle(Gate.Text.tertiary); Chip(rows.count == 1 ? "Row \(rows[0])" : "Rows \(EditorJobs.rowList(rows))", style: .director) }
            }
            GateTextArea(text: $noteText, placeholder: "What should we see?", minHeight: 52, onSubmit: { if ready { add() } })
            HStack {
                KindPicker(kind: $noteKind)
                Spacer()
                Button { add() } label: { HStack(spacing: 6) { Text("Add"); KeyHint("\u{21A9}") } }.buttonStyle(.gate(.normal, .regular)).disabled(!ready)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .hairlineBorder(.top)
    }

    private func add() {
        model.addScriptNote(rows: selected, kind: noteKind, text: noteText.trimmingCharacters(in: .whitespacesAndNewlines))
        noteText = ""; noteKind = nil
    }
}

/// Notes · Questions, each with a mono count.
struct PrepTabs: View {
    @Binding var tab: PrepSheetTab
    var notes: Int
    var questions: Int
    var body: some View {
        HStack(spacing: 2) {
            item(.notes, "Notes", notes)
            item(.questions, "Questions", questions)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .hairlineBorder(.bottom)
    }
    private func item(_ value: PrepSheetTab, _ title: String, _ count: Int) -> some View {
        let on = tab == value, fresh = value == .questions && count > 0 && !on
        return Button { tab = value } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(on ? Gate.Text.primary : Gate.Text.tertiary)
                Text("\(count)").font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(fresh ? Gate.Voice.agent : Gate.Text.disabled)
            }
            .padding(.horizontal, 8).frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { if on { Rectangle().fill(Gate.Text.primary).frame(height: 2) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// One note on rows or shots, with the editor's reply once it's answered.
struct PrepNoteRow: View {
    var note: PrepNote
    var anchor: String
    var drop: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(note.number)").font(Gate.Font.noteNumber).foregroundStyle(Gate.Voice.director).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Chip(anchor, style: .director)
                    if let k = note.kind { Chip(k.label, style: .label, mono: false) }
                    switch note.state {
                    case .turnedOver: Chip("With the editor", style: .agent, mono: false)
                    case .done: Chip("Done", style: .ok, mono: false)
                    default: EmptyView()
                    }
                    Spacer(minLength: 0)
                    if note.state == .written {
                        Button(action: drop) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }.buttonStyle(.gate(.ghost, .small)).help("Drop this note").accessibilityLabel("Drop note \(note.number)")
                    }
                }
                Text(note.text).font(.system(size: 13)).foregroundStyle(Gate.Text.primary).fixedSize(horizontal: false, vertical: true)
                if let reply = note.reply {
                    HStack(alignment: .top, spacing: 8) { GemMark(size: 7, solid: true).padding(.top, 4); Text(reply).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .hairlineBorder(.bottom)
    }
}

struct AnsweredQuestion: View {
    var question: PrepQuestion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 9) { GemMark(size: 7, solid: true).padding(.top, 4); Text(question.text).font(.system(size: 12.5)).foregroundStyle(Gate.Text.secondary) }
            let choice = question.answer.flatMap { id in question.choices.first { $0.id == id }?.label }
            Text([choice.map { "You chose \u{201C}\($0)\u{201D}." }, question.answerText.map { "You said \u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " ")).font(.system(size: 12.5)).foregroundStyle(Gate.Text.primary)
        }
    }
}
